# Infraestructura AWS - Terraform

Este modulo levanta toda la infraestructura del proyecto Innovatech EP2 en AWS:

- **VPC** `10.0.0.0/16` con 1 subred publica + 2 subredes privadas
- **Internet Gateway** para la subred publica
- **NAT Gateway** para que las subredes privadas accedan a ECR y SSM
- **3 instancias EC2** (t3.micro) con Docker pre-instalado:
  - `ec2-frontend` en subred publica (Nginx + React)
  - `ec2-backend` en subred privada (microservicios Ventas + Despachos)
  - `ec2-database` en subred privada (MySQL 8 con volumen persistente)
- **3 Security Groups** con politica de minimo privilegio
- **3 repositorios ECR** privados con escaneo de vulnerabilidades activado

## Arquitectura

```
Internet
   |
   v
[IGW]
   |
   +-- Subred publica  10.0.1.0/24
   |     |-- EC2 Frontend (IP publica, puerto 80)  <-- usuarios
   |     |-- NAT Gateway
   |
   +-- Subred privada 10.0.2.0/24
   |     |-- EC2 Backend (Ventas:8080 + Despachos:8081)
   |
   +-- Subred privada 10.0.3.0/24
         |-- EC2 Database (MySQL:3306 con volumen Docker)
```

## Pre-requisitos

1. AWS Academy Learner Lab activo (Start Lab → Green dot)
2. Terraform >= 1.5 instalado
3. Credenciales temporales del Lab cargadas:
   - En AWS Academy: click en `AWS Details` → `AWS CLI` → copiar credenciales
   - Pegarlas en `~/.aws/credentials` o exportar:
     ```bash
     export AWS_ACCESS_KEY_ID=...
     export AWS_SECRET_ACCESS_KEY=...
     export AWS_SESSION_TOKEN=...
     export AWS_REGION=us-east-1
     ```

> Las credenciales del Lab expiran en ~4 horas. Si Terraform falla con
> error de autenticacion, vuelve a copiar las credenciales.

## Despliegue

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Edita terraform.tfvars y cambia db_password

terraform init
terraform plan
terraform apply
```

El apply tarda ~3-4 minutos (NAT Gateway es el mas lento).

## Outputs utiles

Al final del apply Terraform imprime los datos que necesitas:

```bash
terraform output github_secrets_summary
```

Eso lista los valores exactos a copiar en GitHub → Settings → Secrets:

- `AWS_REGION`, `ECR_REGISTRY`
- `ECR_REPO_VENTAS`, `ECR_REPO_DESPACHOS`, `ECR_REPO_FRONTEND`
- `EC2_FRONTEND_ID`, `EC2_BACKEND_ID`, `EC2_DATABASE_ID`
- `BACKEND_PRIVATE_IP`, `DATABASE_PRIVATE_IP`, `FRONTEND_PUBLIC_IP`

## Validar que las EC2 funcionen

Conectate via SSM Session Manager (no necesitas SSH ni .pem):

```bash
aws ssm start-session --target $(terraform output -raw ec2_frontend_id)
```

Dentro de la sesion verifica Docker:

```bash
sudo docker ps
sudo docker --version
```

En la EC2 Database verifica que MySQL este corriendo:

```bash
sudo docker ps   # debe mostrar el contenedor 'mysql'
sudo docker logs mysql --tail 20
```

## Destruir todo (al terminar el lab)

```bash
terraform destroy
```

Esto borra TODO incluido el volumen MySQL. Tarda ~3-5 minutos.

## Costos en Learner Lab

- 3x EC2 t3.micro: ~free tier
- NAT Gateway: ~$0.045/h + datos transferidos
- ECR storage: ~$0.10/GB-mes (despreciable para este proyecto)
- Total estimado: ~$1-2 por dia de uso

Recuerda hacer `terraform destroy` al terminar para no consumir credito.
