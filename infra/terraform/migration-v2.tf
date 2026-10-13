# MIGRATION-TEMP (ADR-0016) — 커밋 대상 아님.
# Blue/Green 컷오버용 신규 ARM 박스. 컷오버 후:
#   terraform destroy -target=aws_instance.app
#   terraform state mv aws_instance.app_v2 aws_instance.app
#   이 파일 삭제 + ec2.tf/storage.tf 의 MIGRATION-TEMP 되돌림
resource "aws_instance" "app_v2" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.ec2_instance_type
  subnet_id     = aws_subnet.public_a.id
  key_name      = var.ssh_key_name

  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_size = var.ec2_volume_size_gb
    volume_type = "gp3"
    encrypted   = true

    tags = {
      Name = "kicklog-ec2-root"
    }
  }

  user_data = file("${path.module}/user-data.sh")

  tags = {
    Name = "kicklog-ec2"
  }

  lifecycle {
    ignore_changes = [user_data, ami]
  }
}
