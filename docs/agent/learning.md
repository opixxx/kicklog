# Agent Learning Journal

자가수정, Critical 리뷰, 테스트 누락, 운영 리스크가 반복되지 않도록 실패를 재사용 가능한 규칙으로 승격하는 기록이다.

## When to Record

- `SELF_HEAL_ATTEMPT`가 trajectory에 남았다.
- `code-reviewer`가 Critical 또는 반복 Major를 지적했다.
- `backend-test-writer`가 누락된 인수/회귀 테스트를 발견했다.
- 구현이 테스트는 통과했지만 실제 의도와 어긋날 수 있는 reward hacking 가능성이 있었다.

## Promotion Rule

실패가 일회성 오타면 trajectory만 남긴다.
다음 중 하나라도 해당하면 이 파일과 관련 하네스를 갱신한다.

- 같은 유형이 2회 이상 반복될 수 있다.
- 보안, 인증, 인가, PII, 외부 API, DB 마이그레이션과 관련된다.
- 테스트가 없었다면 운영에서만 발견됐을 문제다.
- EXEC_PLAN에 적었다면 막을 수 있었던 누락이다.

## Update Targets

- `tools/templates/EXEC_PLAN.template.md`: 계획 단계에서 반드시 떠올려야 하는 항목.
- `.codex/agents/code-reviewer.md` / `.claude/agents/code-reviewer.md`: 리뷰 체크리스트로 잡아야 하는 항목.
- `.codex/agents/backend-test-writer.md` / `.claude/agents/backend-test-writer.md`: 테스트 작성 규칙으로 잡아야 하는 항목.
- `docs/spec/test-strategy.md`: 프로젝트 전체 테스트 전략.
- `docs/architecture/*.md` 또는 `docs/adr/*.md`: 설계 결정이나 운영 정책.

## Entry Template

```md
### YYYY-MM-DD — <pattern name>

- Trigger: self-heal | review-critical | missing-test | production-risk | security
- Task/PR:
- Failure:
- Root cause:
- Fix applied:
- Prevention:
- Updated:
  - [ ] EXEC_PLAN template
  - [ ] code-reviewer
  - [ ] backend-test-writer
  - [ ] test strategy
  - [ ] architecture/ADR
- Skip reason if not promoted:
```

## Learned Patterns

<!-- Add promoted learnings below. Keep entries short and actionable. -->

### 2026-05-27 — AWS Security Group description/name 은 immutable, RDS-attached 일 때 변경 불가

- Trigger: production-risk
- Task/PR: PR #50 (free-tier-prod-hardening), 1차 apply 실패
- Failure: `terraform apply` 가 RDS SG 를 destroy 시도 → `AuthFailure: detaching RDS ENI` 로 중단
- Root cause: SG `description` 변경을 정책 명문화 목적으로 추가했는데, AWS SG description 은 immutable → terraform 이 SG replace 시도 → RDS-managed ENI 는 RDS service 가 관리해 사용자(admin 포함)가 detach 불가
- Fix applied: SG description/name 을 ADR-0006 원본 그대로 복원. 정책 추가 정보는 HCL 주석으로만 남김
- Prevention:
  - 운영 중인 `aws_security_group` 의 `description` 과 `name` 은 한 번 정한 뒤 손대지 않는다 (정책 변경 시 ingress/egress rule 만 수정)
  - 표현 개선 / 정책 메모는 HCL 주석으로
  - `terraform plan` 출력에 `# forces replacement` 가 SG/EBS/IAM 등 stateful 리소스에 보이면 즉시 정지하고 사용자 확인
- Updated:
  - [x] architecture/ADR — ADR-0009 D5 에 함정 노트 추가
  - [x] code-reviewer (백엔드 전용이라 본 항목은 infra reviewer 가 생기면 이전)
  - [ ] EXEC_PLAN template
  - [ ] backend-test-writer (N/A — infra)
  - [ ] test strategy (N/A — infra)
- Skip reason if not promoted: N/A
