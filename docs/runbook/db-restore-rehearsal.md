> ⚠️ **2026-10-13 (ADR-0016) 이후 RDS 는 존재하지 않는다.** 아래 RDS 절차는 *과거 기록*이며,
> 현재 유효한 복구 절차는 문서 맨 아래 **"컨테이너 Postgres 복구"** 절이다.
> 구 RDS 최종 스냅샷(`kicklog-postgres-final-20260527-042626`)은 보관 중이다.

# Runbook — RDS 백업 복원 리허설 (분기 1회)

ADR-0009 D7 의 코드화된 절차. **백업이 있다 ≠ 백업으로 복구할 수 있다** — 한 번이라도 복구해 본 사람만 사고 대응 가능.

> 대상: `kicklog-postgres` (PostgreSQL 16, db.t3.micro, Single-AZ, 서울 region)
> 주기: **분기 1회** (3·6·9·12월 첫째 주)
> 소요: 30~60분 (RDS 복원 자체가 가장 오래 걸림)
> 비용: **$0** — 임시 인스턴스는 1시간 이내 종료 → Free Tier 750h 안에 흡수

---

## 1. 사전 준비

```bash
# AWS CLI / region 확인
aws sts get-caller-identity
aws configure get region   # ap-northeast-2

# psql 클라이언트 (Mac)
brew install libpq
brew link --force libpq

# 본 절차에서 사용할 변수
SRC_DB=kicklog-postgres
RESTORE_DB=kicklog-restore-rehearsal-$(date +%Y%m%d)
SUBNET_GROUP=$(aws rds describe-db-instances --db-instance-identifier $SRC_DB \
  --query "DBInstances[0].DBSubnetGroup.DBSubnetGroupName" --output text)
SG_ID=$(aws rds describe-db-instances --db-instance-identifier $SRC_DB \
  --query "DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId" --output text)
```

---

## 2. 최신 자동 스냅샷 확인

```bash
aws rds describe-db-snapshots \
  --db-instance-identifier $SRC_DB \
  --snapshot-type automated \
  --query "reverse(sort_by(DBSnapshots, &SnapshotCreateTime))[0:3].[DBSnapshotIdentifier,Status,SnapshotCreateTime]" \
  --output table
```

가장 최근 `available` 상태 스냅샷 식별자를 변수에 담는다.

```bash
SNAPSHOT_ID=<위에서 복사한 스냅샷 ID>
```

> ⚠️ 본 인프라는 `backup_retention_period = 1` (Free Tier 제약). 직전 1일 스냅샷만 존재.
> 더 오래된 시점이 필요하면 **manual snapshot** 로 매월 1회 보관 권장 — terraform 자동화는 별도 PR.

---

## 3. 임시 인스턴스로 복원

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier "$RESTORE_DB" \
  --db-snapshot-identifier "$SNAPSHOT_ID" \
  --db-instance-class db.t3.micro \
  --no-publicly-accessible \
  --vpc-security-group-ids "$SG_ID" \
  --db-subnet-group-name "$SUBNET_GROUP" \
  --no-multi-az \
  --no-auto-minor-version-upgrade \
  --copy-tags-to-snapshot \
  --tags Key=Purpose,Value=restore-rehearsal Key=AutoDelete,Value=true
```

복원 시간 추적:
```bash
watch -n 30 'aws rds describe-db-instances --db-instance-identifier '"$RESTORE_DB"' \
  --query "DBInstances[0].[DBInstanceStatus,Endpoint.Address]" --output table'
```

`available` 상태가 되면 다음 단계.

---

## 4. Sanity Check — psql 접속

EC2 안에서 (RDS 가 publicly_accessible=false 이므로):

```bash
# SSM Session Manager 로 EC2 접속
aws ssm start-session --target $(terraform output -raw ec2_instance_id)

# EC2 안에서
ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier <restore-id> \
  --query "DBInstances[0].Endpoint.Address" --output text)

# Secret Manager 의 비밀번호로 접속
PGPASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id kicklog/db-password \
  --query 'SecretString' --output text | jq -r .password)

PGPASSWORD="$PGPASSWORD" psql -h "$ENDPOINT" -U kicklog -d kicklog <<'SQL'
\echo === 테이블 목록 ===
\dt
\echo === 행 수 sanity ===
SELECT 'users' AS table, COUNT(*) FROM users
UNION ALL SELECT 'matches', COUNT(*) FROM matches
UNION ALL SELECT 'friendships', COUNT(*) FROM friendships;
\echo === 가장 최근 match ===
SELECT id, played_at FROM matches ORDER BY played_at DESC LIMIT 5;
SQL
```

**합격 기준**:
- 모든 도메인 테이블이 존재
- 행 수가 prod 기준 ±5% 이내 (스냅샷 시점 차이 감안)
- 가장 최근 match 의 `played_at` 이 스냅샷 시점 이내

---

## 5. Flyway 메타테이블 검증

```sql
SELECT version, description, success, installed_on
FROM flyway_schema_history
ORDER BY installed_rank DESC
LIMIT 10;
```

마이그레이션 history 가 prod 와 동일한지 확인. 누락된 버전이 있으면 백업 시점에 누락된 마이그레이션이 있다는 신호.

---

## 6. 즉시 삭제

```bash
aws rds delete-db-instance \
  --db-instance-identifier "$RESTORE_DB" \
  --skip-final-snapshot \
  --delete-automated-backups
```

**삭제 확인**:
```bash
aws rds describe-db-instances --db-instance-identifier "$RESTORE_DB" 2>&1 | head -3
# DBInstanceNotFound 오류가 나오면 OK
```

---

## 7. 리허설 기록

`docs/agent/trajectories/YYYY-MM.log` 또는 `docs/runbook/rehearsal-log.md` 에 한 줄 기록:

```
2026-09-03 RDS restore rehearsal — snapshot rds:kicklog-postgres-2026-09-02-17-04, 47분 소요, 행 수 일치, FLYWAY v37 까지 확인. OK.
```

실패하거나 데이터 불일치가 나오면 즉시 **사고로 분류** — `docs/agent/learning.md` 에 root cause + prevention 등재.

---

## 8. 자동화 후보 (별도 PR)

- EventBridge cron → Lambda → 위 절차 자동 실행 + Slack 알림 (분기당 1회)
- 본 runbook 의 변수 부분을 `scripts/rds-restore-rehearsal.sh` 로 분리
- 임시 인스턴스 생성 직후 `AutoDelete=true` 태그 + Lambda 1h 후 자동 삭제 (보호장치)

본 PR 은 절차 코드화만, 자동화는 후속.

---

## 참조

- ADR-0006 D8 (RDS 백업 정책)
- ADR-0009 D7 (백업 리허설 결정)
- AWS RDS 공식 — Restoring from a snapshot: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_RestoreFromSnapshot.html


---

## 부록 — pg_dump 논리 백업에서 복원 (ADR-0015)

자동 스냅샷(보존 **7일**) 외에 매일 04:30 KST 논리 백업이 S3 에 쌓인다 (30일 보관).

```bash
# 1) 백업 목록
aws s3 ls s3://kicklog-backup-576393818807/pg/ --region ap-northeast-2

# 2) 받아서 내용 확인 (복원 전에 반드시)
aws s3 cp s3://kicklog-backup-576393818807/pg/kicklog-<STAMP>.dump /tmp/ --region ap-northeast-2
pg_restore --list /tmp/kicklog-<STAMP>.dump | head -40

# 3) 로컬/임시 DB 로 복원해 검증 (운영에 바로 쏘지 않는다)
createdb kicklog_restore_test
pg_restore --no-owner --no-privileges -d kicklog_restore_test /tmp/kicklog-<STAMP>.dump
psql kicklog_restore_test -c "select count(*) from matches;"

# 4) 테이블 1개만 되살릴 때
pg_restore --no-owner -t matches -d <target> /tmp/kicklog-<STAMP>.dump
```

- 스냅샷 복원과의 역할 분담: **시점 전체 복구 = 스냅샷**, **부분·교차계정·버전 사고 = 논리 백업**
- 덤프는 업로드 전에 `pg_restore --list` 로 이미 1차 검증된다 (`pg-dump-to-s3.sh`)
- 수동 실행: `sudo systemctl start kicklog-pg-dump.service` → `journalctl -u kicklog-pg-dump -n 20`


---

## 현행 — 컨테이너 Postgres 복구 (ADR-0016)

DB 는 `kicklog-postgres` 컨테이너이고 데이터는 **별도 EBS**(`/mnt/pgdata`, vol-0fec57d33306454b3)에 있다.
복구 수단은 3중이다.

| 수단 | 보관 | 복구 단위 | 최대 손실 |
|---|---|---|---|
| S3 논리 백업 (`pg_dump -Fc`) | 매일 04:30 KST, 30일 | 테이블 단위까지 | 24시간 |
| EBS 데이터 볼륨 | 인스턴스와 독립 | 볼륨 통째 | 0 (인스턴스 장애 시) |
| EBS 스냅샷 | 수동 | 볼륨 통째 | 스냅샷 시점 |

### 1) 논리 백업에서 복원

```bash
# 목록
aws s3 ls s3://kicklog-backup-576393818807/pg/ --region ap-northeast-2

# 박스에서 (SSM Session Manager)
cd /opt/kicklog
aws s3 cp s3://kicklog-backup-576393818807/pg/kicklog-<STAMP>.dump /tmp/r.dump --region ap-northeast-2

# 반드시 먼저 열어본다 — 못 여는 덤프는 백업이 아니다
docker exec -i kicklog-postgres pg_restore --list < /tmp/r.dump | head -20

# 복원 (backend 를 내려 커넥션을 끊고 진행)
docker compose --env-file .env --env-file .env.deploy stop backend
docker exec -i kicklog-postgres pg_restore -U kicklog -d kicklog \
  --clean --if-exists --no-owner --no-privileges < /tmp/r.dump
docker compose --env-file .env --env-file .env.deploy start backend

# 검증
docker exec kicklog-postgres psql -U kicklog -d kicklog -c "select count(*) from matches;"
curl -fsS http://127.0.0.1:8080/actuator/health
```

2026-10-13 컷오버 실측: 덤프 + 복원 + 재기동 **23초** (DB 2.9GB · 덤프 42KB).

### 2) 인스턴스를 잃었을 때 (데이터 볼륨은 살아 있음)

1. `terraform apply` 로 새 인스턴스 생성 (user-data 가 볼륨을 **포맷하지 않고** 마운트한다 —
   `blkid` 로 기존 파일시스템을 감지하면 건너뛴다)
2. CD 재실행 또는 `apply-host-config.sh` → compose up
3. `check-host-health.sh` 로 마운트·컨테이너 확인

### 3) 데이터 볼륨까지 잃었을 때

새 볼륨 생성 → 위 1) 논리 백업 복원. 최대 24시간 손실을 수용한다(ADR-0016 Consequences).

### ⚠️ 가장 위험한 실패 모드

볼륨이 **마운트되지 않은 채** compose 가 뜨면 Postgres 가 빈 디렉토리에 새 클러스터를 만들어
"데이터가 사라진 것처럼" 보인다. 이때 **절대 그 상태로 덮어쓰지 말고** 먼저 확인한다:

```bash
findmnt /mnt/pgdata          # 비어 있으면 미마운트
lsblk -o NAME,LABEL,MOUNTPOINT
mount -a && findmnt /mnt/pgdata
```

방어는 3중이다: `fstab(nofail)` + 마운트 지점 **immutable**(`chattr +i`) + `apply-host-config.sh`/
`check-host-health.sh` 의 mountpoint 검사.
