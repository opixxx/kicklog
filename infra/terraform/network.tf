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
resource "aws_security_group" "ec2" {
  name        = "kicklog-ec2-sg"
  description = "EC2: HTTP(80), HTTPS(443), SSH(본인 IP만)"
  vpc_id      = aws_vpc.main.id

  # HTTP — Let's Encrypt 인증서 갱신용 + HTTPS 리다이렉트
  ingress {
    description = "HTTP (Let's Encrypt + redirect to HTTPS)"
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

  # SSH — 본인 IP만 (ADR-0006 보안 정책)
  ingress {
    description = "SSH (admin only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
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

# ─── Security Group: RDS ──────────────────────────────
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
