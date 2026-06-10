# =========================================================
# vpc.tf - VPC + subredes + IGW + NAT + Route Tables
# =========================================================
# Topologia:
#   - 1 VPC (10.0.0.0/16)
#   - 1 subred publica  (10.0.1.0/24) - Frontend + NAT Gateway
#   - 1 subred privada  (10.0.2.0/24) - Backend (Ventas + Despachos)
#   - 1 subred privada  (10.0.3.0/24) - Base de datos (MySQL)
#
# Salida a internet:
#   - Publica:  via Internet Gateway (IGW)
#   - Privadas: via NAT Gateway en subred publica
#     (Necesario para que EC2 privadas hagan pull de imagenes desde ECR
#      y se registren en SSM Session Manager.)
# =========================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

# ----------------------------- Internet Gateway -----------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

# ----------------------------- Subredes -----------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.azs[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-a"
    Tier = "public"
  }
}

resource "aws_subnet" "private_backend" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = local.azs[0]

  tags = {
    Name = "${local.name_prefix}-private-backend-a"
    Tier = "private"
  }
}

resource "aws_subnet" "private_db" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = local.azs[0]

  tags = {
    Name = "${local.name_prefix}-private-db-a"
    Tier = "private"
  }
}

# ----------------------------- NAT Gateway -----------------------------
# Elastic IP para el NAT Gateway
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = { Name = "${local.name_prefix}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.main]

  tags = { Name = "${local.name_prefix}-nat" }
}

# ----------------------------- Route Tables -----------------------------
# Tabla publica: salida via IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name_prefix}-rt-public" }
}

# Tabla privada: salida via NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${local.name_prefix}-rt-private" }
}

# Asociaciones subred -> route table
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_backend" {
  subnet_id      = aws_subnet.private_backend.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_db" {
  subnet_id      = aws_subnet.private_db.id
  route_table_id = aws_route_table.private.id
}
