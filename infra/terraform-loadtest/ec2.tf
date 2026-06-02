# =============================================
# EC2 — backend(t3.large) + loadgen(c5.large)
# =============================================

# ─── IAM: SSM Session Manager 접속용 ──────────────────
resource "aws_iam_role" "ec2" {
  name = "kicklog-lt-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = "kicklog-lt-ec2-role" }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "kicklog-lt-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ─── backend EC2 ──────────────────────────────────────
# user-data 가 docker + GHCR pull + loadtest 프로파일로 8080 직접 노출.
# RDS 가 먼저 떠야 endpoint 를 주입할 수 있으므로 의존.
resource "aws_instance" "backend" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.backend_instance_type
  subnet_id              = aws_subnet.public_a.id
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.backend.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_size = var.ec2_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/user-data-backend.sh.tftpl", {
    rds_address       = aws_db_instance.main.address
    db_name           = var.rds_db_name
    db_username       = var.rds_username
    db_password       = var.rds_password
    jwt_secret        = var.jwt_secret
    github_owner      = var.github_owner
    ghcr_pat          = var.ghcr_pat
    backend_image_tag = var.backend_image_tag
  })

  tags = { Name = "kicklog-lt-backend" }
}

# ─── loadgen EC2 (k6) ─────────────────────────────────
resource "aws_instance" "loadgen" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.loadgen_instance_type
  subnet_id              = aws_subnet.public_a.id
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.loadgen.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = file("${path.module}/templates/user-data-loadgen.sh.tftpl")

  tags = { Name = "kicklog-lt-loadgen" }
}
