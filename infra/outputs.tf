# =========================================================
# outputs.tf - Datos exportados para usar en GitHub Actions
# =========================================================

# ---- IDs de instancias EC2 (necesarios para SSM send-command) ----
output "ec2_frontend_id" {
  description = "Instance ID de la EC2 Frontend (publica)"
  value       = aws_instance.frontend.id
}

output "ec2_backend_id" {
  description = "Instance ID de la EC2 Backend (privada)"
  value       = aws_instance.backend.id
}

output "ec2_database_id" {
  description = "Instance ID de la EC2 Database (privada)"
  value       = aws_instance.database.id
}

# ---- IPs ----
output "frontend_public_ip" {
  description = "IP publica de la EC2 Frontend (acceso desde internet)"
  value       = aws_instance.frontend.public_ip
}

output "frontend_public_dns" {
  description = "DNS publico de la EC2 Frontend"
  value       = aws_instance.frontend.public_dns
}

output "backend_private_ip" {
  description = "IP privada de la EC2 Backend (para nginx proxy desde frontend)"
  value       = aws_instance.backend.private_ip
}

output "database_private_ip" {
  description = "IP privada de la EC2 Database (para conexion JDBC desde backend)"
  value       = aws_instance.database.private_ip
}

# ---- ECR repositories ----
output "ecr_repos" {
  description = "URLs de los 3 repos ECR (formato: account.dkr.ecr.region.amazonaws.com/repo)"
  value = {
    for k, repo in aws_ecr_repository.this : k => repo.repository_url
  }
}

output "ecr_registry" {
  description = "URL del registry ECR (sin nombre de repo)"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}

# ---- VPC ----
output "vpc_id" {
  description = "ID de la VPC creada"
  value       = aws_vpc.main.id
}

# ---- Resumen util para copiar a GitHub ----
# Solo 4 valores van como SECRETS (sensibles / credenciales).
# El resto son no-sensibles -> van como repository VARIABLES
# (Settings -> Secrets and variables -> Actions -> Variables tab).
# Esto reduce el conteo de "secrets" de 11 a 4.
output "github_secrets_summary" {
  description = "Valores SENSIBLES -> pegar en la pestana 'Secrets'"
  value = {
    DB_PASSWORD = "(usar el mismo valor de terraform.tfvars / db_password)"
    # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY y AWS_SESSION_TOKEN
    # se obtienen de AWS Academy -> AWS Details -> AWS CLI (no son output de Terraform)
  }
}

output "github_variables_summary" {
  description = "Valores NO sensibles -> pegar en la pestana 'Variables'"
  value = {
    AWS_REGION          = var.aws_region
    ECR_REGISTRY        = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
    EC2_FRONTEND_ID     = aws_instance.frontend.id
    EC2_BACKEND_ID      = aws_instance.backend.id
    EC2_DATABASE_ID     = aws_instance.database.id
    DB_NAME             = var.db_name
    BACKEND_PRIVATE_IP  = aws_instance.backend.private_ip
    DATABASE_PRIVATE_IP = aws_instance.database.private_ip
    FRONTEND_PUBLIC_IP  = aws_instance.frontend.public_ip
  }
}
