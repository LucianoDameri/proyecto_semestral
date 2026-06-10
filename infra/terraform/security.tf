# =========================================================
# security.tf - Security Groups
# =========================================================
# Politica de minimo privilegio (PPT 2.3 - seguridad y red en EC2):
#
#   Frontend SG:  ingress 80, 22 (SSH temp), ICMP desde 0.0.0.0/0
#   Backend  SG:  ingress 8080+8081 SOLO desde Frontend SG, ICMP intra-VPC
#   Database SG:  ingress 3306 SOLO desde Backend SG
#
# Todo egress: permitido (necesario para ECR pull, SSM, updates).
# =========================================================

# -------------------- Frontend SG --------------------
resource "aws_security_group" "frontend" {
  name        = "${local.name_prefix}-sg-frontend"
  description = "Permite HTTP/SSH desde internet hacia la EC2 Frontend"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP publico"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH (uso temporal - en produccion usar solo SSM)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP para diagnostico (ping)"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida total (ECR, SSM, updates)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg-frontend" }
}

# -------------------- Backend SG --------------------
resource "aws_security_group" "backend" {
  name        = "${local.name_prefix}-sg-backend"
  description = "Solo acepta trafico de microservicios desde el Frontend SG"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Salida total (ECR pull, SSM, conectarse a DB)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg-backend" }
}

# Ingress separado para evitar dependencia circular si despues se requiere
# que el Backend acepte trafico del Frontend SG (referenciandose por ID).
resource "aws_security_group_rule" "backend_ventas_from_frontend" {
  type                     = "ingress"
  description              = "API Ventas desde frontend"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.backend.id
  source_security_group_id = aws_security_group.frontend.id
}

resource "aws_security_group_rule" "backend_despachos_from_frontend" {
  type                     = "ingress"
  description              = "API Despachos desde frontend"
  from_port                = 8081
  to_port                  = 8081
  protocol                 = "tcp"
  security_group_id        = aws_security_group.backend.id
  source_security_group_id = aws_security_group.frontend.id
}

# ICMP intra-VPC (util para troubleshooting)
resource "aws_security_group_rule" "backend_icmp_vpc" {
  type              = "ingress"
  description       = "ICMP intra-VPC"
  from_port         = -1
  to_port           = -1
  protocol          = "icmp"
  security_group_id = aws_security_group.backend.id
  cidr_blocks       = [aws_vpc.main.cidr_block]
}

# -------------------- Database SG --------------------
resource "aws_security_group" "database" {
  name        = "${local.name_prefix}-sg-db"
  description = "Solo acepta conexiones MySQL desde el Backend SG"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Salida total (ECR pull para imagen MySQL, SSM, updates)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg-db" }
}

resource "aws_security_group_rule" "db_mysql_from_backend" {
  type                     = "ingress"
  description              = "MySQL 3306 desde backend"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.database.id
  source_security_group_id = aws_security_group.backend.id
}

resource "aws_security_group_rule" "db_icmp_vpc" {
  type              = "ingress"
  description       = "ICMP intra-VPC para diagnostico"
  from_port         = -1
  to_port           = -1
  protocol          = "icmp"
  security_group_id = aws_security_group.database.id
  cidr_blocks       = [aws_vpc.main.cidr_block]
}
