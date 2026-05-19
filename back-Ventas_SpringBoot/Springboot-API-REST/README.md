# Microservicio Ventas

REST API para gestionar **ordenes de compra** del proyecto Innovatech.

Stack: **Java 17 + Spring Boot 3.4 + JPA + Hibernate + MySQL Connector + Lombok**.

## Endpoints

Base path: `/api/v1/ventas`

| Metodo | Ruta                  | Descripcion             |
|--------|-----------------------|-------------------------|
| GET    | `/`                   | Lista todas las ventas  |
| GET    | `/{idVenta}`          | Detalle por ID          |
| POST   | `/`                   | Crear venta             |
| PUT    | `/{idVenta}`          | Actualizar venta        |
| DELETE | `/{idVenta}`          | Eliminar venta          |

Adicionales:

| Ruta                          | Descripcion                          |
|-------------------------------|--------------------------------------|
| `/actuator/health`            | Healthcheck (usado por Docker)       |
| `/swagger-ui.html`            | Documentacion OpenAPI interactiva    |
| `/v3/api-docs`                | OpenAPI JSON                         |

## Variables de entorno

| Variable        | Default        | Descripcion                          |
|-----------------|----------------|--------------------------------------|
| `SERVER_PORT`   | `8080`         | Puerto de escucha                    |
| `DB_ENDPOINT`   | `localhost`    | Host MySQL                           |
| `DB_PORT`       | `3306`         | Puerto MySQL                         |
| `DB_NAME`       | `innovatech`   | Nombre de la base de datos           |
| `DB_USERNAME`   | `root`         | Usuario MySQL                        |
| `DB_PASSWORD`   | `root`         | Password MySQL                       |
| `JAVA_OPTS`     | -              | Flags JVM (ej. `-XX:MaxRAMPercentage=75`)|

## Build y ejecucion

### Local con Maven

```bash
./mvnw clean package -DskipTests
java -jar target/Springboot-API-REST-0.0.1-SNAPSHOT.jar
```

### Docker (multi-stage)

```bash
docker build -t innovatech-ventas .
docker run --rm -p 8080:8080 \
  -e DB_ENDPOINT=host.docker.internal \
  -e DB_NAME=innovatech \
  -e DB_PASSWORD=secret \
  innovatech-ventas
```

### En el stack completo

Desde la raiz del monorepo:

```bash
docker compose up ventas
```

## Modelo `Venta`

```java
Long    idVenta              // PK auto
String  direccionCompra      // @NotBlank
int     valorCompra
LocalDate fechaCompra        // @NotNull, ISO date
Boolean despachoGenerado     // @NotNull, default false
```
