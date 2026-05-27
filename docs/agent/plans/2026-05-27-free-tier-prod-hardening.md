# EXEC_PLAN — free-tier-prod-hardening

| 항목 | 값 |
|---|---|
| Task | free-tier-prod-hardening |
| Type | chore |
| Branch | chore/free-tier-prod-hardening |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/free-tier-prod-hardening |
| Port | 9000 (사용 안 함 — infra/docs 작업) |
| 생성 시각 | 2026-05-27 20:04 |
| 상태 | `draft` |
| 개발 방식 | infra/docs (Kotlin TDD 비대상 — Terraform plan + YAML lint 로 대체) |

---

## 1. 목표 (Goal)

KickLog MVP 운영 환경을 **AWS Free Tier 한도 안에서 "베스트 프랙티스" 수준으로 격상**시킨다.
ALB / NAT / Multi-AZ / ECS 같은 비용 폭증 리소스는 도입하지 않는다. 대신 **재현 가능성·롤백 가능성·관측 가능성**을 끌어올린다.

핵심 동기:
- 현재 `latest` 태그 의존 → 어떤 빌드가 배포되어 있는지 불확실 + 롤백 불가 (ADR-0008 "후속" 항목).
- 알람·예산이 없어서 비용 사고를 늦게 발견할 위험 (NAT 실수 추가, idle EIP 등).
- RDS 백업/복구 절차가 문서화되어 있지 않아 실제 사고 대응 시 작동 보장 X.
- Terraform state 가 로컬 단일 파일 → 머신 잃으면 인프라 history 잃음 (ADR-0006 D8 후속).

## 2. 접근 (Approach)

### 2.1 Immutable image tag — `latest` 제거

- `infra/docker-compose.prod.yml`
  - `image: ghcr.io/opixxx/kicklog:latest` → `image: ghcr.io/opixxx/kicklog:${KICKLOG_IMAGE_TAG:?KICKLOG_IMAGE_TAG 가 비어 있습니다}`
  - **default 안전장치 없음**: tag 가 비면 compose 가 즉시 실패 → "어디서 온 이미지인지 모를" 상황 자체 차단.
  - env_file 은 그대로 `.env` 만 — secrets/profile/포트 라인은 변동 없음.
- 배포 시점에 EC2 의 `/opt/kicklog/.env.deploy` 에 `KICKLOG_IMAGE_TAG=<full-sha>` 한 줄을 작성하고 `docker compose --env-file .env --env-file .env.deploy pull/up` 으로 주입.
- 직전 SHA 는 `/opt/kicklog/.deploy/previous-tag` 에 저장 → 롤백 시 사용.

### 2.2 cd.yml SHA 파이프라인 + 자동 롤백

- `build-and-push` job: 태그를 `${{ github.sha }}` 한 개로 통일 (`latest` 제거).
- `deploy` job: SSM 스크립트가
  1. 직전 태그 백업 (`previous-tag`)
  2. 새 SHA 를 `current-tag` 로 기록 → `.env.deploy` 갱신
  3. `docker compose --env-file .env --env-file .env.deploy pull && up -d`
  4. 60초 헬스체크
  5. 실패 시 `previous-tag` 로 자동 롤백 + 헬스체크 + non-zero exit
  6. 성공 시 7d 이상 된 이미지/dangling 정리

### 2.3 Terraform 보강

- `infra/terraform/observability.tf` (신규):
  - `aws_sns_topic` `kicklog-alerts` + email subscription (변수)
  - CloudWatch alarms:
    - EC2 `StatusCheckFailed` (sum, 2 of 2 minutes)
    - EC2 `CPUUtilization` ≥ 90% (avg, 3 of 5 minutes — t3 burstable credit 고갈 신호)
    - RDS `CPUUtilization` ≥ 85%
    - RDS `FreeStorageSpace` ≤ 4GiB (20GB 의 20%)
  - `aws_cloudwatch_log_group` `/kicklog/userdata` retention=7d (이미 EC2 가 CloudWatchAgentServerPolicy 보유 — 로그 그룹만 명시).
- `infra/terraform/budget.tf` (신규):
  - `aws_budgets_budget` monthly $5 (Free Tier 사용 중) + 80%/100% forecast + actual 알림 → SNS + email.
- `infra/terraform/variables.tf` 추가:
  - `alert_email` (string, optional — 빈 문자열이면 subscription 생성 안 함)
  - `budget_monthly_usd` (number, default = 5)
  - `enable_ssh_inbound` (bool, default = true — break-glass 유지)
  - `allowed_ssh_cidr` 는 그대로 두되 `enable_ssh_inbound=false` 이면 ingress 자체를 생략.
- `infra/terraform/network.tf`:
  - SSH ingress 를 `count = var.enable_ssh_inbound ? 1 : 0` 로 토글 가능하게.
  - RDS SG 가 EC2 SG 5432 만 허용하는지 재검증 (이미 OK — 주석으로 명시 강화).
- `infra/terraform/outputs.tf`:
  - `sns_alerts_topic_arn`, `budget_name` 추가.

### 2.4 docs 보강

- `docs/adr/0009-free-tier-production-hardening.md` (신규):
  - D1 immutable tag, D2 자동 롤백, D3 알람·예산, D4 SSH 토글 유지, D5 S3 backend 보류, D6 백업 리허설 정책.
- `docs/runbook/free-tier-cost-traps.md` (신규):
  - EC2/RDS 750h, RDS 20GB, Public IPv4 750h, idle EIP, NAT 금지, Multi-AZ, 스냅샷 초과 — 각 항목의 monitoring 위치 + AWS 청구 라인 항목.
- `docs/runbook/rds-restore-rehearsal.md` (신규):
  - 분기별 1회 자동 스냅샷 → 임시 인스턴스 restore → `psql` 로 sanity check → 즉시 delete 절차.
- `docs/runbook/terraform-s3-backend-migration.md` (신규):
  - bootstrap bucket + state lock (S3 native lockfile 또는 DynamoDB) 선택지, `terraform init -migrate-state` 절차, 롤백 절차, 본 PR 미적용 사유.
- `infra/terraform/README.md` 갱신:
  - SSH 토글 / SNS / Budget / alert_email 변수 안내.

### 2.5 양보 불가 규칙

- ❌ NAT Gateway / ALB / Multi-AZ / ECS / Fargate / 새 public IPv4 / RDS 스토리지 20GB 초과 추가
- ❌ 백엔드 컨테이너 publish 를 `0.0.0.0` 으로 노출
- ❌ `latest` 태그 의존 (compose 파일·SSM 스크립트 모두)
- ❌ `--no-verify` 등 자가수정 우회
- ✅ 모든 신규 리소스는 비용 영향을 ADR-0009 의 "비용 영향" 표에 기록
- ✅ Terraform 변경은 `terraform fmt` + `terraform validate` 통과
- ✅ YAML 은 Python `yaml.safe_load()` 파싱 통과

## 3. 테스트 케이스 (Test Cases)

> 본 작업은 Kotlin 비대상 — `backend-test-writer` 호출 없음.
> 대신 **계산적 검증** (terraform plan / fmt / validate, YAML 파싱) 으로 RED→GREEN 사이클 대체.

### 검증 시나리오

#### Happy Path
- [ ] `terraform fmt -recursive -check infra/terraform` → exit 0
- [ ] `terraform validate` (infra/terraform 디렉토리) → success
- [ ] `terraform plan` (apply 안 함) → 의도된 신규 리소스만 추가 (`aws_sns_topic`, `aws_cloudwatch_metric_alarm` ×4, `aws_cloudwatch_log_group`, `aws_budgets_budget`, optional subscription) — NAT/ALB/Multi-AZ 0개.
- [ ] `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' .github/workflows/cd.yml` → exit 0
- [ ] `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' infra/docker-compose.prod.yml` → exit 0
- [ ] `docker compose -f infra/docker-compose.prod.yml --env-file /dev/null config 2>&1 | grep -q "KICKLOG_IMAGE_TAG"` → 누락 시 명확히 실패하는지 확인 (best-effort, docker daemon 가능 시).

#### Unhappy Path
- [ ] cd.yml 의 SSM 스크립트가 `KICKLOG_IMAGE_TAG` 미설정 상태에서 실패하는지 (compose 가 `:?` 표현으로 즉시 abort).
- [ ] 새 SHA 헬스체크 6회 실패 → 롤백 분기 진입 → 직전 SHA 로 다시 up + 헬스체크.

#### Edge Cases
- [ ] `alert_email = ""` 일 때 `aws_sns_topic_subscription` 이 생성되지 않는지 (count=0 또는 dynamic block).
- [ ] `enable_ssh_inbound = false` 일 때 EC2 SG 의 22 ingress rule 이 사라지는지 (terraform plan diff 로 확인).
- [ ] RDS SG 가 EC2 SG 외 어떤 cidr 도 허용하지 않는지 (network.tf 재검토).

### 검증 명령 (Phase 9 에서 실제 실행)

```bash
cd infra/terraform
terraform fmt -recursive -check
terraform validate
# plan 은 tfvars 와 AWS credential 있을 때만 의미 — 본 worktree 에선 validate 까지.

cd ../..
python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" .github/workflows/cd.yml
python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" infra/docker-compose.prod.yml
```

## 4. 검증 (Verification)

### 자동 검증 (Phase 3)

- terraform fmt/validate (위)
- YAML 파싱 (위)
- `git diff --stat` 으로 변경 파일·라인 수 확인 (의도된 범위 내)
- 백엔드 Kotlin compile 게이트: 본 변경에 Kotlin 코드 없으므로 N/A (Stop hook 의 compileKotlin 은 어차피 통과해야 함).

### 추론적 검증 (Phase 4)

- 본 작업은 백엔드 Kotlin 변경 0 → `code-reviewer` agent 자동 호출 트리거 없음.
- 그러나 IAM / SSM / CD 보안 변경이라 사용자 리뷰는 PR 머지 전에 필수.

### 수동 검증 (사용자 — 머지 후)

- `terraform plan` 으로 리소스 추가만, 삭제 0 확인.
- `terraform apply` 후 알람·예산 콘솔에서 가시 확인.
- 다음 PR 머지 시 cd.yml 이 SHA tag 로 동작하는지 + 의도적 헬스체크 실패 시뮬레이션 (예: 일부러 `image: ...:nonexistent` 로 푸시) 으로 롤백 동작 확인.

---

## (Optional) 위험도 / 롤백

**Risk = Risky** (IAM 정책·CD 파이프라인·관측성 동시 변경)

### 롤백 전략

| 시나리오 | 롤백 |
|---|---|
| terraform apply 직후 알람·예산이 잘못 동작 | `terraform destroy -target=<resource>` 또는 PR revert 후 `terraform apply` (state 만 회복 — 백엔드 무중단) |
| cd.yml 신 SHA 배포 실패 + 자동 롤백도 실패 | SSM Session Manager 접속 → `/opt/kicklog/.deploy/previous-tag` 의 직전 SHA 로 `docker compose up -d` 수동 실행 |
| compose 의 `${KICKLOG_IMAGE_TAG:?}` 에러로 EC2 가 컨테이너 못 띄움 | 같은 절차 — `.env.deploy` 에 마지막 정상 SHA 수동 작성 후 up |
| Free Tier 초과 알람 폭발 | SNS 구독 일시 해제 → 알람 임계 재조정 → 재구독 |

### Forward-only 항목 (롤백 불가/불필요)

- 신규 ADR/runbook docs — 롤백 시 PR revert 만으로 사라짐.
- Budget — 비용 손해 없음 (생성 자체 무료).

## (Optional) 후속 / 관련 이슈

- ADR-0008 D6 "SSH 22 룰 완전 제거" — 본 PR 에 toggle 만 추가, 실제 `false` 전환은 SSM 안정 운영 1~2주 후 별도 PR.
- ADR-0006 D8 "S3 backend 이전" — runbook 만 작성, 실제 마이그레이션은 별도 PR (state lock + bootstrap bucket 의 chicken-and-egg 풀고).
- `latest` 태그 정리: GHCR `latest` 가 더 이상 push 되지 않으므로, 기존에 push 된 `latest` 매니페스트는 GHCR UI 에서 수동 untag 권장 (CD 동작에는 무관).

## (Optional) 학습 기록

- Trigger: production-risk + 후속ADR
- Root cause: ADR-0008 채택 직후 "후속 별도 PR" 로 미뤘던 immutable tag/관측성 부재가 누적된 리스크.
- Prevention: ADR-0009 의 알람·예산·롤백 메커니즘 + runbook 으로 사고 대응 절차 코드화.
- Promoted to: `docs/runbook/*`, ADR-0009.

---

## TDD 작업 흐름 (infra 변형)

```
1. EXEC_PLAN 4섹션 확정 ← 현재
2. Compose / cd.yml 변경 (immutable tag)
3. Terraform observability/budget/SSH toggle 추가
4. Docs (ADR-0009 + runbook 3종 + README 갱신)
5. fmt + validate + YAML 파싱 (Phase 3)
6. 사용자 PR 리뷰 (Phase 5)
```

> 완료 시: `상태` 필드를 `done`으로 변경하고 PR 본문에 본 파일 링크 첨부.
