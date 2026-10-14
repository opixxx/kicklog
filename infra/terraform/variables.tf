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

# ─── EC2 ──────────────────────────────────────────────
variable "ec2_instance_type" {
  # ADR-0016: t3.micro(x86, 1GB) → t4g.small(arm64, 2GB).
  # 앱과 Postgres 를 한 박스에 올리므로 메모리가 2GB 필요하고, Graviton 이 같은
  # 사양에서 약 20% 싸다. 실측 CPU 사용률이 평균 0.67% 라 vCPU 는 문제가 아니다.
  description = "EC2 인스턴스 타입 (arm64 — Graviton)"
  type        = string
  default     = "t4g.small"
}

variable "pgdata_volume_size_gb" {
  # 현재 DB 실사용 약 2.9GB. 20GB 면 수년치 여유이고 기존 RDS 스토리지와 같은 크기다.
  description = "Postgres 데이터 전용 EBS 볼륨 크기 (GB)"
  type        = number
  default     = 20
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

# ─── Database (컨테이너 Postgres, ADR-0016) ───────────
# RDS 를 폐지하고 docker compose 의 postgres 서비스로 옮겼다.
# host/port 는 compose 네트워크에서 고정(postgres:5432)이라 변수가 아니다.
variable "db_name" {
  description = "데이터베이스 이름"
  type        = string
  default     = "kicklog"
}

variable "db_username" {
  description = "DB 사용자명"
  type        = string
  default     = "kicklog"
  sensitive   = true
}

variable "db_password" {
  description = "DB 비밀번호 (SSM Parameter Store 에 동기화됨)"
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

variable "sentry_dsn" {
  description = "Sentry DSN (백엔드 에러 트래킹). 빈 값이면 Secrets Manager secret 미생성 + 앱에서 Sentry 비활성."
  type        = string
  default     = ""
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
  # 2026-10-02 경 Free plan 크레딧이 소진되어 EC2/RDS 가 실과금으로 전환됐다.
  # 실측 forecast 가 $42.87 인데 한도가 $5 라서 80%/100%/forecast 알림 3건이
  # 매달 전부 울렸다 — 정작 "NAT 를 실수로 만든" 류의 사고를 못 잡는 상태였다.
  # 현 수준(약 $45)보다 약간 위로 올려 "사고 감지" 기능을 복원한다.
  # 비용 다이어트(ARM 전환·단일 박스 통합) 후에는 그 목표치로 다시 낮춘다.
  description = "AWS Budgets 월 한도 (USD). 실과금 전환 후 사고 감지용 임계."
  type        = number
  default     = 50
}

# ─── 오리진 직접 접근 (break-glass) ───────────────────────
# 평시 EC2 의 80/443 은 Cloudflare 엣지 IP 레인지에서만 받는다 (network.tf).
# DNS 프록시를 끄고 디버깅해야 하는 등 비상 상황에서만 true 로 전환한다.
# enable_ssh_inbound 와 동일한 토글 패턴 (ADR-0009 D4).
variable "allow_direct_origin" {
  description = "오리진(EC2) 80/443 을 direct_origin_cidr 에 직접 노출할지 여부. 평시 false."
  type        = bool
  default     = false
}

variable "direct_origin_cidr" {
  description = "allow_direct_origin=true 일 때 오리진 직접 접근을 허용할 CIDR (본인 IP /32). curl ifconfig.me 로 확인."
  type        = string
  default     = "127.0.0.1/32" # placeholder — 토글이 false 면 미사용
  sensitive   = true
}

# ─── 엣지 헬스 체크 (ADR-0015) ────────────────────────────
variable "edge_health_url" {
  description = "외부에서 감시할 엣지 URL. Lambda 가 5분마다 호출해 200 이 아니면 알람."
  type        = string
  default     = "https://kicklog.org/actuator/health"
}
