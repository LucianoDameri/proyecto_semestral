# GitHub Actions - CI/CD Innovatech EP2/EP3

Este directorio contiene la documentación de los workflows que
construyen, publican y despliegan cada componente del proyecto.

Cada componente (Ventas, Despachos, Frontend) tiene **dos archivos de
workflow separados**: uno de CI y otro de CD. El nombre del archivo deja
explícito a qué etapa corresponde cada uno.

| Archivo                | Nombre en Actions                    | Etapa | Carpeta vigilada / Trigger             | Imagen ECR             | EC2 destino |
|------------------------|----------------------------------------|-------|-------------------------------------------|--------------------------|-------------|
| `ci-ventas.yml`        | "Ventas - CI (Build & Push)"          | CI    | `back-Ventas_SpringBoot/**`              | `innovatech-ventas`      | -           |
| `cd-ventas.yml`        | "Ventas - CD (Deploy)"                | CD    | `workflow_run` de CI Ventas (o manual)   | `innovatech-ventas`      | Backend     |
| `ci-despachos.yml`     | "Despachos - CI (Build & Push)"       | CI    | `back-Despachos_SpringBoot/**`           | `innovatech-despachos`   | -           |
| `cd-despachos.yml`     | "Despachos - CD (Deploy)"             | CD    | `workflow_run` de CI Despachos (o manual)| `innovatech-despachos`   | Backend     |
| `ci-frontend.yml`      | "Frontend - CI (Build & Push)"        | CI    | `front_despacho/**`                      | `innovatech-frontend`    | -           |
| `cd-frontend.yml`      | "Frontend - CD (Deploy)"              | CD    | `workflow_run` de CI Frontend (o manual) | `innovatech-frontend`    | Frontend    |
| `cd-mysql.yml`         | "MySQL - CD (Bootstrap/Deploy)"       | CD    | manual (`workflow_dispatch`)             | `mysql:<tag>` (Docker Hub)| Database    |

> Los antiguos `cicd-<servicio>.yml` (un solo archivo con jobs `ci` + `cd`)
> fueron reemplazados por este esquema de archivos separados. Bórralos de tu
> checkout local con `git rm .github/workflows/cicd-*.yml`.

## Cómo funciona la cadena CI -> CD

1. **CI** (`ci-<servicio>.yml`): se dispara con push a `deploy` (cuando cambia
   la carpeta del servicio) o manualmente. Hace checkout, login a ECR, build
   de la imagen Docker y push de los tags `latest` y `<sha7>`. No toca ningún
   otro recurso de AWS.
2. **CD** (`cd-<servicio>.yml`): se dispara automáticamente cuando el workflow
   de CI correspondiente termina con éxito (`on.workflow_run`), o manualmente
   vía `workflow_dispatch`. Recalcula la URL de la imagen `:latest` en ECR
   (no depende de outputs de otro workflow), resuelve las IPs privadas
   necesarias y despliega el contenedor en la EC2 correspondiente vía
   `aws ssm send-command`.

No se usa SSH ni claves `.pem`. La autenticación es 100% IAM gracias al
`LabInstanceProfile` adjunto a las EC2 (configurado por Terraform).

## Configuración de GitHub: Secrets vs Variables

Para reducir la cantidad de **Secrets** (IE5 de la pauta) solo lo realmente
sensible se guarda como secret. Todo lo demás (IDs de recursos, nombres,
endpoints) son **Repository Variables** (no se ocultan en los logs, pero
tampoco son información comprometedora).

### Secrets (Settings → Secrets and variables → Actions → **Secrets**) — 4 en total

| Secret                  | Origen                                               |
|-------------------------|------------------------------------------------------|
| `AWS_ACCESS_KEY_ID`     | AWS Academy → AWS Details → AWS CLI (Learner Lab)    |
| `AWS_SECRET_ACCESS_KEY` | AWS Academy → AWS Details → AWS CLI                  |
| `AWS_SESSION_TOKEN`     | AWS Academy → AWS Details → AWS CLI                  |
| `DB_PASSWORD`           | mismo password u