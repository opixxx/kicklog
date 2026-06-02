# EXEC_PLAN — loadtest-replica-infra

| 항목 | 값 |
|---|---|
| Task | loadtest-replica-infra |
| Type | chore (infra) |
| Branch | chore/loadtest-replica-infra |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/loadtest-replica-infra |
| Port | 9000 |
| 상태 | `ready` |
| 개발 방식 | Terraform (fmt → validate → plan, apply 는 사용자) |

---

> **트랙 C Phase 1** — 복제 부하테스트 환경 IaC. 백엔드 소스 변경 없음(인프라 전용).
> ATDD 면제 (백엔드 코드 아님) — 검증은 `terraform fmt/validate/plan`.

## 1. 목표 (Goal)

prod(t3.micro)는 작아 부하 시 인프라가 먼저 포화된다. **인프라 천장을 걷어내고 순수 API 코드/쿼리 병목을 측정**하기 위해, prod 보다 넉넉한 일회성 복제 환경을 Terraform 으로 구축한다. 끝나면 `destroy`. **prod state 와 완전 분리**(별도 디렉토리 + 독립 로컬 state)해 운영 리소스를 절대 건드리지 않는다.

## 2. 접근 (Approach)

**신규 디렉토리**: `infra/terraform-loadtest/` (prod `infra/terraform/` 와 독립 — state 물리 분리)

**운영 전용 리소스 제거**: Secrets Manager / GitHub OIDC / certbot·EIP / CD(SSM) / S3 / budget·SNS / observability 전부 제외 (부하테스트에 불필요).

**리소스 구성**:
- `network.tf` — VPC(10.1.0.0/16) + public subnet a/c + IGW + route + SG 3개
  - backend SG: 8080 ← loadgen SG, 22 ← admin IP(옵션), egress all
  - loadgen SG: 22 ← admin IP, egress all
  - rds SG: 5432 ← backend SG
- `ec2.tf` —
  - backend EC2 (`t3.large`): user-data 가 docker + GHCR pull + `SPRING_PROFILES_ACTIVE=loadtest` 로 8080 직접 노출 (nginx hop 제거 — 측정 목적이 코드/쿼리). IAM: SSM 접속용.
  - loadgen EC2 (`c5.large`): docker + grafana/k6 준비 (네트워크 변수 제거 위해 같은 VPC)
- `rds.tf` — `db.t3.medium` PostgreSQL 16, **Performance Insights 켬**(쿼리 병목 관찰), `deletion_protection=false` + `skip_final_snapshot=true`(일회성, destroy 친화), backup_retention=0
- `outputs.tf` — backend public IP, loadgen public IP, rds endpoint
- `templates/user-data-backend.sh.tftpl`, `templates/user-data-loadgen.sh.tftpl`
- `terraform.tfvars.example` + `.gitignore`(*.tfstate, *.tfvars) + `README.md`(apply/destroy/비용)

**시크릿**: Secrets Manager 없이 `terraform.tfvars`(gitignore)로 `rds_password`/`jwt_secret`(더미, 32자+)/`ghcr_pat`/`backend_image_tag` 주입. Kakao 키 불필요(측정 핫스팟에서 제외).

**양보 불가**:
- prod `infra/terraform/` 파일·state 무수정 (별도 디렉토리)
- backend 이미지는 **loadtest 코드 포함 이미지**(PR #62 merge 후 CD 빌드 SHA, 또는 수동 build/push)여야 `/loadtest/*` 동작

## 3. 테스트 케이스 (Verification 으로 대체)

인프라 코드 — ATDD 면제. 아래 "4. 검증" 의 terraform 명령으로 갈음.
- Happy: `terraform validate` 통과 + `terraform plan` 이 backend EC2·loadgen EC2·RDS·VPC·SG 를 생성 예정으로 표시
- Unhappy: tfvars 누락(ssh_key_name 등) 시 plan 단계에서 명확히 실패

## 4. 검증 (Verification)

```bash
cd infra/terraform-loadtest
terraform init           # provider 다운로드 (credentials 불필요)
terraform fmt -check     # 포맷
terraform validate       # 문법/참조 검증
# ↓ 사용자가 직접 (AWS credentials + 과금)
terraform plan -out=tfplan
terraform apply tfplan
# 부하테스트 종료 후
terraform destroy
```

## (Optional) 위험도 / 롤백

- **Risk = Risky** (실 AWS 리소스·과금). 단 **prod state 물리 분리**로 운영 파괴 위험은 차단. 롤백 = `terraform destroy` + 디렉토리 삭제.
- 비용: backend t3.large + loadgen c5.large + RDS db.t3.medium ≈ 시간당 $0.3, 반나절 ~$2. `destroy` 로 종료.

## (Optional) 후속

- Phase 2(관찰: node/postgres exporter, RDS PI 대시보드) → Phase 3(k6 시나리오) → Phase 4(튜닝 before/after) → Phase 5(destroy). 결과 ADR-0011.

## (Optional) 학습 기록

- Trigger: none (작성 시점)
