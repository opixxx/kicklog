# EXEC_PLAN — sentry-error-tracking

| 항목 | 값 |
|---|---|
| Task | sentry-error-tracking |
| Type | feature |
| Branch | feature/sentry-error-tracking |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/sentry-error-tracking |
| Port | 9000 |
| 생성 시각 | 2026-06-23 18:35 |
| 상태 | `done` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

## 1. 목표 (Goal)

배포 후 사용자가 실제로 마주치는 **서버 측 장애(5xx·미처리 예외)를 자동으로 감지·알림**받기 위해
Sentry 에러 트래킹을 백엔드에 연동한다. 현재는 예외가 HTTP 응답으로만 반환되고 운영자에게
도달하는 채널이 없어, 사용자가 에러를 만나도 알 방법이 없다 (모니터링 조사 결과 가장 큰 구멍).

**범위 확정 (사용자 결정):**
- 캡처 대상: **5xx + 미처리(unhandled) 예외만**. 4xx 비즈니스 예외(인증·NOT_FOUND·권한 등)는 정상 흐름이라 제외 → 무료 티어 quota 절약 + 노이즈 제거.
- 통합 방식: **Sentry Spring Boot starter** (`sentry-spring-boot-starter-jakarta`).
- 시크릿: 이번 PR 은 **코드만** — 백엔드가 `SENTRY_DSN` 환경변수를 읽도록만 구현. Secrets Manager/Terraform 반영은 후속.

## 2. 접근 (Approach)

### 2.1 의존성 (`backend/build.gradle.kts`)
- `implementation("io.sentry:sentry-spring-boot-starter-jakarta:<latest 8.x>")` 추가.
  - 버전은 BOM 없이 명시 (프로젝트가 platform BOM 미사용). 구현 시 최신 8.x 안정 버전 확인.

### 2.2 설정 (`application.yml`)
- `sentry` 블록 추가:
  - `dsn: ${SENTRY_DSN:}` — **비어 있으면 Sentry SDK 가 자동 비활성** (local/test 자동 off).
  - `environment: ${SENTRY_ENVIRONMENT:local}` — prod 에서 `prod` 주입.
  - `send-default-pii: false` — JWT·카카오·이메일·헤더 등 PII 비전송.
  - `traces-sample-rate: 0` — 성능 트레이싱 미사용 (에러 트래킹 목적만, 무료 티어).
  - `release: ${SENTRY_RELEASE:}` — 선택. git SHA 주입 시 릴리스별 에러 추적 (후속).
- **Sentry 자동 exception resolver 비활성화**: `sentry.exception-resolver-order` 를
  `Ordered.LOWEST_PRECEDENCE` 로 두거나, starter 의 자동 캡처가 4xx 까지 모두 보내지 않도록
  **명시적 캡처 방식**을 채택 (아래 2.3). → 자동 resolver 가 GlobalExceptionHandler 가 처리한
  4xx 까지 전송하는 것을 막기 위해, 자동 캡처는 끄고 핸들러에서 직접 5xx 만 보낸다.

### 2.3 명시적 캡처 (`common/exception/GlobalExceptionHandler.kt`)
- `handleKickLogException`: `errorCode.status.is5xxServerError` 일 때만 `Sentry.captureException(exception)`.
  - 현재 5xx 인 ErrorCode: `EXTERNAL_APPLE_UNAVAILABLE`(502), `EXTERNAL_KAKAO_UNAVAILABLE`(502), `INTERNAL_ERROR`(500).
- **신규 `@ExceptionHandler(Exception::class)` 추가** (미처리 예외 fallback):
  - 현재 미처리 예외는 Spring 기본 처리(비표준 응답) → `ErrorResponse(INTERNAL_ERROR, 500)` 로 통일.
  - `Sentry.captureException(exception)` 호출 + `logger.error` 로 서버 로그에도 기록.
  - traceId 는 기존 `MDC.get("traceId")` 그대로 응답·로그에 포함.
- traceId 를 Sentry 이벤트 태그로 연동: 캡처 직전 `Sentry.configureScope { it.setTag("traceId", MDC.get("traceId")) }` (null 안전).

### 2.4 양보 불가 규칙
- **4xx 는 절대 Sentry 로 보내지 않는다** (KickLogException 의 4xx 전부 제외).
- **PII 비전송** (`send-default-pii=false` + 메시지에 사용자 식별정보 미포함).
- DSN 미설정 환경(local/test)에서 **앱 부팅·테스트가 영향받지 않아야** 한다.
- 기존 `ErrorResponse` 계약(code·message·path·traceId) 불변 — API 스펙 호환.

### 2.5 외부 의존
- iOS 클라이언트 영향 없음 (응답 계약 불변). 본 하네스 대상 아님.
- 사용자가 별도로 Sentry 프로젝트 생성 → DSN 발급 → 운영 환경변수 주입 필요 (후속, PR 본문에 안내).

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

> **🔴 RED 먼저, 🟢 GREEN 다음, 🔵 REFACTOR 마지막**
>
> Sentry 전송 자체는 외부 I/O 라 단위 테스트에서 실제 전송하지 않는다.
> **핵심 검증 포인트 = "5xx/미처리만 capture 되고 4xx 는 capture 되지 않는다"** 를
> `Sentry` static 호출 또는 주입 가능한 캡처 추상화로 검증한다.
> → 테스트 용이성을 위해 캡처를 얇은 인터페이스(`ErrorReporter`)로 감싸 MockK 로 검증하는 방안을 우선 고려.

### Happy Path
- [ ] 미처리 예외(RuntimeException) 발생 → 500 `ErrorResponse(code=INTERNAL_ERROR)` 반환 + traceId 포함 + ErrorReporter.report 1회 호출
- [ ] `KickLogException(INTERNAL_ERROR, 500)` → 500 응답 + ErrorReporter.report 1회 호출

### Unhappy Path (캡처 제외 검증 — 핵심)
- [ ] `KickLogException(USER_NOT_FOUND, 404)` → 404 응답 + ErrorReporter.report **호출되지 않음**
- [ ] `KickLogException(AUTH_INVALID_TOKEN, 401)` → 401 응답 + report **미호출**
- [ ] `KickLogException(MATCH_NOT_OWNED, 403)` → 403 응답 + report **미호출**
- [ ] `KickLogException(EXTERNAL_KAKAO_UNAVAILABLE, 502)` → 502 응답 + report **1회 호출** (5xx)

### Edge Cases
- [ ] DSN 미설정(빈 문자열) 환경에서 앱 컨텍스트 정상 로드 (`@SpringBootTest` smoke) — Sentry 비활성이어도 부팅 OK
- [ ] traceId 가 MDC 에 있을 때 캡처 이벤트/응답에 traceId 반영, 없을 때 null 안전

### 테스트 작성자 (자동 위임)
- 백엔드 → `backend-test-writer` agent (Testcontainers + JUnit5 + MockK + AssertJ)
- iOS → 본 하네스 대상 아님

## 4. 검증 (Verification)

### 자동 검증
- 백엔드: `cd backend && ./gradlew check`
- 컴파일만 빠른 확인: `cd backend && ./gradlew compileKotlin`

### 시나리오 검증 (수동)
- `SENTRY_DSN` 미설정으로 `./gradlew bootRun` → 정상 부팅, 로그에 Sentry "disabled" 류 메시지 확인
- (선택) 실제 DSN 주입 후 강제 500 유발 엔드포인트/예외 → Sentry 대시보드에 이벤트 도착 + traceId 태그 확인, 4xx 유발 시 이벤트 미도착 확인

### 커버리지
- 새 코드(GlobalExceptionHandler 변경분 + ErrorReporter) 커버리지 70% 이상

---

## (Optional) 위험도 / 롤백

- **Risk = Caution**
- DB 마이그레이션 없음, API 응답 계약 불변(미처리 예외 응답이 비표준→표준 ErrorResponse 로 *개선*되는 방향).
- 롤백: 의존성·설정·핸들러 변경 revert 만으로 원복. DSN 미설정 시 런타임 영향 0 이라 안전.

## (Optional) 후속 / 관련 이슈

- **시크릿 인프라화**: `infra/scripts/fetch-secrets.sh` + Terraform `secrets.tf` 에 `SENTRY_DSN` 추가, `docker-compose.prod.yml` 가 env 로 전달 (별도 PR).
- **release 추적**: CD 에서 git SHA 를 `SENTRY_RELEASE` 로 주입 → 배포별 회귀 추적.
- **모니터링 ADR**: 본 작업 + 향후 로그 집계/메트릭 결정을 ADR 로 남길지 검토 (관측성 로드맵).
- 2·3순위(CloudWatch Logs 앱 로그 수집, Micrometer/Prometheus)는 사용자 증가/민원 시 착수.

## (Optional) 학습 기록

- Trigger: self-heal (2회)
- Root cause: ① Sentry starter 가 Spring Boot 4 미지원(제거된 RestClientCustomizer 참조) → 컨텍스트 로드 실패.
  ② `@ExceptionHandler(Exception::class)` 가 Spring MVC 표준 예외(404/405)까지 가로채 500 으로 둔갑 → 회귀 + Sentry 노이즈.
- Prevention: ① 코어 의존성 + 수동 init 폴백, 컨텍스트 로드 smoke 로 호환성 검증.
  ② Exception 광역 핸들러는 `is org.springframework.web.ErrorResponse` 선분기로 상태코드 보존, 5xx 만 전송. 외부 전송은 runCatching.
- Promoted to: docs/agent/learning.md (2026-06-23 항목)

---

> 완료 시: `상태` 필드를 `done`으로 변경하고 PR 본문에 본 파일 링크 첨부.
