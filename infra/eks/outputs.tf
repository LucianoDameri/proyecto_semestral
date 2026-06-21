# =========================================================
# outputs.tf - Datos exportados del modulo EKS
# =========================================================

output "cluster_name" {
  description = "Nombre del cluster EKS"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint del plano de control EKS"
  value       = aws_eks_cluster.main.endpoint
}

output "kubeconfig_command" {
  description = "Comando para conectar kubectl al cluster (correr antes de cualquier kubectl apply)"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "ecr_repos_reutilizados" {
  description = "Los mismos 3 repos ECR del modulo ECS, reutilizados aqui (no se crean repos nuevos)"
  value = {
    ventas    = data.aws_ecr_repository.ventas.repository_url
    despachos = data.aws_ecr_repository.despachos.repository_url
    frontend  = data.aws_ecr_repository.frontend.repository_url
  }
}

output "github_secrets_to_create" {
  description = "Secrets necesarios en GitHub Actions para los workflows *-eks.yml"
  value       = <<-EOT
  Los mismos 4 de siempre (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
  AWS_SESSION_TOKEN, DB_PASSWORD) ya sirven para EKS - no hace falta
  crear secrets nuevos. El DB_PASSWORD existente se reutiliza como
  MYSQL_ROOT_PASSWORD del mysql.yml de Kubernetes.
  EOT
}
