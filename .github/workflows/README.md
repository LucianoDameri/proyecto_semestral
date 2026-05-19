# GitHub Actions - CI/CD Innovatech EP2

Este directorio contiene la documentación de los tres workflows que
construyen, publican y despliegan cada componente del proyecto.

| Pipeline               | Carpeta vigilada                       | Imagen ECR                  | EC2 destino |
|------------------------|----------------------------------------|-----------------------------|-------------|
| `cicd-ventas.yml`      | `back-Ventas_SpringBoot/**`            | `innovatech-ventas`         | Backend     |
| `cicd-despachos.yml`   | `back-Despachos_SpringBoot/**`         | `innovatech-despachos`      | Backend     |
| `cicd-frontend.yml`    | `front_despacho/**`                    | `innovatech-frontend`       | Frontend    |

Flujo: **Build → Push a ECR → Deploy via SSM `send-command`**.

No se usa SSH ni claves `.pem`. La autenticación es 100% IAM gracias al
`LabInstanceProfile` adjunto a las EC2 (configurado por Terraform).

## GitHub Secrets requeridos

Crear en **Settings → Secrets and variables → Actions → New repository secret**.

### Credenciales AWS Academy (caducan ~4h)

| Secret                  | Origen                                               |
|-------------------------|------------------------------------------------------|
| `AWS_ACCESS_KEY_ID`     | AWS Details → AWS CLI (Learner Lab)                  |
| `AWS_SECRET_ACCESS_KEY` | AWS Details → AWS CLI                                 |
| `AWS_SESSION_TOKEN`     | AWS Details → AWS CLI                                 |

### Recursos AWS (outputs de Terraform)

Después de `terraform apply`, ejecutar:

```bash
terraform -chdir=infra output -json github_secrets_summary
```

Copiar cada valor a su secret correspondiente:

| Secret                | Output Terraform              |
|-----------------------|-------------------------------|
| `ECR_REPO_VENTAS`     | `ecr_repos.ventas`            |
| `ECR_REPO_DESPACHOS`  | `ecr_repos.despachos`         |
| `ECR_REPO_FRONTEND`   | `ecr_repos.frontend`          |
| `EC2_FRONTEND_ID`     | `ec2_frontend_id`             |
| `EC2_BACKEND_ID`      | `ec2_backend_id`              |
| `EC2_DATABASE_ID`     | `ec2_database_id`             |

### Configuración de aplicación

| Secret        | Valor                                     |
|---------------|-------------------------------------------|
| `DB_PASSWORD` | mismo password usado en `terraform.tfvars` |
| `DB_NAME`     | `innovatech` (o el valor elegido)         |

## Cómo funciona el deploy

1. Push a `deploy` → GitHub Actions inicia el workflow correspondiente.
2. `docker build` con tags `latest` y `${SHA::7}`.
3. `docker push` a Amazon ECR.
4. `aws ssm send-command` ejecuta en la EC2:
   - login a ECR (con el LabInstanceProfile, no con el runner)
   - `docker pull` de la imagen `latest`
   - `docker stop` + `docker rm` del contenedor antiguo
   - `docker run` del contenedor nuevo con las variables y puertos correctos
5. El workflow espera al SSM y recoge stdout/stderr en el log de Actions.

## Trigger manual

Cada workflow incluye `workflow_dispatch`. Desde **Actions** es posible ejecutar
el workflow manualmente en cualquier rama con el botón **Run workflow**.

## Tagging y trazabilidad

Cada build deja dos tags en ECR:

- `latest` → último deploy en producción
- `<sha7>` → commit exacto, útil para rollback

## Rollback rápido

Desde la EC2 usando SSM Session Manager:

```bash
aws ecr describe-images --repository-name innovatech-ventas \
  --query 'imageDetails[].imageTags[]' --output text
sudo docker pull <repo>:<sha7-anterior>
sudo docker stop ventas && sudo docker rm ventas
sudo docker run -d --name ventas ... <repo>:<sha7-anterior>
```
