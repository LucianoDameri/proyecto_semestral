# EP3 - Arquitectura alternativa con AWS EKS

> El profesor pidió EKS específicamente para este proyecto. La rúbrica
> oficial permite ECS o EKS indistintamente ("se debe utilizar únicamente
> ECS o EKS, según la arquitectura seleccionada por la dupla"), así que
> esta no es una migración que reemplaza el módulo ECS (`infra/ecs.tf`):
> es un módulo Terraform **separado e independiente** (`infra/eks/`) que
> coexiste con él. Aplican y se destruyen por separado.

## 1. Por qué un módulo separado y no un reemplazo

- `infra/ecs.tf` (y todo lo que cuelga de `infra/*.tf`) ya está probado y
  funcionando — no hay razón para arriesgarlo.
- EKS necesita su propia VPC con subredes en 2 AZ y tags específicos de
  Kubernetes (`kubernetes.io/role/elb`, etc.) que no tiene sentido mezclar
  con la VPC del módulo ECS.
- Mantener ambos permite decidir cuál mostrar en la presentación sin haber
  quemado el trabajo del otro.

## 2. Arquitectura EKS

```
Internet
   |
   v
[ELB clasico]  (Service frontend, type=LoadBalancer, subred publica)
   |
   v
[Pod frontend] --(DNS interno k8s)--> [Service backend-ventas]    -> [Pods backend-ventas x2-5]
                                   \-> [Service backend-despachos] -> [Pods backend-despachos x2-5]
                                                                            |
                                                                            v
                                                                    [Pod mysql] (sin PVC,
                                                                     ephemeral, EXCLUSIVO
                                                                     de este modulo - no es
                                                                     la misma DB que usa ECS)

EKS Cluster (control plane administrado por AWS)
  Node Group: 1-2 EC2 t3.medium en subredes privadas
  LabRole reutilizado como cluster role Y node role (sin crear roles IAM nuevos)
```

### Decisiones clave

- **LabRole reutilizado**: AWS Academy bloquea `iam:CreateRole`. El cluster
  y el node group usan `data.aws_iam_role.labrole.arn` directamente. Esto
  solo funciona si la trust policy de `LabRole` permite que `eks.amazonaws.com`
  (cluster) y `ec2.amazonaws.com` (node group) lo asuman. Verificado con
  `lifecycle.precondition` en ambos recursos (`infra/eks/main.tf`) - si no
  se cumple, Terraform falla en segundos en vez de a los 10-15 minutos.
- **ECR reutilizado**: no se crean repos nuevos. `infra/eks/main.tf` usa
  `data "aws_ecr_repository"` para apuntar a los mismos 3 repos que ya usa
  ECS (`innovatech-ventas`, `innovatech-despachos`, `innovatech-frontend`).
  Los workflows de CI (`ci-ventas.yml`, etc.) no cambiaron en nada.
- **MySQL propio**: el cluster EKS corre su propio MySQL como Deployment
  (`infra/k8s/mysql.yml`), sin PVC (Academy no tiene EBS CSI driver
  instalado por defecto). Es una base de datos *distinta* a la que usa la
  EC2 de `infra/ec2.tf` - no comparten datos.
- **LoadBalancer nativo, sin AWS Load Balancer Controller**: el Service
  `frontend` usa `type: LoadBalancer`, que en EKS crea automáticamente un
  Classic ELB usando el proveedor de nube integrado - basta con que las
  subredes públicas tengan el tag `kubernetes.io/role/elb=1` (ya están así
  en `infra/eks/main.tf`). Evita instalar Helm/el Load Balancer Controller.
- **Pipelines siempre manuales**: a diferencia de los `cd-*.yml` de ECS
  (que se disparan solos con `workflow_run` tras el CI), los `*-eks.yml`
  son `workflow_dispatch` únicamente, para no competir con los despliegues
  automáticos hacia ECS en cada push a `deploy`.

## 3. Orden de ejecución

1. `cd infra/eks && terraform init && terraform apply` (10-15 min: VPC,
   NAT, cluster EKS, node group).
2. `aws eks update-kubeconfig --region us-east-1 --name innovatech-eks`
3. Actions → **"EKS - Bootstrap Cluster (manual)"** → Run workflow.
   (instala metrics-server, crea `mysql-secret` y `ecr-secret`, aplica
   `mysql.yml` y `hpa-backends.yml`)
4. Actions → **"Ventas - CD EKS (manual)"**, **"Despachos - CD EKS (manual)"**,
   **"Frontend - CD EKS (manual)"** → Run workflow en cada uno (en ese orden,
   porque el frontend depende de que los Services de backend ya existan).
5. `kubectl get service frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
   para la URL pública.

## 4. Evidencia para la rúbrica / presentación

- **IE1 (clúster)**: `kubectl get nodes`, `aws eks describe-cluster`, y la
  explicación del bloqueo de IAM + cómo se verificó con `precondition`.
- **IE2 (despliegue)**: `kubectl get pods -o wide`, `kubectl get deployments`,
  variables de entorno visibles en `kubectl describe pod <pod>`.
- **IE3 (autoscaling)**: `kubectl get hpa` (necesita metrics-server activo),
  generar carga con un loop de `curl` contra la URL del ELB y observar el
  `REPLICAS` subir de 2 a más.
- **IE4 (pipeline)**: tiempos de cada workflow en la pestaña Actions.
- **IE5 (secrets)**: mismos 4 secrets de siempre (`AWS_*`, `DB_PASSWORD`),
  reutilizados para `mysql-secret` - no se crearon secrets nuevos.
- **IE6 (logs/métricas)**: `kubectl logs deployment/backend-ventas` (la
  rúbrica acepta explícitamente "logs en CloudWatch **o** kubectl logs"),
  más los logs del plano de control que sí van a CloudWatch
  (`/aws/eks/innovatech-eks/cluster`, habilitados en `aws_eks_cluster.main`).
- **IE7 (validación funcional / self-healing)**:
  ```
  kubectl delete pod -l app=backend-ventas
  kubectl get pods -w
  ```
  Kubernetes recrea el pod solo. Usa un pod de **backend**, no el de
  `mysql` (ese pierde los datos al recrearse, por no tener PVC).
