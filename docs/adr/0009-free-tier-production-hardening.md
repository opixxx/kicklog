# ADR-0009: Free Tier 안에서 운영 인프라 격상 (Immutable Deploy + 관측·예산·SSH 토글)

- **Status**: Accepted
- **Date**: 2026-05-27
- **선행 ADR**: ADR-0006 (호스팅), ADR-0008 (CD via SSM)

## Context

PR #47/#49 머지 후 자동 배포 (SSM + S3 staging + OIDC) 가 동작 중이지만 다음 리스크가 누적되어 있다.

1. **`latest` 태그 의존** — 어떤 빌드가 prod 인지 즉시 식별 불가, 롤백 시 직전 SHA 를 모름. ADR-0008 의 "후속" 섹션에 immutable tag 가 미해결로 남아 있었다.
2. **관측·예산 부재** — NAT/ALB/Multi-AZ 등을 실수로 추가했을 때 청구서 도착 전까지 감지 채널이 없다. EC2/RDS 장애도 사용자 신고에 의존.
3. **RDS 백업/복구 미검증** — `backup_retention_period=1` 만 설정되어 있고 실제 복원 절차는 한 번도 리허설 안 됨.
4. **SSH 22 break-glass 정책 미확정** — ADR-0008 D6 에서 "유지" 결정, "안정 운영 후 별도 PR" 로 미뤘으나 그 별도 PR 이 본 ADR.
5. **Terraform state 로컬 단일 파일** — 사용자 머신 분실 시 state 잃음 (ADR-0006 D8 후속).

전제 — **NAT/ALB/Multi-AZ/ECS/Fargate 도입 금지, EC2 t3.micro × 1·RDS db.t3.micro Single-AZ 유지, RDS 20GB 한도, 새 public IPv4 금지.** 본 ADR 은 그 안에서 가능한 격상만 다룬다.

---

## Decisions

### D1. Image tag — **Immutable git SHA**, `latest` 제거

- **선택**: `infra/docker-compose.prod.yml` 의 image 라인을
  `ghcr.io/opixxx/kicklog:${KICKLOG_IMAGE_TAG:?...}` 로 변경.
  배포 시 cd.yml 이 `/opt/kicklog/.env.deploy` 에 `KICKLOG_IMAGE_TAG=<full sha>` 를 기록.
- **고려한 옵션**:
  - (A) `docker-compose.override.yml` 동적 생성 — 파일 2개 관리 복잡
  - (B) `envsubst` 로 SHA 치환된 compose 생성 — 산출물이 매번 달라 진단 어려움
  - (C) **`${KICKLOG_IMAGE_TAG}` env var + 별도 `.env.deploy`** — 원본 compose 는 SoT 그대로, SHA 만 분리. **채택**
- **이유**:
  - `${VAR:?msg}` 표현으로 누락 시 compose 가 **즉시 abort** → "어디서 온 이미지인지 모를" 상황 자체 차단
  - `.env` (secrets) 와 `.env.deploy` (SHA) 가 별도 — secrets 회전과 배포 SHA 가 직교
  - 직전 SHA 를 `/opt/kicklog/.deploy/previous-tag` 에 저장 → 자동 롤백 가능 (D2)

### D2. CD — SHA pull + **헬스 실패 시 자동 롤백**

- **선택**: cd.yml `deploy` job 의 SSM 스크립트가
  1. 직전 SHA 백업 → 새 SHA 로 `.env.deploy` 갱신
  2. `docker compose --env-file .env --env-file .env.deploy pull && up -d`
  3. 60초 헬스체크 (`/actuator/health` 6회 폴링)
  4. 실패 시 직전 SHA 로 자동 롤백 + 헬스체크 재시도 → workflow 는 fail 로 보고
- **이유**:
  - prod 가 깨진 채로 머무는 시간을 1~2분으로 제한
  - 롤백 대상 SHA 는 항상 직전 정상 배포 (current-tag → previous-tag)
  - 다시 실패하면 SSM Session Manager 로 수동 개입 (D4)

### D3. 관측성 — **SNS + CloudWatch Alarms + Budget**

- **선택**: `infra/terraform/observability.tf` + `budget.tf` 신규.
  - SNS topic `kicklog-alerts` + **AWS managed KMS key (`alias/aws/sns`) 로 SSE 활성** + (optional) email subscription
  - Alarms 4종:
    - EC2 `StatusCheckFailed` (1분 ×2)
    - EC2 `CPUUtilization` ≥ 90% (5분 중 3분)
    - RDS `CPUUtilization` ≥ 85% (5분 중 3분)
    - RDS `FreeStorageSpace` ≤ 4 GiB (5분 ×2) — 20GB 한도의 20%
  - `aws_cloudwatch_log_group /kicklog/userdata retention=30d` — 미래 로그 push 시 비용 폭증 방지 + 단기 audit
  - `aws_budgets_budget` monthly $5 (변수) + 80% actual / 100% actual / 100% forecast 알림 → SNS + email
- **고려한 옵션**:
  - CloudWatch Synthetics (canary) — 월 $0.0012/run, 5분 주기면 ~$0.4/m. 후속 검토.
  - Container Insights — t3.micro 메모리 압박, 비채택.
- **이유**:
  - CloudWatch 알람 10개까지 Free, 본 PR 4개 사용 → 추가 비용 0
  - Budget 리소스 무료, 알림 SNS 도 1,000 publication/m 까지 Free
  - email subscription 은 `alert_email = ""` 이면 생성 안 함 (1인 MVP 환경 친화)
  - **SNS SSE**: AWS managed key `alias/aws/sns` 는 추가 비용 0 — 정공법 (SonarQube hotspot 해소). 본 토픽의 메시지는 알람 메타데이터뿐이라 PII/secret 없음, 고객 관리 CMK ($1/m + API 비용) 는 과잉
  - **Log retention 30d**: SonarQube "short retention" hotspot 해소 + Free Tier 5GB storage 안에 들어옴
- **비용 함정 주의**:
  - CloudWatch Logs ingestion 5GB/m 초과 시 GB 당 $0.50 → user-data 로그 1회 약 5KB 라 무시 가능
  - Alarm 개수 10개 초과 시 알람당 월 $0.10 — 본 PR 미사용

### D4. SSH 22 — **분리된 rule + count 토글 (기본 false)**

- **선택**: `aws_security_group_rule.ec2_ssh_break_glass` 를 SG 본체와 분리하고 `count = var.enable_ssh_inbound ? 1 : 0` 으로 토글.
  - `enable_ssh_inbound` 변수 기본값 = **false**
  - `allowed_ssh_cidr` 는 그대로 두되 toggle 이 false 면 무시 (placeholder default = `127.0.0.1/32`)
- **고려한 옵션**:
  - (A) ADR-0006 D10 처럼 22 ingress 를 항상 켜고 본인 IP/32 — 키 분실/유출 위험 잔존
  - (B) 22 ingress 완전 삭제, 변경 불가 — 사고 대응 채널 0
  - (C) **toggle 변수로 평시 false / 비상 true** — 채택
- **이유**:
  - 평시 공격 표면 ↓ — TCP 22 자체가 인터넷에서 보이지 않음
  - SSM Session Manager + SSM Run Command 로 SSH 대체 가능 (ADR-0008 인프라 그대로)
  - 사고 시 `terraform apply -var enable_ssh_inbound=true -var allowed_ssh_cidr=$(curl -s ifconfig.me)/32` 한 줄로 활성화 → 작업 후 다시 false 로 apply
  - ADR-0008 D6 "안정 운영 후 별도 PR" 의 후속

### D5. RDS SG — **EC2 SG 5432 only 재검증 + 주석 강화**

- **선택**: `aws_security_group.rds` 의 ingress 가 `security_groups = [aws_security_group.ec2.id]` 한 줄만, egress 비명시 (terraform default = 빈 set). publicly_accessible=false 와 함께 이중 방어.
- **이유**:
  - 코드 리뷰 시 "혹시 cidr_blocks 가 추가되어 있나?" 의문이 즉시 사라지도록 주석 강화
  - 실질 변경은 없음 — 정책 명문화

> **함정 (학습)**: AWS Security Group 의 `description` 필드는 **immutable**.
> 변경하려면 SG replace 가 필요하고, RDS-attached SG 의 ENI 는 RDS service 가 관리해서 사용자가 admin 이어도 detach 불가 (`AuthFailure`). 따라서 운영 중인 SG 의 description / name 은 손대지 않는다. 정책 추가 정보는 **HCL 주석** 으로만 남긴다. (1차 apply 실패 → 본 ADR 머지 전 보정)

### D6. Terraform state — **S3 backend 이전은 본 PR 미적용**

- **선택**: 본 PR 은 `docs/runbook/terraform-s3-backend-migration.md` 체크리스트만 작성. 실제 마이그레이션은 별도 PR.
- **이유**:
  - chicken-and-egg — bootstrap bucket·DynamoDB lock table 자체를 terraform 으로 만들면 state 가 다시 로컬에서 시작. 별도 bootstrap module 필요.
  - 본 PR 은 infra/observability/CD 변경이 이미 큰데, state migration 까지 한 PR 에 묶으면 롤백 단위가 커짐
  - 1인 MVP 단계에서 state 동시 편집 충돌이 발생할 일이 없음 → 긴급도 낮음
  - 비용: S3 (수 KB) + DynamoDB on-demand lock = 월 < $0.05, 부담 없음 → 향후 별도 PR 우선순위 상

### D7. RDS 백업 — **분기별 복원 리허설 절차 코드화**

- **선택**: `docs/runbook/rds-restore-rehearsal.md` 에 절차 작성.
  - 자동 스냅샷 (현재 `backup_retention_period=1`) 또는 수동 스냅샷에서 `--db-snapshot-identifier` 로 신규 인스턴스 복원
  - 임시 인스턴스 endpoint 에 psql 접속 → `SELECT COUNT(*)` sanity check
  - 즉시 delete (Free Tier 인스턴스 시간 보호)
- **이유**:
  - 실제 사고 시 "백업이 있다" ≠ "백업으로 복구한다" — 한 번이라도 해본 사람만 복구 가능
  - 비용: 스냅샷은 가장 최근 + 백업 보존 기간 + manual 1개 만 유지 → 무료 한도 안

### D8. Backup retention — **현 상태 유지** (1일)

- **선택**: `backup_retention_period = 1` 그대로. 7일 회복은 Free Tier 졸업 후.
- **이유**:
  - RDS Free Tier 는 backup_retention_period ≤ 1 만 무료 (스냅샷 스토리지가 free tier RDS 와 같은 크기까지만 무료)
  - 7일로 늘리면 스냅샷 크기가 db 크기 × 7 / 7일 평균 ≈ db 크기 1개 분량 → 무료 한도 안에 들지만 변경 폭이 별도 검토 필요
  - 본 PR 은 절차 (D7) 만 마련하고 retention 변경은 13개월 후 별도 ADR

---

## 비용 영향

| 항목 | 변경 전 | 변경 후 | 월 비용 차이 |
|---|---|---|---|
| GHCR push (latest + sha) | 2 태그/배포 | 1 태그/배포 (sha) | ~0 (GHCR private 1GB 무료) |
| S3 staging | 1 객체 | 1 객체 | 0 |
| Secrets Manager (~4 secrets) | 동일 | 동일 | 0 |
| CloudWatch Alarms 4개 | 0 | 4 | $0 (Free 10개) |
| CloudWatch Log Group (7d retention) | 0 | 1 (미사용 — 미래 대비) | 0 (ingestion 시에만) |
| SNS topic + (email) sub | 0 | 1 + 0~1 | 0 (Free 1,000 publication/m) |
| AWS Budgets | 0 | 1 | 0 (계정당 2개 무료) |
| RDS 백업 리허설 (분기 1회 ~1h) | 0 | ~1h × db.t3.micro | $0 (Free Tier 750h 안) |
| **합계 (12개월 Free 기간)** | ~$2 | **~$2** | **0** |
| **합계 (Free Tier 졸업 후)** | ~$24 | **~$24** | **0** |

### 비용 폭증 함정 (본 PR 이 막는 것)

- NAT Gateway 실수 추가 ($30/m) → Budget 80% 임계가 1주 안에 알람
- idle EIP — 본 PR 에 변화 없음 (이미 EIP 1개 attached, 인스턴스 중지 시에만 과금)
- CloudWatch Logs ingestion 초과 — 본 PR 의 retention=7d 가 자동 만료
- Multi-AZ 실수 활성화 — 본 PR 에 변화 없음, ADR-0006 D2 그대로

---

## 보안 영향

| 영역 | 변경 전 | 변경 후 |
|---|---|---|
| Image 출처 | `latest` (변동) | git SHA (불변) — supply chain 추적 가능 |
| CD 롤백 | 수동 SSH 필요 | 자동 + SSM 수동 fallback |
| SSH 22 ingress | 본인 IP/32 상시 열림 | 평시 닫힘, break-glass 시만 toggle |
| RDS 접근 경계 | EC2 SG 5432 only | 동일 (정책 명문화) |
| 운영 알림 | 없음 (사용자 신고 의존) | SNS + email + Budget 알람 |

---

## Consequences

### 긍정
- prod 빌드의 supply chain 이 항상 명시적 (어떤 SHA 가 도는지)
- 비용/장애를 사용자가 보고하기 전에 SNS 가 먼저 도착
- SSH 공격 표면 평시 0 — SSM 만 노출
- AWS 학습 가치 — CloudWatch Alarms / Budgets / SNS / SG toggle 패턴

### 부정 / 감수
- cd.yml 의 SSM 스크립트가 길어짐 (heredoc + 롤백 분기) → 디버깅 시 SSM stdout 가독성 ↑ 필요
- 첫 배포 시 `previous-tag` 가 없어 롤백 불가능 → "실패 시 수동 개입" 경고만 출력
- SSM Session Manager 학습 1회 (사용자가 한 번도 안 써본 경우)
- email 알림 신규 — confirm 메일 1회 클릭 필요

### Risk = Risky
- CD 파이프라인·IAM·SG·observability 동시 변경. 롤백 절차:
  1. PR revert (compose `latest` 복귀 + cd.yml 이전 버전)
  2. `terraform destroy -target=<alarm/budget/sns>` 또는 전체 PR revert + apply
  3. 본인 IP 변경 시 `terraform apply -var enable_ssh_inbound=true -var allowed_ssh_cidr=$(curl -s ifconfig.me)/32` 임시 활성화

---

## 머지 후 사용자 수동 작업

1. (선택) `terraform.tfvars` 에 `alert_email = "you@example.com"` 추가
2. `terraform plan` — 신규 리소스만, 삭제 0 확인 (특히 SG ingress diff)
3. `terraform apply`
4. SNS 확인 메일 → confirm 클릭
5. `terraform output sns_alerts_topic_arn budget_name` 으로 콘솔 확인
6. (별도 PR 후속) S3 backend migration — `docs/runbook/terraform-s3-backend-migration.md` 절차

---

## 후속 (별도 PR)

- ADR-0006 D8 — Terraform state S3 backend 이전 (체크리스트 작성 완료)
- ADR-0006 졸업 후 (~2027-05) — RDS `backup_retention_period` 1 → 7
- ADR-0007 후속 — Let's Encrypt + 도메인 → HTTPS 알람 추가
- CloudWatch Synthetics canary (`/actuator/health` 외부 폴링) — 월 ~$0.4
- ADR-0006 D10 후속 — SSH key pair 자체 회전·삭제 (SSM 만 사용 정착 후)

---

## Revisions

| 날짜 | 변경 | 사유 |
|---|---|---|
| 2026-05-27 | 초기 작성 | Free Tier 안에서 운영 격상 — immutable tag + 알람 + 예산 + SSH 토글 + 백업 리허설 |
