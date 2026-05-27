# ADR-0007: 운영 도메인 확정 — kicklog.org + 초대 URL 외부화

- **Status**: Accepted
- **Date**: 2026-05-27
- **선행 ADR**: ADR-0003 (친구 초대 D4 — `kicklog.app/i/{token}` 표기), ADR-0006 (호스팅 — `.app/.io/.com` 후보 보류)

## Context

ADR-0003 D4 작성 시점부터 친구 초대 링크 예시를 `kicklog.app/i/{token}` 으로 명시했고, ADR-0006 의 D? 에서도 도메인을 "정식 출시 시점에 `.app` 또는 `.io`/`.com` 등록" 으로 보류해 두었다. 그러나 사용자가 실제로 보유한 도메인은 `kicklog.org` 이며, iOS 클라이언트의 prod baseURL 도 이미 `https://kicklog.org` 로 박혀 있다.

이 상태로 TestFlight 사용 중 친구 초대 링크가 `https://kicklog.app/i/...` 로 발급되는 mismatch 가 발견됨 — 백엔드 `InvitationService.INVITATION_BASE_URL` 상수가 ADR 의 예시를 그대로 받아 하드코딩된 것이 원인.

또한 외부 사용자에게 노출되는 URL host 가 production 코드에 상수로 박혀 있으면 환경별(local/test/staging/prod) 분리·테스트 가능성이 떨어진다.

---

## Decisions

### D1. 운영 도메인 — **`kicklog.org`** 확정

- **선택**: `kicklog.org` (사용자 보유)
- **고려한 옵션**:
  - `kicklog.app` (ADR-0003 작성 시점 후보, 미보유)
  - `kicklog.io` / `kicklog.com` (미조사)
  - **`kicklog.org` — 선택**
- **이유**:
  - 사용자가 이미 보유 — 추가 구매 / 등록 비용 0
  - iOS prod baseURL 이 이미 `.org` → iOS 측 변경 불필요
  - MVP 출시 일정상 도메인 변경/추가는 비용 대비 가치 낮음

### D2. URL Base 외부화 — **`@ConfigurationProperties`**

- **선택**: `kicklog.invitation.base-url` 프로퍼티로 외부화 (`AppleProperties` 동일 패턴)
- **고려한 옵션**:
  - 상수 그대로 두고 `.org` 로만 치환 (재발 가능성 그대로)
  - `@Value("\${...}")` 직접 주입 (타입 안전성·테스트 주입 불편)
  - **`@ConfigurationProperties` 외부화 — 선택**
- **이유**:
  - 운영 도메인이 추후 바뀌어도 코드 변경 없이 env 만 갱신 가능
  - 단위 테스트에서 `InvitationProperties("https://example.test/i")` 처럼 명시 주입 가능 — 외부화 자체가 검증 대상이 됨
  - 기존 `AppleProperties` / `KakaoProperties` 와 동일 패턴으로 일관성 유지
- **구현**:
  - `backend/.../friend/service/InvitationProperties.kt` — `@ConfigurationProperties(prefix = "kicklog.invitation")`
  - `application.yml` — `kicklog.invitation.base-url: ${INVITATION_BASE_URL:https://kicklog.org/i}`
  - `InvitationService` 생성자에 `properties: InvitationProperties` 주입, `toResult()` 에서 `${properties.baseUrl}/${invitation.token}` 사용

### D3. 문서 일괄 갱신

- ADR-0003 D4 의 `kicklog.app` 예시 → `kicklog.org`
- `docs/spec/api-spec.md` — Base URL (`https://api.kicklog.app/v1` → `https://api.kicklog.org/v1`) 및 초대 URL 예시
- `docs/architecture/api-conventions.md` — 운영 API base URL + CORS 화이트리스트
- `docs/setup/manual-checklist.md` — 도메인 구매 항목
- ADR-0006 — 도메인 후보 표기 → `.org` 확정 명시

### D4. 후속 — Universal Link / AASA

- iOS `Associated Domains` 에 `applinks:kicklog.org` 추가 + `https://kicklog.org/.well-known/apple-app-site-association` 호스팅은 본 PR 범위 밖
- 사용자가 Xcode + 도메인 호스팅 측에서 별도 작업

### D5. 후속 — 백엔드 API 서브도메인

- 운영 API 는 `https://api.kicklog.org/v1` 로 갈 예정 (현재는 EC2 EIP)
- 인증서(Let's Encrypt) 발급 + DNS A 레코드 + nginx server_name 매핑은 ADR-0006 후속 작업으로 별도 PR

---

## Consequences

### 긍정
- 도메인 mismatch 가 운영 사용자에게 노출되기 전에 차단
- 외부화로 환경별 분리 가능 — 테스트·로컬·스테이징·프로덕션 격리
- 향후 도메인 변경 시 코드 변경 없이 env 변수만 갱신
- 도메인 결정이 ADR 로 명문화되어 향후 같은 결정을 두 번 하지 않음

### 부정 / 감수
- 운영 EC2 / systemd unit 의 환경변수에 `INVITATION_BASE_URL` 을 명시 주입할 필요는 **없음** (application.yml 디폴트가 이미 `.org`). 단, staging 환경 분리 시점에는 명시 주입 권장.

### Risk = Caution
- 응답 포맷 자체는 그대로이고 URL host 만 바뀜
- iOS 는 응답의 `url` 필드를 그대로 `ShareLink` 에 넘기므로 클라이언트 변경 불필요
- 롤백: `application.yml` 디폴트를 `.app/i` 로 되돌리면 즉시 복귀

---

## Notes

- ADR-0005 는 결번
- 본 ADR 작성 동기: TestFlight 사용 중 mismatch 발견 (production-risk trigger). 외부화 + ADR 명문화가 prevention.
