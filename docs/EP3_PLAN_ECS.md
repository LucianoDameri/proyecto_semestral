# EP3 - Plan de migración a ECS Fargate (AWS Academy / LabRole)

> Estado: PLAN. La EP2 (EC2 + SSM) sigue funcionando como base; esta es la
> hoja de ruta para llegar a EP3 (orquestación con ECS) dentro de las 6h
> asignadas, manteniendo el costo en el margen del Learner Lab.

## 1. Por qué ECS Fargate (y no EKS)

- AWS Academy Learner Lab solo entrega el rol **`LabRole`** /
  `LabInstanceProfile`. No se pueden crear roles IAM nuevos
  (`iam:CreateRole` está bloqueado).
- EKS necesita como mínimo: un Cluster IAM Role y un Node IAM Role propios.
  Sin poder crear roles, EKS es inviable en el tiempo disponible.
- ECS Fargate permite usar `LabRole` tanto como **execution role** como
  **task role** (ya existe, no hay que crearlo). No hay nodos que
  administrar (serverless), por lo que tampoco se necesita un node role.
- Costo: Fargate cobra por vCPU/RAM-segundo mientras la tarea corre. Con
  tareas pequeñas (0.25 vCPU / 0.5 GB) y `desired_count` bajo (1-2), el costo
  es del orden de unos pocos USD por el día de uso — cabe en los créditos
  del Lab. EKS tiene un cargo fijo de ~$0.10/h por el control plane que no
  es necesario asumir.

**Decisión: ECS Fargate**, reutilizando la VPC, subredes, Security Groups y
los 3 repos ECR ya creados en `infra/` (EP2).

## 2. Arquitectura objetivo

```
Internet
   |
   v
 [ALB público]  (subred pública)
   |  \
   |   \-- target group :8080 -> Service Ventas (Fargate, subred privada)
   |   \-- target group :8081 -> Service Despachos (Fargate, subred privada)
   \---- target group :80   -> Service Frontend (Fargate, subred privada
                                 con regla "asignar IP pública" o vía ALB)

 ECS Cluster (capacity provider: FARGATE)
   - Service frontend  (1-3 tasks, HPA via Target Tracking CPU 50%)
   - Service ventas    (1-3 tasks, Target Tracking CPU 50%)
   - Service despachos (1-3 tasks, Target Tracking CPU 50%)

 Base de datos: se mantiene en la EC2 actual (innovatech_mysql_data) o se
 mueve a RDS MySQL db.t3.micro (free tier 750h/mes). Recomendado: dejar
 MySQL en la EC2 existente para no gastar tiempo/cupo en RDS, y apuntar
 los servicios ECS a su IP privada (igual que hoy).
```

### Networking

- Reutilizar `aws_vpc.main`, `aws_subnet.public`, `aws_subnet.private_backend`.
- Nuevo Security Group `sg-alb` (80/443 desde 0.0.0.0/0).
- Nuevo Security Group `sg-ecs-tasks` (puertos 8080/8081/80 solo desde
  `sg-alb`).
- Las tareas Fargate en subred privada necesitan salida a internet para
  `docker pull` desde ECR → ya existe el NAT Gateway de EP2, se reutiliza.

### IAM (clave para AWS Academy)

```hcl
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}
```

Usar `data.aws_iam_role.lab_role.arn` como `execution_role_arn` y
`task_role_arn` en cada `aws_ecs_task_definition`. **No crear roles nuevos.**

## 3. Recursos Terraform a agregar (`infra/ecs.tf`, nuevo archivo)

1. `aws_ecs_cluster.this` (capacity_providers = ["FARGATE", "FARGATE_SPOT"]).
2. `aws_lb.public` (ALB en subred pública) + `aws_lb_listener` puerto 80.
3. `aws_lb_target_group` x3 (frontend, ventas, despachos) — `target_type = "ip"`.
4. `aws_lb_listener_rule` para enrutar `/api/v1/ventas*` y
   `/api/v1/despachos*` a sus target groups (frontend en el default).
5. `aws_ecs_task_definition` x3 (`requires_compatibilities = ["FARGATE"]`,
   `network_mode = "awsvpc"`, `cpu = "256"`, `memory = "512"`,
   `execution_role_arn` y `task_role_arn` = LabRole, imagen = `<ECR_REGISTRY>/innovatech-<svc>:latest`,
   variables de entorno: mismas que hoy en `docker run -e ...`).
6. `aws_ecs_service` x3 (`launch_type = "FARGATE"`, `desired_count = 1`,
   `network_configuration` con subred privada + `sg-ecs-tasks`,
   `load_balancer { target_group_arn, container_name, container_port }`).
7. `aws_appautoscaling_target` + `aws_appautoscaling_policy`
   (TargetTrackingScaling, `ECSServiceAverageCPUUtilization`, target = 50%,
   `min_capacity = 1`, `max_capacity = 3`) x3 servicios → cumple IE3.
8. `aws_cloudwatch_log_group` por servicio (`/ecs/innovatech-<svc>`,
   retención 3-7 días para no acumular costo) → logs para IE6/IE7.

## 4. Pipeline CI/CD para ECS (nuevo job `cd` por workflow)

Reemplaza el job `cd` (SSM/EC2) por:

```yaml
  cd:
    needs: ci
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with: { ... }

      - name: Forzar nuevo deployment en ECS
        run: |
          aws ecs update-service \
            --cluster innovatech-cluster \
            --service innovatech-${{ env.SERVICE_NAME }} \
            --force-new-deployment

      - name: Esperar a que el servicio este estable
        run: |
          aws ecs wait services-stable \
            --cluster innovatech-cluster \
            --services innovatech-${{ env.SERVICE_NAME }}
```

Como la Task Definition usa el tag `:latest` y `force-new-deployment` vuelve
a tirar (`docker pull`) la imagen, no es obligatorio registrar una nueva
revisión de Task Definition en cada push — simplifica el pipeline y reduce
llamadas IAM. (Alternativa más "best practice": registrar nueva revisión con
el tag `<sha7>` vía `aws ecs register-task-definition` +
`update-service --task-definition`, para trazabilidad/rollback real — se
puede agregar como mejora si el tiempo alcanza, ítem para la sección
"oportunidades de optimización" de IE6.)

### Nuevas variables/secrets necesarios

Solo **1 variable nueva**: `ECS_CLUSTER_NAME` (ej. `innovatech-cluster`).
No se necesitan secrets adicionales — se sigue usando
`AWS_ACCESS_KEY_ID/SECRET/SESSION_TOKEN` (LabRole tiene permisos ECS/ELB
suficientes en Academy).

## 5. Checklist para las 6h

1. (30 min) `terraform apply` de `infra/ecs.tf` (cluster, ALB, target
   groups, task defs con `desired_count=1`, sin autoscaling todavía).
2. (30 min) Actualizar GitHub Variables: `ECS_CLUSTER_NAME`,
   `ALB_DNS_NAME` (output de Terraform).
3. (30 min) Editar los 3 workflows: reemplazar job `cd` SSM → `ecs
   update-service` (sección 4).
4. (20 min) Push a `deploy`, verificar en consola ECS que las 3 tareas
   pasan a `RUNNING` y el ALB las marca `healthy`.
5. (15 min) Probar `http://<ALB_DNS_NAME>/` (frontend) y que el frontend
   pueda llamar a ventas/despachos vía el ALB.
6. (20 min) Agregar `aws_appautoscaling_target/policy` (Target Tracking CPU
   50%), `terraform apply` de nuevo.
7. (20 min) Generar carga (ej. `hey`/`ab` o un loop de `curl`) contra un
   endpoint y capturar pantallas de Service → Metrics mostrando el scale-out
   (IE3 + "evidencia de métricas/simulación de carga").
8. (15 min) Revisar logs en CloudWatch (`/ecs/innovatech-ventas`, etc.) y
   capturar pantallas para IE6.
9. (15 min) Provocar un fallo (parar manualmente una tarea desde la consola)
   y verificar que ECS la recrea sola → evidencia "recuperación post-deploy"
   (IE7).
10. (resto) Preparar la presentación: arquitectura, roles/LabRole,
    autoscaling, métricas de pipeline (tiempos de cada job en la pestaña
    Actions), problemas encontrados (incluyendo el fix del bug de SSM/jq de
    la fase EC2) y cómo se resolvieron.

## 6. Mapeo con la rúbrica (qué cubre qué)

| Indicador | Cómo se cumple |
|-----------|----------------|
| IE1 Clúster AWS | `aws_ecs_cluster`, capacity provider FARGATE, VPC/subnets/SG reutilizados de EP2, LabRole documentado y justificado |
| IE2 Despliegue Front+Back | 3 `aws_ecs_service` con imágenes desde ECR, env vars en la task definition, ALB con listener rules |
| IE3 Autoscaling | `aws_appautoscaling_policy` Target Tracking CPU 50% por servicio + capturas + prueba de carga |
| IE4 Pipeline CI/CD | jobs `ci` (build/push) y `cd` (`ecs update-service` + `wait services-stable`) ya separados y documentados |
| IE5 Secrets | 4 secrets sensibles + variables no sensibles (ver `.github/workflows/README.md`) |
| IE6 Logs/métricas/tiempos | CloudWatch Logs por servicio + duración de jobs visible en pestaña Actions |
| IE7 Validación funcional | URL pública del ALB, comunicación front→back vía rutas del ALB, recuperación tras matar una task |
