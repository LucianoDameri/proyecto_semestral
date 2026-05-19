# GitHub Actions - CI/CD Innovatech EP2

Tres pipelines independientes, uno por capa de la aplicacion. Cada uno
se dispara con un `push` a la rama `deploy` cuando cambian sus archivos.

| Pipeline               | Carpeta vigilada                       | Imagen ECR                  | EC2 destino |
|------------------------|----------------------------------------|-----------------------------|-------------|
| `cicd-ventas.yml`      | `back-Ventas_SpringBoot/**`            | `innovatech-ventas`         | Backend     |
| `cicd-despachos.yml`   | `back-Despachos_SpringBoot/**`         | `innovatech-despachos`      | Backend     |
| `cicd-frontend.yml`    | `front_despacho/**`                    | `innovatech-frontend`       | Frontend    |

Flujo: **Build -> Push a ECR -> Deploy via SSM `send-command`**.

No usamos SSH ni claves `.pem`. La autenticacion es 100% IAM gracias a
`LabInstanceProfile` adjunto a las EC2 (configurado por Terraform).

## GitHub Secrets requeridos

Crear en **Settings -> Secrets and variables -> Actions -> New repository secret**:

### Credenciales AWS Academy (caducan ~4h, hay que actualizarlas)

| Secret                  | Donde sacarlo                                           |
|-------------------------|---------------------------------------------------------|
| `AWS_ACCESS_KEY_ID`     | AWS Details -> AWS CLI (Learner Lab)                    |
| `AWS_SECRET_ACCESS_KEY` | AWS Details -> AWS CLI                                  |
| `AWS_SESSION_TOKEN`     | AWS Details -> AWS CLI                                  |

### Recursos AWS (outputs de Terraform)

Despues de `terraform apply`, corre:

```bash
terraform -chdir=infra output -json github_secrets_summary
```

Y copia cada valor:

| Secret                | Output Terraform              |
|-----------------------|-------------------------------|
| `ECR_REPO_VENTAS`     | `ecr_repos.ventas`            |
| `ECR_REPO_DESPACHOS`  | `ecr_repos.despachos`         |
| `ECR_REPO_FRONTEND`   | `ecr_repos.frontend`          |
| `EC2_FRONTEND_ID`     | `ec2_frontend_id`             |
| `EC2_BACKEND_ID`      | `ec2_backend_id`              |
| `EC2_DATABASE_ID`     | `ec2_database_id`             |

### Configuracion app

| Secret        | Valor                                     |
|---------------|-------------------------------------------|
| `DB_PASSWORD` | mismo password usado en `terraform.tfvars`|
| `DB_NAME`     | `innovatech` (o lo que pusiste)           |

## Como funciona el deploy

1. Push a `deploy` -> GitHub Actions arranca el workflow correspondiente.
2. `docker build` con tag `${SHA::7}` + `latest`.
3. `docker push` a Amazon ECR.
4. `aws ssm send-command` ejecuta dentro de la EC2:
   - login a ECR (con credenciales del LabInstanceProfile, no del runner)
   - `docker pull` de la imagen `latest`
   - `docker stop` + `docker rm` del contenedor viejo
   - `docker run` del contenedor nuevo con env vars y puertos correctos
5. El workflow espera al SSM y trae stdout/stderr al log de Actions.

## Trigger manual

Cada workflow tiene `workflow_dispatch`. Desde **Actions** se puede correr
en cualquier rama con el boton **Run workflow**.

## Tagging y trazabilidad

Cada build deja DOS tags en ECR:

- `latest` -> el ultimo deploy (lo que esta corriendo)
- `<sha7>` -> commit exacto, para rollback (`docker pull repo:<sha7>`)

## Rollback rapido

Desde la EC2 (via SSM Session Manager):

```bash
aws ecr describe-images --repository-name innovatech-ventas \
  --query 'imageDetails[].imageTags[]' --output text
sudo docker pull <repo>:<sha7-anterior>
sudo docker stop ventas && sudo docker rm ventas
sudo docker run -d --name ventas ... <repo>:<sha7-anterior>
```
