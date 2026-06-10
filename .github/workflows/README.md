# GitHub Actions - CI/CD Innovatech EP2 (Kubernetes)
 
Este repositorio utiliza un workflow unificado para construir, publicar y desplegar la aplicación en un cluster de Amazon EKS.
 
## Flujo de CI/CD
 
**Build → Push a ECR → Update EKS Deployment**.
 
1. **Build & Push**: Se construyen las imágenes de Frontend, Ventas y Despachos usando `docker buildx`. Las imágenes se etiquetan con el SHA del commit y se suben a Amazon ECR.
2. **K8s Config**: El workflow se autentica en el cluster EKS mediante `aws eks update-kubeconfig`.
3. **Secret Management**: Se crea o actualiza el secreto `db-secrets` en Kubernetes con las credenciales de la base de datos.
4. **Manifest Apply**: Se aplican los archivos YAML definidos en `infra/k8s/`.
5. **Image Update**: Se actualiza la imagen de los deployments activos mediante `kubectl set image`, forzando un despliegue progresivo (Rolling Update).
 
## GitHub Secrets requeridos
 
Crear en **Settings → Secrets and variables → Actions → New repository secret**.
 
### Credenciales AWS Academy (caducan ~4h)
 
| Secret                  | Origen                                               |
|-------------------------|------------------------------------------------------|
| `AWS_ACCESS_KEY_ID`     | AWS Details → AWS CLI (Learner Lab)                  |
| `AWS_SECRET_ACCESS_KEY` | AWS Details → AWS CLI                                 |
| `AWS_SESSION_TOKEN`     | AWS Details → AWS CLI                                 |
 
### Configuración de aplicación
 
| Secret        | Valor                                     |
|---------------|-------------------------------------------|
| `DB_PASSWORD` | mismo password usado en `terraform.tfvars` |
| `DB_NAME`     | `innovatech` (o el valor elegido)         |
 
## Trigger
 
El despliegue se dispara automáticamente al hacer push a la rama `deploy`. También puede ejecutarse manualmente mediante `workflow_dispatch`.
 
## Trazabilidad y Rollback
 
Gracias al uso de etiquetas basadas en el SHA del commit, es posible revertir la versión de la aplicación rápidamente:
 
```bash
kubectl rollout undo deployment/frontend
kubectl rollout undo deployment/ventas
kubectl rollout undo deployment/despachos
```
