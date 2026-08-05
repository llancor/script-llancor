# GuardiaPro

Monorepo para gestión integral de seguridad física.

## Inicio rápido

1. Crea la base con `backend/database/schema.sql` y carga `backend/database/seed.sql` (o usa Prisma).
2. Copia `backend/.env.example` a `backend/.env` y configura MySQL.
3. Ejecuta `npm install` en la raíz.
4. Ejecuta `npm run db:push` y `npm run db:seed`.
5. Inicia todo con `npm run dev`.

La web queda en `http://localhost:5173` y la API en `http://localhost:4000/api`.

Usuario inicial del seed: `admin@seguridpro.cl` / `SeguridPro2026!`.

## Despliegue en Debian con Docker

Instala Docker Engine y el complemento Compose. Luego:

```bash
cp .env.docker.example .env
# Edita .env y reemplaza todas las claves de ejemplo.
docker compose up -d --build
docker compose ps
```

La aplicación queda publicada en el puerto indicado por `HTTP_PORT` (8080 por defecto). MySQL no se expone a Internet y sus datos persisten en el volumen `mysql_data`. Para actualizar: `git pull && docker compose up -d --build`.

Para producción con dominio, sitúa un proxy TLS (Caddy, Traefik o Nginx) delante del puerto HTTP y define `APP_URL=https://tu-dominio`.

### Menú de administración para Debian

```bash
chmod +x Instalar_GuardiaPro_llancor_v3.0.sh
./Instalar_GuardiaPro_llancor_v3.0.sh
```

Permite instalar Docker, desplegar y actualizar GuardiaPro, consultar/iniciar/detener/reiniciar servicios, cambiar el puerto, mostrar la URL, restablecer contraseñas y desinstalar conservando o eliminando la base de datos. La opción **Actualizar GuardiaPro** descarga los cambios de GitHub y reconstruye los servicios sin eliminar el volumen MySQL.

El archivo también funciona de manera autónoma: si se copia solo `Instalar_GuardiaPro_llancor_v3.0.sh` a un Debian, la opción **Instalar Control de Seguridad** clona automáticamente `https://github.com/llancor/script-llancor.git` en `/opt/guardiapro` y utiliza la carpeta `GuardiaPro-beta`. La ubicación puede cambiarse definiendo `GUARDIAPRO_INSTALL_DIR` antes de ejecutar el script.

Cuando el repositorio ya existe, el instalador ejecuta `git pull --ff-only` antes de construir para utilizar siempre el código y los Dockerfiles más recientes.

La desinstalación completa elimina los contenedores, imágenes locales, volumen MySQL y `/opt/guardiapro` después de exigir la confirmación literal `ELIMINAR TODO`. Docker Engine se conserva para no afectar otros proyectos.

### Instalador para Windows

Abre PowerShell y ejecuta:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Instalar_SeguridPro_HHRR_v3.0.ps1
```

El menú puede instalar Git, WSL 2 y Docker Desktop mediante Winget, descargar el repositorio, desplegar GuardiaPro y administrar servicios, puertos y usuarios.

## Estructura

```text
backend/   Express, Prisma, MySQL, JWT y REST API
frontend/  React, Vite, Tailwind, Leaflet y UI responsive
```
