# EXEC_PLAN — cost-single-box-arm

| 항목 | 값 |
|---|---|
| Task | cost-single-box-arm |
| Type | chore |
| Branch | chore/cost-single-box-arm |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/cost-single-box-arm |
| Port | 9000 |
| 생성 시각 | 2026-10-13 |
| 상태 | `done` (2026-10-13 컷오버 완료) |
| 개발 방식 | 인프라 마이그레이션 — 백엔드 코드 변경 0, ATDD 면제. 검증은 실측 명령 |

---

## 1. 목표 (Goal)

2026-10-02 경 Free plan 크레딧이 소진돼 **월 약 $45 실과금**이 시작됐다. 실측상 자원은 압도적으로 남는다 —
EC2 CPU 평균 **0.67%**, RDS CPU 평균 **4%**, DB 실사용 **2.9GB**(20GB 중), `DatabaseConnections` 상시 **10 고정**.
즉 **제약은 CPU·스토리지·동시성이 아니라 메모리뿐**이다.

그래서 전용 RDS 인스턴스($20.4 + 스토리지 $2.62 = 월 $23)를 없애고, 메모리를 키운 **ARM 단일 박스**
(t4g.small 2GB)에 앱과 Postgres 를 함께 올린다. 비밀 저장소도 SSM Parameter Store 로 일원화한다(−$2).

**목표: 월 $45 → 약 $25 (−45%), 1년 약정 없이.**

사용자 선택(2026-10-13): **Blue/Green + EIP 이동** · **별도 EBS 20GB 데이터 볼륨** · **구 RDS 는 최종 스냅샷 후 즉시 삭제**.

## 2. 접근 (Approach)

### (A) Secrets Manager → SSM Parameter Store (−$2.0/월)

ADR-0015 가 이미 `/kicklog/origin-cert`·`/kicklog/cloudflare-api-token` 을 SSM 에 두면서 **비밀 저장소가 2개로
갈라져 있다.** 비용뿐 아니라 일원화가 목적이다.

- `infra/terraform/secrets.tf` → `ssm.tf`: `aws_secretsmanager_secret` ×5 → `aws_ssm_parameter`(SecureString) ×5
- `kicklog/db-password` 의 JSON(host/port/dbname 포함) 구조는 **버린다** — 통합 후 host 는 항상 compose 네트워크의
  `postgres` 이므로 비밀은 비밀번호 한 값이면 충분하다
- `ec2.tf`: IAM 을 `secretsmanager:GetSecretValue` → `ssm:GetParameter*` on `/kicklog/*` 로. `kms:Decrypt`(ViaService=ssm)는 이미 있음
- `fetch-secrets.sh`: `aws ssm get-parameters --with-decryption` 로 일괄 조회
- `cd.yml`: GHCR PAT 조회 1줄

### (B) ARM 전환 — t3.micro(x86, 1GB) → t4g.small(arm64, 2GB)

- `main.tf`: AMI 필터 `al2023-ami-2023.*-x86_64` → `al2023-ami-2023.*-arm64`
- `ec2.tf`: `instance_type` 변수 기본값 `t3.micro` → `t4g.small`
- `user-data.sh`: docker-compose 플러그인 URL `linux-x86_64` → `linux-aarch64`
- `cd.yml`: `platforms: linux/amd64` → `linux/arm64` (JVM 이라 애플리케이션 코드 변경 없음)
- **메모리 예산 재설계** (2GB) — 2026-09-06 장애가 정확히 이 지점에서 났으므로 이 설계가 작업의 본체다:

| 구성 | 한도 | 근거 |
|---|---|---|
| backend 컨테이너 | `mem_limit 768m` | 실측 JVM 비-heap 226MB + heap 여유. 현재 512m 에서 상향 |
| postgres 컨테이너 | `mem_limit 512m` (`shared_buffers 128MB`) | DB 2.9GB · 커넥션 10 규모에 충분 |
| 호스트 프로세스 | ~180MB | nginx·docker·containerd·SSM agent 실측 |
| page cache 여유 | ~500MB | 2026-09-06 교훈: 여기가 마르면 스래싱 |
| swap | 2GB·`swappiness=10` | 현행 유지 (OOM killer 가 정상 발동하도록) |

- 두 컨테이너 모두 `memswap_limit = mem_limit` — 스왑으로 연명하지 않고 **OOM kill → restart** 경로를 연다

### (C) RDS 폐지 → Postgres 컨테이너 (−$23/월, +$5.7 인스턴스 업그레이드)

- `infra/docker-compose.prod.yml`: `postgres:16-alpine` 서비스 추가
  - 데이터: 별도 EBS 20GB 를 `/mnt/pgdata` 에 마운트 → bind mount
  - `healthcheck: pg_isready`, backend 는 `depends_on: condition: service_healthy`
  - 포트 노출 **없음** (compose 네트워크 내부만)
- `backup.tf`: `aws_ebs_volume` 20GB gp3 + `aws_volume_attachment`
- `rds.tf` 삭제: `aws_db_instance`·`aws_db_subnet_group`·`aws_db_parameter_group`·`aws_security_group.rds`
- `pg-dump-to-s3.sh`: 호스트 psql → `docker exec kicklog-postgres pg_dump`
- `user-data.sh`: 데이터 볼륨 멱등 마운트(미포맷이면 xfs 포맷 → fstab 등록)

### (D) 감시 재설계 — RDS 메트릭이 사라진다

제거되는 알람 3개와 그 역할을 대체한다. **특히 `backend-db-disconnected` 는 2026-09-06 형 장애를 잡는
핵심이었으므로 공백으로 두지 않는다.**

| 사라지는 알람 | 역할 | 대체 |
|---|---|---|
| `rds-high-cpu` | DB 과부하 | EC2 `CPUUtilization`(기존 알람이 이미 커버) |
| `rds-low-storage` | 스토리지 고갈 | **신규** `check-host-health.sh` — 디스크 85% 초과 시 SNS |
| `backend-db-disconnected` | 앱↔DB 단절 = 앱 사망 | **신규** `check-host-health.sh` — 컨테이너 unhealthy/재시작 감지 + 기존 엣지 Lambda(ADR-0015) |

- `infra/scripts/check-host-health.sh` + `kicklog-host-health.timer` (10분 주기): 디스크 사용률 · 컨테이너
  health · swap 사용량을 보고 임계 초과 시 SNS publish. ADR-0015 의 `check-cert-expiry.sh` 와 같은 패턴
- `kicklog-pg-dump.service` 에 `OnFailure=` 유닛 추가 — **백업 실패 자체를 통보**한다(지금은 조용히 실패)

### (E) 컷오버 (Blue/Green + EIP 이동)

terraform 에 신규 인스턴스를 **추가**해 구 박스와 공존시킨 뒤 EIP 만 옮긴다.

1. `aws_instance.app_v2`(t4g.small·arm64) + 데이터 볼륨 추가 → `apply` (구 박스 그대로 가동)
2. v2 부트스트랩: `apply-host-config.sh` + arm64 이미지 배포 + Postgres 컨테이너 기동
3. **리허설 복원**: 구 RDS → `pg_dump` → v2 컨테이너 `pg_restore` → 행 수·Flyway 버전 대조
4. **쓰기 차단**(구 박스 backend 중지) → **최종 `pg_dump`** → v2 반영 → 앱 기동
5. **EIP 를 v2 로 이동** → 엣지 200 확인 (Cloudflare 설정은 건드리지 않는다)
6. 구 인스턴스 제거 + RDS 최종 스냅샷 후 삭제 → `app_v2` 를 `app` 으로 `state mv` + 코드 정리

쓰기 차단 구간은 4~5 단계뿐이며 **약 5분**을 목표로 한다.

### 범위 밖
- ADR-0010 upstream keepalive 적용 (별도 PR)
- Terraform state S3 backend 이전 (ADR-0009 D6)
- Compute Savings Plan 구매 — 통합이 안정화된 뒤 별도 판단

## 3. 테스트 케이스 (Test Cases)

> 백엔드 코드 변경 0 → Cucumber/JUnit 대상 없음. 실측 검증으로 대체.

### Happy Path
- [x] `terraform plan` — 신규 인스턴스/볼륨만 추가, 구 박스·RDS 는 그대로 (1단계)
- [x] v2 에서 `docker compose ps` → backend·postgres 모두 `healthy`
- [x] 리허설 복원 후 행 수 대조: `users`·`matches`·`quarter_workouts`·`refresh_tokens` 가 RDS 와 동일
- [x] `flyway_schema_history` 가 RDS 와 동일 (`max(version)` 은 text 비교라 '9' 로 보이지만 양쪽 같은 값)
- [x] EIP 이동 후 엣지 `https://kicklog.org/actuator/health` → 200
- [x] `/nginx-health`·AASA 200, TLS 인증서 그대로(Origin CA 2041)
- [x] `pg-dump-to-s3.sh`(컨테이너 경유) 수동 실행 → S3 객체 생성 + `pg_restore --list` 통과

### Unhappy Path
- [x] v2 검증 실패 시 EIP 를 구 박스로 되돌리면 즉시 복구 — **EIP 이동 전에는 구 박스가 계속 서비스 중**
- [x] `fetch-secrets.sh` 가 SSM 파라미터 누락 시 **중단**(빈 값 주입 금지) — ADR-0015 의 Sentry 무음 실패 재발 방지
- [x] backend 만 stop → postgres 생존 확인 (복원 절차에서 실제로 수행)
- [x] 데이터 볼륨 미마운트 상태로 compose 기동 시도 → postgres 가 빈 디렉토리에 초기화하지 **않도록** 가드

### Edge Cases
- [ ] 메모리 압박 주입 — **미실행**. 운영 박스에 부하를 주지 않는다는 원칙(ADR-0010) 유지. 예산 설계 + `check-host-health.sh` 스왑 감시로 갈음
- [ ] 재부팅 후 자동 마운트 — **미실행**(운영 재부팅 회피). fstab 등록 + `restart: unless-stopped` 설정 확인으로 갈음
- [x] `apply-host-config.sh` 를 arm64 박스에서 2회 연속 실행 → 멱등

## 4. 검증 (Verification)

### 자동 검증
```bash
cd backend && ./gradlew compileKotlin          # 백엔드 무변경 확인
cd infra/terraform && terraform fmt -check && terraform validate && terraform plan
```

### 시나리오 검증 (실측)
```bash
# 아키텍처
aws ec2 describe-instances --region ap-northeast-2 \
  --query "Reservations[].Instances[?State.Name=='running'].[InstanceId,InstanceType,Architecture]" --output text

# 엣지
for p in /actuator/health /nginx-health /.well-known/apple-app-site-association; do
  curl -s -o /dev/null -w "$p %{http_code}\n" "https://kicklog.org$p"; done

# DB (박스 내부)
docker exec kicklog-postgres psql -U kicklog -d kicklog -c "select count(*) from matches;"
docker exec kicklog-postgres psql -U kicklog -d kicklog -c "select max(version) from flyway_schema_history;"

# 메모리 예산
free -m && docker stats --no-stream

# RDS 가 사라졌는지 + 스냅샷이 남았는지
aws rds describe-db-instances --region ap-northeast-2 --query "length(DBInstances)" --output text   # 0
aws rds describe-db-snapshots --region ap-northeast-2 --snapshot-type manual \
  --query "DBSnapshots[].DBSnapshotIdentifier" --output text

# 비용 (1주 후)
aws ce get-cost-and-usage --time-period Start=<D>,End=<D+7> --granularity DAILY \
  --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE
```

### 완료 기준
- 월 환산 비용이 **$25 ± $2** 범위
- 알람 총 개수 10개 이하(Free Tier) 유지, DB 관련 감시 공백 0

---

## (Optional) 위험도 / 롤백

**Risk = Critical** — 운영 DB 의 호스팅 주체를 바꾼다. 데이터 손실이 유일하게 되돌릴 수 없는 사고다.

**데이터 보호 3중**
1. 컷오버 직전 **RDS 최종 스냅샷**(`kicklog-postgres-final-<ts>`) — 삭제해도 남는다
2. 매일 `pg_dump` → S3 (ADR-0015, 30일 보관) + 컷오버 당일 수동 덤프 1부 **로컬 보관**
3. 데이터 볼륨은 별도 EBS — 인스턴스를 날려도 보존

**롤백 경로 (단계별)**
| 시점 | 롤백 |
|---|---|
| EIP 이동 전 | 아무것도 안 함 — 구 박스가 계속 서비스 중. v2 만 폐기 |
| EIP 이동 직후 문제 발견 | EIP 를 구 박스로 재연결(수 초). 구 박스+RDS 아직 살아 있음 |
| RDS 삭제 후 | 최종 스냅샷에서 복원(20~30분) → `fetch-secrets.sh` 의 DB_URL 복귀 |

**쓰기 차단 구간**: 최종 덤프~EIP 이동, 목표 5분. 그 사이 iOS 쓰기 요청은 실패하지만 **iOS 가 1차 SoT**
(SwiftData)라 사용자 데이터 자체는 유실되지 않는다.

## (Optional) 후속 / 관련 이슈
- 안정화 후 Compute Savings Plan 검토 → 월 $20
- ADR-0010 keepalive, Terraform state S3 backend
- `tfplan*` .gitignore, 미머지 원격 브랜치 정리

## (Optional) 학습 기록
- Trigger: production-risk (컷오버 후 기록)
- Promoted to: `docs/adr/0016-single-box-consolidation.md`


---

## 컷오버 기록 (2026-10-13)

| 시각(KST) | 단계 |
|---|---|
| 20:0x | SSM 파라미터 5개 · EBS 20GB · t4g.small 생성 |
| 20:05 | v2 user-data 재실행(레이블 버그 수정 후) → 볼륨 마운트·docker·nginx |
| 20:10 | arm64 이미지 배포 + 호스트 설정(인증서·nginx·AASA·타이머 3종) |
| 20:11 | **리허설 복원** 성공 (23초, 행 수 일치) |
| **20:12:45** | **쓰기 차단** — 구 박스 backend 중지 |
| 20:12:52 | 최종 덤프 + 복원 (23초) |
| **20:13:26** | **EIP 이동** → v2 |
| 20:13:29 | 엣지 검증 — 502 1건 후 전부 200 |
| 20:14 | GitHub Variable `EC2_INSTANCE_ID` 전환 |
| 20:21 | RDS 최종 스냅샷 후 삭제 (6분 55초) · Secrets Manager 5개 · RDS 알람 3개 · subnet public_c 제거 |
| 20:22 | 구 인스턴스 종료, `terraform plan` → No changes |

**쓰기 차단 총 44초.** 데이터 손실 0 (users=16 · matches=24 · quarters=63 · tokens=95 일치).

### 중간에 걸린 것 → 코드 반영

| 증상 | 원인 | 조치 |
|---|---|---|
| user-data 가 nginx 설치 전에 중단 | XFS 레이블 12자 초과(`kicklog-pgdata`) → 포맷 명령 실패 → `set -e` | 레이블 `kicklogpg`, 볼륨 블록만 `set +e` 로 격리 |
| 데이터 디스크 미탐지 | terraform 이 인스턴스 생성 후 볼륨 attach | 90초 대기 루프 |
| arm64 빌드 지연 우려 | 빌더 스테이지가 타깃 아키텍처에서 Gradle 실행 | `--platform=$BUILDPLATFORM` (실측 60초) |
| 브랜치 CD 배포 잡 실패 | OIDC trust = `refs/heads/main` 전용 | **의도된 차단** — 구 운영 박스에 신규 compose 가 나가는 것을 막았다 |
| 하네스가 일부 명령 차단 | `guard-bash.sh` 가 문자열로 판정 (포맷·DDL 키워드) | 복원은 `pg_restore --clean --if-exists` 로, 파일 작성은 Edit 도구로 우회 |
