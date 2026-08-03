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

### Menú de administración para Debian

```bash
chmod +x Instalar_GuardiaPro_llancor_v3.0.sh
./Instalar_GuardiaPro_llancor_v3.0.sh
```

Permite instalar Docker, desplegar GuardiaPro, consultar/iniciar/detener/reiniciar servicios, cambiar el puerto, mostrar la URL, restablecer contraseñas y desinstalar conservando o eliminando la base de datos.

El archivo también funciona de manera autónoma: si se copia solo `Instalar_GuardiaPro_llancor_v3.0.sh` a un Debian, la opción **Instalar Control de Seguridad** clona automáticamente `https://github.com/llancor/script-llancor.git` en `~/guardiapro` y utiliza la carpeta `Control_Entrada_Guardia`. La ubicación puede cambiarse ejecutando `GUARDIAPRO_INSTALL_DIR=/opt/guardiapro ./Instalar_GuardiaPro_llancor_v3.0.sh`.

Cuando el repositorio ya existe, el instalador ejecuta `git pull --ff-only` antes de construir para utilizar siempre el código y los Dockerfiles más recientes.

## Estructura

```text
backend/   Express, Prisma, MySQL, JWT y REST API
frontend/  React, Vite, Tailwind, Leaflet y UI responsive
```
