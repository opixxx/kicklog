# =============================================
# Network — VPC, Subnet, IGW, Route, SG
# =============================================
# 부하테스트 전용 VPC. 부하 생성기(loadgen)와 backend 를 같은 VPC 에 두어
# 인터넷 너머 RTT/대역폭 변수를 제거한다.

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "kicklog-lt-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "kicklog-lt-igw" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.public_subnet_az
  map_public_ip_on_launch = true
  tags                    = { Name = "kicklog-lt-public-a" }
}

# RDS subnet group 은 최소 2 AZ 요구 (multi-AZ 는 안 쓰지만 정책 충족용)
resource "aws_subnet" "public_c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.rds_subnet_cidr_b
  availability_zone       = var.rds_subnet_az_b
  map_public_ip_on_launch = true
  tags                    = { Name = "kicklog-lt-public-c" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "kicklog-lt-public-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

# ─── SG: backend (8080 ← loadgen, 22 ← admin) ────────
resource "aws_security_group" "backend" {
  name        = "kicklog-lt-backend-sg"
  description = "loadtest backend: 8080 from loadgen, SSH from admin"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "backend HTTP 8080 from loadgen"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.loadgen.id]
  }

  # admin 직접 접근(브라우저 확인/디버깅)도 허용 — 부하테스트 일회성 환경
  ingress {
    description = "backend HTTP 8080 from admin"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "all outbound (docker pull, GHCR)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "kicklog-lt-backend-sg" }
}

# ─── SG: loadgen (k6 부하 생성기) ─────────────────────
resource "aws_security_group" "loadgen" {
  name        = "kicklog-lt-loadgen-sg"
  description = "loadtest loadgen: SSH from admin"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "all outbound (backend 8080, k6 image pull)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "kicklog-lt-loadgen-sg" }
}

# ─── SG: RDS (5432 ← backend) ─────────────────────────
resource "aws_security_group" "rds" {
  name        = "kicklog-lt-rds-sg"
  description = "loadtest RDS: 5432 from backend SG only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from backend"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  tags = { Name = "kicklog-lt-rds-sg" }
}
