# KickLog AWS Infrastructure (Terraform)

ADR-0006에 따라 AWS Seoul region (`ap-northeast-2`) Free Tier 인프라를 Terraform으로 관리.

## 사전 준비

### 1. AWS 계정 + IAM 사용자

```bash
# AWS CLI 설치 (macOS)
brew install awscli

# IAM 사용자 생성 (AWS Console에서)
# - 권한: AdministratorAccess (MVP 단계, v1.1에서 최소 권한으로 좁힘)
# - 액세스 키 생성

aws configure
# AWS Access Key ID: AKIA...
# AWS Secret Access Key: ...
# Default region: ap-northeast-2
# Default output format: json
```

### 2. SSH Key Pair

```bash
# AWS Console > EC2 > Key Pairs > Create
# Name: kicklog-keypair
# Type: ED25519 (또는 RSA 4096)
# 다운로드된 .pem 파일을 ~/.ssh/에 저장
chmod 400 ~/.ssh/kicklog-keypair.pem
```

### 3. Terraform 설치

```bash
brew install terraform
terraform version  # 1.6.0 이상 권장
```

### 4. 카카오 디벨로퍼 콘솔

- https://developers.kakao.com → 내 애플리케이션 → 추가
- 앱 이름: KickLog, 회사명: (본인)
- 앱 키 → **REST API 키** 복사

### 5. JWT secret 생성

```bash
openssl rand -base64 32
```

---

## 셋업

### 1. 변수 파일 작성

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars  # 실제 값 채우기
```

### 2. 본인 IP 확인 (SSH 허용용)

```bash
curl ifconfig.me
# 결과 IP를 terraform.tfvars의 allowed_ssh_cidr에 /32 추가
```

### 3. Terraform 초기화

```bash
terraform init
```

### 4. 계획 확인 (apply 전 필수)

```bash
terraform plan
```

> ⚠️ plan 결과를 꼼꼼히 읽어라. 예상치 못한 리소스(NAT Gateway, ALB 등 비싼 것)가 생성되는지 확인.

### 5. 실제 생성

```bash
terraform apply
# yes 입력
```

약 5~10분 소요 (RDS 생성이 가장 오래 걸림).

---

## 검증

### EC2 SSH 접속

```bash
# terraform output 에서 SSH 명령 복사
$(terraform output -raw ssh_command)
# 또는
ssh -i ~/.ssh/kicklog-keypair.pem ec2-user@$(terraform output -raw ec2_public_ip)
```

### user-data 실행 확인

```bash
# EC2 안에서
cat /var/log/kicklog-userdata.log
# 마지막에 "user-data 완료" 보이면 OK

sudo systemctl status docker
sudo systemctl status nginx
docker compose version
```

### RDS 연결 테스트

```bash
# EC2 안에서 (RDS는 EC2에서만 접근 가능)
sudo dnf install -y postgresql15
PGPASSWORD='your_password' psql \
  -h $(terraform output -raw rds_endpoint | cut -d: -f1) \
  -U kicklog -d kicklog -c "SELECT version();"
```

### Secrets Manager 읽기 테스트

```bash
# EC2 안에서 (IAM role 자동 적용)
aws secretsmanager get-secret-value \
  --secret-id kicklog/db-password \
  --region ap-northeast-2 \
  --query SecretString --output text
```

---

## 비용 모니터링

### AWS Cost Explorer
- AWS Console > Billing > Cost Explorer
- 매일 체크 권장 (실수로 NAT/ALB 생성 시 즉시 발견)

### Budget Alarm 설정 (강력 권장)
```
Budgets > Create budget > Monthly $5 → 이메일 알림
```

---

## 일상 운영

### Spring Boot 새 버전 배포

```bash
# 로컬에서 Docker 이미지 빌드 & push
cd backend
docker build -t ghcr.io/opixxx/kicklog:latest .
docker push ghcr.io/opixxx/kicklog:latest

# EC2 SSH 후
ssh -i ~/.ssh/kicklog-keypair.pem ec2-user@<EIP>
cd /opt/kicklog
docker compose pull
docker compose up -d
docker compose logs -f
```

### 인프라 변경

```bash
# 로컬에서
cd infra/terraform
vi *.tf  # 변경
terraform plan  # 확인
terraform apply
```

### 인프라 삭제 (개발 끝 / 비용 절감)

```bash
# ⚠️ 모든 데이터 삭제됨. RDS는 deletion_protection = true라 먼저 해제 필요
# 1. rds.tf에서 deletion_protection = false로 변경 + terraform apply
# 2. terraform destroy
terraform destroy
```

---

## 트러블슈팅

### `terraform apply` 권한 오류
- IAM 사용자 권한 확인 (AdministratorAccess 권장 MVP)
- `aws sts get-caller-identity`로 자격증명 확인

### SSH 안 됨
- `allowed_ssh_cidr` 본인 IP 확인 (IP 변경 시 `terraform apply` 재실행)
- Security Group 적용 1~2분 지연 가능

### RDS 연결 안 됨
- EC2 안에서만 접근 가능 (publicly_accessible = false)
- Security Group: rds-sg에 ec2-sg 인바운드 허용 확인

### Free Tier 초과 알림
- EC2 750h/m → 1개월 = 720~744h, **1대만 띄우면 안전**
- RDS 750h/m 동일
- Data Transfer Out 100GB/m 초과 가능성 — CloudWatch에서 모니터링

---

## v1.1 예정 마이그레이션

| 영역 | MVP | v1.1 |
|---|---|---|
| State backend | 로컬 `terraform.tfstate` | S3 + DynamoDB lock |
| HTTPS | nginx + Let's Encrypt | ALB + ACM |
| 도메인 | EIP 직접 | Route 53 + 도메인 |
| 배포 | 수동 SSH + docker compose | GitHub Actions + ECR |
| 모니터링 | 기본 CloudWatch | CloudWatch Synthetics + Alarms |
| 네트워크 | 단일 Public Subnet | Public + Private + NAT |

---

## 참조

- ADR-0006: 호스팅 결정 영구 기록 (`docs/adr/0006-hosting.md`)
- ADR-0003: 데이터 모델 + Secret 사용처 (`docs/adr/0003-data-model-and-api.md`)
