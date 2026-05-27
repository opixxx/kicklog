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

# ─── Security Group: EC2 ──────────────────────────────
# ADR-0009: SSH(22) ingress 는 분리된 aws_security_group_rule + count 토글.
# SG 본체에는 HTTP/HTTPS 만. description 필드는 immutable 이라 ADR-0006 원본 그대로 유지
# (변경하면 SG replace → RDS-attached ENI detach 권한 부재로 apply 실패함).
resource "aws_security_group" "ec2" {
  name        = "kicklog-ec2-sg"
  description = "EC2: HTTP(80), HTTPS(443), SSH(admin only)"
  vpc_id      = aws_vpc.main.id

  # HTTP — Let's Encrypt 인증서 갱신용 + HTTPS 리다이렉트
  ingress {
    description = "HTTP (LetsEncrypt + redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
