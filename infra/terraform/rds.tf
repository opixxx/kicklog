# =============================================
# RDS — PostgreSQL 16
# =============================================
# ADR-0006: db.t3.micro Free Tier, multi-AZ X, 백업 7일

resource "aws_db_subnet_group" "main" {
  name       = "kicklog-rds-subnet-group"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_c.id]

  tags = {
    Name = "kicklog-rds-subnet-group"
  }
}

resource "aws_db_parameter_group" "postgres16" {
  name        = "kicklog-postgres16"
  family      = "postgres16"
  description = "KickLog PostgreSQL 16 parameter group"

  # 로깅 강화 (개발 단계)
  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "500" # 500ms 이상 쿼리 로깅
  }
}

resource "aws_db_instance" "main" {
  identifier             = "kicklog-postgres"
  engine                 = "postgres"
  engine_version         = "16.14"
  instance_class         = var.rds_instance_class
  allocated_storage      = var.rds_storage_size_gb
  storage_type           = "gp3"
  storage_encrypted      = true

  db_name                = var.rds_db_name
  username               = var.rds_username
  password               = var.rds_password # Secrets Manager에도 동기화됨

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres16.name

  publicly_accessible    = false # MVP는 EC2에서만 접근

  # 백업 — RDS Free Tier 는 backup_retention_period <= 1 만 허용 (서버가 거부).
  # ADR-0006: Free Tier 졸업 (12개월) 후 7일로 회복 검토.
  # 짧은 보존 기간으로 인한 데이터 손실 위험은 MVP 단계에서 명시적으로 수용 (N=20 규모).
  backup_retention_period = 1 # NOSONAR: Free Tier 제약, ADR-0006 참조
  backup_window           = "17:00-18:00" # UTC = KST 02:00~03:00

  # 유지보수
  maintenance_window      = "sun:18:00-sun:19:00" # UTC

  # MVP는 multi-AZ X (비용 절감)
  multi_az = false

  # 자동 minor 버전 업그레이드 (보안 패치)
  auto_minor_version_upgrade = true

  # 삭제 보호 — terraform destroy 실수 방지
  deletion_protection = true

  # 최종 스냅샷 (삭제 시)
  skip_final_snapshot       = false
  final_snapshot_identifier = "kicklog-postgres-final-${formatdate("YYYYMMDD-hhmmss", timestamp())}"

  tags = {
    Name = "kicklog-rds"
  }

  lifecycle {
    # password 변경 시 RDS 재생성 방지 (Secrets Manager rotation으로 처리)
    ignore_changes = [password, final_snapshot_identifier]
  }
}
