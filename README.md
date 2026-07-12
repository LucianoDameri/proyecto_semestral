# Innovatech Chile — Plataforma de Despachos

> **ISY1101 — Introducción a Herramientas DevOps**  
> EP3 / Evaluación Final Transversal (EFT)  
> Orquestación con AWS EKS · CI/CD con GitHub Actions · Contenedores Docker

---

## Descripción del proyecto

Plataforma de microservicios para la gestión de **órdenes de compra (Ventas)** y **órdenes de despacho (Despachos)** de Innovatech Chile. Compuesta por un frontend SPA en React, dos backends Spring Boot y una base de datos MySQL, todo contenedorizado y orquestado en AWS EKS con despliegue automático vía GitHub Actions.

---

## Arquitectura — AWS EKS

```
INTERNET
   |
   v
[Classic ELB  :80]   ← Service type=LoadBalancer (subred pública)
   |
   v
[Pod frontend  nginx:8080]
   |    DNS interno Kubernetes
   +---> [Service backend-ventas    ClusterIP :8080]  → [Pods x2-5]
   +---> [Service backend-despachos ClusterIP :8081]  → [Pods x2-5]
                                                              |
                                                              v
                                                    [Pod MySQL 8.0  :3306]

EKS Cluster: innovatech-eks
  VPC: 10.1.0.0/16
    Subredes públicas:  10.1.0.0/24, 10.1.1.0/24  → ELB
    Subredes privadas:  10.1.2.0/24, 10.1.3.0/24  → Nodos EC2
  Node Group: 1-2 × t3.medium (desired 1 / min 1 / max 2)
  IAM: LabRole reutilizado como cluster role + node role (Academy no permite iam:CreateRole)
  Security Groups:
    sg-cluster : permite 443 desde Internet (control plane)
    sg-nodes   : permite todo el tráfico interno 10.1.0.0/16
  HPA: CPU 50% → escala réplicas 2→5 automáticamente
```

**Flujo de comunicación:**
```
Usuario → ELB :80 → frontend nginx → proxy inverso por DNS k8s
  /api/v1/ventas    → backend-ventas:8080    → mysql:3306
  /api/v1/despachos → backend-despachos:8081 → mysql:3306
```

---

## Stack tecnológico

| Capa | Tecnología |
|------|-----------|
| Frontend | React 18 + Vite 5 + Tailwind 3 + Axios |
| Web server | Nginx (nginx-unprivileged 1.27 alpine, non-root) |
| Backend Ventas | Java 17 + Spring Boot 3.4 + JPA + Actuator |
| Backend Despachos | Java 17 + Spring Boot 3.4 + JPA + Actuator |
| Base de datos | MySQL 8.0 |
| Contenedores | Docker (multi-stage, non-root, healthchecks) |
| Orquestación local | Docker Compose |
| Orquestación nube | AWS EKS (Kubernetes) |
| Infraestructura | Terraform 1.5+ |
| Registry | Amazon ECR (3 repos con scan automático) |
| CI/CD | GitHub Actions (`cd-eks.yml`) |

---

## Estructura del repositorio

```
proyecto_semestral/
├── docker-compose.yml                # Stack local completo (4 servicios)
├── .env                              # Variables de entorno locales (no commitear)
├── README.md
│
├── back-Ventas_SpringBoot/Springboot-API-REST/
│   ├── Dockerfile                    # Multi-stage: builder Maven → runtime JRE alpine
│   ├── .dockerignore
│   └── src/                          # Código Java + application.properties
│
├── back-Despachos_SpringBoot/Springboot-API-REST-DESPACHO/
│   ├── Dockerfile                    # Mismo patrón, puerto 8081
│   ├── .dockerignore
│   └── src/
│
├── front_despacho/
│   ├── Dockerfile                    # Multi-stage: Node build → nginx-unprivileged
│   ├── .dockerignore
│   ├── nginx.conf                    # Template con envsubst para VENTAS_HOST/DESPACHOS_HOST
│   └── src/                          # Componentes React + config.js
│
├── infra/
│   ├── main.tf  vpc.tf  security.tf  ecr.tf  ec2.tf  ecs.tf
│   ├── eks/
│   │   ├── main.tf                   # Cluster EKS + node group + VPC propia
│   │   ├── variables.tf  outputs.tf
│   │   └── terraform.tfstate
│   └── k8s/
│       ├── mysql.yml                 # Deployment MySQL
│       ├── backend-ventas.yml        # Deployment + Service + maxSurge:0
│       ├── backend-despachos.yml     # Deployment + Service + maxSurge:0
│       ├── frontend.yml              # Deployment + Service LoadBalancer
│       └── hpa-backends.yml          # HPA CPU 50% → 2-5 réplicas
│
├── docs/
│   ├── EP3_PLAN_EKS.md              # Decisiones técnicas y arquitectura detallada
│   └── EP3_Presentacion_Innovatech.pptx
│
└── .github/workflows/
    ├── cd-eks.yml                    # Pipeline unificado EKS (build+push+deploy)
    ├── ci-ventas.yml                 # CI tests backend Ventas
    ├── ci-despachos.yml              # CI tests backend Despachos
    ├── ci-frontend.yml               # CI lint/build frontend
    ├── cd-ventas.yml                 # CD ECS backend Ventas
    ├── cd-despachos.yml              # CD ECS backend Despachos
    ├── cd-frontend.yml               # CD ECS frontend
    ├── cd-mysql.yml                  # Bootstrap BD en EC2
    └── README.md                     # Lista de secrets y configuración
```

---

## 1. Correr el stack localmente (Docker Compose)

**Requisitos:** Docker Desktop instalado.

```bash
# Clonar el repo
git clone https://github.com/<usuario>/proyecto_semestral.git
cd proyecto_semestral

# Configurar variables de entorno
cp .env .env.local
# Editar DB_PASSWORD en .env si es necesario

# Levantar todos los servicios
docker compose up --build
```

Una vez levantado (~2 min primera vez):

| Servicio | URL |
|---------|-----|
| Frontend | http://localhost:3000 |
| Ventas API | http://localhost:8080/api/v1/ventas |
| Ventas Swagger | http://localhost:8080/swagger-ui.html |
| Ventas Health | http://localhost:8080/actuator/health |
| Despachos API | http://localhost:8081/api/v1/despachos |
| Despachos Swagger | http://localhost:8081/swagger-ui.html |
| MySQL | localhost:3306 |

```bash
# Detener
docker compose down

# Detener y borrar datos
docker compose down -v
```

---

## 2. Desplegar en AWS EKS

### Paso 1 — Credenciales AWS en GitHub Secrets

Copiar los 3 valores **del mismo momento** desde AWS Academy → AWS Details:

| Secret | Valor |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | AccessKeyId |
| `AWS_SECRET_ACCESS_KEY` | SecretAccessKey |
| `AWS_SESSION_TOKEN` | SessionToken |
| `DB_PASSWORD` | Password para MySQL (elegir uno) |

> ⚠️ Las credenciales de Academy expiran en ~4h. Si el pipeline falla con "token invalid", actualizar los 3 juntos.

### Paso 2 — Infraestructura Terraform (solo al crear/recrear el cluster)

```bash
# Recrear solo ECR (rápido, si el Lab se reinició)
cd infra
terraform apply -target=aws_ecr_repository.this

# Crear/recrear el cluster EKS completo (~15 min)
cd eks
terraform init
terraform apply
```

### Paso 3 — Disparar el pipeline

```bash
git push origin deploy
```

GitHub Actions ejecuta `cd-eks.yml` automáticamente:
1. Build de 3 imágenes Docker (linux/amd64)
2. Push a Amazon ECR
3. Conecta kubectl al cluster EKS
4. Instala metrics-server (requerido por HPA)
5. Crea/refresca `mysql-secret` y `ecr-secret`
6. Aplica los 5 manifiestos Kubernetes
7. Espera rollouts (~5 min)
8. Imprime URL pública del ELB

### Paso 4 — Verificar

```bash
# Configurar kubectl local (requerido para comandos manuales)
aws eks update-kubeconfig --name innovatech-eks --region us-east-1

# Ver estado del cluster
kubectl get nodes
kubectl get pods -o wide
kubectl get services
kubectl get hpa

# Ver logs de la aplicación
kubectl logs deployment/backend-ventas --tail=50
kubectl logs deployment/backend-despachos --tail=50

# URL del frontend
kubectl get service frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

> ⚠️ **Error "The connection to the server localhost:8080 was refused"**: kubectl no tiene configurado el cluster. Ejecutar `aws eks update-kubeconfig` del paso anterior. El pipeline lo hace automáticamente, pero en local hay que hacerlo a mano.

---

## 3. Contenedores — Dockerfiles

### Patrón común (multi-stage, non-root)

**Backends (Java 17 + Spring Boot):**
```dockerfile
# Stage 1: builder — Maven + JDK completo (~600 MB)
FROM maven:3.9-eclipse-temurin-17-alpine AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn package -DskipTests

# Stage 2: runtime — solo JRE alpine (~150 MB)
FROM eclipse-temurin:17-jre-alpine
RUN addgroup -S app && adduser -S app -G app   # usuario no-root
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
USER app
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**Frontend (Node + nginx-unprivileged):**
```dockerfile
# Stage 1: build React
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json .
RUN npm ci
COPY . .
ARG VITE_API_URL=""
RUN npm run build

# Stage 2: nginx no-root
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/templates/default.conf.template
EXPOSE 8080
```

### Buenas prácticas aplicadas

- **Multi-stage build**: imagen final sin herramientas de compilación (~150 MB vs ~600 MB)
- **Usuario no-root**: backends como `app` (UID 1000), frontend como `nginx` (UID 101)
- **Imágenes base alpine/slim**: menor superficie de ataque, menor tamaño
- **`.dockerignore`**: excluye `target/`, `node_modules/`, `.git/` del contexto de build
- **Healthchecks**: Spring Actuator (`/actuator/health`) verifica que la app esté UP, no solo el proceso

---

## 4. Registro de imágenes — Amazon ECR

Tres repositorios ECR con las mismas imágenes para ECS y EKS:

| Repositorio | Tag | Descripción |
|------------|-----|-------------|
| `innovatech-ventas` | `latest` | Backend Ventas Spring Boot |
| `innovatech-despachos` | `latest` | Backend Despachos Spring Boot |
| `innovatech-frontend` | `latest` | Frontend React + Nginx |

El pipeline reemplaza el tag `latest` con la URL real de ECR antes del `kubectl apply`:
```bash
sed -i "s|image: innovatech-ventas:latest|image: <account>.dkr.ecr.us-east-1.amazonaws.com/innovatech-ventas:latest|g" infra/k8s/backend-ventas.yml
```

ECR tiene scan de vulnerabilidades automático activado en cada push.

---

## 5. Pipeline CI/CD — GitHub Actions

### Archivo: `.github/workflows/cd-eks.yml`

**Trigger:** push a rama `deploy` o ejecución manual (`workflow_dispatch`)

**Etapas del pipeline:**

```
Push a 'deploy'
      │
      ▼
[1] Checkout + configurar credenciales AWS
      │
      ▼
[2] Login a Amazon ECR
      │
      ▼
[3] Build & Push 3 imágenes Docker → ECR  (~4-6 min)
      │
      ▼
[4] Instalar kubectl + conectar al cluster EKS
      │
      ▼
[5] Instalar metrics-server (HPA lo requiere)
      │
      ▼
[6] Crear/refrescar mysql-secret + ecr-secret
      │
      ▼
[7] kubectl apply — 5 manifiestos Kubernetes
      │
      ▼
[8] Forzar rollout restart × 4 deployments
      │
      ▼
[9] Esperar rollouts (timeout 300s)
      │
      ▼
[10] Imprimir URL pública del frontend
```

**Gestión de secretos en el pipeline:**
```yaml
- name: Configurar credenciales AWS
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id:     ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-session-token:     ${{ secrets.AWS_SESSION_TOKEN }}

- name: Crear/refrescar Secret de MySQL
  env:
    DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
  run: |
    kubectl create secret generic mysql-secret \
      --from-literal=MYSQL_ROOT_PASSWORD="${DB_PASSWORD}" \
      --dry-run=client -o yaml | kubectl apply -f -
```

Los secrets nunca aparecen en los logs de Actions. GitHub los enmascara automáticamente.

---

## 6. Configuración y Secretos

### GitHub Secrets (4 en total)

| Secret | Uso | Tipo |
|--------|-----|------|
| `AWS_ACCESS_KEY_ID` | Autenticación AWS | Credencial temporal Academy |
| `AWS_SECRET_ACCESS_KEY` | Autenticación AWS | Credencial temporal Academy |
| `AWS_SESSION_TOKEN` | Autenticación AWS | Credencial temporal Academy |
| `DB_PASSWORD` | Contraseña MySQL | Permanente |

### Kubernetes Secrets (2 en cluster)

| Secret | Tipo | Contenido |
|--------|------|-----------|
| `mysql-secret` | `generic` | `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE` |
| `ecr-secret` | `docker-registry` | Token ECR para pull de imágenes |

Los pods los consumen vía `secretKeyRef`:
```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: mysql-secret
        key: MYSQL_ROOT_PASSWORD
```

---

## 7. Observabilidad — Logs y Métricas

### CloudWatch (plano de control EKS)

```
Log group: /aws/eks/innovatech-eks/cluster
Streams activos: 24
Tipos: api, audit, authenticator, controllerManager, scheduler
```

Configurado en Terraform:
```hcl
resource "aws_eks_cluster" "main" {
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}
```

### kubectl logs (aplicaciones)

```bash
# Logs Spring Boot en tiempo real
kubectl logs deployment/backend-ventas --tail=50 -f

# Logs del frontend
kubectl logs deployment/frontend --tail=30
```

### Métricas (HPA + kubectl top)

```bash
kubectl get hpa                   # CPU actual vs umbral
kubectl top nodes                 # CPU/RAM del nodo
kubectl top pods                  # CPU/RAM por pod
```

---

## 8. Seguridad básica

| Práctica | Implementación |
|----------|---------------|
| Imágenes base alpine | `eclipse-temurin:17-jre-alpine`, `nginx-unprivileged:1.27-alpine` |
| Usuario no-root | `adduser -S app` en backends, `nginx` (UID 101) en frontend |
| Puertos mínimos | Solo 8080 (ventas), 8081 (despachos), 8080 (frontend), 3306 (mysql) |
| Security Groups | `sg-cluster`: 443 inbound; `sg-nodes`: tráfico interno VPC solo |
| IAM mínimo privilegio | LabRole sin permisos extra; `aws-actions` sin credenciales hardcodeadas |
| ECR scan | Escaneo de vulnerabilidades automático en cada push |
| Secrets | GitHub Secrets + Kubernetes Secrets, nunca hardcodeados en YAML |

---

## 9. Orquestación y Escalabilidad — ¿Por qué EKS?

| Criterio | EC2 manual | EKS (Kubernetes) |
|----------|-----------|-----------------|
| Despliegue | SSH + comandos manuales | `kubectl apply` declarativo |
| Autoscaling | Manual o scripts custom | HPA automático por CPU/memoria |
| Auto-recuperación | Ninguna | ReplicaSet recrea pods caídos en <30s |
| Rolling updates | Downtime durante deploy | maxSurge/maxUnavailable sin downtime |
| Monitoreo | Logs por SSH | CloudWatch + kubectl logs centralizados |
| Portabilidad | Solo AWS | On-premise, GKE, AKS sin cambiar manifiestos |

**HPA configurado:**
```yaml
minReplicas: 2
maxReplicas: 5
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
```

Demo de autoscaling: con 500 requests paralelos, CPU llegó al 94% y el HPA escaló de 2 → 4 réplicas automáticamente en ~30 segundos.

---

## Ramas del repositorio

| Rama | Propósito |
|------|-----------|
| `main` | Desarrollo, no dispara deploy |
| `deploy` | Producción — cualquier push dispara `cd-eks.yml` |

---

## Integrantes

- Luciano Castelli
- Alejandro Venegas

**Sección:** 302D | **Asignatura:** ISY1101 — Introducción a Herramientas DevOps
