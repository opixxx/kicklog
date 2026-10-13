# =============================================
# Storage — Postgres 데이터 볼륨
# =============================================
# ADR-0016: RDS 를 없애고 Postgres 를 컨테이너로 옮기면서, 데이터는 **루트와 분리된
# 별도 EBS** 에 둔다.
#
# 왜 분리하는가:
#   - 인스턴스를 교체해도(ARM 전환·장애 복구) 볼륨만 재부착하면 데이터가 살아 있다
#   - OS·도커 이미지가 디스크를 채워도 DB 가 말려들지 않는다
#   - EBS 스냅샷으로 DB 만 따로 백업/복원할 수 있다
# 비용: gp3 20GB = 약 $1.82/월 (기존 RDS 스토리지 $2.62 보다 싸다)

resource "aws_ebs_volume" "pgdata" {
  availability_zone = var.public_subnet_az
  size              = var.pgdata_volume_size_gb
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "kicklog-pgdata"
  }

  # 데이터 볼륨은 실수로 교체되지 않도록 막는다 — size 변경은 의도적으로만.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "pgdata" {
  device_name = "/dev/sdf" # AL2023(nitro) 에서는 /dev/nvme1n1 으로 보인다
  volume_id   = aws_ebs_volume.pgdata.id
  instance_id = aws_instance.app_v2.id # MIGRATION-TEMP

  # 인스턴스가 교체될 때 강제 detach 하지 않는다 — 파일시스템 손상 방지.
  # 교체가 필요하면 먼저 컨테이너를 내리고 수동 detach 한다.
  stop_instance_before_detaching = true
}
