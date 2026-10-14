# Runbook — AWS Free Tier 비용 함정 (KickLog)

이 문서는 **이미 만들어진 인프라가 의도치 않게 과금 한도를 넘는 시나리오** 와 **감지·대응** 방법을 모은 SoT 다.
ADR-0006 (호스팅), ADR-0008 (CD via SSM), ADR-0009 (Free Tier 운영 격상) 와 함께 읽는다.

> 본 인프라는 **`ap-northeast-2` (서울 region)** 기준. 작성 시점 = 2026-05-27.
>
> ⚠️ **2026-10-02 경 Free plan 크레딧이 소진되어 실과금으로 전환됐다** (실측 월 약 $45).
> **2026-10-13 ADR-0016 으로 RDS 를 폐지하고 ARM 단일 박스로 통합해 월 약 $25 로 내렸다.**
> 아래 "Free Tier 한도" 표의 EC2/RDS 항목은 역사적 기록이며, 현재 구성은 다음과 같다:
>
> | 항목 | 월 |
> |---|---|
> | EC2 t4g.small (arm64) | 약 $15.2 |
> | EBS gp3 30GB (루트) | $2.74 |
> | EBS gp3 20GB (pgdata) | $1.82 |
> | Public IPv4 | $3.65 |
> | SSM Parameter Store · Lambda · 알람 4개 · S3 | 약 $0.1 |
> | **합계 (VAT 포함)** | **약 $25** |
>
> RDS·Secrets Manager 항목은 더 이상 존재하지 않는다.

---

## 1. Free Tier 한도 요약

| 리소스 | Free Tier | KickLog 현재 사용 | 위험 시나리오 |
|---|---|---|---|
| EC2 t2.micro/t3.micro | 750h/m (인스턴스 시간) | 1대 24/7 ≈ 720h | 인스턴스 2대 동시 가동 시 즉시 초과 |
| RDS db.t2.micro/db.t3.micro | 750h/m | 1대 24/7 ≈ 720h | Multi-AZ 활성화 시 2배 = 1,440h |
| RDS gp2 storage | 20 GB | `rds_storage_size_gb = 20` | autoscaling 또는 수동 확장 시 즉시 초과 |
| RDS backup storage | DB 크기까지 무료 | `backup_retention_period=1` | retention 늘릴수록 스냅샷 누적 |
| EBS gp2/gp3 | 30 GB | `ec2_volume_size_gb = 30` | 추가 볼륨 attach 시 초과 |
| Public IPv4 | 750h/m (한 instance 에 1개 attached 일 때) | EIP 1개 attached | 인스턴스 중지 시 EIP 가 detached → idle 과금 ($0.005/h) |
| EIP idle | 무료 (attached 동안) | 1개 | 인스턴스 종료/EIP detach 시 즉시 시간당 과금 |
| Data Transfer Out | 100 GB/m | < 1 GB 추정 | 영상/대용량 자산 노출 시 위험 |
| CloudWatch metrics | 10 custom + Basic monitoring 무료 | AWS/EC2, AWS/RDS basic | CloudWatch Agent custom 메트릭 푸시 시 초과 |
| CloudWatch alarms | 10개 | ADR-0009 로 4개 | 11번째 알람부터 $0.10/alarm/m |
| CloudWatch Logs | 5 GB ingestion + 5 GB storage | `aws_cloudwatch_log_group.userdata` 미사용 | 컨테이너 로그 전체 push 시 즉시 초과 |
| SNS publication | 1,000건/m | 알람 빈도 < 50/m | 알람 폭풍 시 초과 가능 |
| Secrets Manager | 무료 X (30일 trial) | 4 secrets × $0.40 ≈ $1.6/m | 추가 secret 마다 +$0.40 |
| AWS Budgets | 계정당 2개 무료 | 1개 (`kicklog-monthly-budget`, 한도 **$50** — ADR-0015) | 3개 이상 만들면 +$0.02/budget/day |
| Lambda (엣지 감시) | 월 100만 요청 / 400,000 GB-s | 5분 주기 = 월 8,640회 | 주기를 1분으로 줄여도 Free Tier 안 |
| CloudWatch 커스텀 메트릭 | 10개 | 2개 (`KickLog/Edge`) | 11번째부터 $0.30/metric/m |
| S3 백업 버킷 | Free Tier 5GB (12개월) | pg_dump 수십 KB × 30일 | lifecycle 30일 만료 걸려 있음 |
| Cost Explorer API | 무료 GUI / API 호출당 $0.01 | GUI 만 사용 | 자동화 스크립트가 API 자주 호출 시 초과 |

---

## 2. 금지 리소스 (도입 시 비용 폭증)

| 리소스 | 월 비용 (서울) | KickLog 정책 |
|---|---|---|
| NAT Gateway | ~$32 + Data Processed $0.045/GB | **금지** (ADR-0006 D2). EC2 가 Public Subnet 이라 불필요 |
| ALB | ~$16 + LCU | **금지** (ADR-0006 D5). nginx + LE 로 대체 |
| RDS Multi-AZ | 단일 AZ 대비 2배 | **금지** (ADR-0006). MVP N=20 규모 |
| RDS Proxy | ~$11 + connection-hour | 금지 (Spring Boot HikariCP 충분) |
| ECS Fargate | task-vCPU-h 과금 | **금지** (ADR-0006). EC2 + Docker Compose 로 대체 |
| Lambda + Aurora | spec 불일치 | 금지 (ADR-0006 D1) |
| CloudFront | 1 TB Data Transfer 무료 (12개월) | 미도입. MVP 트래픽 < 1 GB |
| Route 53 hosted zone | $0.50/zone/m | 도메인 등록 시 필수 (ADR-0007). 본 PR 무관 |
| Backup vaults / AWS Backup | vault 무료, storage 과금 | 미도입 (RDS 자체 스냅샷 사용) |

---

## 3. 일상 모니터링 위치

### AWS Console
- **Billing > Cost Explorer**: 매주 1회 (월요일) 확인 권장
- **Billing > Budgets > kicklog-monthly-budget**: ADR-0009 가 만든 예산. 80%/100% actual + 100% forecast 알림
- **CloudWatch > Alarms > In alarm**: 빨간색 0개 인지 확인
- **EC2 > Instances**: 1개 (`kicklog-ec2`) 가 running 인지 확인 — 2개면 사고
- **VPC > NAT Gateways**: 0개여야 함
- **Elastic Load Balancing**: 0개여야 함
- **RDS > Databases**: 1개 (`kicklog-postgres`) 가 Single-AZ 인지 확인

### CLI 빠른 점검
```bash
# 한 줄로 prod 인프라 인벤토리 (의도된 리소스만 있는지)
aws ec2 describe-instances --region ap-northeast-2 \
  --query "Reservations[].Instances[?State.Name=='running'].[InstanceId,InstanceType,Tags[?Key=='Name']|[0].Value]" \
  --output table

aws ec2 describe-nat-gateways --region ap-northeast-2 \
  --query "NatGateways[?State!='deleted']"
# → 빈 배열 [] 이어야 함

aws elbv2 describe-load-balancers --region ap-northeast-2 \
  --query "LoadBalancers[]"
# → [] 이어야 함

aws rds describe-db-instances --region ap-northeast-2 \
  --query "DBInstances[].[DBInstanceIdentifier,DBInstanceClass,MultiAZ,AllocatedStorage]" \
  --output table
# → kicklog-postgres / db.t3.micro / False / 20 이어야 함
```

---

## 4. 사고 대응 시나리오

### 4.1 Budget 80% 알림 도착
1. `aws ce get-cost-and-usage --time-period Start=<this-month-start>,End=<today> --granularity DAILY --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE`
2. 의외의 서비스 비용 (NAT/ALB/Lambda 등) 있는지 확인
3. terraform state 와 실제 콘솔 차이 (`terraform plan` 후 unexpected drift) 확인
4. 의도하지 않은 리소스면 `terraform destroy -target=<resource>` 또는 콘솔 삭제

### 4.2 EC2 StatusCheckFailed 알람
1. EC2 콘솔에서 인스턴스 상태 확인
2. `aws ec2 reboot-instances --instance-ids <id>` 으로 재부팅 시도
3. 5분 후에도 미회복이면 stop/start (EIP 그대로 attached 이므로 IP 변동 없음)
4. user-data 로그 (`/var/log/kicklog-userdata.log`) 확인을 위해 SSM Session Manager 접속

### 4.3 RDS FreeStorageSpace ≤ 4 GiB 알람
1. `psql` 접속 후 `SELECT pg_size_pretty(pg_database_size('kicklog'));` 로 실제 사용량 확인
2. 가장 큰 table: `SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;`
3. 오래된 데이터 archive 또는 vacuum FULL
4. **storage 20GB 초과 = Free Tier 졸업 비용 발생** → archive 우선

### 4.4 RDS CPUUtilization ≥ 85% 알람
1. `pg_stat_statements` 로 slow query 확인 (이미 `log_min_duration_statement=500` 활성화)
2. CloudWatch RDS Insights > Top SQL 확인
3. 인덱스 누락 의심 시 Flyway 마이그레이션 추가

### 4.5 idle EIP 발견
1. `aws ec2 describe-addresses --region ap-northeast-2 --query "Addresses[?InstanceId==null]"` 로 unattached EIP 확인
2. 일부러 보존 필요 없으면 `aws ec2 release-address --allocation-id <id>` 로 즉시 해제
3. terraform 으로 관리되는 EIP 면 `terraform state list | grep eip` 확인 후 destroy

---

## 5. 12개월 졸업 (~2027-05) 전후 변경 점검

졸업 시점부터 EC2/RDS 가 즉시 시간당 과금 ($7.50 + $12.50 + EBS $2.40 ≈ 월 $24).
사전 점검:
- [ ] Cost Explorer 의 "예상 월 비용" 이 변동되었는지 (시뮬레이션 가능)
- [ ] Savings Plan 1년 commit ($17~22/m, 30~40% 절감) 검토
- [ ] db.t3.micro 가 충분한지 (CPU/RAM 30일 평균)
- [ ] RDS `backup_retention_period` 1 → 7 변경 검토 (스냅샷 스토리지 추가 비용 확인 후)

---

## 참조

- ADR-0006 (`docs/adr/0006-hosting.md`) — 호스팅 선택 + 비용 예측
- ADR-0008 (`docs/adr/0008-cd-via-ssm.md`) — CD 채널
- ADR-0009 (`docs/adr/0009-free-tier-production-hardening.md`) — 본 runbook 의 모태
- AWS Free Tier 공식: https://aws.amazon.com/free/
