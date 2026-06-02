# =============================================
# Variables — terraform.tfvars 에서 값 주입
# =============================================

variable "aws_region" {
  description = "AWS region (prod 와 동일 서울)"
  type        = string
  default     = "ap-northeast-2"
}

# ─── Network (prod 10.0.0.0/16 와 겹치지 않게 10.1) ───
variable "vpc_cidr" {
  description = "VPC CIDR (prod 와 분리)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidr" {
  description = "backend/loadgen EC2 용 public subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "public_subnet_az" {
  description = "메인 subnet AZ"
  type        = string
  default     = "ap-northeast-2a"
}

variable "rds_subnet_cidr_b" {
  description = "RDS subnet group 용 2번째 AZ subnet (정책상 2 AZ 필요)"
  type        = string
  default     = "10.1.2.0/24"
}

variable "rds_subnet_az_b" {
  description = "RDS subnet group 용 2번째 AZ"
  type        = string
  default     = "ap-northeast-2c"
}

# ─── EC2 — prod 보다 넉넉히(인프라 천장 제거) ─────────
variable "backend_instance_type" {
  description = "backend EC2 타입 (prod t3.micro → 부하용 t3.large)"
  type        = string
  default     = "t3.large"
}

variable "loadgen_instance_type" {
  description = "부하 생성기(k6) EC2 타입 — 충분히 커야 부하 자체가 병목이 안 됨"
  type        = string
  default     = "c5.large"
}

variable "ec2_volume_size_gb" {
  description = "EC2 루트 EBS 크기"
  type        = number
  default     = 30
}

variable "ssh_key_name" {
  description = "EC2 SSH key pair 이름 (AWS Console 에서 미리 생성). SSM 대신 SSH 디버깅용."
  type        = string
}

variable "admin_cidr" {
  description = "SSH(22) 허용 IP CIDR (본인 IP/32). curl ifconfig.me 로 확인."
  type        = string
  sensitive   = true
}

# ─── RDS — prod 보다 넉넉히 ───────────────────────────
variable "rds_instance_class" {
  description = "RDS 인스턴스 클래스 (prod db.t3.micro → 부하용 db.t3.medium)"
  type        = string
  default     = "db.t3.medium"
}

variable "rds_storage_size_gb" {
  description = "RDS 할당 스토리지 (대량 시드 여유)"
  type        = number
  default     = 50
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
  description = "RDS 마스터 비밀번호 (terraform.tfvars)"
  type        = string
  sensitive   = true
}

# ─── Backend 배포 (GHCR 이미지) ───────────────────────
variable "github_owner" {
  description = "GHCR owner (docker login)"
  type        = string
  default     = "opixxx"
}

variable "ghcr_pat" {
  description = "GHCR private 이미지 pull 용 PAT (read:packages)"
  type        = string
  sensitive   = true
}

variable "backend_image_tag" {
  description = "pull 할 backend 이미지 태그. **loadtest 코드 포함 이미지**(PR #62 merge 후 CD SHA, 또는 수동 build/push)여야 /loadtest/* 동작."
  type        = string
  # 예: "sha-abc1234" 또는 "latest"
}

variable "jwt_secret" {
  description = "JWT 서명 시크릿 (32자 이상, 부하테스트 더미값이어도 됨 — 토큰은 /loadtest/token 우회 발급)"
  type        = string
  sensitive   = true
}
