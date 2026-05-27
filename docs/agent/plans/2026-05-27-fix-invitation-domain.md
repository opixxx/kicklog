# EXEC_PLAN — fix-invitation-domain

| 항목 | 값 |
|---|---|
| Task | fix-invitation-domain |
| Type | fix |
| Branch | fix/fix-invitation-domain |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/fix-invitation-domain |
| Port | 9000 |
| 생성 시각 | 2026-05-27 17:43 |
| 상태 | `draft` |
| 개발 방식 | **TDD (Red → Green → Refactor)** |

---

## 1. 목표 (Goal)

친구 초대 링크 도메인이 **백엔드 `kicklog.app` ↔ iOS prod `kicklog.org`** 로 불일치한다 (TestFlight 사용 중 발견). 사용자는 `kicklog.org` 만 보유 → `.org` 로 통일하고 동시에 하드코딩된 base URL 을 `@ConfigurationProperties` 로 외부화해 환경별(local/test/prod) 주입이 가능하도록 한다. 도메인 결정을 ADR-0007 로 명문화해 향후 동일 mismatch 재발을 방지한다.

## 2. 접근 (Approach)

### 백엔드 변경
- 신규: `backend/.../friend/service/InvitationProperties.kt`
  - `@ConfigurationProperties(prefix = "kicklog.invitation")`
  - `data class InvitationProperties(val baseUrl: String)` (`AppleProperties` 동일 패턴)
- 수정: `backend/.../friend/service/InvitationService.kt`
  - `companion object` 의 `INVITATION_BASE_URL` 상수 제거
  - 생성자에 `private val properties: InvitationProperties` 추가
  - `@EnableConfigurationProperties(InvitationProperties::class)` 부착
  - `toResult()` 의 `"$INVITATION_BASE_URL/${token}"` → `"${properties.baseUrl}/${token}"`
- 수정: `backend/src/main/resources/application.yml`
  - `kicklog.invitation.base-url: ${INVITATION_BASE_URL:https://kicklog.org/i}` 추가
  - 디폴트는 `.org` (운영 도메인). 로컬은 env 미주입 → 디폴트 사용. 운영은 systemd env 로 명시 주입 가능.
- 수정: `backend/.../InvitationServiceTest.kt`
  - `InvitationProperties("https://kicklog.org/i")` 명시 주입
  - 어설션 `https://kicklog.app/i/Abc12345` → `https://kicklog.org/i/Abc12345`
- 수정 불필요: `InvitationAcceptanceTest.kt` — URL `isNotEmpty()` 만 검증 (도메인 미명시)
- 수정: `backend/.../KicklogApplicationTests.kt` — `kicklog.invitation.base-url=http://localhost/i` 테스트 프로퍼티 추가 (Context Load 시 NPE 방지)

### 문서 변경
- 신규: `docs/adr/0007-domain-decision.md` (Status: Accepted, 2026-05-27)
  - Why `.org`: 사용자 보유 도메인, MVP 출시 일정
  - Why 외부화: 환경별 분리·테스트 가능성·하드코딩 제거
- 갱신: `docs/adr/0003-data-model-and-api.md` D4 의 `kicklog.app` 예시 → `kicklog.org`
- 갱신: `docs/spec/api-spec.md` — Base URL 및 초대 링크 예시 일괄 `.app → .org`
- 갱신: `docs/architecture/api-conventions.md` — 운영 API base URL 및 CORS 화이트리스트
- 갱신: `docs/setup/manual-checklist.md` — 도메인 구매 항목 `.app → .org`
- 갱신: `docs/adr/0006-hosting.md` D? — `.app/.io/.com` 후보 표기 → `.org` 확정 메모

### iOS / 후속
- iOS APIConfig.swift 의 prod baseURL 은 이미 `https://kicklog.org` → 변경 불필요
- Universal Link / Associated Domains / AASA 파일은 사용자가 Xcode + 도메인 호스팅 측에서 별도 작업 (본 PR 범위 밖)

### 트랜잭션 / 권한 / 멱등성
- 본 변경은 **순수 외부화 + 상수 변경** — 트랜잭션·인증·DB 스키마 영향 없음

## 3. 테스트 케이스 (Test Cases) — TDD 핵심

### (3-A) 인수 시나리오 (Gherkin)
본 변경은 **신규 endpoint 추가가 아니라 기존 응답 필드의 prefix 변경** 이라 별도 Cucumber feature 신설은 불필요. 기존 `InvitationAcceptanceTest` 가 URL 비공백만 검증 → 도메인 변경에 영향 없음 (그대로 통과해야 함).

### (3-B) 유스케이스 / 단위 테스트 케이스
#### Happy Path
- [ ] 🔴 `InvitationServiceTest · 8자 base62 토큰과 15일 만료 초대를 생성한다`
      → `invitation.url == "https://kicklog.org/i/Abc12345"` (현재 `.app` 어설션이 RED 가 되도록 먼저 수정)
- [ ] 🔴 신규 케이스: `InvitationService 는 주입된 baseUrl 을 그대로 사용한다`
      → `InvitationProperties("https://example.test/i")` 로 service 생성 → `invitation.url.startsWith("https://example.test/i/")` 검증
      → **외부화가 실제로 동작하는지** 보장하는 핵심 테스트

#### Unhappy / Edge
- [ ] `application.yml` 의 디폴트가 `.org` 인지 확인하는 통합 테스트는 불필요 — Spring Boot 의 `@ConfigurationProperties` 바인딩은 프레임워크 책임. `KicklogApplicationTests` 의 Context Load 만 통과하면 충분.

### 테스트 작성자
- 백엔드 → 본 변경은 기존 단위 테스트 1개 수정 + 1개 추가로 충분. `backend-test-writer` 위임 생략 (스코프 작음).

## 4. 검증 (Verification)

### 자동 검증
- `cd backend && ./gradlew check` — 전체 테스트 + 정적 검사 통과
- `cd backend && ./gradlew compileKotlin` — 컴파일 게이트

### 시나리오 검증 (수동)
- `curl -X POST localhost:8080/invitations -H "Authorization: Bearer <jwt>"` → 응답 `url` 필드가 `https://kicklog.org/i/...` 로 시작하는지 육안 확인
- (옵션) `INVITATION_BASE_URL=https://staging.kicklog.org/i ./gradlew bootRun` → env 주입 동작 확인

### 커버리지
- 신규 추가 코드 = `InvitationProperties` (data class, 4 줄) — 커버리지 측정 의미 없음
- 변경 코드 = `InvitationService.toResult()` 1 라인 — 기존 + 신규 테스트 2개로 충분

---

## (Optional) 위험도 / 롤백

- **Risk = Caution** (운영 응답 포맷 변경. 단, 응답 구조는 그대로이고 URL 의 host 만 바뀜)
- iOS 클라이언트는 응답의 `url` 필드를 그대로 `ShareLink` 에 넘기므로 **iOS 코드 변경 불필요**
- 롤백: `application.yml` 의 디폴트만 `.app/i` 로 되돌리면 즉시 복귀. ADR-0007 은 보존(historical record).
- DB 마이그레이션 없음 / Breaking API 없음 / 인증 경계 변경 없음

## (Optional) 후속 / 관련 이슈

- iOS Universal Link 설정 (`Associated Domains` 에 `applinks:kicklog.org` 추가, AASA 파일 `https://kicklog.org/.well-known/apple-app-site-association` 호스팅) — 사용자가 Xcode + 도메인 호스팅 측에서 별도 작업
- 향후 `api.kicklog.org` 서브도메인 + 인증서(Let's Encrypt) 발급 — ADR-0006 후속 작업으로 분리

## (Optional) 학습 기록

- **Trigger**: production-risk (도메인 mismatch 가 TestFlight 출시 직전에 발견됨)
- **Root cause**: 백엔드 상수 하드코딩 + 도메인 결정이 ADR 에 명문화되지 않아 문서/구현 drift 발생
- **Prevention**: 외부 사용자 노출 URL 은 `@ConfigurationProperties` 로 외부화하고 도메인 결정은 ADR 로 명문화
- **Promoted to**: 본 PR 의 ADR-0007 자체가 prevention. 별도 learning.md 등재는 불필요 (1회성 mismatch).

---

## TDD 작업 흐름

1. ✅ EXEC_PLAN 작성 완료
2. 🔴 RED: `InvitationServiceTest` 수정 + 신규 케이스 1개 추가 → `./gradlew test` 실패 확인
3. 🟢 GREEN: `InvitationProperties` 신설 + `InvitationService` 외부화 + `application.yml` / `KicklogApplicationTests` 프로퍼티 추가 → 통과
4. 🔵 REFACTOR: 필요 시 (변경 규모 작아 생략 가능)
5. 📄 문서 갱신 (ADR-0007 / ADR-0003 / api-spec / api-conventions / manual-checklist / ADR-0006)
6. ✅ `./gradlew check` 최종 통과
7. 🔍 code-reviewer 호출
8. 📤 `/pr-guide` 로 PR
