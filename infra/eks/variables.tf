# =========================================================
# variables.tf - Inputs del modulo EKS
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

variable "cluster_name" {
  description = "Nombre del cluster EKS (distinto del nombre del cluster ECS para no confundirlos)"
  type        = string
  default     = "innovatech-eks"
}

variable "node_instance_type" {
  description = "Tipo de instancia EC2 para los nodos worker (Spring Boot necesita al menos t3.medium)"
  type        = string
  default     = "t3.medium"
}

variable "db_name" {
  description = "Nombre de la base de datos MySQL (debe coincidir con el secret MYSQL_DATABASE usado en el pipeline)"
  type        = string
  default     = "innovatech"
}
