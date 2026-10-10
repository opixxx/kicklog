# =============================================
# Network — VPC, Subnet, IGW, Route Table, SG
# =============================================
# ADR-0006 D2: 단일 Public Subnet, NAT/ALB 없이 단순 구성
# RDS subnet group은 정책상 2 AZ 필요해서 subnet 2개 (하나만 실제 사용)

# ─── VPC ──────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "kicklog-vpc"
  }
}

# ─── Internet Gateway ─────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "kicklog-igw"
  }
}

# ─── Public Subnet (EC2용, 메인) ──────────────────────
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.public_subnet_az
  map_public_ip_on_launch = true

  tags = {
    Name = "kicklog-public-a"
    Tier = "public"
  }
}

# ─── RDS subnet group용 2번째 subnet ─────────────────
# AWS DB Subnet Group은 최소 2 AZ 요구. MVP에 multi-AZ는 안 쓰지만 정책 충족 필요.
resource "aws_subnet" "public_c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.rds_subnet_cidr_b
  availability_zone       = var.rds_subnet_az_b
  map_public_ip_on_launch = true

  tags = {
    Name = "kicklog-public-c"
    Tier = "public"
  }
}

# ─── Route Table ──────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "kicklog-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

# ─── Cloudflare 엣지 IP 목록 ──────────────────────────
# ADR-0015: kicklog.org 의 DNS A 레코드는 Cloudflare 프록시 IP 다(dig 로 확인).
# 즉 정상 트래픽은 100% Cloudflare 엣지에서 온다. 그런데 2026-10-10 점검에서
# `curl -k https://<EIP>/nginx-health` 가 200 을 반환했다 — 오리진 IP 를 아는 쪽은
# Cloudflare 의 WAF·rate limit·캐시를 전부 우회해 백엔드를 직접 때릴 수 있었다.
#
# 공식 목록을 apply 시점에 받아 SG 를 그 레인지로만 좁힌다.
# 주의: terraform plan/apply 시 cloudflare.com 으로의 네트워크 접근이 필요하다.
#       목록이 바뀌면 (연 1~2회 수준) 재 apply 로 반영된다.
data "http" "cloudflare_ips_v4" {
  url = "https://www.cloudflare.com/ips-v4"
}

data "http" "cloudflare_ips_v6" {
  url = "https://www.cloudflare.com/ips-v6"
}

locals {
  cloudflare_ipv4 = compact(split("\n", trimspace(data.http.cloudflare_ips_v4.response_body)))
  cloudflare_ipv6 = compact(split("\n", trimspace(data.http.cloudflare_ips_v6.response_body)))
}

# ─── Security Group: EC2 ──────────────────────────────
# ADR-0009: SSH(22) ingress 는 분리된 aws_security_group_rule + count 토글.
# description 필드는 immutable 이라 ADR-0006 원본 그대로 유지
# (변경하면 SG replace → RDS-attached ENI detach 권한 부재로 apply 실패함).
resource "aws_security_group" "ec2" {
  name        = "kicklog-ec2-sg"
  description = "EC2: HTTP(80), HTTPS(443), SSH(admin only)"
  vpc_id      = aws_vpc.main.id

  # HTTPS — Cloudflare 엣지 레인지에서만 수신 (ADR-0015).
  #
  # 80 은 더 이상 열지 않는다:
  #   - 열어둔 유일한 이유가 Let's Encrypt HTTP-01 챌린지였고,
  #     Cloudflare Origin CA 전환으로 ACME 갱신 자체가 사라졌다 (ADR-0015 D1)
  #   - 클라이언트의 http→https 승격은 Cloudflare 엣지가 처리한다
  #   - 덤으로 SG inbound 룰 수가 절반이 된다 (CIDR 1개 = 룰 1개, 기본 쿼터 60)
  dynamic "ingress" {
    for_each = toset([443])
    content {
      # AWS API 가 ASCII 만 허용 — 한글 사유는 위 주석 참조.
      description      = "HTTPS from Cloudflare edge ranges only"
      from_port        = ingress.value
      to_port          = ingress.value
      protocol         = "tcp"
      cidr_blocks      = local.cloudflare_ipv4
      ipv6_cidr_blocks = local.cloudflare_ipv6
    }
  }

  # break-glass — DNS 프록시를 끄고 오리진을 직접 봐야 할 때만 (평시 false).
  # 80 도 함께 여는 이유: 프록시를 끈 상태에서는 ACME HTTP-01 이나 평문 디버깅이 필요할 수 있다.
  dynamic "ingress" {
    for_each = var.allow_direct_origin ? toset([80, 443]) : toset([])
    content {
      description = "Direct origin access (break-glass, admin IP only)"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [var.direct_origin_cidr]
    }
  }

  # 모든 outbound 허용 (카카오 API, apt, docker pull 등)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kicklog-ec2-sg"
  }
}

# ADR-0009: SSH(22) break-glass — enable_ssh_inbound=true 일 때만 본인 IP/32 ingress 추가.
# 평시는 SSM Session Manager 만 사용한다 (SSH 키 분실/유출 표면 제거).
resource "aws_security_group_rule" "ec2_ssh_break_glass" {
  count = var.enable_ssh_inbound ? 1 : 0

  type              = "ingress"
  security_group_id = aws_security_group.ec2.id
  # AWS API 가 ASCII 만 허용 (한글/em-dash 사용 불가). 한글 사유는 본 리소스 위 주석 참조.
  description = "SSH break-glass: admin IP only. Prefer SSM Session Manager."
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [var.allowed_ssh_cidr]
}

# ─── Security Group: RDS ──────────────────────────────
# ADR-0009 검증: ingress 는 EC2 SG 5432 단일 출처만, egress 는 명시 안 해
# 기본 deny (terraform 은 SG egress 미지정 시 빈 set 적용) — 외부 통신 없음.
# publicly_accessible=false 와 함께 이중 방어.
# description 필드는 immutable + RDS-attached ENI 라 변경 불가 — ADR-0006 원본 그대로 유지.
resource "aws_security_group" "rds" {
  name        = "kicklog-rds-sg"
  description = "RDS: 5432 from EC2 SG only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  # RDS는 outbound 불필요 (백업 등은 AWS 내부)
  # 보안상 명시적으로 제거

  tags = {
    Name = "kicklog-rds-sg"
  }
}
