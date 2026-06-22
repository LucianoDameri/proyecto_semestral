# GitHub Actions - CI/CD Innovatech EP3 (ECS Fargate)

Este directorio contiene la documentación de los workflows que
construyen, publican y despliegan cada componente del proyecto.

Cada componente (Ventas, Despachos, Frontend) tiene **dos archivos de
workflow separados**: uno de CI y otro de CD. El nombre del archivo deja
explícito a qué etapa corresponde cada uno.

| Archivo                | Nombre en Actions                    | Etapa | Carpeta vigilada / Trigger             | Imagen ECR             | Destino ECS |
|------------------------|----------------------------------------|-------|-------------------------------------------|--------------------------|-------------|
| `ci-ventas.yml`        | "Ventas - CI (Build & Push)"          | CI    | `back-Ventas_SpringBoot/**`              | `innovatech-ventas`      | -           |
| `cd-ventas.yml`        | "Ventas - CD (Deploy)"                | CD    | `workflow_run` de CI Ventas (o manual)   | `innovatech-ventas`      | Service ECS `innovatech-ventas` |
| `ci-despachos.yml`     | "Despachos - CI (Build & Push)"       | CI    | `back-Despachos_SpringBoot/**`           | `innovatech-despachos`   | -           |
| `cd-despachos.yml`     | "Despachos - CD (Deploy)"             | CD    | `workflow_run` de CI Despachos (o manual)| `innovatech-despachos`   | Service ECS `innovatech-despachos` |
| `ci-frontend.yml`      | "Frontend - CI (Build & Push)"        | CI    | `front_despacho/**`                      | `innovatech-frontend`    | Service ECS `innovatech-frontend` |
| `cd-frontend.yml`      | "Frontend - CD (Deploy)"              | CD    | `workflow_run` de CI Frontend (o manual) | `innovatech-frontend`    | Service ECS `innovatech-frontend` |
| `cd-mysql.yml`         | "MySQL - CD (Bootstrap/Deploy)"       | CD    | manual (`workflow_dispatch`)             | -                        | EC2 Database (verificación de estado) |

> Los antiguos `cicd-<servicio>.yml` (un solo archivo con jobs `ci` + `cd`) y
> el flujo basado en SSM (EP2) fueron reemplazados por este esquema:
> archivos CI/CD separados + despliegue directo en ECS Fargate.

## Arquitectura (EP3)

- **Cluster ECS Fargate** (`innovatech-cluster`) con 3 servicios: ventas,
  despachos, frontend. Sin servidores que administrar (serverless).
- **Application Load Balancer** público en el puerto 80, con reglas de
  enrutamiento por path: `/api/v1/ventas*` → service Ventas,
  `/api/v1/despachos*` → service Despachos, el resto → service Frontend.
- **MySQL** sigue corriendo en la EC2 `database` (EP2), en subred privada.
  Las tareas ECS se conectan a su IP privada por el puerto 3306.
- **Autoscaling** por CPU (Target Tracking, 50%) en los 3 servicios,
  `min_capacity=1` / `max_capacity=3`.
- **LabRole** de AWS Academy se reutiliza como execution role y task role
  de cada Task Definition (no se crean roles IAM nuevos).

## Cómo funciona la cadena CI -> CD

1. **CI** (`ci-<servicio>.yml`): se dispara con push a `deploy` (cuando cambia
   la carpeta del servicio) o manualmente. Hace checkout, login a ECR, build
   de la imagen Docker y push de los tags `latest` y `<sha7>`. No toca ningún
   otro recurso de AWS.
2. **CD** (`cd-<servicio>.yml`): se dispara automáticamente cuando el workflow
   de CI correspondiente termina con éxito (`on.workflow_run`), o manualmente
   vía `workflow_dispatch`. Ejecuta `aws ecs update-service --force-new-deployment`
   sobre el servicio ECS correspondiente (la Task Definition usa el tag
   `:latest`, así que ECS vuelve a hacer `docker pull` de la imagen recién
   publicada) y espera con `aws ecs wait services-stable` a que las tareas
   nuevas queden `RUNNING` y saludables en el target group del ALB.

No se usa SSH, claves `.pem` ni AWS SSM Session Manager para el despliegue de
los 3 servicios. La autenticación es 100% IAM vía
`AWS_ACCESS_KEY_ID/SECRET/SESSION_TOKEN` (credenciales temporales de AWS
Academy), que tienen permisos suficientes sobre ECS/ELB en el Learner Lab.

**Importante - orden de despliegue inicial:** los servicios ECS deben existir
(`terraform apply` de `infra/ecs.tf`) y tener al menos una imagen `:latest` en
ECR (CI ejecutado al menos una vez) **antes** de que el primer `cd-*.yml`
pueda tener éxito. Si el servicio ECS aún no existe, `aws ecs update-service`
falla con `ServiceNotFoundException` - es esperado en el primer push.

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
| `DB_PASSWORD`           | mismo password usado en `terraform.tfvars` (`db_password`) |

> Las credenciales de AWS Academy expiran cada ~4h. Hay que actualizarlas en
> GitHub Secrets cada vez que se reinicia el Learner Lab.

### Variables (Settings → Secrets and variables → Actions → **Variables**)

No sensibles - sirven de referencia / documentación, los workflows de ECS
usan valores fijos en su bloque `env:` (`ECS_CLUSTER`, `ECS_SERVICE`,
`ECR_REPO_NAME`) porque son nombres fijos definidos en Terraform y no cambian
entre cada `terraform apply` (a diferencia de los IDs de instancia EC2 de la
fase EP2, que sí cambiaban en cada `destroy/apply`).

Aun se mantiene `EC2_DATABASE_ID` como secret/variable para `cd-mysql.yml`,
que solo consulta el estado de la instancia de base de datos.

## Si algo falla en el primer despliegue

1. Verifica que `terraform apply` de `infra/ecs.tf` haya terminado sin error
   y que el cluster/servicios existan en la consola ECS.
2. Verifica que el CI del servicio haya corrido al menos una vez (imagen
   `:latest` presente en el repo ECR correspondiente).
3. Si el servicio existe pero las tareas no llegan a `RUNNING`/healthy,
   revisa CloudWatch Logs (`/ecs/innovatech-<servicio>`) - ahí queda el
   stdout/stderr de cada contenedor (errores de conexión a la DB, excepciones
   de arranque de Spring Boot, etc.).
4. Re-ejecuta el CD manualmente (`workflow_dispatch`) una vez resuelta la causa.

## Arquitectura usada para la entrega: EKS (`cd-eks.yml`)

El profesor pidió específicamente EKS para este proyecto (la rúbrica acepta
ECS o EKS indistintamente, pero la entrega final es EKS). El código de ECS
(arriba) se deja intacto en el repo como referencia, pero no se despliega.

A diferencia de ECS (separado en CI/CD por servicio), EKS usa **un solo
workflow** (`cd-eks.yml`) que hace todo en una sola corrida automática,
disparada con cualquier push a `deploy`: build+push de las 3 imágenes,
conectar `kubectl`, instalar `metrics-server`, crear/refrescar `mysql-secret`
y `ecr-secret`, aplicar los manifiestos de `infra/k8s/` y esperar los
rollouts. Se simplificó a un solo archivo (en vez de 4 separados por
componente) para reducir puntos de falla mientras se termina de probar.

Todo es automático - **el único paso manual en la vida del proyecto** es el
`terraform apply` inicial de `infra/eks` (crea el cluster; no se puede
automatizar desde Actions con credenciales temporales de Academy). Una vez
que el cluster existe, cada push a `deploy` redespliega solo.

El detalle completo de la arquitectura está en `docs/EP3_PLAN_EKS.md`.
