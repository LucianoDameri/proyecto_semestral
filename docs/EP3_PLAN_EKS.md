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
- **Un solo workflow, automático**: `cd-eks.yml` hace build+push de las 3
  imágenes y deploy completo en una sola corrida, disparada con cualquier
  push a `deploy`. Se simplificó desde un diseño inicial de 4 workflows
  separados por componente (mysql/ventas/despachos/frontend) a uno solo,
  para reducir puntos de falla mientras se depuraba el pipeline.

## 3. Orden de ejecución

El único paso manual de todo el proceso es el primero, y se hace **una sola
vez** en la vida del proyecto:

1. `cd infra/eks && terraform init && terraform apply` (10-15 min: VPC,
   NAT, cluster EKS, node group). Si el Lab de Academy se reinicia, el
   cluster se borra y hay que repetir este paso.
2. Push a `deploy` (cualquier commit). Dispara los 4 pipelines de EKS en
   cadena: `cd-mysql-eks.yml` por el push directo, y los 3 de servicio en
   cuanto su CI respectivo termine. No hace falta tocar nada a mano.
3. Revisar cada workflow en Actions, o el log de `cd-frontend-eks.yml`
   (el último en la cadena) para ver `kubectl get pods` y la URL pública.

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

## 5. Problemas encontrados y cómo se resolvieron

Material directo para la sección "Problemas encontrados" de la presentación
(IE6/defensa técnica):

1. **AWS Academy resetea todo al reiniciar el Lab.** Cada vez que el Lab se
   detiene/reinicia, se borran el cluster EKS, los nodos y los repos ECR.
   Solución: `terraform apply -target=aws_ecr_repository.this` en `infra/`
   para recrear solo los ECR (rápido), seguido de `terraform apply` completo
   en `infra/eks` (10-15 min) para recrear el cluster.

2. **`The security token included in the request is invalid` en GitHub
   Actions.** Las credenciales de AWS Academy son temporales (~4h) y deben
   actualizarse como un set completo (los 3 valores juntos, del mismo
   momento) en GitHub Secrets cada vez que se reinicia el Lab - actualizar
   solo uno o reusar un valor de un momento distinto produce este error,
   aunque el mismo set funcione en la terminal local.

3. **Pods en `CrashLoopBackOff` y MySQL atascado en `Pending`.** Causa raíz:
   un solo nodo (t3.medium) con poco margen de recursos, combinado con el
   comportamiento por defecto de `RollingUpdate` en Kubernetes (`maxSurge`
   25%, redondeado a 1 pod extra). Cuando un rollout de los backends no
   podía completarse (porque MySQL no estaba lista), Kubernetes dejaba la
   generación vieja Y la nueva de pods corriendo a la vez, agotando la
   memoria/CPU del nodo y sin dejarle espacio a MySQL para programarse -
   un ciclo que se retroalimentaba. Solución aplicada en el código
   (`infra/k8s/backend-ventas.yml`, `backend-despachos.yml`, `frontend.yml`):
   ```yaml
   strategy:
     type: RollingUpdate
     rollingUpdate:
       maxSurge: 0
       maxUnavailable: 1
   ```
   Esto obliga a Kubernetes a apagar un pod viejo antes de crear uno nuevo
   en cada rollout, en vez de sumar uno extra - nunca se vuelve a exceder
   la cantidad de réplicas configurada, sin importar si una dependencia
   (como MySQL) tarda en estar lista.
