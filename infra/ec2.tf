# =========================================================
# ec2.tf - 3 instancias EC2 con Docker + SSM
# =========================================================
# AWS Academy Learner Lab solo permite usar el role "LabRole"
# (no podemos crear IAM roles propios).
# El instance profile equivalente es "LabInstanceProfile".
# =========================================================

# user_data comun: instala docker + habilita SSM (SSM Agent ya viene en AL2023).
locals {
  user_data_common = <<-EOT
    #!/bin/bash
    set -eux

    # ---------- Update + Docker ----------
    dnf update -y
    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user

    # ---------- AWS CLI v2 (ya viene en AL2023 pero validamos) ----------
    if ! command -v aws >/dev/null 2>&1; then
      dnf install -y awscli
    fi

    # ---------- SSM Agent ----------
    systemctl enable --now amazon-ssm-agent || true

    echo "Bootstrap base completo: $(date)" >> /var/log/bootstrap.log
  EOT
}

# user_data especifico para la EC2 de DB: instala docker y levanta MySQL con volumen persistente.
locals {
  user_data_db = <<-EOT
    #!/bin/bash
    set -eux

    dnf update -y
    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user

    systemctl enable --now amazon-ssm-agent || true

    # Volumen Docker para persistencia de MySQL
    docker volume create innovatech_mysql_data || true

    # MySQL 8 con bind 0.0.0.0 para que el backend pueda conectarse via IP privada
    docker run -d \
      --name mysql \
      --restart unless-stopped \
      -e MYSQL_ROOT_PASSWORD='${var.db_password}' \
      -e MYSQL_DATABASE='${var.db_name}' \
      -e MYSQL_ROOT_HOST='%' \
      -p 3306:3306 \
      -v innovatech_mysql_data:/var/lib/mysql \
      --log-opt max-size=10m \
      --log-opt max-file=3 \
      mysql:8.0 \
      --bind-address=0.0.0.0 \
      --performance-schema=OFF

    echo "MySQL bootstrap completo: $(date)" >> /var/log/bootstrap.log
  EOT
}

# ----------------------------- EC2 Frontend (publica) -----------------------------
resource "aws_instance" "frontend" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.frontend.id]
  associate_public_ip_address = true
  iam_instance_profile        = var.instance_profile_name
  key_name                    = var.key_pair_name != "" ? var.key_pair_name : null

  user_data = local.user_data_common

  root_block_device {
    volume_size = 16
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens   = "required" # IMDSv2 obligatorio (mas seguro)
    http_endpoint = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-ec2-frontend"
    Role = "frontend"
    Tier = "public"
  }
}

# ----------------------------- EC2 Backend (privada) -----------------------------
resource "aws_instance" "backend" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_backend.id
  vpc_security_group_ids = [aws_security_group.backend.id]
  iam_instance_profile   = var.instance_profile_name
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null

  user_data = local.user_data_common

  root_block_device {
    volume_size = 16
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-ec2-backend"
    Role = "backend"
    Tier = "private"
  }
}

# ----------------------------- EC2 Database (privada) -----------------------------
resource "aws_instance" "database" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_db.id
  vpc_security_group_ids = [aws_security_group.database.id]
  iam_instance_profile   = var.instance_profile_name
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null

  user_data = local.user_data_db

  # Mas disco para data de MySQL
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-ec2-database"
    Role = "database"
    Tier = "private"
  }
}
