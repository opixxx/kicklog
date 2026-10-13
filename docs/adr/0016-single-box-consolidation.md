# ADR-0016: RDS 폐지 + ARM 단일 박스 통합, Secrets → SSM

- **Status**: Accepted
- **Date**: 2026-10-13
- **선행 ADR**: ADR-0006 (호스팅 — EC2 + RDS), ADR-0009 (Free Tier 운영 격상), ADR-0015 (운영 결함 정리)

## Context

2026-10-02 경 AWS **Free plan 크레딧이 소진**되어 EC2/RDS 가 실과금으로 전환됐다.
실측 월 환산 약 **$45** (VAT 포함):

```
RDS db.t3.micro      $20.40  ████████████████████  50%
EC2 t3.micro          $9.50  █████████             23%
Public IPv4           $3.65  ████                   9%
EBS gp3 30GB          $2.74  ███                    7%
RDS 스토리지 20GB      $2.62  ███                    6%
Secrets Manager 5개    $2.00  ██                     5%
```

그런데 **자원은 압도적으로 남는다** (14일 실측):

| 메트릭 | 값 | 해석 |
|---|---|---|
| EC2 CPU | 평균 **0.67%** / 최대 3.6% | vCPU 는 제약이 아니다 |
| RDS CPU | 평균 4.0% / 최대 59.9% | 동일 |
| DB 실사용 | **2.9GB** (20GB 중) | 스토리지도 제약이 아니다 |
| DatabaseConnections | 상시 **10 고정** | 동시성 요구가 사실상 없다 (HikariCP 풀) |
| NetworkOut | 375MB/월 | 100GB 무료 한도의 0.4% |

**제약은 CPU·스토리지·동시성이 아니라 메모리뿐이다.** t3.micro 의 1GB 가 앱 하나로 빠듯했고
(2026-09-06 메모리 고갈 → 스래싱 → 9일 마비), 그래서 DB 를 분리해 둔 것이지 부하 때문이 아니었다.

검토한 선택지(월 비용, VAT 포함):

| 안 | 구성 | 비용 | 약정 |
|---|---|---|---|
| 현행 유지 | EC2 + RDS | $45 | — |
| A+B-1 | ARM 전환 + SSM | $38 | 없음 |
| A+B-1+C | 위 + 1년 커밋(SP/RI) | $26 | **1년** |
| **A+B+D** | **ARM 단일 박스 + SSM** | **$25** | **없음** |
| Lightsail | 번들 $10 | $11 | 없음 — ADR-0006 D1 에서 학습 가치로 기각한 선택 |

$26(커밋)과 $25(통합)가 거의 같아, 선택 기준은 비용이 아니라 **무엇을 얻는가**였다.
사용자는 **A+B+D** 를 택했다 — 1년에 묶이지 않고, 실측 기반 right-sizing 과 메모리 예산
재설계라는 결과물이 남는다.

> **새 프리티어 계정으로 이전하는 안은 기각했다.** 2025-07 이후 신규 계정은 크레딧 $100/6개월
> 모델이라 반년 뒤 같은 문제가 반복되고, 다계정 프리티어는 약관 리스크가 있다. 기술적으로도
> AWS 관리형 KMS 키로 암호화된 **AMI·RDS 스냅샷은 교차 계정 공유가 불가**해 이전 비용이 크다.

---

## Decisions

### D1. Secrets Manager → **SSM Parameter Store** (−$2.0/월)

- **선택**: 비밀 5개를 `/kicklog/*` SecureString 으로 이전. Standard tier + `alias/aws/ssm` → 저장·조회 무료
- **이유**:
  - 비용 외에 **일원화**가 목적이다 — ADR-0015 가 `origin-cert`·`cloudflare-api-token` 을 SSM 에 두면서
    비밀 저장소가 2개로 갈라져 있었다
  - IAM 을 ARN 나열 → **경로 기반**(`parameter/kicklog/*`)으로 바꿨다. 2026-09-16 에 sentry-dsn ARN 이
    누락돼 Sentry 가 조용히 꺼져 있던 사고(ADR-0015)의 **실수 유형 자체를 없앤다**
- **포기**: 자동 rotation(미사용), 교차계정 공유(미사용)

### D2. **t3.micro(x86, 1GB) → t4g.small(arm64, 2GB)**

- **선택**: Graviton 전환 + 메모리 2배
- **이유**: 앱과 DB 를 합치려면 메모리가 필요하고, Graviton 이 동급에서 약 20% 싸다
- **빌드 함정**: Dockerfile 빌더 스테이지에 `--platform=$BUILDPLATFORM` 이 **필수**다.
  없으면 amd64 러너에서 Gradle 빌드 전체가 QEMU 에뮬레이션으로 돌아 20~40분이 걸린다.
  jar 는 아키텍처 중립이므로 네이티브로 만들고 런타임 스테이지만 arm64 로 둔다 (실측 빌드 60초)

### D3. RDS 폐지 → **Postgres 컨테이너 + 전용 EBS** (−$23/월)

- **선택**: `postgres:16-alpine` 컨테이너, 데이터는 **별도 EBS 20GB** 를 `/mnt/pgdata` 에 마운트
- **별도 볼륨인 이유**: 인스턴스를 교체해도 데이터가 살아남고, OS·도커 이미지가 디스크를 채워도
  DB 가 말려들지 않으며, EBS 스냅샷으로 DB 만 따로 백업할 수 있다. gp3 20GB = $1.82 로
  기존 RDS 스토리지($2.62)보다 싸다
- **메모리 예산 (2GB)** — 2026-09-06 재발 방지가 이 결정의 본체다:

| 구성 | 한도 | 근거 |
|---|---|---|
| backend | `mem_limit 512m` | 3주 이상 `RestartCount=0` 으로 검증된 값. heap 실측 93MB(상한 224m) |
| postgres | `mem_limit 512m` (`shared_buffers 128MB`) | DB 2.9GB · 커넥션 10 규모에 충분 |
| 호스트 | ~180MB | nginx·docker·containerd·SSM agent |
| page cache | ~800MB | **남는 메모리는 캐시로 보내는 편이 작은 DB 에 더 이롭다** |

  두 컨테이너 모두 `memswap_limit = mem_limit` — 스왑으로 연명하지 않고 **OOM kill → restart**
  경로로 간다. 호스트 스왑 2GB 는 OS 프로세스용 완충으로 유지한다.

- **"빈 DB 초기화" 사고를 3중으로 막는다.** 볼륨이 빠진 채 compose 가 뜨면 Postgres 가 빈
  디렉토리에 새 클러스터를 만들어 **데이터가 사라진 것처럼** 보인다. 가장 위험한 실패 모드다:
  1. `fstab` 에 `nofail` + 라벨 마운트
  2. 마운트 지점 디렉토리를 **immutable**(`chattr +i`) 로 — 볼륨 없이 쓰려 하면 실패한다
  3. `apply-host-config.sh` 가 기동 전에 `mountpoint` 검사, `check-host-health.sh` 가 10분마다 재확인

### D4. 감시 재설계 — RDS 메트릭 알람 3개의 역할 이전

RDS 가 사라지면 알람도 사라진다. **공백으로 두지 않는다**:

| 사라진 알람 | 역할 | 대체 |
|---|---|---|
| `rds-high-cpu` | DB 과부하 | 기존 EC2 `CPUUtilization` 알람 |
| `rds-low-storage` | 스토리지 고갈 | `check-host-health.sh` — 디스크 85% 초과 시 SNS |
| `backend-db-disconnected` | 앱↔DB 단절 = 앱 사망 | `check-host-health.sh` 컨테이너 health + 엣지 Lambda(ADR-0015) |

- `check-host-health.sh` (10분 타이머): 볼륨 마운트 · 디스크 · 컨테이너 health · 스왑 사용률.
  동일 문제는 6시간 쿨다운으로 묶어 알림 폭주를 막는다
- `kicklog-pg-dump.service` 에 `OnFailure=` 추가 — **백업 실패 자체를 통보**한다.
  RDS 자동 스냅샷이 사라진 지금 pg_dump 가 1차 복구 수단이라 조용한 실패를 허용할 수 없다

### D5. 컷오버 — **Blue/Green + EIP 이동**

- **선택**: 신규 박스를 띄워 복원·검증까지 마친 뒤 **EIP 만 옮긴다**. Cloudflare 설정은 건드리지 않는다
- **이유**: DNS 전파 대기가 없고(EIP 재연결은 수 초), 롤백이 "EIP 되돌리기" 한 번이다.
  검증 중에도 **구 박스가 계속 서비스**하므로 실패해도 사용자 영향이 0 이다
- **구 RDS**: 최종 스냅샷 후 즉시 삭제. 인스턴스를 2주 살려두는 것보다 스냅샷 보관(월 $0.3)이 싸고,
  두 DB 가 공존하며 어느 쪽이 정본인지 헷갈릴 위험도 없앤다

---

## 적용 결과 (2026-10-13)

| 항목 | 전 | 후 |
|---|---|---|
| 인스턴스 | t3.micro (x86, 1GB) | **t4g.small (arm64, 2GB)** |
| DB | RDS db.t3.micro + 20GB | **postgres:16-alpine 컨테이너 + EBS 20GB** |
| 비밀 저장소 | Secrets Manager 5개 | **SSM Parameter Store** (`/kicklog/*`) |
| CloudWatch 알람 | 7개 | 4개 + 박스 타이머 3종 |
| **월 비용** | **약 $45** | **약 $25** (−43%) |

**데이터 이전**: `users=16 · matches=24 · quarters=63 · tokens=95` — RDS 원본과 복원 결과 **완전 일치**.
**쓰기 차단 44초** (20:12:45 → 20:13:29). 엣지는 전환 순간 502 1건 후 전부 200.
최종 스냅샷 `kicklog-postgres-final-20260527-042626` 보관 중.

### 중간에 걸린 것 (모두 코드에 반영)

| 증상 | 원인 | 조치 |
|---|---|---|
| user-data 가 중간에 멈춰 nginx 조차 미설치 | **XFS 레이블은 최대 12자** — `kicklog-pgdata`(14자) 로 `mkfs` 실패 → `set -e` 로 전체 중단 | 레이블 `kicklogpg` + 볼륨 블록만 `set +e` 로 격리 |
| 데이터 디스크 탐지 실패 | terraform 이 인스턴스 **생성 후** 볼륨을 붙여 user-data 가 먼저 돈다 | 최대 90초 attach 대기 루프 |
| arm64 빌드가 느릴 뻔함 | Dockerfile 빌더가 타깃 아키텍처에서 Gradle 실행 | `--platform=$BUILDPLATFORM` (실측 60초) |
| 브랜치에서 CD 배포 잡 실패 | OIDC trust 가 `refs/heads/main` 전용 | **의도된 동작** — 구 운영 박스에 신규 compose 가 배포되는 것을 막았다 |

---

## Consequences

**좋아지는 것**
- 월 $45 → $25, **약정 없음**
- 비밀 저장소·IAM 이 경로 기반으로 단순해졌다
- DB 가 앱과 같은 네트워크 네임스페이스 안이라 커넥션 지연이 사라졌다(loopback)

**받아들이는 위험 (정직하게)**
- **물리적 격리를 잃었다** — 앱이 호스트를 메모리로 압박하면 DB 도 함께 위험하다.
  메모리 예산(D3)과 `memswap_limit`, 호스트 감시(D4)가 유일한 방어선이다
- **관리형 백업·PITR 이 사라졌다** — 복구 단위가 "매일 pg_dump"(최대 24시간 손실)다.
  iOS 가 1차 SoT(SwiftData)라 수용 가능하지만, 사용자가 늘면 재검토해야 한다
- **마이너 버전 업그레이드가 수동**이 됐다 (이미지 태그 갱신)
- 단일 장애점이 하나 늘었다 — 박스를 잃으면 앱과 DB 를 동시에 잃는다.
  대비는 별도 데이터 볼륨 + EBS 스냅샷 + S3 논리 백업 3중이다

## 후속

- 안정화 후 Compute Savings Plan 검토 → 월 $20 (통합과 양립 가능, RDS RI 와 달리 낭비되지 않는다)
- EBS 스냅샷 자동화(DLM) — 현재는 논리 백업만
- ADR-0010 upstream keepalive 적용 (별도 PR)
- Terraform state S3 backend 이전 (ADR-0009 D6 미완)
