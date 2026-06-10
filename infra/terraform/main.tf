# =========================================================
# main.tf - Provider + backend + locals
# =========================================================

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
      Course      = "ISY1101-Innovatech-EP2"
      Environment = var.environment
    }
  }
}

# Locales: nombres derivados del project_name para evitar repeticion.
locals {
  name_prefix = var.project_name
  azs         = ["${var.aws_region}a", "${var.aws_region}b"]
}

# AMI Amazon Linux 2023 mas reciente (incluye SSM Agent y soporta cloud-init).
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Cuenta y region actual (para componer URLs de ECR en outputs).
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
