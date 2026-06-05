# ADR-0011: 복제 부하테스트 1차 측정 — 앱 티어 병목(HikariCP 풀=10 + t3 버스트 고갈)이 쿼리 병목을 가린다

- **Status**: Accepted — 1차 측정(iteration 1)
- **Date**: 2026-06-03
- **선행 ADR**: ADR-0006 (호스팅: EC2+RDS), ADR-0010 (keepalive lifecycle — 경로 B)
- **설계 SoT**: `docs/research/loadtest-portfolio-scenario.md` (트랙 C)
- **하네스**: PR #62 (`@Profile("loadtest & !prod")` token/seed), PR #63 (`infra/terraform-loadtest/` + `k6/api-load.js`)
- **측정 산출물(로컬·gitignore)**: `docs/research/assets/measurement-trackC-iter1.md`

## Context

트랙 C 의 목표는 **인프라 천장을 걷어내고 순수 API 코드·쿼리 병목을 측정**하는 것이다. 운영(prod)은 t3.micro × 1 + RDS db.t3.micro 라 인프라가 먼저 터져 코드 병목이 안 보인다. 그래서 prod 와 **state 격리된** 일회성 복제 환경을 Terraform 으로 구축한다 (`infra/terraform-loadtest/`, 로컬 state, 끝나면 `destroy`).

측정 핫스팟(read): `GET /users/me/seasons/{year}`(통계 derive — 가장 무거움), `GET /matches`(커서 페이지네이션 N+1 의심), `GET /friendships`.

**가설**: 넉넉한 인스턴스(backend t3.large 2vCPU/8GB, RDS db.t3.medium 2vCPU)면 인프라 천장이 사라져 `seasons` 통계 derive 집계 SQL 이 1차 병목으로 드러날 것이다.

**결과(요약)**: 가설은 **틀렸다**. 복제 환경에서도 1차 병목은 쿼리가 아니라 **앱 티어 설정·인스턴스 천장**(HikariCP 풀=10 + backend t3.large 버스트 CPU 고갈)이었고, RDS 는 72% 로 아직 진짜 벽이 아니었다. 즉 **쿼리 병목을 측정하려면 먼저 이 두 천장을 제거**해야 한다.

---

## 측정 셋업

| 구성 | 값 |
|---|---|
| backend EC2 | t3.large (2 vCPU / 8 GB), 8080 직접, `SPRING_PROFILES_ACTIVE=loadtest` |
| loadgen EC2 | c5.large, 같은 VPC (backend private IP 타격 → 네트워크 변수 최소) |
| RDS | db.t3.medium PostgreSQL 16.14, Performance Insights ON |
| 시드 | user 1,000 · match 300,000 · quarter 1,200,000 · **friendship 0** (`LoadTestSeedService`, JdbcTemplate batch) |
| 부하 | k6 v2.0.0 `ramping-arrival-rate`, up to 800 iters/s, 7m30s 5단계 (50→150→400→800→0 VU), readScenario = seasons + matches(2page) + friendships |
| HikariCP | `maximum-pool-size` **미설정 → 기본 10** (loadtest·base yml 모두 명시 없음) |

1 iteration = `seasons` + `matches_list`(2페이지) + `friendships` ≈ HTTP 4회.

## 측정 결과 (2회 재현, ±1% 일치)

| 지표 | 1차 | 2차 |
|---|---|---|
| 처리량 | 353 req/s · 88.2 iters/s | 356 req/s · 88.9 iters/s |
| dropped_iterations | 90,838 | 90,617 |
| 에러율 (http_req_failed) | **0.00%** | **0.00%** |
| p95 `seasons` (목표 1.5s) | 2.65s ✗ | 2.67s ✗ |
| p95 `matches_list` (목표 0.8s) | 2.56s ✗ | 2.59s ✗ |
| p95 `friendships` (목표 0.5s) | 2.53s ✗ | 2.56s ✗ |

**티어별 (CloudWatch, 피크 14:28~14:33):**

| 티어 | 지표 | 값 |
|---|---|---|
| backend EC2 | CPUUtilization | avg 66~68% / **max 90%** |
| backend EC2 | **CPUCreditBalance** | 0.93 → **0.0 (고갈)** |
| backend EC2 | CPUSurplusCreditBalance | 0.0 → **4.39 (적자 차입)** |
| RDS | CPUUtilization | 5% → **72% (피크)** |
| RDS | **DatabaseConnections** | **전 구간 정확히 10.0 고정** |

---

## Decisions (관측 기반 판정)

### D1. 1차 병목은 DB 가 아니라 **앱 티어** — "공유 자원 큐잉"

세 엔드포인트 p95 가 거의 동일(2.53~2.67s)하고, **시드 0건이라 빈 결과를 반환하는 `friendships` 조차 p95 2.5s** 다. 빈 쿼리가 2.5s 걸린다는 건 쿼리 자체가 느린 게 아니라 **요청이 공유 자원에서 줄 서고 있다**는 결정적 증거다. min 응답은 빠름(seasons 25ms, matches 12ms, friendships 2.4ms) → 한가할 땐 빠르고 부하 시 큐잉 = 전형적 자원 포화.

### D2. 공유 자원 ① — **HikariCP 풀 = 10** 이 DB 동시성 하드캡

`DatabaseConnections` 가 테스트 내내 **정확히 10.0** 에 붙어 있었다. 풀(기본 10)이 DB 로 가는 동시성을 10 으로 고정 → 800 VU 가 몰려도 DB 는 동시 10 쿼리만 처리, 나머지는 풀 대기. Little's Law 로 교차검증: 10 conn × ~28ms/op ≈ **350 ops/s** 로 실측 처리량(356 req/s)과 일치. 에러 0% 인 이유 = Hikari `connectionTimeout`(기본 30s) 안에 커넥션을 받아 200 OK 로 응답하되 느림.

### D3. 공유 자원 ② — **backend t3.large 버스트 CPU 고갈**

backend 가 버스터블(t3) 인데 지속 부하로 **CPUCreditBalance 가 0 으로 고갈**되고 CPU 90% 까지 찼다. 앱 서버 연산(통계 derive 인앱 집계·직렬화·JWT 검증)이 2 vCPU + 버스트에 묶여 또 하나의 천장을 형성. 버스터블 인스턴스를 **지속 부하 측정 대상**으로 쓰면 안 된다는 함정.

### D4. RDS(72%)는 아직 진짜 벽이 아니다

DB 는 10 커넥션을 받아 CPU 72% — 바쁘지만 미포화. 풀을 올리면 RDS CPU 가 100% 로 향할 것(72% × N/10). 즉 **현재 측정으로는 `seasons` 통계 derive 쿼리 비용을 분리 측정하지 못했다**. 풀·버스트 천장에 가려졌다.

### D5. 재현성 확보

2회 측정이 처리량·dropped·p95 모두 ±1% 로 일치 → ~356 req/s 천장은 노이즈가 아닌 **구조적·재현 가능한 knee**.

---

## Consequences / 후속 (iteration 2)

쿼리 병목(특히 `seasons` derive)을 드러내려면 **앞단 천장부터 제거**한 뒤 재측정한다:

1. **HikariCP `maximum-pool-size` 상향** (10 → 30~50) — `application-loadtest.yml`. RDS db.t3.medium `max_connections ≈ 410` 이라 안전.
2. **backend 인스턴스를 non-burstable 로** (t3.large → c5.large/c5.xlarge) — 버스트 고갈 변수 제거.
3. 재측정 → 병목이 **RDS CPU(2 vCPU)** 로 넘어가는지 확인. 넘어가면 그때가 `seasons` 집계 SQL 최적화(인덱스/쿼리 재작성) or RDS 스케일의 출발점.
4. **(미해결) write(PUT /matches) 측정** — `UpsertMatchRequest.venueId` non-null FK 인데 현재 시드가 venue 미생성. `LoadTestSeedService` 에 venue 시드 추가 후 `k6` writeScenario 활성화.

> **본질 프레이밍(포트폴리오)**: "복제환경이면 코드 병목이 보일 것"이라는 직관이 **풀 사이징(커넥션 풀) → 버스터블 인스턴스 함정 → DB CPU** 의 3층 구조에 막힌 사례. knee point 를 한 층씩 걷어내며 진짜 병목으로 내려가는 과정 자체가 측정 스토리다. 측정 산출물·그래프는 `docs/research/assets/`(로컬·gitignore, 블로그용).

## 비용

측정 후 `terraform destroy` 로 종료(사용자 직접 실행). EC2 ×2 + RDS 일회성 (~$2 수준).
