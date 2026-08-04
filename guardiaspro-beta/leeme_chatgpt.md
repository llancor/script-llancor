Este proyecto se llama GuardiaPro-beta.

Es un monorepo:
- backend: Express, TypeScript, Prisma y MySQL.
- frontend: React, TypeScript, Vite, Tailwind y Leaflet.
- despliegue: Docker Compose en Debian.
- instalador: Instalar_GuardiaPro_llancor_v3.0.sh.

El instalador clona:
https://github.com/llancor/script-llancor.git

Y utiliza:
PROJECT_SUBDIR="GuardiaPro-beta"

Funciones recientes:
- Administración de usuarios.
- Importar, exportar y limpiar datos sin borrar usuarios.
- Seguimiento de rondas mediante GPS.
- Botón Ver ruta para supervisores.
- Opción 9 para mostrar credenciales iniciales.
- Opción 10 para actualizar desde GitHub sin eliminar MySQL.
- hero_description admite NULL en Prisma.

Antes de modificar, revisa README.md, docker-compose.yml y el código existente.
No elimines el volumen MySQL durante las actualizaciones.