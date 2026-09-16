# EXEC_PLAN — observability-sentry-alarms

| 항목 | 값 |
|---|---|
| Task | observability-sentry-alarms |
| Type | chore |
| Branch | chore/observability-sentry-alarms |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/observability-sentry-alarms |
| Port | 9000 |
| 생성 시각 | 2026-09-16 |
| 상태 | `in-progress` |
| 개발 방식 | **인프라(terraform) + 셸 스크립트 — Kotlin 변경 없음, TDD 비적용** |

---

## 1. 목표 (Goal)

2026-09-06 9일 마비의 **감지 사각지대**를 메운다 (`docs/agent/learning.md` 2026-09-15 항목 후속).

장애 당시 알람이 한 건도 울리지 않았다. 기존 알람은 `StatusCheckFailed` 와 `CPU >= 90%` 인데
실제 값은 StatusCheck 정상 / CPU 53% 였다. Sentry 도 꺼져 있어 에러가 수집되지 않았다.

1. **Sentry 활성화** — DSN 시크릿은 존재하나 EC2 IAM role 에 읽기 권한이 없어 빈 값이 주입되고 있었다.
2. **앱 레벨 알람 2종** — 기존 메트릭만 사용해 추가 비용 0.

> 외부 HTTPS 감시(Route53 health check)는 **비용 발생($0.50/월)으로 이번 범위에서 제외**한다.
> 무료 메트릭만으로 이번 장애는 두 번 잡힌다 (아래 3장 참조).

## 2. 접근 (Approach)

| 파일 | 변경 |
|---|---|
| `infra/terraform/secrets.tf` | 수동 생성된 `kicklog/sentry-dsn` 참조용 data source 추가 |
| `infra/terraform/ec2.tf` | IAM 정책 Resource 에 sentry-dsn ARN 추가 (`concat` + splat) |
| `infra/terraform/observability.tf` | 알람 2종 추가 |
| `infra/scripts/fetch-secrets.sh` | AccessDenied 와 시크릿 미발급을 구분해 경고 출력 |

### Sentry 가 꺼져 있던 경로

```
kicklog/sentry-dsn 시크릿  →  존재함 (콘솔·CLI 로 수동 생성, terraform state 밖)
EC2 IAM 정책              →  ARN 누락  ← 원인
fetch-secrets.sh          →  `2>/dev/null || echo ""` 로 AccessDenied 를 삼킴  ← 은폐
결과                       →  .env 에 SENTRY_DSN= (빈 값) → 앱이 Sentry 비활성으로 기동
```

`var.sentry_dsn` 이 빈 값이라 `aws_secretsmanager_secret.sentry_dsn` 은 `count=0` 이다.
따라서 IAM 정책은 **resource splat + data source splat 을 모두 concat** 해 두 경로를 커버한다.

### 알람 설계 근거 (실측)

| 알람 | 임계 | 정상값 | 장애 시 | 이번 장애에서 |
|---|---|---|---|---|
| `backend-db-disconnected` | 커넥션 < 1, 15분 | 10 고정 | 0 (9일간) | **9/6 23:00 즉시 감지** |
| `ec2-disk-read-surge` | 5분당 > 1GiB, 15분 | 36KB~1.4MB | 4.5GB | **8/22 조기 경보** (붕괴 15일 전) |

- DB 알람 15분: 배포 중 컨테이너 재시작으로 1~2분 0 이 될 수 있어 오탐 방지.
- 디스크 임계 1GiB: 정상의 700배 이상, 스래싱의 1/4.5 — 오탐 없이 조기 포착.

## 3. 검증 (Verification)

### 코드 검증 (완료)

- [x] `terraform validate` → Success
- [x] `bash -n fetch-secrets.sh` → 문법 통과
- [x] `terraform.tfvars`/`tfstate` 가 `.gitignore` 로 무시됨 확인 (평문 시크릿 커밋 방지)

### apply 후 검증

- [ ] `terraform plan` → 변경이 **IAM 정책 1건 + 알람 2건**뿐일 것 (다른 drift 없음)
- [ ] `aws iam get-role-policy` → Resource 에 `kicklog/sentry-dsn-9MnCTQ` 포함
- [ ] 서버에서 `fetch-secrets.sh` 재실행 → `✅ Sentry DSN 조회 성공` 출력
- [ ] `.env` 의 `SENTRY_DSN=` 이 빈 값이 아닐 것
- [ ] 컨테이너 재기동 후 로그에 `SENTRY_DSN 미설정` 이 **없을 것**
- [ ] `aws cloudwatch describe-alarms` → 신규 알람 2건이 `OK` 상태

### 알람 실효 검증 (가능하면)

- [ ] `backend-db-disconnected` 를 `set-alarm-state` 로 강제 ALARM → 이메일 수신 확인 → OK 복귀
  (실제 장애를 만들지 않고 통보 경로만 검증)

## 4. 위험도 / 롤백

**Risk: Safe**

- IAM 정책은 **읽기 권한 1건 추가**뿐 (축소 없음). 기존 4개 시크릿 접근에 영향 없음.
- 알람 추가는 인프라 동작에 영향 없음 — 감시만 한다.
- `fetch-secrets.sh` 변경은 출력 메시지 개선이며 `SENTRY_DSN=""` fallback 은 그대로라
  실패해도 배포가 막히지 않는다.
- 롤백: `terraform apply` 로 이전 커밋 상태 재적용.

## 5. 후속

1. **호스트 스왑 1~2GB** (terraform user-data) — 미착수
2. **healthcheck → 실제 재시작 연결** (autoheal / systemd watchdog) — 미착수
3. **외부 HTTPS 감시** — 비용 문제로 보류. 무료 대안: Lambda+EventBridge(프리티어) 또는 외부 무료 서비스.
   현재 알람으로 못 잡는 것은 "nginx 만 사망"·"TLS 인증서 만료"·"Cloudflare 장애".
   TLS 는 Let's Encrypt 만료 예고 메일로 일부 커버된다.
4. **ADR** — free-tier 메모리 예산 + 앱 레벨 감시 정책 (ADR-0009 후속)
5. **iOS 방어** — 앱 시작 blocking chain, `URLError.timedOut` → "알 수 없는 오류" 매핑

## 6. 학습 기록

- Trigger: **production-risk**
- Root cause: 시크릿을 terraform 밖(콘솔·CLI)에서 만들면 IAM 정책 갱신이 함께 이뤄지지 않는다.
  게다가 조회 실패를 `2>/dev/null || echo ""` 로 삼키면 설정 실수가 영원히 드러나지 않는다.
- Prevention:
  - optional 한 외부 연동이라도 **"없음"과 "권한 없음"은 구분해서 로그를 남긴다.**
  - 관측 도구는 도입 후 **실제 이벤트 수신까지 확인**해야 도입이 끝난 것이다.
- Promoted to: `docs/agent/learning.md` (2026-09-16 항목)
