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

# ---- Resumen util para copiar a GitHub Secrets ----
output "github_secrets_summary" {
  description = "Pega estos valores en Settings -> Secrets and variables -> Actions"
  value = {
    AWS_REGION             = var.aws_region
    ECR_REGISTRY           = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
    ECR_REPO_VENTAS        = aws_ecr_repository.this["ventas"].repository_url
    ECR_REPO_DESPACHOS     = aws_ecr_repository.this["despachos"].repository_url
    ECR_REPO_FRONTEND      = aws_ecr_repository.this["frontend"].repository_url
    EC2_FRONTEND_ID        = aws_instance.frontend.id
    EC2_BACKEND_ID         = aws_instance.backend.id
    EC2_DATABASE_ID        = aws_instance.database.id
    BACKEND_PRIVATE_IP     = aws_instance.backend.private_ip
    DATABASE_PRIVATE_IP    = aws_instance.database.private_ip
    FRONTEND_PUBLIC_IP     = aws_instance.frontend.public_ip
  }
}
