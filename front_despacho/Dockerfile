# =========================================================
# Frontend Despacho - React 18 + Vite 5
# Multi-stage build: builder (Node) -> runtime (Nginx no-root)
# =========================================================

# -------- Stage 1: Builder --------
FROM node:20-alpine AS builder

WORKDIR /build

# Cache de dependencias: copia solo manifests primero
COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund

# Copia el resto del codigo y construye
COPY . .

# La URL del API se inyecta en build-time como variable VITE_*
ARG VITE_API_URL=""
ENV VITE_API_URL=$VITE_API_URL

RUN npm run build

# -------- Stage 2: Runtime --------
# nginx-unprivileged corre como usuario no root (UID 101) en el puerto 8080
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime

LABEL org.opencontainers.image.title="despacho-frontend" \
      org.opencontainers.image.description="SPA React + Nginx - Innovatech" \
      org.opencontainers.image.source="https://github.com/luciano/ep2-devops"

# Copia el template de Nginx (envsubst lo procesa al iniciar el contenedor)
# Las variables ${VENTAS_HOST} y ${DESPACHOS_HOST} se inyectan en docker run.
COPY --chown=nginx:nginx nginx.conf /etc/nginx/templates/default.conf.template

# Copia el build estatico desde el stage builder
COPY --from=builder --chown=nginx:nginx /build/dist /usr/share/nginx/html

# nginx-unprivileged expone el 8080 por defecto (no necesita CAP_NET_BIND para puertos <1024)
EXPOSE 8080

# Healthcheck simple via curl al puerto 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -q -O- http://localhost:8080/healthz > /dev/null || exit 1

# Usuario ya viene como "nginx" (101) en la imagen base; no hace falta USER explicito
