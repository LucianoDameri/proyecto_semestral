// =========================================================
// Configuracion centralizada de la API
// =========================================================
// Toda llamada axios usa este modulo en vez de IPs hardcodeadas.
//
// En produccion (build con Docker) las URLs son relativas, asi
// el navegador llama al mismo host del frontend (la EC2 publica)
// y Nginx hace el reverse proxy a los microservicios.
//
// En desarrollo (npm run dev) se puede setear VITE_API_URL en .env
// para apuntar a otro host, ej:
//   VITE_API_URL=http://localhost:8080
// =========================================================

const RAW_BASE = import.meta.env.VITE_API_URL ?? "";
// Normaliza: sin "/" al final
const API_BASE = RAW_BASE.replace(/\/+$/, "");

// Endpoints expuestos por los microservicios (a traves del proxy Nginx)
export const VENTAS_URL    = `${API_BASE}/api/v1/ventas`;
export const DESPACHOS_URL = `${API_BASE}/api/v1/despachos`;

// Helper para hacer rutas: buildUrl(VENTAS_URL, 5) -> "/api/v1/ventas/5"
export const buildUrl = (base, ...segments) =>
  [base, ...segments].filter((s) => s !== undefined && s !== null).join("/");

// Headers JSON estandar para axios
export const JSON_HEADERS = {
  "Content-Type": "application/json",
  Accept: "application/json",
};
