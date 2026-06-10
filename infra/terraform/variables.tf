# =========================================================
# variables.tf - Inputs del modulo
# =========================================================

variable "aws_region" {
  description = "Region AWS donde desplegar (AWS Academy: us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo para nombrar recursos"
  type        = string
  default     = "innovatech"
}

variable "environment" {
  description = "Entorno logico (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "Tipo de instancia EC2 (Learner Lab permite hasta t3.medium)"
  type        = string
  default     = "t3.micro"
}

variable "instance_profile_name" {
  description = "Instance profile pre-creado en AWS Academy. Permite SSM + ECR pull."
  type        = string
  default     = "LabInstanceProfile"
}

variable "key_pair_name" {
  description = "Nombre del key pair AWS para SSH (opcional - SSM ya basta)"
  type        = string
  default     = ""
}

variable "db_name" {
  description = "Nombre de la base de datos a crear en MySQL"
  type        = string
  default     = "innovatech"
}

variable "db_password" {
  description = "Password root de MySQL (pasalo via -var o terraform.tfvars)"
  type        = string
  sensitive   = true
}
