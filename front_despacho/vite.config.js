import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";

// =========================================================
// Configuracion Vite
// =========================================================
// En desarrollo (npm run dev) el dev server escucha en 5173 y
// reenvia las llamadas a /api/v1/* hacia los microservicios
// que deben estar corriendo localmente (docker compose up).
//
// En produccion el bundle se sirve desde Nginx (Dockerfile),
// que tiene su propio reverse proxy en nginx.conf.
// =========================================================

export default defineConfig({
  plugins: [react()],
  server: {
    host: true, // permite acceso desde la red (util para probar en otros dispositivos)
    port: 5173,
    proxy: {
      "/api/v1/ventas": {
        target: process.env.VITE_DEV_VENTAS_URL || "http://localhost:8080",
        changeOrigin: true,
      },
      "/api/v1/despachos": {
        target: process.env.VITE_DEV_DESPACHOS_URL || "http://localhost:8081",
        changeOrigin: true,
      },
    },
  },
});
