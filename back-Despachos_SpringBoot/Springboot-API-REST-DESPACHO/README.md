# Microservicio Despachos

REST API para gestionar **ordenes de despacho** del proyecto Innovatech.

Stack: **Java 17 + Spring Boot 3.4 + JPA + Hibernate + MySQL Connector + Lombok**.

## Endpoints

Base path: `/api/v1/despachos`

| Método | Ruta                | Descripción              |
|--------|---------------------|--------------------------|
| GET    | `/`                 | Lista todos los despachos |
| GET    | `/{idDespacho}`     | Detalle por ID           |
| POST   | `/`                 | Crear despacho           |
| PUT    | `/{idDespacho}`     | Actualizar despacho      |
| DELETE | `/{idDespacho}`     | Eliminar despacho        |

Adicionales:

| Ruta                  | Descripción                         |
|-----------------------|-------------------------------------|
| `/actuator/health`    | Healthcheck (usado por Docker)      |
| `/swagger-ui.html`    | Documentación OpenAPI interactiva   |
| `/v3/api-docs`        | OpenAPI JSON                        |

## Variables de entorno

| Variable        | Default      | Descripción                          |
|-----------------|--------------|--------------------------------------|
| `SERVER_PORT`   | `8081`       | Puerto de escucha                    |
| `DB_ENDPOINT`   | `localhost`  | Host de MySQL                        |
| `DB_PORT`       | `3306`       | Puerto de MySQL                      |
| `DB_NAME`       | `innovatech` | Nombre de la base de datos          |
| `DB_USERNAME`   | `root`       | Usuario MySQL                        |
| `DB_PASSWORD`   | `root`       | Password MySQL                       |
| `JAVA_OPTS`     | -            | Flags JVM                            |

## Build y ejecución

### Local con Maven

```bash
./mvnw clean package -DskipTests
java -jar target/Springboot-API-REST-DESPACHO-0.0.1-SNAPSHOT.jar
```

### Docker (multi-stage)

```bash
docker build -t innovatech-despachos .
docker run --rm -p 8081:8081 \
  -e DB_ENDPOINT=host.docker.internal \
  -e DB_NAME=innovatech \
  -e DB_PASSWORD=secret \
  innovatech-despachos
```

### En el stack completo

Desde la raíz del monorepo:

```bash
docker compose up despachos
```

## Modelo `Despacho`

```java
Long      idDespacho        // PK auto
LocalDate fechaDespacho     // ISO date
String    patenteCamion
int       intento           // intentos de entrega
Long      idCompra          // referencia a Venta
String    direccionCompra
Long      valorCompra
boolean   despachado        // default false
```

## CORS

`CorsConfig.java` permite todos los orígenes (`*`) en GET/POST/PUT/DELETE/OPTIONS.
Esto es necesario porque el frontend hace llamadas desde un dominio distinto
durante el desarrollo. En producción el frontend usa rutas relativas y nginx hace
reverse proxy, por lo que la política CORS no se activa.
