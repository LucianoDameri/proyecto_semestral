# Innovatech Chile - Plataforma de Despachos

> **ISY1101 - Introducción a Herramientas DevOps - Evaluación Parcial N°2**
> Contenedorización, despliegue automatizado en AWS EC2 y CI/CD con GitHub Actions.

Este repositorio presenta una solución basada en **microservicios** para la
gestión de **ordenes de compra (Ventas)** y **ordenes de despacho (Despachos)**,
con un frontend SPA en React y persistencia en MySQL.

---

## Arquitectura

```
                          INTERNET
                             |
                             v
         +----------------- IGW ----------------+
         |                                      |
         |    Subred Pública  10.0.1.0/24       |
         |    +-----------------------------+   |
         |    | EC2 Frontend  (IP pública)  |   |
         |    |   docker run nginx + React  |   |
         |    |   puerto host 80            |   |
         |    +--------------+--------------+   |
         |                   | red privada      |
         |                   v                  |
         |    Subred Privada 10.0.2.0/24        |
         |    +-----------------------------+   |
         |    | EC2 Backend                 |   |
         |    |   docker run ventas    :8080|   |
         |    |   docker run despachos :8081|   |
         |    +--------------+--------------+   |
         |                   | red privada      |
         |                   v                  |
         |    Subred Privada 10.0.3.0/24        |
         |    +-----------------------------+   |
         |    | EC2 Database                |   |
         |    |   docker run mysql:8 :3306  |   |
         |    |   volumen: innovatech_mysql_data |
         |    +-----------------------------+   |
         |                                      |
         +--------------------------------------+
                       VPC 10.0.0.0/16
```

![Diagrama de Arquitectura](https://file.garden/ZAdhH1kUN2HXHCpM/img42.jpg)

**Flujo de tráfico HTTP:**

```
Usuario -> http://<EC2-Frontend-IP>/
       -> Nginx (SPA + reverse proxy)
            +-- /             -> archivos estáticos React
            +-- /api/v1/ventas -> http://<EC2-Backend-IP>:8080
            +-- /api/v1/despachos -> http://<EC2-Backend-IP>:8081
                                       ambos -> mysql en <EC2-DB-IP>:3306
```

Solo el frontend es accesible desde internet. Backend y base de datos viven en
subredes privadas; solo acceden a internet para `docker pull` desde ECR mediante
NAT Gateway.

---

## Stack tecnológico

| Capa               | Tecnología                                               |
|--------------------|----------------------------------------------------------|
| Frontend           | React 18 + Vite 5 + Tailwind 3 + axios + react-hook-form |
| Web server         | Nginx (nginx-unprivileged 1.27 alpine, non-root)         |
| Backend Ventas     | Java 17 + Spring Boot 3.4 + JPA + Hibernate              |
| Backend Despachos  | Java 17 + Spring Boot 3.4 + JPA + Hibernate              |
| Base de datos      | MySQL 8.0                                                |
| Contenedorización  | Docker (multi-stage, non-root, healthchecks)             |
| Orquestación local | Docker Compose                                           |
| Infraestructura    | Terraform 1.5+ sobre AWS                                 |
| Registry           | Amazon ECR (3 repos con scan + lifecycle)                |
| CI/CD              | GitHub Actions                                           |
| Deploy en EC2      | AWS Systems Manager (SSM) `send-command`                 |

---

## Estructura del repositorio

```
proyecto semestral/
|-- docker-compose.yml                # stack local completo
|-- .env.example                      # plantilla de variables de entorno
|-- .gitignore
|-- README.md                         # este archivo
|
|-- back-Ventas_SpringBoot/Springboot-API-REST/
|   |-- Dockerfile                    # multi-stage, JRE alpine, non-root, healthcheck
|   |-- .dockerignore
|   |-- pom.xml                       # Spring Boot 3.4 + Actuator
|   `-- src/                          # código Java + application.properties
|
|-- back-Despachos_SpringBoot/Springboot-API-REST-DESPACHO/
|   |-- Dockerfile                    # mismo patrón, puerto 8081
|   |-- .dockerignore
|   |-- pom.xml
|   `-- src/
|
|-- front_despacho/
|   |-- Dockerfile                    # multi-stage Node + Nginx no-root
|   |-- .dockerignore
|   |-- nginx.conf                    # template con ${VENTAS_HOST}/${DESPACHOS_HOST}
|   |-- vite.config.js                # proxy en dev
|   |-- package.json
|   `-- src/                          # componentes React + src/api/config.js
|
|-- infra/                            # Terraform AWS
|   |-- main.tf  vpc.tf  security.tf  ecr.tf  ec2.tf
|   |-- variables.tf  outputs.tf
|   |-- terraform.tfvars.example
|   `-- README.md                     # cómo aplicar la infra
|
`-- .github/workflows/                # 3 pipelines CI/CD
    |-- cicd-ventas.yml
    |-- cicd-despachos.yml
    |-- cicd-frontend.yml
    `-- README.md                     # lista de secrets + cómo configurar
```

---

## Correr el stack localmente

Requisitos: **Docker Desktop**.

```bash
cd "proyecto semestral"
cp .env.example .env
# Edita .env y cambia DB_PASSWORD
docker compose up --build
```

Una vez levantado (~2 minutos en la primera build):

| Servicio              | URL                                       |
|-----------------------|-------------------------------------------|
| Frontend              | http://localhost:3000                     |
| Ventas API            | http://localhost:8080/api/v1/ventas       |
| Ventas Swagger        | http://localhost:8080/swagger-ui.html     |
| Ventas Health         | http://localhost:8080/actuator/health     |
| Despachos API         | http://localhost:8081/api/v1/despachos    |
| Despachos Swagger     | http://localhost:8081/swagger-ui.html     |
| Despachos Health      | http://localhost:8081/actuator/health     |
| MySQL                 | localhost:3306 (root / $DB_PASSWORD)      |

Para detener: `docker compose down`. Para borrar el volumen: `docker compose down -v`.

---

## Desplegar en AWS

### 1. Infraestructura (Terraform)

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# edita db_password
terraform init
terraform apply
```

Outputs útiles:

```bash
terraform output github_secrets_summary
```

Detalles en [`infra/README.md`](infra/README.md).

### 2. GitHub Secrets

Crear los secrets listados en [`.github/workflows/README.md`](.github/workflows/README.md):
credenciales AWS, IDs de EC2, URLs de ECR y password de la base de datos.

### 3. Pipeline CI/CD

Hacer push a la rama `deploy`:

```bash
git checkout -b deploy
git push origin deploy
```

GitHub Actions construye, publica y despliega automáticamente.
Cualquier cambio futuro en `back-Ventas_SpringBoot/`, `back-Despachos_SpringBoot/`
o `front_despacho/` dispara su pipeline correspondiente.

### 4. Validación

- Frontend en `http://<EC2_FRONTEND_PUBLIC_IP>/`
- Crear/listar ventas y despachos desde la UI
- Verificar persistencia: `docker compose restart` o reiniciar la EC2 de DB,
  los datos siguen ahí (named volume).

---

## Decisiones tecnicas y justificaciones

### Dockerfiles

- **Multi-stage build**: el stage `builder` tiene Maven/Node con todas las
  dependencias de compilacion (~600 MB); el `runtime` solo trae el binario
  y un JRE alpine (~150 MB). Menor superficie de ataque, menor costo de
  storage en ECR, transferencias mas rapidas.
- **Usuario no root**: backends corren como `app` (UID 1000), frontend como
  `nginx` (UID 101 en `nginx-unprivileged`). Si un atacante consigue RCE
  dentro del contenedor, no tiene privilegios para escapar al host.
- **Tini como init (`/sbin/tini --`)**: maneja SIGTERM y zombies
  correctamente. Sin tini, Spring Boot puede quedar en estado raro al hacer
  `docker stop`.
- **HEALTHCHECK con Spring Actuator**: Docker sabe si la app esta UP, no
  solo si el proceso vive. Compose espera el `service_healthy` antes de
  iniciar dependientes.
- **IMDSv2 obligatorio** (Terraform): bloquea SSRF abusando del metadata
  endpoint de EC2.

### Persistencia (IE3 = 10%)

Se usa **named volume** (`innovatech_mysql_data`) en lugar de bind mount:

| Criterio       | Named volume          | Bind mount             |
|----------------|-----------------------|------------------------|
| Portabilidad   | Independiente del SO  | Dependiente del path   |
| Rendimiento I/O| FS nativo Docker      | FS del host (mas lento)|
| Backups        | `docker volume`       | `cp`/`tar` manual      |
| Permisos       | Gestiona Docker       | Hay que sincronizar UID|
| EC2/cloud      | Funciona out-of-box   | Hay que crear el path  |

Los datos sobreviven `docker compose down/up` y reinicios de la EC2 (el
volumen vive en `/var/lib/docker/volumes/` del host EC2).

### Pipeline CI/CD

- **3 workflows independientes** (uno por capa): cambios al frontend NO
  rebuildean los backends. Builds mas rapidos y deploys atomicos.
- **Trigger en `deploy`**: separa main (desarrollo) de produccion. Push a
  main no afecta el entorno desplegado.
- **Tags `${SHA::7}` + `latest`**: trazabilidad commit -> imagen, rollback
  rapido a una version anterior.
- **SSM `send-command` en lugar de SSH**: no hay claves `.pem` que rotar,
  no hay puerto 22 abierto a internet en las EC2 privadas, IAM gestiona
  todo. AWS Academy ya da el `LabInstanceProfile` con permisos SSM.
- **ECR sobre Docker Hub**: integracion IAM nativa, scan de
  vulnerabilidades incluido, sin rate limit anonimo, latencia baja desde
  EC2.

### Redes y seguridad

- 3 Security Groups encadenados (frontend -> backend -> db): cada capa solo
  acepta trafico de la capa superior. Principio de **least privilege**.
- Backend y DB en subredes privadas: ningun acceso directo desde internet.
- NAT Gateway para que las privadas alcancen ECR/SSM sin perder
  aislamiento de entrada.

---


## Autor

Luciano - ISY1101 EP2 - 2025
