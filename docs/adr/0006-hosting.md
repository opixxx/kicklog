# ADR-0006: 백엔드 호스팅 선택 — AWS EC2 + RDS + Terraform

- **Status**: Accepted
- **Date**: 2026-05-21
- **선행 ADR**: ADR-0001 (MVP 스코프), ADR-0003 (데이터 모델 + 카카오 API 의존)

## Context

ADR-0001에서 "Railway / Fly.io 후보"로 보류된 호스팅 결정. ADR-0003 D6.1에서 카카오 로컬 API outbound가 추가되면서 **한국 region 가용성**이 중요 변수로 부상.

사용자(백엔드 개발자)가 **AWS + Terraform 학습 가치**를 활용하고 12개월 후 비용($20~30/m)도 받아들임.

---

## Decisions

### D1. 호스팅 플랫폼 — **AWS EC2 + RDS + Terraform**

- **선택**: AWS EC2 t3.micro (Public Subnet) + RDS db.t3.micro PostgreSQL, ap-northeast-2 (서울)
- **고려한 옵션**:
  - Railway ($5/m, Singapore region — 카카오 API 80~150ms RTT)
  - Fly.io (무료 티어 큼, 도쿄 region — 30~50ms)
  - GCP Cloud Run + Cloud SQL (서울 region, 5~20ms, 학습 비용 큼)
  - **AWS EC2 + RDS Free Tier (서울 region, 5~20ms) — 선택**
  - AWS Lightsail (단순, 학습 가치 약함)
  - AWS ECS Fargate (Free Tier 없음)
  - AWS Lambda + Aurora (Spring Boot 4 Native 미검증, 비추)
- **이유**:
  - **서울 region** — 카카오 API RTT 5~20ms (최단)
  - **12개월 Free Tier** — MVP 기간 운영비 거의 0
  - **AWS + Terraform 학습 가치** — 사용자 백엔드 본업의 클라우드 강점 확장
  - **본업 백엔드 개발자라 OS·docker·nginx 운영 부담 받아들임** (Lightsail 추상화 안 함)
  - **12개월 후 ~$20~30/m** 비용 부담 의지 확정

### D2. MVP 인프라 구조 — **단순 (NAT/ALB 없음)**

- **선택**: VPC + 단일 Public Subnet + EC2 1대 + RDS 1대 + Security Group 2개
- **명시적으로 안 쓰는 것**:
  - **NAT Gateway** ($30/m) — EC2가 Public Subnet에서 직접 outbound
  - **ALB** ($16/m) — nginx + Let's Encrypt로 HTTPS 직접 처리
  - **Private Subnet** — NAT 필요해지므로 MVP는 안 씀
  - **Bastion Host** — 단일 public EC2, SSH는 본인 IP 화이트리스트
- **이유**:
  - MVP는 사용자 N=20 규모, 고가용성·private 네트워크 over-engineering
  - 비용 폭증 함정 회피
  - v1.1+ 정식 출시 시 ALB + Private Subnet + NAT 도입 검토

### D3. OS / Runtime — **Amazon Linux 2023 + JDK 17 (일반 JVM)**

- **선택**: Amazon Linux 2023 + Amazon Corretto 17 + 일반 JVM (Spring Boot 4 fat jar)
- **고려한 옵션**: Ubuntu, GraalVM Native (메모리 100MB 수준)
- **이유**:
  - Amazon Linux 2023 — AWS 최적화 + 무료 + 빠른 부팅
  - JDK 17 — backend `build.gradle.kts`와 일치
  - **GraalVM Native는 Spring Boot 4 호환성 미검증** + 학습 비용 +1~2일 → v1.1 검토
  - t3.micro (1GB RAM)에서 일반 JVM은 빡빡(500~700MB heap) — OS swap + RAM 부족 시 t3.small 업그레이드 검토

### D4. 배포 방식 — **Docker + docker-compose on EC2**

- **선택**: Spring Boot multi-stage Dockerfile → Docker Hub or GHCR push → EC2에서 `docker compose pull && up -d`
- **CI/CD**: 초기 ADR 작성 시점에는 MVP 수동(SSH+docker compose), v1.1 GitHub Actions 로 계획. PR #47 머지 후 SSH 보안 룰 충돌 발생 → **ADR-0008** 에서 SSM Run Command + S3 staging + OIDC 로 자동 배포 전환 (22 포트 의존 제거)
- **이유**:
  - Docker = 표준 + 환경 재현성
  - 1인 사이드 MVP에 CI/CD over-engineering
  - v1.1에서 GitHub Actions OIDC + ECR push

### D5. HTTPS — **nginx + Let's Encrypt (Certbot)**

- **선택**: nginx reverse proxy + Let's Encrypt 자동 갱신
- **고려한 옵션**: ALB + ACM (월 $16, 자동 갱신 자동)
- **이유**:
  - ALB 월 $16 절감 (Free Tier 아님)
  - Let's Encrypt + Certbot 표준 흐름 — 학습 가치 (인증서 갱신 자동화)
  - 정식 출시 + 트래픽 증가 시 ALB 도입 검토

### D6. Secrets 관리 — **AWS Secrets Manager**

- **선택**: Secrets Manager에 DB 비밀번호·카카오 API 키·JWT secret 저장
- **고려한 옵션**: SSM Parameter Store (무료), 환경변수 직접 (위험)
- **이유**:
  - **약 $0.40/secret/m** — 5~6 secrets = 월 $2 정도 (예산 안에 있음)
  - 학습 가치 (자동 rotation 가능, IAM 통합)
  - SSM Parameter Store는 더 저렴 (free tier — `String` 타입 무료) 하지만 secret 전용 기능 부족
  - **대안**: 비용 부담이 진짜 부담이면 SSM SecureString으로 전환 가능

### D7. 도메인 — **MVP는 IP 직접, 정식 출시 시 등록**

- **선택**: MVP는 EC2 EIP로 접근 (`https://13.xxx.xxx.xxx`). 정식 출시 시점에 `kicklog.app` 또는 `.io`/`.com` 등록 (~$15/년)
- **이유**:
  - 본인+팀원 TestFlight 단계 = IP 직접 접근 OK
  - Universal Link (친구 초대) 위해서는 도메인 필수 — 정식 출시 시 ADR-0005에서 결정
  - Let's Encrypt는 도메인 필요 → MVP TestFlight 단계는 self-signed cert 또는 HTTP, 정식 출시 직전 도메인 + HTTPS

### D8. State 관리 — **MVP는 로컬, v1.1에 S3 backend**

- **선택**: MVP는 `terraform.tfstate` 로컬 파일 + gitignore
- **고려한 옵션**: Terraform Cloud (Free Tier), S3 backend + DynamoDB lock
- **이유**:
  - 1인 사이드 + MVP에 collaborative state 불필요
  - 로컬 백업으로 충분 (사용자 머신 백업 시 같이)
  - v1.1+ S3 backend 도입 학습 가치 — `terraform init -backend-config=...` 마이그레이션

---

## MVP 인프라 다이어그램

```
                      Internet
                         │
                         │ (DNS: MVP는 EIP, v1.1에 Route 53)
                         ▼
                  ┌─────────────┐
                  │   EIP       │ (탄력 IP, 1개)
                  └──────┬──────┘
                         │
        ┌────────────────┴─────────────────────────┐
        │  VPC (10.0.0.0/16)                       │
        │  ┌─────────────────────────────────────┐ │
        │  │ Public Subnet (10.0.1.0/24)          │ │
        │  │  ┌───────────────────────────────┐  │ │
        │  │  │ EC2 t3.micro                  │  │ │
        │  │  │   - Amazon Linux 2023         │  │ │
        │  │  │   - Docker + docker-compose   │  │ │
        │  │  │   - Spring Boot 4 (JDK 17)    │  │ │
        │  │  │   - nginx (HTTPS proxy)       │  │ │
        │  │  │   - Certbot (LE auto-renew)   │  │ │
        │  │  │ SG: 80, 443 (0.0.0.0/0)       │  │ │
        │  │  │     22 (본인 IP only)         │  │ │
        │  │  └───────────────┬───────────────┘  │ │
        │  │                  │ 5432              │ │
        │  │  ┌───────────────┴───────────────┐  │ │
        │  │  │ RDS db.t3.micro               │  │ │
        │  │  │   - PostgreSQL 16             │  │ │
        │  │  │   - 백업 자동 7일               │  │ │
        │  │  │ SG: 5432 (EC2 SG에서만)        │  │ │
        │  │  └───────────────────────────────┘  │ │
        │  └─────────────────────────────────────┘ │
        │                                          │
        │  Secrets Manager:                        │
        │    - kicklog/db-password                 │
        │    - kicklog/kakao-rest-api-key          │
        │    - kicklog/jwt-secret                  │
        └──────────────────────────────────────────┘
```

---

## 비용 예측 (서울 region, 2026 기준)

### 12개월 무료 기간

| 리소스 | 비용 |
|---|---|
| EC2 t3.micro 750h/m | $0 (Free Tier) |
| RDS db.t3.micro 750h/m | $0 (Free Tier) |
| EBS gp3 30GB | $0 (Free Tier) |
| EIP (활성 1개) | $0 (사용 중인 동안) |
| Data Transfer Out 100GB/m | $0 (Free Tier) |
| Secrets Manager 5 secrets | ~$2/m |
| **합계** | **~$2/m** |

### 13개월 후

| 리소스 | 월 비용 |
|---|---|
| EC2 t3.micro On-Demand | ~$7.50 |
| RDS db.t3.micro | ~$12.50 |
| EBS gp3 30GB | ~$2.40 |
| Secrets Manager | ~$2 |
| Data Transfer (100GB 이내) | $0~9 |
| **합계** | **~$24~33** |

→ **Savings Plan (1년 commit)** 적용 시 EC2/RDS 약 30~40% 할인 → $17~22/m.

---

## 일정 영향

| 작업 | 시간 (Terraform 처음 가정) |
|---|---|
| Terraform 기초 학습 | 1일 |
| AWS Free Tier 인프라 정의 (.tf 작성) | 1일 |
| `terraform init/plan/apply` + 트러블슈팅 | 0.5~1일 |
| EC2 SSH + Docker + nginx + Certbot 셋업 | 0.5일 |
| Spring Boot 컨테이너 + EC2 배포 검증 | 0.5일 |
| RDS 연결 검증 + Flyway 마이그레이션 실행 | 0.5일 |
| **합계** | **약 3~4일** |

→ Fly.io (반나절) 대비 **+3일** 학습 투자.

---

## 보안 정책 (Security Group 요약)

| SG | 인바운드 | 아웃바운드 |
|---|---|---|
| **ec2-sg** | 80 (0.0.0.0/0), 443 (0.0.0.0/0), 22 (본인 IP/32) | All (카카오 API outbound) |
| **rds-sg** | 5432 (ec2-sg) | None |

SSH는 본인 IP 변경 시마다 `terraform apply`로 업데이트 — 약간 마찰이지만 보안 우선. 자동 CD 는 SSH 를 거치지 않고 SSM Run Command 로 동작 (ADR-0008). SSH 22 룰 자체의 완전 제거는 SSM 안정 운영 확인 후 별도 PR.

---

## Consequences

### 긍정
- **AWS + Terraform 학습** — 본인 백엔드 강점 확장
- **서울 region** — 카카오 API RTT 최단
- **12개월 무료** — MVP 비용 거의 0
- **표준 인프라 패턴** — VPC + Subnet + SG + EC2 + RDS = 면접에서 설명 쉬움
- **IaC** — `terraform destroy` 후 `apply`로 환경 재현 가능

### 부정 / 트레이드오프
- **MVP +3~4일** (학습 포함)
- **운영 부담** — OS 패치, RDS minor 버전 업데이트, 인증서 만료 모니터링
- **13개월 후 ~$24/m** 비용 즉시 노출
- **t3.micro RAM 1GB 빡빡** — 일반 JVM 메모리 부족 시 t3.small 업그레이드
- **잘못 구성 시 비용 폭증 위험** — NAT Gateway 실수 추가, RDS 큰 instance 등 (Terraform plan 검토 필수)

### v1.1+ 마이그레이션 후보
- ALB + ACM (TLS 자동화 + 도메인 직접 연결)
- Private Subnet + NAT Gateway (DB 격리)
- S3 backend for Terraform state
- ECR + GitHub Actions OIDC 자동 배포
- CloudWatch Synthetics (헬스체크 + 알람)
- AWS WAF (Bot 방어)

---

## Revisions

| 날짜 | 변경 | 사유 |
|---|---|---|
| 2026-05-21 | 초기 작성 | grill-me 인터뷰 D1~D8 |
