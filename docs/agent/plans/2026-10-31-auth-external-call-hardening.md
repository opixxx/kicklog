# EXEC_PLAN — auth-external-call-hardening

| 항목 | 값 |
|---|---|
| Task | auth-external-call-hardening |
| Type | fix |
| Branch | fix/auth-external-call-hardening |
| 생성 시각 | 2026-10-31 |
| 상태 | `active` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |
| 근거 | ADR-0017 D11 |

## 1. 목표 (Goal)

ADR-0017 의 동시성 측정 과정에서 **외부 호출 경로를 전수 조사**하다 드러난 운영 결함 셋을 고친다.
가상 스레드 도입(D4)은 보류지만, 이 셋은 동시성 모델과 무관하게 지금 위험하다.

| # | 결함 | 위험 |
|---|---|---|
| ① | `AppleIdentityVerifier` · `KakaoOAuthClient` 가 `RestClient.create()` — **타임아웃 미설정** | `HttpURLConnection` 기본값 0 = **무한 대기** |
| ② | Apple JWKS 를 **매 로그인마다 fetch** | 불필요한 외부 호출, ①의 노출 확대 |
| ③ | `server.shutdown: graceful` 운영 미설정 | 배포마다 in-flight 요청 절단 |

**①이 가장 위험하다.** 외부가 거부(connection refused)하는 게 아니라 **응답을 안 하고 물고 있으면**
그 스레드는 영구 점유된다. 초당 1건만 와도 200초면 Tomcat 스레드 200개가 전부 소진되고,
그 순간 로그인뿐 아니라 **경기 목록·시즌 통계까지 전부 멈춘다** — 트래픽 규모와 무관하다.

같은 리포의 `KakaoLocalRestClient` 는 공유 `restClientBuilder`(connect 2s / read 3s)를 써서
멀쩡하다. **인증 두 곳만 빠져 있다.**

## 2. 접근 (Approach)

### 2-1. 변경 대상

| 파일 | 변경 |
|---|---|
| `config/RestClientConfig.kt` | 타임아웃 프로퍼티를 `kicklog.kakao.*` → **`kicklog.external-http.*`** 로 일반화 |
| `auth/service/AppleIdentityVerifier.kt` | `RestClient.create()` → 주입받은 빌더 + **JWKS 캐시** |
| `auth/service/KakaoOAuthClient.kt` | `RestClient.create()` → 주입받은 빌더 |
| `resources/application.yml` | 프로퍼티 이동, `server.shutdown: graceful` 추가 |
| `backend/.env.example` | 환경변수 이름 갱신 |

### 2-2. 양보 불가 규칙

1. **모든 외부 HTTP 클라이언트는 공유 `RestClient.Builder` 를 쓴다.** `RestClient.create()` 금지가
   이 PR 의 핵심 규약이다. 빌더에 KDoc 으로 명시한다.
2. **프로퍼티 이름 일반화**: 지금 `kicklog.kakao.connect-timeout-millis` 인데 Apple 도 쓰게 되므로
   이름이 거짓이 된다. `kicklog.external-http.*` 로 옮긴다.
   `KAKAO_LOCAL_*` 환경변수는 `.env.example` 에 주석으로만 있고 실제 사용처가 없어 **이름 변경이 안전**하다.
3. **JWKS 캐시는 키 로테이션에 안전해야 한다.** 캐시가 신선해도 **요청한 `kid` 가 없으면 재조회**한다.
   그러지 않으면 Apple 이 키를 돌린 직후 TTL 동안 **모든 로그인이 실패**한다.
   재조회 후에도 없으면 그때 `AUTH_INVALID_APPLE_TOKEN`.
4. **Clock 주입**: TTL 만료를 테스트로 고정하려면 시간을 통제해야 한다. 기존 `TimeConfig` 의 `clock` 빈을 쓴다.
5. 운영 동작(응답 계약·ErrorCode)은 바꾸지 않는다.

### 2-3. 계약

```
kicklog.external-http.connect-timeout-millis   (기본 2000)
kicklog.external-http.read-timeout-millis      (기본 3000)
kicklog.apple.jwks-cache-ttl-minutes           (기본 360 = 6시간)

server.shutdown: graceful
spring.lifecycle.timeout-per-shutdown-phase: 20s
```

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

기존 `AppleIdentityVerifierTest` 가 이미 실제 `HttpServer` stub 을 쓴다. 그 패턴을 이어간다.

### Happy Path
- [ ] 유효한 Apple JWT 검증 — 기존 테스트가 생성자 변경 후에도 통과
- [ ] **같은 kid 로 2회 검증 시 JWKS 요청은 1회** (캐시 적중)

### Unhappy Path (예외)
- [ ] upstream 이 응답하지 않으면 **read timeout 안에** `EXTERNAL_APPLE_UNAVAILABLE` 로 끝난다
      (무한 대기하지 않음 — ①의 회귀 방지)
- [ ] Kakao 사용자 정보 조회도 동일하게 타임아웃된다

### Edge Cases
- [ ] **키 로테이션**: 캐시가 신선해도 요청한 kid 가 캐시에 없으면 재조회한다
- [ ] 재조회 후에도 kid 가 없으면 `AUTH_INVALID_APPLE_TOKEN` (무한 재조회 금지 — 조회는 1회만)
- [ ] TTL 경과 후에는 kid 가 캐시에 있어도 재조회한다

## 4. 검증 (Verification)

```bash
cd backend && ./gradlew check
```

### 수동 확인
- `kicklog.external-http.*` 미설정 시 기본값(2000/3000)이 적용되는지
- `server.shutdown: graceful` 이 운영 프로파일에서 활성인지

## (Optional) 위험도 / 롤백

**Risk = Caution**

- DB 마이그레이션 없음, API 계약 변경 없음.
- 실질 위험은 **타임아웃 도입으로 느린 정상 응답이 실패하는 것**. Apple JWKS·Kakao 는 통상 수백 ms 라
  read 3s 는 넉넉하다. 그래도 운영에서 `EXTERNAL_APPLE_UNAVAILABLE` 발생률을 관찰한다(Sentry).
- 롤백: 브랜치 revert. 설정·스키마 영구 변경 없음.

## (Optional) 후속

- Bulkhead(ADR-0017 D4 조건 4) — 외부 장애가 나머지 API 를 끌고 들어가지 않게 격리. 본 PR 범위 밖.
