# BastControl

Monorepo para gestión integral de seguridad física.

## Inicio rápido

1. Crea la base con `backend/database/schema.sql` y carga `backend/database/seed.sql` (o usa Prisma).
2. Copia `backend/.env.example` a `backend/.env` y configura MySQL.
3. Ejecuta `npm install` en la raíz.
4. Ejecuta `npm run db:push` y `npm run db:seed`.
5. Inicia todo con `npm run dev`.

La web queda en `http://localhost:5173` y la API en `http://localhost:4000/api`.

Usuario inicial del seed: `admin@bastcontrol.com` / `BastControl2026!`.

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
chmod +x Instalar_BastControl_HHRR_v4.1.sh
./Instalar_BastControl_HHRR_v4.1.sh
```

Permite instalar Docker, desplegar y actualizar BastControl, consultar/iniciar/detener/reiniciar servicios, cambiar el puerto, mostrar la URL, restablecer contraseñas y desinstalar conservando o eliminando la base de datos. La opción **Actualizar BastControl** descarga los cambios de GitHub y reconstruye los servicios sin eliminar el volumen MySQL.

### Instalación desde la carpeta local

Para instalar el proyecto sin descargar su código desde GitHub, copia **la carpeta completa** al servidor (no solamente el script) y ejecuta:

```bash
chmod +x Instalar_BastControl_HHRR-offline_v4.1.sh
./Instalar_BastControl_HHRR-offline_v4.1.sh
```

Selecciona la opción **3) Instalar offline desde esta carpeta**. El script copia el proyecto local a `/opt/bast-control`, genera secretos, conserva un `.env` existente y construye los contenedores en el puerto `8082` por defecto.

Esta modalidad evita descargar el código fuente, pero para una instalación completamente desconectada el servidor debe tener previamente Docker Engine, Docker Compose, `rsync` y `openssl`, además de las imágenes `mysql:8.4`, `node:22-alpine` y `nginx:1.27-alpine` y las dependencias de pnpm disponibles en la caché de construcción. La opción **1) Instalar dependencias** y una primera construcción sin caché requieren Internet.

El archivo también funciona de manera autónoma: si se copia solo `Instalar_BastControl_HHRR_v4.1.sh` a un Debian, la opción **Instalar o migrar a BastControl** clona automáticamente `https://github.com/llancor/Bast-Control-Acceso.git`, extrae la carpeta `Bast-Control` y la instala en `/opt/bast-control`. La ubicación puede cambiarse definiendo `BASTCONTROL_INSTALL_DIR` antes de ejecutar el script. El instalador propone el puerto `8082`; una instalación manual con `.env.docker.example` usa `8080`.

Para actualizar una instalación administrada por el menú, usa la opción **Actualizar BastControl**. El instalador descarga una copia nueva de `BastControl`, conserva `.env` y reconstruye los servicios sin eliminar el volumen de MySQL.

La desinstalación completa elimina los contenedores, imágenes locales, volumen MySQL y la ruta de instalación elegida después de exigir la confirmación literal `ELIMINAR TODO`. Docker Engine se conserva para no afectar otros proyectos.

### Instalador para Windows

Abre PowerShell y ejecuta:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Instalar_BastControl_HHRR_v4.1.ps1
```

El menú puede instalar Git, WSL 2 y Docker Desktop mediante Winget, descargar el repositorio, desplegar BastControl y administrar servicios, puertos y usuarios.

## Estructura

```text
backend/   Express, Prisma, MySQL, JWT y REST API
frontend/  React, Vite, Tailwind, Leaflet y UI responsive
```
