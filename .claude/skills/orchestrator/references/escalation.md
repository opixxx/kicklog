# 에스컬레이션 — 즉시 정지 조건

다음 중 하나라도 발생하면 **즉시 작업을 멈추고** 사용자에게 보고:

## 자가수정 한계

- 자가수정 3회 연속 실패 (`self-heal-loop.md` 참조)
- 총 30분 초과 자가수정 시도
- 동일 에러 메시지 3회

## Scope Creep

- EXEC_PLAN의 변경 대상(`Affected`) 대비 실제 diff 규모 **150% 초과**
- 새 의존성 추가 (build.gradle.kts)
- 새 패키지/디렉토리 생성
- 의도하지 않은 마이그레이션 작성

## 데이터 무결성

- **DB 마이그레이션** 필요한 변경 (Flyway V2+) — 사용자 확인 필수
- **Breaking API** 변경 (기존 endpoint 시그니처 변경, 응답 형식 변경)

## 보안 경계

- **인증/인가 변경** — JWT, Sign in with Apple, Kakao Login, friendship 권한
- **PII 처리** — 사용자 이메일·display_name
- **카카오 API 키 노출 가능성** — 환경변수에서 안전하지 않은 곳으로 이동
- **AWS IAM 권한** 변경 — terraform 적용 시 권한 확장

## 외부 의존

- **카카오 API 통합** 변경 — Local API 엔드포인트 변경, OAuth 흐름 변경
- **AWS 인프라** 변경 — terraform plan에서 비싼 리소스 추가 감지 (NAT, ALB, RDS 큰 인스턴스)

## 비용 영향

- AWS terraform plan에서 **새 비용 리소스** 등장
- 카카오 API 호출량 급증 가능성 (캐시 무효화 등)
- 동기화 정책 변경으로 백엔드 호출량 증가

---

## 에스컬레이션 보고 양식

```markdown
🛑 에스컬레이션 — 사람 결정 필요

**유형**: <자가수정 한계 | scope creep | DB 마이그레이션 | Breaking API | 보안 | 외부 의존 | 비용>

**현재 상태**:
- 진행한 단계: <Phase X 완료, Phase Y 진행 중>
- 마지막 시도: <간단 요약>
- 차단 사유: <구체적>

**필요한 결정**:
- <옵션 A> (예: "친구 권한 검증 어떻게?")
- <옵션 B>
- <옵션 C>

**관련 ADR/문서**:
- <docs/adr/...>
```
