# ADR-0015: 운영 결함 정리 — Origin CA TLS · 백업 이중화 · 호스트 설정 IaC 화 · 오리진 차단

- **Status**: Accepted
- **Date**: 2026-10-10
- **선행 ADR**: ADR-0006 (호스팅), ADR-0007 (도메인), ADR-0008 (CD via SSM), ADR-0009 (Free Tier 운영 격상), ADR-0013 (SNS 알람 전달)

## Context

2026-10-10 운영 실측 점검에서 **앱 밖의 결함 4건**이 드러났다. 앱 레이어는 건강하다 —
uptime 25일, `RestartCount=0`, `OOMKilled=false`, 30일 커널 OOM 로그 0건, 7일 ERROR 로그 1건.
2026-09-06 장애 대책(`mem_limit 512m` + swap 2GB + `swappiness=10`)은 실제로 작동하고 있다.

### 1. 오리진 TLS 가 46일째 만료 상태였다

```
오리진(3.37.14.253) CN=kicklog.org  notAfter=Aug 25 2026   ← 만료
엣지(Cloudflare)    CN=kicklog.org  notAfter=Dec 21 2026   ← 정상
certbot.timer        존재하지 않음
certbot-renew.timer  disabled
/var/www/certbot     디렉토리 없음 · 80 server 는 return 404
```

DNS 는 Cloudflare 프록시(A 레코드 = `104.21.33.107`/`172.67.189.210`)이고 SSL 모드가
`Full(비 strict)` 이라 엣지가 오리진 인증서를 **검증하지 않는다**. 그래서 46일간 무증상이었다.

근본 원인은 두 겹이다.
- **구조**: `certbot --nginx` 의 HTTP-01 갱신은 프록시 뒤에서 성립하지 않는다. 80/443 이 엣지로
  흡수되고 오리진 80 에 ACME 경로가 없었다. 게다가 타이머가 `disabled` 라 실패조차 발생하지 않았다.
- **감시**: 알람 6개가 전부 인프라 메트릭(StatusCheck·CPU·FreeStorage·DatabaseConnections·
  VolumeReadBytes)이라 **사용자 경로를 보는 눈이 0개**였다. ADR-0013 이 "알람이 있는데 통보가
  안 가던" 문제를 고쳤다면, 여기서는 **애초에 그 현상을 보는 알람이 없었다.**

### 2. 백업이 1일분뿐이고 예산 알람이 무의미해졌다

- `backup_retention_period = 1`, 수동 스냅샷 0개. 2026-09-06 장애는 **인지까지 9일** 걸렸다 —
  그 시점에 복구 가능한 백업은 존재하지 않았다. `rds.tf` 의 "Free Tier 가 1일만 허용" 주석은
  2026-10-02 경 크레딧 소진으로 실과금 전환되면서 더 이상 사실이 아니다.
- Budget 한도 $5 / 실적 $13.16 / **forecast $42.87** → 80%·100%·forecast 알림 3건이 매달 전부
  울려 alert fatigue 상태. 정작 "NAT 를 실수로 만든" 류의 사고를 못 잡는다.

### 3. 호스트 설정이 코드 밖에 있었다 (IaC 공백)

`terraform plan` 은 "No changes" 지만, 그건 박스 내부가 애초에 Terraform 밖이기 때문이다.

| | 운영 박스 | 저장소 |
|---|---|---|
| AASA location · `/nginx-health` · `client_max_body_size 10M` · `proxy_read_timeout 30s` | ✅ | ❌ |
| rate limit (auth 10r/s · api 50r/s) | ❌ **미적용** | ✅ |
| ADR-0010 upstream keepalive | ❌ | ❌ |

추가로 `user-data.sh` 에 `jq` 가 없어 **새 박스는 첫 배포가 반드시 실패**하고(`fetch-secrets.sh`
가 `exit 1`), AASA 파일은 nginx 가 경로만 가리킬 뿐 **실제 파일이 없었다**.
즉 지금 박스를 잃으면 코드만으로 복구할 수 없는 상태였다.

### 4. 오리진이 인터넷에 직접 노출돼 있었다

`curl -k https://3.37.14.253/nginx-health` → **200**. SG 가 80/443 을 `0.0.0.0/0` 으로 열어둬서
Cloudflare 의 WAF·rate limit·캐시를 우회해 백엔드를 직접 때릴 수 있었다. nginx access log 에
실제로 스캐너(Palo Alto Xpanse, internet-measurement.com, GenomeCrawler)와 정체불명 IP 의
직접 요청이 남아 있고, 이들은 Spring Security 까지 도달해 401 을 받고 있었다.
저장소에만 있던 rate limit 이 운영에 없어 **인증 엔드포인트 brute force 완화도 0** 이었다.

---

## Decisions

### D1. TLS — **Cloudflare Origin CA (15년)**, certbot/LE 의존 제거

- **선택**: Origin CA 인증서를 발급해 SSM SecureString 에 보관하고 박스가 받아 설치.
  Cloudflare SSL 모드는 `Full(strict)` 로 격상.
- **고려한 옵션**:
  - (A) certbot 을 고쳐 HTTP-01 복구 — 프록시 뒤라 `/.well-known` 을 엣지가 가로채지 않도록
    별도 룰이 필요하고, 90일마다 같은 실패 지점이 돌아온다
  - (B) DNS-01 (`certbot-dns-cloudflare`) — 동작하지만 API 토큰 + 플러그인 + 90일 갱신 의존 유지
  - (C) **Cloudflare Origin CA — 채택**
- **이유**:
  - 엣지만 신뢰하면 되므로 공인 CA 가 필요 없다. 유효기간 15년 → 갱신 자동화 자체가 사라진다
  - `Full(strict)` 와 짝을 이뤄야 의미가 있다. strict 가 아니면 **오리진이 깨져도 사용자에게는
    200 이 내려간다** — 이번 사고의 은폐 메커니즘이 바로 그것이었다
  - 80 포트 의존(ACME)이 사라져 D4(오리진 차단)에서 80 을 아예 닫을 수 있다
- **구현**: `issue-origin-cert.sh`(로컬 1회) → SSM → `install-origin-cert.sh`(박스).
  인증서/키 쌍 일치를 공개키 해시로 검증한 뒤에만 설치한다.
- **함께 바꾼 엣지 설정** (둘 다 D4 의 전제이기도 하다):
  - `always_use_https: off → on`. 꺼져 있어서 엣지가 평문 요청을 **오리진 80 으로 그대로 전달**하고
    있었다(실측: `172.64.192.161 → :80`, 301). 켜면 승격이 엣지에서 끝나 오리진 80 이 불필요해진다
  - `min_tls_version: 1.0 → 1.2`. TLS 1.0/1.1 을 엣지가 받아주고 있었다. 클라이언트는
    iOS 18+ 앱과 현대 브라우저뿐이라 영향 없음

### D2. 감시 — **사용자 경로를 보는 알람 2종 추가**

- **선택**:
  - Lambda(`kicklog-edge-health`) 가 EventBridge 5분 주기로 **엣지** `https://kicklog.org/actuator/health`
    를 외부에서 호출 → 커스텀 메트릭 `KickLog/Edge.EdgeHealthy` → 10분 연속 비정상이면 SNS
  - 박스 systemd timer 가 매일 오리진 인증서 잔여일을 확인, 21일 이하이면 SNS 직접 발행
- **고려한 옵션**: Cloudflare Health Checks(유료 플랜), 외부 SaaS(UptimeRobot 등), CloudWatch Synthetics(월 ~$0.4)
- **이유**:
  - Lambda 월 8,640회(무료 100만) + 커스텀 메트릭 2개(무료 10개) + 알람 1개(무료 10개 중 7번째) = **$0**
  - VPC 밖에서 실행되므로 "사용자가 보는 경로" 와 동일하다 — nginx 만 사망·엣지 장애·TLS 만료를 모두 잡는다
  - 인증서는 박스 로컬 파일이라 CloudWatch 가 볼 수 없다 → 박스에서 직접 SNS 발행이 유일하게 단순한 길
- **임계 근거**: 5분 × 2 = 10분. 배포 중 순간 502 로 오탐하지 않을 만큼 길고, "9일간 아무도 모름" 은 확실히 막는다

### D3. 백업·예산 — **보존 7일 + pg_dump 논리 백업 이중화**, 예산 한도 현실화

- **선택**:
  - `backup_retention_period` 1 → **7**
  - `kicklog-backup-<account_id>` 버킷 + 매일 04:30 KST `pg_dump -Fc` → `pg/` prefix, 30일 lifecycle
  - `budget_monthly_usd` 5 → **50**
- **이유**:
  - 스냅샷만으로는 ① 교차 계정 복원 불가(AWS 관리형 KMS 키로 암호화) ② 테이블 단위 부분 복구 불가
    ③ 엔진 업그레이드 사고 시 되돌릴 포맷 없음 — 논리 백업이 이 셋을 모두 커버한다
  - 업로드 전에 `pg_restore --list` 로 덤프를 검증한다. **검증 없는 백업은 백업이 아니다**
  - EC2 IAM 은 `s3:PutObject` 만 — 박스가 침해돼도 과거 백업을 지울 수 없다
  - 비용: 스냅샷 증분 ~$0.3/월 + S3 수십 MB → 월 $0.5 미만
  - 예산 한도는 "현 수준보다 약간 위" 로 둬서 사고 감지 기능을 복원한다. 비용 다이어트 후 재조정

### D4. 오리진 차단 — **Cloudflare 레인지만 443 허용**, break-glass 토글

- **선택**: `data.http` 로 Cloudflare 공식 IP 목록을 받아 SG ingress 를 그 레인지로 제한.
  80 은 닫는다(엣지의 Always Use HTTPS 가 http→https 승격을 처리). `var.allow_direct_origin`
  토글(기본 false)로 비상 시 본인 IP/32 만 임시 허용 — `enable_ssh_inbound`(ADR-0009 D4) 와 동일 패턴
- **고려한 옵션**: Authenticated Origin Pulls(mTLS) — 더 강하지만 인증서 운용이 추가된다. 후속 검토
- **이유**:
  - 정상 트래픽은 100% 엣지 경유다. 직접 경로는 공격 표면일 뿐이고 실제로 스캔당하고 있었다
  - 80 을 닫으면 SG 룰 수가 절반이 된다 (CIDR 1개 = 룰 1개, 기본 쿼터 60)
  - 관리 채널이 SSM 이라 SG 를 좁혀도 접근 수단을 잃지 않는다
- **함정**: 목록 조회는 apply 시점 네트워크 의존이다. 또 **realip 설정이 선행돼야 한다** —
  프록시 뒤에서는 모든 요청의 `remote_addr` 이 엣지 IP 라, 복원하지 않으면 rate limit 이
  전 사용자를 한 버킷으로 묶고 로그·Sentry 의 IP 도 전부 엣지 IP 가 된다

### D5. 호스트 설정 — **배포 산출물로만 변경** (`apply-host-config.sh`)

- **선택**: nginx conf · TLS 인증서 · realip · AASA · systemd timer 를 S3 staging(`host/` prefix)에
  올리고, SSM 이 `apply-host-config.sh` 를 실행해 멱등 배치. `nginx -t` 통과 시에만 reload,
  실패 시 직전 conf 자동 롤백. `cd.yml` 의 `paths` 에 `infra/scripts/**`·`infra/systemd/**`·`infra/web/**` 추가
- **이유**:
  - 박스에 직접 손대면 저장소와 운영이 갈라지고, `terraform plan` 의 "No changes" 가 거짓 안심을 준다
  - ADR-0008 이 만든 S3→SSM 경로를 그대로 재사용한다 — 새 채널을 만들지 않는다
  - 적용 순서(인증서 → realip → nginx conf)가 스크립트에 고정되어 "순서를 틀려서 깨지는" 여지를 없앤다
- **범위 밖**: ADR-0010 의 upstream keepalive 적용은 성능 변경이라 분리한다(별도 PR + 적용 후 실측)

---

## Consequences

**좋아지는 것**
- 오리진 TLS 가 15년짜리로 바뀌고, 깨지면 **10분 안에 메일이 온다**
- `Full(strict)` 로 올려 "오리진이 깨져도 200" 이라는 은폐가 사라진다
- 복구 창이 1일 → 7일(+30일 논리 백업)로 넓어진다
- 박스를 통째로 잃어도 `user-data.sh` + CD 한 번으로 재현된다
- 오리진 직접 공격 경로가 닫히고, 인증 엔드포인트에 rate limit 이 처음으로 적용된다

**비용**: 월 +$0.5 미만 (스냅샷 증분 + S3). Lambda·메트릭·알람은 Free Tier 안.

**받아들이는 위험**
- `terraform plan/apply` 가 cloudflare.com 네트워크 접근에 의존한다 (목록 조회 실패 시 plan 실패)
- Cloudflare 가 IP 레인지를 추가하면 재 apply 전까지 일부 엣지 노드가 차단될 수 있다 (연 1~2회 수준)
- rate limit 이 운영에 처음 적용된다 — 임계(auth 10r/s·burst 20, api 50r/s·burst 100)는 측정 기반이
  아니라 보수적 추정이다. 429 가 관측되면 조정한다

## 적용 결과 (2026-10-10)

| 항목 | 적용 전 | 적용 후 |
|---|---|---|
| 오리진 인증서 | 2026-08-25 만료 (46일 경과) | Origin CA, **2041-10-06** |
| Cloudflare SSL | `full` (오리진 미검증) | **`strict`** |
| 오리진 직접 접근 | `https://<EIP>/nginx-health` → 200 | **차단** (CF 443: v4 15 + v6 7) |
| rate limit | 없음 | `/auth/` 40회 동시 → 23×405 / **17×429** |
| DB 백업 | 자동 스냅샷 1일 | 스냅샷 7일 + 매일 pg_dump (첫 덤프 41KB, `pg_restore --list` 검증) |
| 사용자 경로 감시 | 없음 | Lambda 5분 주기 (`EdgeHealthy=1`, 알람 `OK`) + 인증서 잔여일(5,474일) |
| Budget | $5 (상시 초과) | $50 |
| AASA | 파일 없음 | 200 · `application/json` |

`terraform plan` → **No changes** (코드와 실제 인프라 일치).

## 후속

- ADR-0010 upstream keepalive 운영 적용 (별도 PR)
- 비용 다이어트: ARM 전환 / RDS → 단일 박스 통합 → 월 $45 → $20~25
- Terraform state S3 backend 이전 (ADR-0009 D6 미완)
- Authenticated Origin Pulls(mTLS) 검토
- iOS: `KickLog.entitlements` 에 `com.apple.developer.associated-domains`(`applinks:kicklog.org`) 추가 — 서버 쪽 AASA 는 본 ADR 에서 갖췄다
