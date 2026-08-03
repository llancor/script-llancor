# GuardiaPro

Monorepo para gestión integral de seguridad física.

## Inicio rápido

1. Crea la base con `backend/database/schema.sql` y carga `backend/database/seed.sql` (o usa Prisma).
2. Copia `backend/.env.example` a `backend/.env` y configura MySQL.
3. Ejecuta `npm install` en la raíz.
4. Ejecuta `npm run db:push` y `npm run db:seed`.
5. Inicia todo con `npm run dev`.

La web queda en `http://localhost:5173` y la API en `http://localhost:4000/api`.

Usuario inicial del seed: `admin@guardiapro.cl` / `GuardiaPro2026!`.

## Despliegue en Debian con Docker

Instala Docker Engine y el complemento Compose. Luego:

```bash
cp .env.docker.example .env
# Edita .env y reemplaza todas las claves de ejemplo.
docker compose up -d --build
docker compose ps
```

La aplicación queda publicada en el puerto indicado por `HTTP_PORT` (80 por defecto). MySQL no se expone a Internet y sus datos persisten en el volumen `mysql_data`. Para actualizar: `git pull && docker compose up -d --build`.

Para producción con dominio, sitúa un proxy TLS (Caddy, Traefik o Nginx) delante del puerto HTTP y define `APP_URL=https://tu-dominio`.

## Estructura

```text
backend/   Express, Prisma, MySQL, JWT y REST API
frontend/  React, Vite, Tailwind, Leaflet y UI responsive
```
