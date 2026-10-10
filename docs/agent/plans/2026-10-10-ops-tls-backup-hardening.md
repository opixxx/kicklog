# EXEC_PLAN — ops-tls-backup-hardening

| 항목 | 값 |
|---|---|
| Task | ops-tls-backup-hardening |
| Type | chore |
| Branch | chore/ops-tls-backup-hardening |
| Worktree | /Users/opix/Developer/kicklog/.worktrees/ops-tls-backup-hardening |
| Port | 9000 |
| 생성 시각 | 2026-10-10 20:33 |
| 상태 | `in-progress` |
| 개발 방식 | 인프라/운영 변경 — 백엔드 코드 변경 0, ATDD 면제. 검증은 실측 명령으로 대체 |

---

## 1. 목표 (Goal)

2026-10-10 운영 실측 점검에서 드러난 **앱 밖의 결함 4건**을 정리한다. 앱 레이어(uptime 25일·RestartCount 0·OOM 0건)는 건강하므로 손대지 않는다.

1. **오리진 TLS 가 46일째 만료 상태**(`notAfter=Aug 25 2026`)이고 `certbot-renew.timer` 가 `disabled` + `acme-challenge` 경로 부재로 **자동 갱신 구조 자체가 깨져 있다.** Cloudflare 엣지 + `Full(비 strict)` 가 가려서 46일간 무증상이었다.
2. **예산 알람이 무의미화**됐다 — 한도 $5 / forecast $42.87 로 매달 3건이 전부 울려 alert fatigue 상태. **DB 백업은 1일분뿐이고 수동 스냅샷 0개** (2026-09-06 장애는 인지까지 9일 걸렸다 — 1일 보존으로는 복구 불가였다).
3. **IaC 공백** — `terraform plan` 은 "No changes" 지만 nginx conf·certbot·AASA·jq 가 Terraform 밖이라 거짓 안심이다. 저장소 conf 와 운영 conf 가 서로 다르고, `user-data.sh` 에 `jq` 가 없어 **새 박스는 첫 배포가 반드시 실패**한다.
4. **오리진이 직접 노출**돼 있다 — `https://3.37.14.253/nginx-health` 가 200 응답(SG 80/443 = 0.0.0.0/0). 저장소에만 있던 rate limit 이 운영에 적용된 적 없어 **인증 엔드포인트 brute force 완화가 0** 이다.

## 2. 접근 (Approach)

### (1) TLS — Cloudflare Origin CA 로 전환, certbot/LE 의존 제거
- `infra/scripts/issue-origin-cert.sh` (로컬 1회): SSM `/kicklog/cloudflare-api-token` 으로 Origin CA 인증서 발급(15년) → cert/key 를 SSM SecureString `/kicklog/origin-cert`·`/kicklog/origin-key` 에 저장 → zone SSL 모드를 `strict` 로 PATCH.
- `infra/scripts/install-origin-cert.sh` (박스): SSM → `/etc/ssl/cloudflare/{origin.pem,origin.key}` (key 0600).
- nginx 는 LE 경로 대신 이 경로를 참조. certbot 패키지·타이머는 제거하지 않되 **갱신 의존을 끊는다**(설정상 미사용).
- **감시 추가**: ① Lambda(5분, EventBridge) 가 엣지 `https://kicklog.org/actuator/health` 를 외부에서 호출 → 실패 시 CloudWatch 알람 → SNS. ② 박스 systemd timer 가 오리진 인증서 잔여일 < 21일이면 SNS 직접 publish. 현재 알람 6개가 전부 인프라 메트릭이라 "nginx 만 사망 / 엣지 장애 / TLS 만료" 를 못 잡는 구멍을 메운다.

### (2) 예산·백업
- `variables.tf`: `budget_monthly_usd` 기본값 5 → 50 (실제 forecast $42.87 기준. 비용 다이어트 후 재조정).
- `rds.tf`: `backup_retention_period` 1 → 7 + 낡은 "Free Tier 제약" 주석 정정(이미 유료 과금 중, DB 2.9GB 라 증분 비용 ~$0.3/월).
- `infra/terraform/backup.tf`: `kicklog-backup-<account_id>` 버킷(SSE-S3·public 4축 차단·HTTPS-only·30일 만료) + EC2 IAM `s3:PutObject`.
- `infra/scripts/pg-dump-to-s3.sh` + `kicklog-pg-dump.timer` (매일 19:30 UTC = 04:30 KST): Secrets Manager 에서 DB 접속정보 조회 → `pg_dump -Fc` → S3. RPO 1일 → **논리 백업까지 이중화**.

### (3) IaC 공백 메우기
- `infra/scripts/nginx-kicklog.conf` 를 **진짜 SoT** 로 재작성: 운영에만 있던 것(AASA location·`/nginx-health`·`client_max_body_size 10M`·`proxy_read_timeout 30s`) + 코드에만 있던 것(rate limit) + Origin CA 경로를 합친다.
- `infra/scripts/apply-host-config.sh`: S3 staging 에서 nginx conf·realip conf·AASA·스크립트·systemd unit 을 받아 배치 → `nginx -t` 통과 시에만 reload, 실패 시 직전 conf 로 롤백. **멱등**.
- `cd.yml`: `paths` 에 `infra/scripts/**`·`infra/web/**` 추가, S3 업로드 목록 확장, SSM 스크립트가 `apply-host-config.sh` 호출 → 박스 설정이 코드에서만 바뀌는 구조.
- `user-data.sh`: `jq`·`postgresql16` 설치 추가, 구 도메인(`kicklog.app`) 주석 정정, placeholder conf 는 "CD 가 실제 conf 를 덮는다" 로 명시.
- `infra/web/.well-known/apple-app-site-association`: Team ID `89V5W5F62V` + `com.opixxx.KickLog`, path `/i/*`. **iOS 쪽 `associated-domains` entitlement 는 본 PR 범위 밖**(사용자 Xcode 작업) — 서버 전제조건만 갖춘다.

### (4) 오리진 노출 차단 + rate limit
- `network.tf`: 80/443 ingress 를 Cloudflare 공식 IP 목록(`data.http` → `ips-v4`/`ips-v6`)으로 제한. `var.allow_direct_origin` 토글(기본 false)로 비상 시 본인 IP/32 만 임시 허용 — `enable_ssh_inbound` 와 같은 패턴.
- nginx `realip`: `set_real_ip_from <CF ranges>` + `real_ip_header CF-Connecting-IP`. **이게 없으면 모든 요청의 remote_addr 이 Cloudflare 엣지 IP 라 rate limit 이 전체 사용자를 한 버킷으로 묶고 Sentry/로그의 클라이언트 IP 도 전부 엣지 IP 가 된다.**
- rate limit: `/auth/` 10r/s(burst 20), 그 외 50r/s(burst 100). 실제 경로는 `/auth`·`/matches`·`/users`·`/friendships`·`/places`·`/venues` (prefix 없음).

### 범위에서 명시적으로 제외
- **ADR-0010 upstream keepalive 적용** — 운영 미적용 상태가 맞지만 성능 변경이라 blast radius 를 분리한다(별도 PR + 적용 후 실측).
- 비용 다이어트(ARM/단일 박스 통합), Terraform state S3 backend 이전, P3 위생(tfplan .gitignore·미머지 브랜치).

## 3. 테스트 케이스 (Test Cases)

> 백엔드 코드 변경이 0 이라 Cucumber/JUnit 대상이 없다. 대신 **실측 검증 케이스**로 대체한다 (ATDD 면제 근거: `docs/spec/test-strategy.md` 는 백엔드 소스 변경에 적용).

### Happy Path
- [ ] `terraform plan` → 의도한 리소스만 변경(NAT/ALB/Multi-AZ 0건)
- [ ] Origin CA 설치 후 `openssl s_client -connect <EIP>:443` 의 `notAfter` 가 15년 후
- [ ] `curl https://kicklog.org/actuator/health` → 200 (엣지 경유, SSL 모드 strict 상태)
- [ ] `curl https://kicklog.org/.well-known/apple-app-site-association` → 200 + `application/json`
- [ ] `apply-host-config.sh` 2회 연속 실행 → 두 번째도 성공(멱등)
- [ ] `pg-dump-to-s3.sh` 수동 실행 → S3 객체 생성 + `pg_restore --list` 로 덤프 유효성 확인

### Unhappy Path
- [ ] 깨진 nginx conf 를 넣고 `apply-host-config.sh` → `nginx -t` 실패 → **직전 conf 로 롤백 + 비정상 종료**, 서비스 무중단
- [ ] SG 제한 후 `curl -k https://<EIP>/nginx-health` (오리진 직접) → **연결 타임아웃**
- [ ] 동시에 엣지 경유 `https://kicklog.org/actuator/health` → 여전히 200
- [ ] `/auth/refresh` 를 1초에 30회 → 429 응답 발생(rate limit 동작), 일반 API 는 영향 없음
- [ ] Lambda 헬스 체크: 알람 임계 도달 시 SNS 메일 수신 확인(테스트 publish)

### Edge Cases
- [ ] `allow_direct_origin=true` apply → 본인 IP 에서만 오리진 직접 접근 가능, 다시 false 로 복귀
- [ ] rate limit 키가 **실제 클라이언트 IP** 인지 확인 — 서로 다른 두 네트워크에서 동시 호출 시 독립 카운트
- [ ] 인증서 잔여일 체크 스크립트에 만료 임박 인증서를 주입 → SNS publish 발생

## 4. 검증 (Verification)

### 자동 검증
```bash
# 백엔드 변경 없음을 확인 (컴파일 게이트는 통과해야 함)
cd backend && ./gradlew compileKotlin

# Terraform 정적 검사
cd infra/terraform && terraform fmt -check && terraform validate && terraform plan
```

### 시나리오 검증 (실측)
```bash
# TLS — 오리진 인증서 교체 확인
echo | openssl s_client -connect 3.37.14.253:443 -servername kicklog.org 2>/dev/null \
  | openssl x509 -noout -subject -enddate -issuer

# 엣지 정상 + strict 모드
curl -s -o /dev/null -w "%{http_code}\n" https://kicklog.org/actuator/health

# 오리진 직접 접근 차단
curl -k --max-time 8 https://3.37.14.253/nginx-health ; echo "exit=$?"   # 타임아웃 기대

# AASA
curl -sI https://kicklog.org/.well-known/apple-app-site-association | head -3

# 백업
aws s3 ls s3://kicklog-backup-576393818807/pg/ --region ap-northeast-2

# RDS 보존 기간
aws rds describe-db-instances --region ap-northeast-2 \
  --query "DBInstances[].BackupRetentionPeriod" --output text   # 7 기대

# 예산
aws budgets describe-budgets --account-id 576393818807 \
  --query "Budgets[].[BudgetLimit.Amount,CalculatedSpend.ForecastedSpend.Amount]" --output text
```

### 커버리지
해당 없음 (백엔드 코드 변경 0).

---

## (Optional) 위험도 / 롤백

**Risk = Risky** — 운영 TLS·SG·nginx 를 동시에 건드린다. 따라서 **박스 적용 순서를 고정**한다:

1. Origin CA 인증서 설치 (nginx 설정은 아직 LE 경로) → 영향 없음
2. 새 nginx conf 적용 (`nginx -t` 게이트 + 자동 롤백) → 엣지 200 확인
3. Cloudflare SSL 모드 `Full(strict)` 전환 → 엣지 200 재확인 (실패 시 즉시 `full` 로 되돌림)
4. SG 를 Cloudflare 레인지로 제한 → 엣지 200 + 오리진 직접 차단 확인
5. 백업·예산·Lambda 감시 apply (서비스 영향 없음)

**롤백 경로**
- nginx: `apply-host-config.sh` 가 `/etc/nginx/conf.d/kicklog.conf.bak-<ts>` 를 남기고 `nginx -t` 실패 시 자동 복원
- SG: `terraform apply -var allow_direct_origin=true` (1분) 또는 직전 state 로 revert
- Cloudflare SSL 모드: API PATCH 한 줄로 `full` 복귀
- 박스 접근 경로는 SSM Session Manager 이므로 SG 변경이 관리 채널을 끊지 않는다 (SSH 22 는 이미 미개방)

## (Optional) 후속 / 관련 이슈

- ADR-0010 upstream keepalive 운영 적용 (별도 PR, 적용 후 실측)
- 비용 다이어트: ARM 전환 / RDS→단일 박스 통합 → 월 $45 → $20~25
- Terraform state S3 backend 이전 (ADR-0009 D6 미완)
- iOS: `KickLog.entitlements` 에 `com.apple.developer.associated-domains` + `applinks:kicklog.org` 추가 (사용자 Xcode 작업)
- P3 위생: `tfplan*` .gitignore, 미머지 원격 브랜치 6개 정리
- Authenticated Origin Pulls(mTLS) 도입 검토 — Cloudflare 우회 차단의 다음 층

## (Optional) 학습 기록

- **Trigger**: production-risk
- **Root cause**: 감시가 인프라 메트릭(StatusCheck·CPU·Storage)만 보고 **사용자 경로(TLS·엣지→오리진)** 를 보지 않았다. 또 박스 설정이 Terraform/배포 경로 밖에 있어 `terraform plan` 의 "No changes" 가 거짓 안심을 줬다.
- **Prevention**:
  1. 운영 상태를 바꾸는 모든 설정은 **배포 산출물(S3→SSM)** 로만 적용한다 — 박스에 직접 손대면 재현 불가 상태가 된다.
  2. 외부에서 보이는 경로(엣지 HTTPS·인증서 잔여일)에 알람을 둔다. 인프라 메트릭만으로는 "앱은 살아 있고 TLS 만 죽은" 상태를 못 잡는다.
  3. `certbot --nginx` 를 프록시(Cloudflare) 뒤에서 쓰면 갱신이 조용히 죽는다 — 프록시 환경에서는 Origin CA 또는 DNS-01 을 쓴다.
- **Promoted to**: docs/agent/learning.md, docs/adr/0015-ops-tls-backup-hardening.md
