# =============================================
# RDS — PostgreSQL 16 (부하테스트용 db.t3.medium)
# =============================================
# prod 와 달리 일회성이므로 deletion_protection=false + skip_final_snapshot=true
# (destroy 친화). Performance Insights 를 켜서 쿼리 병목을 직접 관찰한다.

resource "aws_db_subnet_group" "main" {
  name       = "kicklog-lt-rds-subnet-group"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_c.id]
  tags       = { Name = "kicklog-lt-rds-subnet-group" }
}

resource "aws_db_parameter_group" "postgres16" {
  name        = "kicklog-lt-postgres16"
  family      = "postgres16"
  description = "KickLog loadtest PostgreSQL 16 parameter group"

  # 느린 쿼리 가시화 — 부하 중 병목 쿼리 식별
  parameter {
    name  = "log_min_duration_statement"
    value = "200" # 200ms 이상 쿼리 로깅
  }
}

resource "aws_db_instance" "main" {
  identifier        = "kicklog-lt-postgres"
  engine            = "postgres"
  engine_version    = "16.14"
  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_storage_size_gb
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.rds_db_name
  username = var.rds_username
  password = var.rds_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres16.name

  publicly_accessible = false

  # 쿼리 병목 관찰 — 어떤 쿼리가 느린지 직접 본다
  performance_insights_enabled          = true
  performance_insights_retention_period = 7 # 무료 구간

  # 일회성 — 백업/스냅샷/삭제보호 불필요 (destroy 친화)
  backup_retention_period    = 0
  multi_az                   = false
  auto_minor_version_upgrade = false
  deletion_protection        = false
  skip_final_snapshot        = true

  tags = { Name = "kicklog-lt-rds" }
}
