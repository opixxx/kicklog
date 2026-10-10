# =============================================
# KickLog AWS Infrastructure — main.tf
# =============================================
# Terraform 진입점. provider 설정 + 공통 태그.
# 상세 설명은 README.md, 결정 근거는 docs/adr/0006-hosting.md 참조.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }

    # Cloudflare 공식 IP 목록 조회용 (network.tf) — 오리진 SG 를 엣지로만 좁힌다.
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }

    # 엣지 헬스 체크 Lambda 패키징용 (observability.tf)
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # MVP는 로컬 state (ADR-0006 D8)
  # v1.1: S3 backend로 마이그레이션
  # backend "s3" {
  #   bucket         = "kicklog-tfstate"
  #   key            = "infra/terraform.tfstate"
  #   region         = "ap-northeast-2"
  #   dynamodb_table = "kicklog-tfstate-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "kicklog"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

# 현재 AWS 계정 ID 조회 (정보용)
data "aws_caller_identity" "current" {}

# Amazon Linux 2023 최신 AMI 자동 조회
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
