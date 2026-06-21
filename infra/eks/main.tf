# ============================================================
# infra/eks - Orquestacion con AWS EKS (alternativa a infra/ecs.tf)
# ============================================================
# Modulo Terraform AUTOCONTENIDO (su propio provider, su propia VPC,
# su propio state) para no tocar nada del modulo ECS que vive en
# infra/*.tf. La rubrica EP3 pide usar UNICAMENTE ECS o EKS - este
# modulo existe para poder demostrar EKS sin desarmar lo que ya
# funciona en ECS. Se aplican por separado:
#
#   cd infra            && terraform apply   -> arquitectura ECS
#   cd infra/eks         && terraform apply   -> arquitectura EKS
#
# Reusa los mismos 3 repos ECR del modulo ECS (innovatech-ventas,
# innovatech-despachos, innovatech-frontend) via data source, asi los
# pipelines de CI (ci-ventas.yml, etc.) no cambian en nada - siguen
# publicando en el mismo lugar sin importar a cual cluster se despliegue.
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Course      = "ISY1101-Innovatech-EP3"
      Stack       = "EKS"
    }
  }
}

# ------------------------------------------------------------
# Data sources
# ------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# AWS Academy entrega el rol LabRole (no se pueden crear roles IAM nuevos).
data "aws_iam_role" "labrole" {
  name = "LabRole"
}

# Reusar los repos ECR que ya crea infra/ecr.tf (modulo ECS). Se referencian
# por nombre via data source: no hay dependencia de Terraform state entre
# los dos modulos, solo se consulta el recurso real en AWS.
data "aws_ecr_repository" "ventas" {
  name = "innovatech-ventas"
}

data "aws_ecr_repository" "despachos" {
  name = "innovatech-despachos"
}

data "aws_ecr_repository" "frontend" {
  name = "innovatech-frontend"
}

# ------------------------------------------------------------
# VPC propia (CIDR distinto al de infra/vpc.tf para evitar confusiones)
# EKS exige subredes en al menos 2 AZ.
# ------------------------------------------------------------

resource "aws_vpc" "eks" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-eks-vpc" }
}

resource "aws_internet_gateway" "eks" {
  vpc_id = aws_vpc.eks.id
  tags   = { Name = "${var.project_name}-eks-igw" }
}

# ---- Subredes publicas (ALB/ELB de los Services type=LoadBalancer) ----
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.eks.id
  cidr_block              = "10.1.10.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name                                          = "${var.project_name}-eks-public-a"
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
    "kubernetes.io/role/elb"                      = "1"
    Tier                                           = "public"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.eks.id
  cidr_block              = "10.1.20.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name                                          = "${var.project_name}-eks-public-b"
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
    "kubernetes.io/role/elb"                      = "1"
    Tier                                           = "public"
  }
}

# ---- Subredes privadas (nodos worker / pods) ----
resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.eks.id
  cidr_block              = "10.1.30.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name                                          = "${var.project_name}-eks-private-a"
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
    Tier                                           = "private"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.eks.id
  cidr_block              = "10.1.40.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name                                          = "${var.project_name}-eks-private-b"
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
    Tier                                           = "private"
  }
}

# ------------------------------------------------------------
# NAT Gateway (salida a internet desde subredes privadas: ECR pull, API EKS)
# ------------------------------------------------------------

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.eks]
  tags       = { Name = "${var.project_name}-eks-nat-eip" }
}

resource "aws_nat_gateway" "eks" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.eks]
  tags          = { Name = "${var.project_name}-eks-nat" }
}

# ------------------------------------------------------------
# Route tables
# ------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks.id
  }

  tags = { Name = "${var.project_name}-eks-rt-public" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.eks.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks.id
  }

  tags = { Name = "${var.project_name}-eks-rt-private" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# ------------------------------------------------------------
# Security Group de los nodos
# ------------------------------------------------------------

resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-eks-nodes-sg"
  description = "Trafico entre nodos EKS, plano de control y NodePorts"
  vpc_id      = aws_vpc.eks.id

  ingress {
    description = "Trafico interno entre nodos (pods, CNI, kubelet)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "NodePort para Services type=LoadBalancer (frontend)"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-eks-nodes-sg" }
}

# ------------------------------------------------------------
# EKS Cluster
# ------------------------------------------------------------

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = data.aws_iam_role.labrole.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.public_a.id,
      aws_subnet.public_b.id,
      aws_subnet.private_a.id,
      aws_subnet.private_b.id,
    ]
    security_group_ids      = [aws_security_group.eks_nodes.id]
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  # Logs del plano de control hacia CloudWatch (IE6) - no necesita agentes
  # extra como Fluent Bit, EKS los publica nativamente si se habilitan aqui.
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = { Name = var.cluster_name }

  # AWS Academy bloquea iam:CreateRole - EKS solo es viable si LabRole ya
  # puede ser asumido por el servicio EKS. Falla en segundos en vez de
  # esperar 10-15 min a que la API de AWS rechace la creacion del cluster.
  lifecycle {
    precondition {
      condition     = strcontains(data.aws_iam_role.labrole.assume_role_policy, "eks.amazonaws.com")
      error_message = "LabRole no permite que eks.amazonaws.com lo asuma (revisa: aws iam get-role --role-name LabRole --query Role.AssumeRolePolicyDocument). AWS Academy bloquea iam:CreateRole, asi que no se puede crear un rol nuevo para EKS - es un bloqueo de la plataforma, no del codigo."
    }
  }
}

resource "aws_cloudwatch_log_group" "eks_cluster" {
  # Debe llamarse exactamente asi para que EKS publique ahi los logs habilitados arriba.
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7
}

# ------------------------------------------------------------
# EKS Node Group (nodos privados, autoscaling 1-2 via HPA + capacidad fija)
# ------------------------------------------------------------

resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-eks-workers"
  node_role_arn   = data.aws_iam_role.labrole.arn

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
  ]

  instance_types = [var.node_instance_type]
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  tags = { Name = "${var.project_name}-eks-workers" }

  depends_on = [
    aws_eks_cluster.main,
    aws_route_table_association.public_a,
    aws_route_table_association.public_b,
    aws_route_table_association.private_a,
    aws_route_table_association.private_b,
    aws_nat_gateway.eks,
  ]

  # Los nodos son instancias EC2: LabRole tambien debe poder ser asumido por
  # ec2.amazonaws.com (casi siempre es asi en Academy, ya se usa igual para
  # el instance profile de las EC2 del modulo ECS) - se verifica para fallar
  # rapido en vez de a mitad de la creacion del node group.
  lifecycle {
    precondition {
      condition     = strcontains(data.aws_iam_role.labrole.assume_role_policy, "ec2.amazonaws.com")
      error_message = "LabRole no permite que ec2.amazonaws.com lo asuma. El Node Group de EKS necesita esto para lanzar las instancias EC2 de los nodos worker."
    }
  }
}
