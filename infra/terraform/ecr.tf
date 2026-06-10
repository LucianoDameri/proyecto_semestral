# =========================================================
# ecr.tf - Repositorios ECR
# =========================================================
# 3 repos privados para las 3 imagenes del stack.
# Lifecycle policy: conservar solo las ultimas 5 imagenes
# para evitar acumulacion de capas viejas y bajar costo de storage.
# =========================================================

locals {
  ecr_repos = {
    ventas    = "${local.name_prefix}-ventas"
    despachos = "${local.name_prefix}-despachos"
    frontend  = "${local.name_prefix}-frontend"
  }
}

resource "aws_ecr_repository" "this" {
  for_each = local.ecr_repos

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = true # permite destroy aunque haya imagenes (lab)

  image_scanning_configuration {
    scan_on_push = true # vulnerability scan automatico
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = each.value
    Role = each.key
  }
}

# Politica de retencion: mantener 5 imagenes por repo
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
