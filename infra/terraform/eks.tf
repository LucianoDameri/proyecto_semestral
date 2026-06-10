# =========================================================
# eks.tf - Elastic Kubernetes Service (EKS) Configuration
# =========================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "innovatech-cluster"
  cluster_version = "1.30"

  # VPC settings from vpc.tf
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.public.id, aws_subnet.private_backend.id]

  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 3
      desired_size = 2

      instance_types = ["t3.medium"]
      capacity_type   = "ON_DEMAND"
    }
  }

  # Cluster access for the user creating the cluster
  enable_cluster_creator_admin_permissions = true

  tags = {
    Environment = var.environment
  }
}
