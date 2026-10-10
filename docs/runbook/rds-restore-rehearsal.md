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
