# =============================================
# Variables — terraform.tfvars에서 값 주입
# =============================================

variable "aws_region" {
  description = "AWS region (서울 — 카카오 API RTT 최단)"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "환경 이름 (dev / prod). MVP는 prod 단일."
  type        = string
  default     = "prod"
}

# ─── Network ──────────────────────────────────────────
variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public Subnet CIDR (단일, ADR-0006 D2)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_az" {
  description = "Public Subnet의 가용 영역"
  type        = string
  default     = "ap-northeast-2a"
}

# RDS는 multi-AZ 안 쓰지만 subnet group은 최소 2 AZ 필요
variable "rds_subnet_cidr_b" {
  description = "RDS subnet group용 2번째 AZ subnet (실제 사용 안 함, AWS 정책)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "rds_subnet_az_b" {
  description = "RDS subnet group용 2번째 AZ"
  type        = string
  default     = "ap-northeast-2c"
}

# ─── EC2 ──────────────────────────────────────────────
variable "ec2_instance_type" {
  description = "EC2 인스턴스 타입 (Free Tier: t3.micro)"
  type        = string
  default     = "t3.micro"
}

variable "ec2_volume_size_gb" {
  description = "EC2 루트 EBS 크기 (Free Tier: 30GB)"
  type        = number
  default     = 30
}

variable "ssh_key_name" {
  description = "EC2 SSH key pair 이름 (AWS Console에서 미리 생성)"
  type        = string
  # 예: "kicklog-keypair"
}

variable "allowed_ssh_cidr" {
  description = "SSH 22번 허용 IP CIDR (본인 IP만, /32 필수). curl ifconfig.me 로 확인. enable_ssh_inbound=false 면 무시됨."
  type        = string
  default     = "127.0.0.1/32" # ADR-0009: enable_ssh_inbound=false 가 기본이라 미사용 — placeholder.
  sensitive   = true
}

# ADR-0009: SSH 22 ingress 토글. true 이면 본인 IP/32 break-glass 룰 유지,
# false 이면 SG ingress 자체 생성 안 함 (SSM Session Manager 만 사용).
variable "enable_ssh_inbound" {
  description = "EC2 SG 의 SSH(22) ingress 룰 생성 여부. SSM Session Manager 가 안정 운영되면 false 유지."
  type        = bool
  default     = false
}

# ─── RDS ──────────────────────────────────────────────
variable "rds_instance_class" {
  description = "RDS 인스턴스 클래스 (Free Tier: db.t3.micro)"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_storage_size_gb" {
  description = "RDS 할당 스토리지 (Free Tier: 20GB)"
  type        = number
  default     = 20
}

variable "rds_db_name" {
  description = "초기 데이터베이스 이름"
  type        = string
  default     = "kicklog"
}

variable "rds_username" {
  description = "RDS 마스터 사용자명"
  type        = string
  default     = "kicklog"
  sensitive   = true
}

variable "rds_password" {
  description = "RDS 마스터 비밀번호 (terraform.tfvars에 sensitive로 저장, Secrets Manager에 동기화됨)"
  type        = string
  sensitive   = true
}

# ─── Application Secrets ──────────────────────────────
variable "kakao_rest_api_key" {
  description = "카카오 REST API 키 (Secrets Manager 저장용)"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT 서명용 시크릿 (32자 이상)"
  type        = string
  sensitive   = true
}

variable "ghcr_pat" {
  description = "GHCR private package pull 용 PAT (Secrets Manager 저장용, ADR-0008)"
  type        = string
  sensitive   = true
}

# ─── GitHub Actions OIDC ──────────────────────────────
variable "github_repo_owner" {
  description = "GitHub 저장소 owner (OIDC trust condition)"
  type        = string
  default     = "opixxx"
}

variable "github_repo_name" {
  description = "GitHub 저장소 이름 (OIDC trust condition)"
  type        = string
  default     = "kicklog"
}

# ─── Observability / Budget (ADR-0009) ────────────────
variable "alert_email" {
  description = "운영 알림 수신 이메일. 빈 문자열이면 SNS email subscription 을 생성하지 않는다."
  type        = string
  default     = ""
}

variable "budget_monthly_usd" {
  description = "AWS Budgets 월 한도 (USD). Free Tier 운영 가정 — 실수 감지용."
  type        = number
  default     = 5
}
