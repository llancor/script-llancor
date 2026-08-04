#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="${GUARDIAPRO_REPO_URL:-https://github.com/llancor/script-llancor.git}"
DEFAULT_INSTALL_ROOT="/optguardiapro"
DEFAULT_HTTP_PORT="8080"
INSTALL_ROOT="${GUARDIAPRO_INSTALL_DIR:-$DEFAULT_INSTALL_ROOT}"
PROJECT_SUBDIR="guardiapro"
APP_DIR="$SCRIPT_DIR"

# Si se ejecuta desde una copia instalada, administra esa instancia concreta.
if [[ -z "${GUARDIAPRO_INSTALL_DIR:-}" && -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
  detected_root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$detected_root" ]] && INSTALL_ROOT="$detected_root"
fi

# Si el instalador está separado del proyecto, reutiliza una descarga anterior.
if [[ ! -f "$APP_DIR/docker-compose.yml" && -f "$INSTALL_ROOT/$PROJECT_SUBDIR/docker-compose.yml" ]]; then
  APP_DIR="$INSTALL_ROOT/$PROJECT_SUBDIR"
fi
cd "$APP_DIR"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; B='\033[1m'; N='\033[0m'

title(){ clear; printf "${C}${B}========================================\n  GuardiaPro · Administrador Debian\n========================================${N}\n\n"; }
pause(){ printf '\nPresiona Enter para continuar...'; read -r; }
has(){ command -v "$1" >/dev/null 2>&1; }
root(){ if [[ ${EUID:-$(id -u)} -eq 0 ]]; then "$@"; else sudo "$@"; fi; }
instance_name(){
  local path="$1" base suffix
  base="$(basename "$path" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
  [[ -n "$base" ]] || base="guardiapro"
  suffix="$(printf '%s' "$path" | sha256sum | cut -c1-8)"
  printf 'guardiapro_%s_%s' "$base" "$suffix"
}
select_installation(){
  local chosen port
  printf "Ruta de instalacion [${C}%s${N}]: " "$DEFAULT_INSTALL_ROOT"
  read -r chosen
  chosen="${chosen:-$DEFAULT_INSTALL_ROOT}"
  if [[ "$chosen" != /* || "$chosen" == "/" || "$chosen" == "/opt" ]]; then
    printf "${R}La ruta debe ser absoluta y no puede ser / ni /opt.${N}\n"
    return 1
  fi
  INSTALL_ROOT="${chosen%/}"
  APP_DIR="$INSTALL_ROOT/$PROJECT_SUBDIR"
  printf "Puerto HTTP [${C}%s${N}]: " "$DEFAULT_HTTP_PORT"
  read -r port
  port="${port:-$DEFAULT_HTTP_PORT}"
  if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
    printf "${R}Puerto invalido. Debe estar entre 1 y 65535.${N}\n"
    return 1
  fi
  INSTALL_HTTP_PORT="$port"
}
dc(){
  if ! has docker; then printf "${R}Docker no está instalado.${N}\n"; return 1; fi
  if ! docker info >/dev/null 2>&1; then printf "${R}Docker no está accesible. Usa sudo o vuelve a iniciar sesión tras agregarte al grupo docker.${N}\n"; return 1; fi
  local project_name
  project_name="$(getenv COMPOSE_PROJECT_NAME "$(instance_name "$INSTALL_ROOT")")"
  docker compose --project-name "$project_name" "$@"
}

project_ready(){ [[ -f "$APP_DIR/docker-compose.yml" && -d "$APP_DIR/backend" && -d "$APP_DIR/frontend" ]]; }

download_project(){
  if project_ready; then
    local existing_root
    existing_root="$(git -C "$APP_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$existing_root" ]]; then
      printf "${B}Buscando actualizaciones en GitHub...${N}\n"
      if ! git -C "$existing_root" pull --ff-only; then
        printf "${R}No fue posible actualizar el proyecto. Revisa la conexion o los cambios locales.${N}\n"
        return 1
      fi
      printf "${G}Proyecto actualizado.${N}\n"
    fi
    return 0
  fi
  title
  printf "${B}Descargando Control de Seguridad desde GitHub...${N}\n\n"
  if ! has git; then
    root apt-get update || return 1
    root apt-get install -y git ca-certificates || return 1
  fi
  if [[ -d "$INSTALL_ROOT/.git" ]]; then
    printf 'Actualizando instalación existente...\n'
    git -C "$INSTALL_ROOT" pull --ff-only || return 1
  elif [[ -e "$INSTALL_ROOT" ]]; then
    printf "${R}La ruta $INSTALL_ROOT ya existe pero no es un repositorio Git.${N}\n"
    printf 'Elimínala, muévela o define otra ruta con GUARDIAPRO_INSTALL_DIR.\n'
    return 1
  else
    root install -d -o "$(id -un)" -g "$(id -gn)" "$INSTALL_ROOT" || return 1
    git clone --depth 1 --branch main "$REPO_URL" "$INSTALL_ROOT" || return 1
  fi
  APP_DIR="$INSTALL_ROOT/$PROJECT_SUBDIR"
  if [[ ! -f "$APP_DIR/docker-compose.yml" ]]; then
    printf "${R}No se encontró $PROJECT_SUBDIR/docker-compose.yml en el repositorio.${N}\n"
    return 1
  fi
  cd "$APP_DIR" || return 1
  printf "${G}Proyecto descargado en $APP_DIR.${N}\n"
}
setenv(){
  local k="$1" v="$2"; touch .env
  if grep -q "^${k}=" .env; then sed -i "s|^${k}=.*|${k}=${v}|" .env; else printf '%s=%s\n' "$k" "$v" >>.env; fi
}
getenv(){ local v; v="$(grep -E "^$1=" .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"; printf '%s' "${v:-$2}"; }
prepare_env(){
  if [[ ! -f .env ]]; then
    if [[ -f .env.docker.example ]]; then
      cp .env.docker.example .env
    else
      printf '%s\n' \
        'MYSQL_PASSWORD=' \
        'MYSQL_ROOT_PASSWORD=' \
        'JWT_SECRET=' \
        'APP_URL=' \
        "HTTP_PORT=$DEFAULT_HTTP_PORT" \
        "COMPOSE_PROJECT_NAME=$(instance_name "$INSTALL_ROOT")" \
        'GOOGLE_CLIENT_ID=' \
        'SMTP_HOST=' \
        'SMTP_PORT=587' \
        'SMTP_USER=' \
        'SMTP_PASS=' \
        'MAIL_FROM=GuardiaPro <no-reply@guardiapro.local>' > .env
      printf "${Y}No se encontró .env.docker.example; se creó una configuración nueva.${N}\n"
    fi
    setenv MYSQL_PASSWORD "$(openssl rand -hex 24)"
    setenv MYSQL_ROOT_PASSWORD "$(openssl rand -hex 24)"
    setenv JWT_SECRET "$(openssl rand -hex 48)"
    setenv HTTP_PORT "${INSTALL_HTTP_PORT:-$DEFAULT_HTTP_PORT}"
    setenv COMPOSE_PROJECT_NAME "$(instance_name "$INSTALL_ROOT")"
    local server_ip
    server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [[ -n "$server_ip" ]] && setenv APP_URL "http://${server_ip}:$(getenv HTTP_PORT "$DEFAULT_HTTP_PORT")"
  fi
}

dependencies(){
  title; printf "${B}Instalando dependencias oficiales de Docker...${N}\n\n"
  if has docker && docker compose version >/dev/null 2>&1; then printf "${G}Docker y Compose ya están instalados.${N}\n"; return; fi
  root apt-get update || return
  root apt-get install -y ca-certificates curl git openssl || return
  root install -m 0755 -d /etc/apt/keyrings || return
  root curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc || return
  root chmod a+r /etc/apt/keyrings/docker.asc || return
  local code arch; code="$(. /etc/os-release && printf '%s' "$VERSION_CODENAME")"; arch="$(dpkg --print-architecture)"
  printf 'Types: deb\nURIs: https://download.docker.com/linux/debian\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' "$code" "$arch" | root tee /etc/apt/sources.list.d/docker.sources >/dev/null
  root apt-get update || return
  root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return
  root systemctl enable --now docker || return
  if [[ ${EUID:-$(id -u)} -ne 0 ]] && ! id -nG "$USER" | grep -qw docker; then
    root usermod -aG docker "$USER"
    printf "${Y}Usuario agregado al grupo docker. Cierra sesión y vuelve a entrar antes de continuar.${N}\n"
  else printf "${G}Dependencias listas.${N}\n"; fi
}

show_url(){
  prepare_env; local port url ip; port="$(getenv HTTP_PORT "$DEFAULT_HTTP_PORT")"; url="$(getenv APP_URL '')"; ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf "\n${B}Ruta instalada:${N} %s\n" "$INSTALL_ROOT"
  printf "${B}Instancia Docker:${N} %s\n" "$(getenv COMPOSE_PROJECT_NAME "$(instance_name "$INSTALL_ROOT")")"
  printf "${B}Puerto publicado:${N} %s\n" "$port"
  [[ -n "$url" ]] && printf "${B}URL configurada:${N} ${C}%s${N}\n" "$url"
  [[ -n "$ip" ]] && printf "${B}Acceso por IP:${N} ${C}http://%s:%s${N}\n" "$ip" "$port"
}

install_app(){
  title
  select_installation || return
  if ! has docker; then printf "${R}Primero usa la opción Instalar dependencias.${N}\n"; return; fi
  download_project || return
  title
  prepare_env; local url; printf "URL actual: ${C}%s${N}\n" "$(getenv APP_URL '')"; read -rp 'URL pública (Enter para conservar): ' url
  setenv HTTP_PORT "$INSTALL_HTTP_PORT"
  setenv COMPOSE_PROJECT_NAME "$(instance_name "$INSTALL_ROOT")"
  [[ -n "$url" ]] && setenv APP_URL "$url"
  printf "\n${B}Construyendo y arrancando GuardiaPro...${N}\n"
  if dc up -d --build; then printf "${G}Instalación terminada.${N}\n"; show_url; else printf "${R}Falló la instalación. Revisa los registros desde el menú de estado.${N}\n"; fi
}

services(){
  while true; do title; printf "${C}${B}Estado y control del servicio${N}\n\n${Y}1)${C} Ver estado${N}\n${Y}2)${C} Iniciar${N}\n${Y}3)${C} Detener${N}\n${Y}4)${C} Reiniciar${N}\n${Y}5)${C} Ver registros${N}\n${Y}6)${C} Volver${N}\n\n"; read -rp 'Opción: ' o
    case "$o" in 1) dc ps; pause;; 2) dc up -d; pause;; 3) dc stop; pause;; 4) dc restart; pause;; 5) dc logs --tail=150; pause;; 6) return;; *) printf "${R}Opción inválida.${N}\n"; sleep 1;; esac
  done
}

port(){
  title; prepare_env; local p; printf "Puerto actual: ${C}%s${N}\n" "$(getenv HTTP_PORT "$DEFAULT_HTTP_PORT")"; read -rp 'Nuevo puerto (1-65535): ' p
  if ! [[ "$p" =~ ^[0-9]+$ ]] || ((p<1 || p>65535)); then printf "${R}Puerto inválido.${N}\n"; return; fi
  setenv HTTP_PORT "$p"
  if dc up -d --force-recreate frontend; then printf "${G}Puerto actualizado.${N}\n"; show_url; fi
}

users(){
  while true; do title; printf "${C}${B}Gestión de usuarios${N}\n\n${Y}1)${C} Listar usuarios${N}\n${Y}2)${C} Restablecer contraseña${N}\n${Y}3)${C} Volver${N}\n\n"; read -rp 'Opción: ' o
    case "$o" in
      1) dc exec -T backend node dist/src/admin-cli.js list-users; pause;;
      2)
        local email pass confirm; read -rp 'Email: ' email; read -rsp 'Nueva contraseña (mínimo 8 caracteres): ' pass; printf '\n'; read -rsp 'Confirmar contraseña: ' confirm; printf '\n'
        if [[ ${#pass} -lt 8 ]]; then printf "${R}Debe tener al menos 8 caracteres.${N}\n"; elif [[ "$pass" != "$confirm" ]]; then printf "${R}Las contraseñas no coinciden.${N}\n"; else dc exec -T backend node dist/src/admin-cli.js reset-password "$email" "$pass"; fi; pause;;
      3) return;; *) printf "${R}Opción inválida.${N}\n"; sleep 1;;
    esac
  done
}

repair_database(){
  title
  printf "${C}${B}Reparar base de datos${N}\n\n"
  printf "${Y}Esta operacion elimina y vuelve a crear la base de datos de esta instancia.${N}\n"
  printf "Se perderan usuarios, guardias, recintos, turnos, rondas y configuraciones actuales.\n\n"
  local confirmation
  read -rp 'Escribe REPARAR BASE para continuar: ' confirmation
  [[ "$confirmation" == 'REPARAR BASE' ]] || { printf 'Operacion cancelada.\n'; return; }
  project_ready || { printf "${R}No se encontro una instalacion valida en $APP_DIR.${N}\n"; return; }
  prepare_env
  dc down -v --remove-orphans || return
  if dc up -d --build; then printf "${G}Base de datos reparada e instancia iniciada.${N}\n"; dc ps; show_url; else printf "${R}La reparacion fallo. Revisa los registros del backend.${N}\n"; fi
}

show_initial_credentials(){
  title
  printf "${C}${B}Credenciales iniciales${N}\n\n"
  printf "${B}Usuario:${N} admin@guardiapro.cl\n"
  printf "${B}Contraseña:${N} GuardiaPro2026!\n\n"
  printf "${Y}Por seguridad, cambia esta contraseña después del primer inicio de sesión.${N}\n"
}

update_app(){
  title
  printf "${C}${B}Actualizar GuardiaPro${N}\n\n"
  if ! project_ready; then
    if [[ -f "$INSTALL_ROOT/$PROJECT_SUBDIR/docker-compose.yml" ]]; then
      APP_DIR="$INSTALL_ROOT/$PROJECT_SUBDIR"
      cd "$APP_DIR" || return 1
    else
      printf "${R}No se encontró una instalación de GuardiaPro en $INSTALL_ROOT/$PROJECT_SUBDIR.${N}\n"
      return 1
    fi
  fi
  if ! has git; then
    printf "${R}Git no está instalado. Ejecuta primero la opción 1.${N}\n"
    return 1
  fi
  local repository_root
  repository_root="$(git -C "$APP_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$repository_root" ]]; then
    printf "${R}La instalación no pertenece a un repositorio Git.${N}\n"
    return 1
  fi
  printf "${B}Descargando cambios desde GitHub...${N}\n"
  if ! git -C "$repository_root" pull --ff-only; then
    printf "${R}No fue posible actualizar. Revisa la conexión o los cambios locales.${N}\n"
    return 1
  fi
  APP_DIR="$repository_root/$PROJECT_SUBDIR"
  cd "$APP_DIR" || return 1
  project_ready || { printf "${R}La carpeta actualizada no contiene una instalación válida.${N}\n"; return 1; }
  prepare_env
  printf "\n${B}Reconstruyendo y reiniciando servicios sin borrar los datos...${N}\n"
  if dc up -d --build --remove-orphans; then
    printf "${G}GuardiaPro fue actualizado correctamente. La base de datos se conservó.${N}\n"
    dc ps
    show_url
  else
    printf "${R}La actualización falló. Revisa los registros desde la opción 3.${N}\n"
    return 1
  fi
}

uninstall_app(){
  title
  printf "${C}${B}Desinstalacion completa de GuardiaPro${N}\n\n"
  printf "${R}Se eliminaran contenedores, imagenes, red, volumen MySQL y todos los archivos de esta instancia.${N}\n\n"
  local confirmation target
  read -rp 'Escribe ELIMINAR TODO para continuar: ' confirmation
  [[ "$confirmation" == 'ELIMINAR TODO' ]] || { printf 'Operacion cancelada.\n'; return; }
  target="$(realpath -m "$INSTALL_ROOT")"
  case "$target" in
    /opt/*|/root/*|/home/*/*)
      [[ -f "$target/$PROJECT_SUBDIR/docker-compose.yml" ]] || { printf "${R}No se encontro una instalacion valida en $target.${N}\n"; return; }
      dc down -v --rmi local --remove-orphans || return
      cd / || return
      root rm -rf -- "$target"
      printf "${R}La instancia completa fue eliminada permanentemente.${N}\n"
      APP_DIR="$SCRIPT_DIR"
      return;;
    *) printf "${R}Ruta no permitida para borrado automatico: $target${N}\n";;
  esac
}

while true; do
  title
  printf "${C}${B} INSTALACIÓN${N}\n"
  printf "  ${Y}1)${C} Instalar dependencias${N}\n"
  printf "  ${Y}2)${C} Instalar Control de Seguridad${N}\n\n"
  printf "${C}${B} ADMINISTRACIÓN${N}\n"
  printf "  ${Y}3)${C} Estado y control del servicio${N}\n"
  printf "  ${Y}4)${C} Cambiar puerto de Docker${N}\n"
  printf "  ${Y}5)${C} Ver URL y puerto${N}\n"
  printf "  ${Y}6)${C} Gestión de usuarios${N}\n\n"
  printf "${C}${B} MANTENIMIENTO${N}\n"
  printf "  ${Y}7)${C} Desinstalar y borrar todo${N}\n"
  printf "  ${Y}8)${C} Reparar base de datos${N}\n"
  printf "  ${Y}9)${C} Ver credenciales iniciales${N}\n"
  printf "  ${Y}10)${C} Actualizar GuardiaPro${N}\n"
  printf "  ${Y}0)${C} Salir${N}\n\n"
  read -rp 'Selecciona una opción: ' o
  if [[ "$o" == 8 ]]; then repair_database; pause; continue; fi
  case "$o" in 1) dependencies; pause;; 2) install_app; pause;; 3) services;; 4) port; pause;; 5) title; show_url; pause;; 6) users;; 7) uninstall_app; pause;; 9) show_initial_credentials; pause;; 10) update_app; pause;; 0) exit 0;; *) printf "${R}Opción inválida.${N}\n"; sleep 1;; esac
done
