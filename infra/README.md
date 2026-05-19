# Infraestructura AWS - Terraform

Este módulo levanta la infraestructura del proyecto Innovatech EP2 en AWS:

- **VPC** `10.0.0.0/16` con 1 subred pública + 2 subredes privadas
- **Internet Gateway** para la subred pública
- **NAT Gateway** para que las subredes privadas accedan a ECR y SSM
- **3 instancias EC2** (t3.micro) con Docker preinstalado:
  - `ec2-frontend` en subred pública (Nginx + React)
  - `ec2-backend` en subred privada (microservicios Ventas + Despachos)
  - `ec2-database` en subred privada (MySQL 8 con volumen persistente)
- **3 Security Groups** con política de mínimo privilegio
- **3 repositorios ECR** privados con escaneo de vulnerabilidades activado

## Arquitectura

```
Internet
   |
   v
[IGW]
   |
   +-- Subred pública  10.0.1.0/24
   |     |-- EC2 Frontend (IP pública, puerto 80)  <-- usuarios
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
   - En AWS Academy: haz clic en `AWS Details` → `AWS CLI` → copiar credenciales
   - Pegarlas en `~/.aws/credentials` o exportar:
     ```bash
     export AWS_ACCESS_KEY_ID=...
     export AWS_SECRET_ACCESS_KEY=...
     export AWS_SESSION_TOKEN=...
     export AWS_REGION=us-east-1
     ```

> Las credenciales del Lab expiran en ~4 horas. Si Terraform falla por
> autenticación, vuelve a copiar las credenciales.

## Despliegue

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# edita terraform.tfvars y cambia db_password
terraform init
terraform plan
terraform apply
```

El apply tarda ~3-4 minutos (la creación del NAT Gateway suele ser la parte más
lenta).

## Outputs útiles

Al final del apply, Terraform imprime los valores necesarios:

```bash
terraform output github_secrets_summary
```

Copiar estos valores en GitHub → Settings → Secrets:

- `AWS_REGION`, `ECR_REGISTRY`
- `ECR_REPO_VENTAS`, `ECR_REPO_DESPACHOS`, `ECR_REPO_FRONTEND`
- `EC2_FRONTEND_ID`, `EC2_BACKEND_ID`, `EC2_DATABASE_ID`
- `BACKEND_PRIVATE_IP`, `DATABASE_PRIVATE_IP`, `FRONTEND_PUBLIC_IP`

## Validar que las EC2 funcionen

Conéctate mediante SSM Session Manager (sin SSH ni `.pem`):

```bash
aws ssm start-session --target $(terraform output -raw ec2_frontend_id)
```

Dentro de la sesión, comprueba Docker:

```bash
sudo docker ps
sudo docker --version
```

En la EC2 Database revisa que MySQL esté activo:

```bash
sudo docker ps   # debe mostrar el contenedor 'mysql'
sudo docker logs mysql --tail 20
```

## Destruir todo

```bash
terraform destroy
```

Esto borra toda la infraestructura, incluido el volumen MySQL. Tarda ~3-5
minutos.

## Costos en Learner Lab

- 3x EC2 t3.micro: ~free tier
- NAT Gateway: ~$0.045/h + datos transferidos
- ECR storage: ~$0.10/GB-mes
- Total estimado: ~$1-2 por día de uso

Recuerda ejecutar `terraform destroy` al terminar para no consumir crédito.
