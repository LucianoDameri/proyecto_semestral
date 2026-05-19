# =========================================================
# Backend Ventas - Spring Boot 3.4 + Java 17
# Multi-stage build: builder (Maven) -> runtime (JRE slim)
# =========================================================

# -------- Stage 1: Builder --------
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# Cache de dependencias (capa separada para acelerar rebuilds)
COPY pom.xml .
RUN mvn -B -q dependency:go-offline

# Copia el codigo y compila
COPY src ./src
RUN mvn -B -q clean package -DskipTests \
    && cp target/*.jar app.jar

# -------- Stage 2: Runtime --------
FROM eclipse-temurin:17-jre-alpine AS runtime

# Metadatos (buena practica)
LABEL org.opencontainers.image.title="ventas-api" \
      org.opencontainers.image.description="Microservicio Ventas - Innovatech" \
      org.opencontainers.image.source="https://github.com/luciano/ep2-devops"

# Utilidades minimas para healthcheck y un usuario no root
RUN apk add --no-cache curl tini \
    && addgroup -S app && adduser -S -G app -u 1000 app

WORKDIR /app

# Copia el jar desde el stage builder con ownership del usuario no root
COPY --from=builder --chown=app:app /build/app.jar app.jar

# Variables de entorno por defecto (override en compose / EC2)
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0" \
    SERVER_PORT=8080

EXPOSE 8080

# Healthcheck via Spring Boot Actuator
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:8080/actuator/health | grep -q '"status":"UP"' || exit 1

# Drop a usuario no root
USER app

# tini = init mas pequeno, maneja senales correctamente (SIGTERM, etc.)
ENTRYPOINT ["/sbin/tini","--"]
CMD ["sh","-c","java $JAVA_OPTS -jar app.jar"]
