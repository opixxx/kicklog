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
  identifier        = "kicklog-postgres"
  engine            = "postgres"
  engine_version    = "16.14"
  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_storage_size_gb
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.rds_db_name
  username = var.rds_username
  password = var.rds_password # Secrets Manager에도 동기화됨

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres16.name

  publicly_accessible = false # MVP는 EC2에서만 접근

  # 백업 — 2026-10 Free plan 크레딧 소진으로 이미 실과금 전환됐으므로
  # "Free Tier 가 1일만 허용한다" 는 전제는 더 이상 유효하지 않다 (ADR-0015).
  #
  # 1일 보존의 실질 위험: 2026-09-06 장애는 인지까지 9일이 걸렸다. 그 시점에
  # 복구 가능한 백업은 이미 존재하지 않았다. 7일이면 "주말에 터진 걸 월요일에
  # 알아차려도" 복구 창이 남는다.
  # 비용: DB 실사용 약 2.9GB 기준 증분 스냅샷 월 $0.3 수준.
  # 논리 백업(pg_dump → S3)은 backup.tf + pg-dump-to-s3.sh 로 이중화한다.
  backup_retention_period = 7
  backup_window           = "17:00-18:00" # UTC = KST 02:00~03:00

  # 유지보수
  maintenance_window = "sun:18:00-sun:19:00" # UTC

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
