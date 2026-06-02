# =============================================
# KickLog 복제 부하테스트 환경 — main.tf
# =============================================
# prod(infra/terraform/) 와 **완전히 독립**된 일회성 부하테스트 환경.
# 목적: 인프라 천장을 걷어내고 순수 API 코드/쿼리 병목을 측정 → 끝나면 destroy.
#
# state 는 이 디렉토리의 로컬 terraform.tfstate (prod state 와 물리 분리 — 운영 무접촉).
# 결정 근거: docs/adr/0006-hosting.md, EXEC_PLAN(2026-06-02-loadtest-replica-infra).

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
  # 의도적으로 로컬 state — prod 의 S3 backend 와 절대 공유하지 않는다.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "kicklog"
      ManagedBy   = "terraform"
      Environment = "loadtest" # prod 와 구분 — 비용 추적·일괄 정리 용이
    }
  }
}

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
