# Infraestructura AWS - Terraform & EKS
 
Este módulo levanta la infraestructura del proyecto Innovatech EP2 en AWS utilizando Kubernetes (EKS):
 
- **VPC** `10.0.0.0/16` con 1 subred pública + 2 subredes privadas
- **Internet Gateway** para la subred pública
- **NAT Gateway** para que las subredes privadas accedan a ECR y AWS API
- **Amazon EKS Cluster**: Cluster gestionado con Node Groups (t3.medium)
- **Kubernetes Manifests**: Despliegue de pods para Frontend, Ventas, Despachos y MySQL
- **3 repositorios ECR** privados para el almacenamiento de imágenes
 
## Arquitectura
 
```
Internet
   |
   v
[Load Balancer]
   |
   +-- EKS Cluster (Managed Node Group)
         |
         +-- Pod Frontend (Puerto 80)
         |
         +-- Pod Ventas (Puerto 8080) <--- DNS Interno
         |
         +-- Pod Despachos (Puerto 8081) <--- DNS Interno
         |
         +-- Pod MySQL (Puerto 3306) <--- DNS Interno
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
 
## Despliegue
 
```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# edita terraform.tfvars y cambia db_password
terraform init
terraform plan
terraform apply
```
 
## Outputs útiles
 
Al final del apply, Terraform imprime los valores necesarios:
 
```bash
terraform output github_secrets_summary
```
 
## Destruir todo
 
```bash
terraform destroy
```
 
## Costos en Learner Lab
 
- EKS Cluster: ~$0.10/h
- Node Group (t3.medium): ~free tier / bajo costo
- NAT Gateway: ~$0.045/h
- ECR storage: ~$0.10/GB-mes
 
Recuerda ejecutar `terraform destroy` al terminar para no consumir crédito.
