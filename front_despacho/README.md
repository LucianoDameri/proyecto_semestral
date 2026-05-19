# Frontend Despacho (SPA)

SPA React 18 + Vite 5 + Tailwind 3 para la gestión de **Ventas** y **Despachos**
del proyecto Innovatech.

## Stack

| Capa            | Tecnología                      |
|-----------------|----------------------------------|
| Framework UI    | React 18                         |
| Bundler / dev   | Vite 5                           |
| Estilos         | Tailwind 3                       |
| HTTP            | axios                            |
| Forms           | react-hook-form                  |
| Routing         | react-router-dom                 |
| Alerts          | sweetalert2                      |
| Runtime prod    | Nginx (nginx-unprivileged 1.27)  |

## Estructura clave

```
front_despacho/
+- Dockerfile             # multi-stage: Node 20 -> Nginx no-root
+- nginx.conf             # template, envsubst inyecta ${VENTAS_HOST}/${DESPACHOS_HOST}
+- vite.config.js         # proxy dev a localhost:8080 / 8081
+- src/
   +- api/config.js       # URLs y headers centralizados
   +- componentes/CrudAdmin/
      +- TableCompras.jsx
      +- TableDespachos.jsx
      +- FormDespacho.jsx
      +- FormCierreDespacho.jsx
```

## Variables de entorno

### Build-time (Vite, leídas por `import.meta.env`)

| Variable        | Default | Uso                                               |
|-----------------|---------|---------------------------------------------------|
| `VITE_API_URL`  | `""`   | Base URL del API. Vacio = relativo, Nginx hace proxy. |

### Runtime (resueltas por `envsubst` al iniciar Nginx)

| Variable          | Ejemplo            | Uso                                          |
|-------------------|--------------------|----------------------------------------------|
| `VENTAS_HOST`     | `ventas:8080`      | Host:puerto del backend Ventas               |
| `DESPACHOS_HOST`  | `despachos:8081`   | Host:puerto del backend Despachos            |

En Docker Compose se usan los nombres DNS de la red. En EC2, se usa la IP
privada del backend (ej. `10.0.2.5:8080`).

## Desarrollo local

```bash
npm install
npm run dev
```

La app de Vite se abre en `http://localhost:5173`.
El proxy de Vite redirige `/api/v1/ventas` → `localhost:8080` y
`/api/v1/despachos` → `localhost:8081`.

## Build y ejecución con Docker

```bash
docker build --build-arg VITE_API_URL="" -t innovatech-frontend .
docker run --rm \
  -e VENTAS_HOST="host.docker.internal:8080" \
  -e DESPACHOS_HOST="host.docker.internal:8081" \
  -p 3000:8080 \
  innovatech-frontend
```

## Detalles técnicos

- **Multi-stage**: `node:20-alpine` (build) → `nginxinc/nginx-unprivileged:1.27-alpine` (runtime).
- **Usuario no root**: la imagen base corre como `nginx` (UID 101) y escucha en 8080
  sin `CAP_NET_BIND_SERVICE`.
- **Cache de assets**: archivos hashed por Vite → `Cache-Control: public, immutable; max-age=30d`.
- **SPA fallback**: rutas no-API caen a `index.html` (`try_files`).
- **Reverse proxy**: `/api/v1/ventas` y `/api/v1/despachos` se redirigen a los microservicios.
- **Healthcheck**: `wget /healthz` retorna 200.
