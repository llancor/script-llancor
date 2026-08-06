#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="${SEGURIDPRO_REPO_URL:-https://github.com/llancor/script-llancor.git}"
DEFAULT_INSTALL_ROOT="/opt/seguridpro"
DEFAULT_HTTP_PORT="8081"
INSTALL_ROOT="${SEGURIDPRO_INSTALL_DIR:-$DEFAULT_INSTALL_ROOT}"
SOURCE_SUBDIR="SeguridPro"
HHRR_SUBDIR="SeguridPro-HHRR"
APP_DIR="$INSTALL_ROOT"

# Si el instalador se ejecuta desde una instalación, administra esa ruta concreta.
if [[ -z "${SEGURIDPRO_INSTALL_DIR:-}" && -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
  INSTALL_ROOT="$SCRIPT_DIR"
  APP_DIR="$INSTALL_ROOT"
fi

# Compatibilidad con instalaciones antiguas que usaban /opt/seguridpro/SeguridPro.
LEGACY_APP_DIR="$INSTALL_ROOT/$SOURCE_SUBDIR"
if [[ ! -f "$APP_DIR/docker-compose.yml" && -f "$LEGACY_APP_DIR/docker-compose.yml" ]]; then
  APP_DIR="$LEGACY_APP_DIR"
fi

cd "$APP_DIR"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; B='\033[1m'; N='\033[0m'
# Estilos
B='\033[1m'      # Negrita
D='\033[2m'      # Atenuado
I='\033[3m'      # Cursiva
U='\033[4m'      # Subrayado
BL='\033[5m'     # Parpadeo
RV='\033[7m'     # Invertido
############################################################
# Colores normales
############################################################

K='\033[0;30m'   # Negro
R='\033[0;31m'   # Rojo
G='\033[0;32m'   # Verde
Y='\033[0;33m'   # Amarillo
BLU='\033[0;34m' # Azul
M='\033[0;35m'   # Magenta
C='\033[0;36m'   # Cyan
W='\033[0;37m'   # Blanco

############################################################
# Colores brillantes
############################################################

LK='\033[1;30m'  # Gris oscuro
LR='\033[1;31m'  # Rojo brillante
LG='\033[1;32m'  # Verde brillante
LY='\033[1;33m'  # Amarillo brillante
LBL='\033[1;34m' # Azul brillante
LM='\033[1;35m'  # Magenta brillante
LC='\033[1;36m'  # Cyan brillante
LW='\033[1;37m'  # Blanco brillante

title(){ clear; printf "${C}${B}========================================\n  SeguridPro · Administrador Debian\n========================================${N}\n\n"; }
pause(){ printf '\nPresiona Enter para continuar...'; read -r; }
has(){ command -v "$1" >/dev/null 2>&1; }
root(){ if [[ ${EUID:-$(id -u)} -eq 0 ]]; then "$@"; else sudo "$@"; fi; }
instance_name(){
  local path="$1" base suffix
  base="$(basename "$path" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
  [[ -n "$base" ]] || base="seguridpro"
  suffix="$(printf '%s' "$path" | sha256sum | cut -c1-8)"
  printf 'seguridpro_%s_%s' "$base" "$suffix"
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
  APP_DIR="$INSTALL_ROOT"
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

clone_project_folder(){
  local temp_dir
  temp_dir="$(mktemp -d /tmp/seguridpro-install-XXXXXX)" || return 1

  if ! git clone --depth 1 --filter=blob:none --no-checkout --branch main "$REPO_URL" "$temp_dir"; then
    rm -rf "$temp_dir"
    return 1
  fi

  if ! git -C "$temp_dir" sparse-checkout set --no-cone "/$SOURCE_SUBDIR/"; then
    rm -rf "$temp_dir"
    return 1
  fi

  if ! git -C "$temp_dir" checkout main; then
    rm -rf "$temp_dir"
    return 1
  fi

  if [[ ! -f "$temp_dir/$SOURCE_SUBDIR/docker-compose.yml" ]]; then
    printf "${R}No se encontró $SOURCE_SUBDIR/docker-compose.yml en el repositorio.${N}\n"
    rm -rf "$temp_dir"
    return 1
  fi

  root install -d -o "$(id -un)" -g "$(id -gn)" "$INSTALL_ROOT" || {
    rm -rf "$temp_dir"
    return 1
  }

  root rsync -a --exclude='.git/' "$temp_dir/$SOURCE_SUBDIR/" "$INSTALL_ROOT/" || {
    rm -rf "$temp_dir"
    return 1
  }

  rm -rf "$temp_dir"
  APP_DIR="$INSTALL_ROOT"
}

migrate_legacy_layout(){
  local legacy_dir="$INSTALL_ROOT/$SOURCE_SUBDIR"

  [[ -f "$legacy_dir/docker-compose.yml" ]] || return 0

  printf "${Y}Se detectó una instalación antigua en $legacy_dir.${N}\n"
  printf "Migrando los archivos directamente a $INSTALL_ROOT...\n"

  root rsync -a \
    --exclude='.git/' \
    --exclude='.env' \
    "$legacy_dir/" "$INSTALL_ROOT/" || return 1

  if [[ ! -f "$INSTALL_ROOT/.env" && -f "$legacy_dir/.env" ]]; then
    root cp "$legacy_dir/.env" "$INSTALL_ROOT/.env" || return 1
  fi

  [[ -f "$INSTALL_ROOT/docker-compose.yml" ]] || {
    printf "${R}La migración no produjo una instalación válida.${N}\n"
    return 1
  }

  root rm -rf "$legacy_dir"
  root rm -rf "$INSTALL_ROOT/.git"
  APP_DIR="$INSTALL_ROOT"
  cd "$APP_DIR" || return 1
  printf "${G}Instalación antigua migrada correctamente.${N}\n"
}

download_project(){
  title
  printf "${B}Descargando SeguridPro desde GitHub...${N}\n\n"

  if ! has git; then
    root apt-get update || return 1
    root apt-get install -y git ca-certificates rsync || return 1
  fi

  if ! has rsync; then
    root apt-get update || return 1
    root apt-get install -y rsync || return 1
  fi

  migrate_legacy_layout || return 1

  if project_ready; then
    printf "${G}Ya existe una instalación válida en $INSTALL_ROOT.${N}\n"
    return 0
  fi

  if [[ -e "$INSTALL_ROOT" ]] && [[ -n "$(find "$INSTALL_ROOT" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
    printf "${R}La ruta $INSTALL_ROOT contiene archivos pero no es una instalación válida.${N}\n"
    printf "Muévelos, elimínalos o usa otra ruta con SEGURIDPRO_INSTALL_DIR.\n"
    return 1
  fi

  clone_project_folder || return 1
  cd "$APP_DIR" || return 1
  printf "${G}Proyecto descargado directamente en $APP_DIR.${N}\n"
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
        'MAIL_FROM=SeguridPro <no-reply@seguridpro.local>' > .env
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
  root apt-get install -y ca-certificates curl git openssl rsync || return
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

install_app() {

    title

    select_installation || return 1

    if ! has docker; then
        printf "${R}Docker no está instalado.${N}\n"
        printf "${Y}Primero usa la opción 1: Instalar dependencias.${N}\n"
        return 1
    fi

    download_project || return 1

    title
    prepare_env

    local url
    local current_url

    current_url="$(getenv APP_URL '')"

    printf "${C}${B}CONFIGURACIÓN DE SEGURIDPRO${N}\n\n"
    printf "${B}URL actual:${N} ${C}%s${N}\n" "${current_url:-No configurada}"

    printf "\n"
    read -rp 'URL pública (Enter para conservar): ' url

    setenv HTTP_PORT "$INSTALL_HTTP_PORT"
    setenv COMPOSE_PROJECT_NAME "$(instance_name "$INSTALL_ROOT")"

    if [[ -n "$url" ]]; then
        setenv APP_URL "$url"
    fi

    printf "\n${C}${B}Construyendo y arrancando SeguridPro...${N}\n\n"

    if dc up -d --build; then

        title

        printf "${G}${B}════════════════════════════════════════════${N}\n"
        printf "${G}${B}       INSTALACIÓN COMPLETADA${N}\n"
        printf "${G}${B}════════════════════════════════════════════${N}\n\n"

        printf "${G}SeguridPro fue instalado correctamente.${N}\n"

        show_url

        printf "\n${Y}Presiona Enter para ver las credenciales iniciales...${N}"
        read -r

        show_initial_credentials

    else

        printf "\n${R}${B}La instalación de SeguridPro falló.${N}\n"
        printf "${Y}Revisa los registros desde la opción Estado y control del servicio.${N}\n"

        return 1

    fi
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
  printf "${B}Usuario:${N} admin@seguridpro.cl\n"
  printf "${B}Contraseña:${N} SeguridPro2026!\n\n"
  printf "${Y}Por seguridad, cambia esta contraseña después del primer inicio de sesión.${N}\n"
}

update_app(){
  title
  printf "${C}${B}Actualizar SeguridPro${N}\n\n"

  migrate_legacy_layout || return 1
  APP_DIR="$INSTALL_ROOT"
  cd "$APP_DIR" || return 1
  project_ready || {
    printf "${R}No se encontró una instalación válida en $INSTALL_ROOT.${N}\n"
    return 1
  }

  if ! has git || ! has rsync; then
    printf "${Y}Instalando herramientas necesarias...${N}\n"
    root apt-get update || return 1
    root apt-get install -y git rsync ca-certificates || return 1
  fi

  local temp_dir backup_dir changes confirmation
  temp_dir="$(mktemp -d /tmp/seguridpro-update-XXXXXX)" || return 1
  backup_dir="$INSTALL_ROOT/backups/antes_actualizacion_$(date +%Y%m%d_%H%M%S)"

  printf "${B}Descargando la versión más reciente...${N}\n"
  git clone --depth 1 --filter=blob:none --no-checkout --branch main "$REPO_URL" "$temp_dir" || {
    rm -rf "$temp_dir"
    return 1
  }
  git -C "$temp_dir" sparse-checkout set --no-cone "/$SOURCE_SUBDIR/" || {
    rm -rf "$temp_dir"
    return 1
  }
  git -C "$temp_dir" checkout main || {
    rm -rf "$temp_dir"
    return 1
  }

  changes="$(rsync -ainc --out-format='%i %n' \
    --exclude='.env' --exclude='.git/' --exclude='node_modules/' \
    --exclude='dist/' --exclude='build/' --exclude='uploads/' \
    "$temp_dir/$SOURCE_SUBDIR/" "$APP_DIR/")"

  if [[ -z "$changes" ]]; then
    printf "${G}SeguridPro ya está actualizado.${N}\n"
    rm -rf "$temp_dir"
    return 0
  fi

  printf "${B}Archivos nuevos o modificados:${N}\n\n%s\n\n" "$changes"
  read -rp 'Escribe ACTUALIZAR para continuar: ' confirmation
  [[ "$confirmation" == 'ACTUALIZAR' ]] || {
    printf 'Operación cancelada.\n'
    rm -rf "$temp_dir"
    return 0
  }

  root mkdir -p "$backup_dir" || { rm -rf "$temp_dir"; return 1; }
  root rsync -a --exclude='.env' --exclude='node_modules/' --exclude='dist/' \
    --exclude='build/' --exclude='uploads/' "$APP_DIR/" "$backup_dir/" || {
    rm -rf "$temp_dir"
    return 1
  }

  root rsync -a --checksum --exclude='.env' --exclude='.git/' \
    --exclude='node_modules/' --exclude='dist/' --exclude='build/' \
    --exclude='uploads/' "$temp_dir/$SOURCE_SUBDIR/" "$APP_DIR/" || {
    rm -rf "$temp_dir"
    return 1
  }

  rm -rf "$temp_dir"
  prepare_env
  printf "\n${B}Reconstruyendo y reiniciando servicios sin borrar datos...${N}\n"
  if dc up -d --build --remove-orphans; then
    printf "${G}SeguridPro fue actualizado correctamente.${N}\n"
    printf "${B}Respaldo:${N} %s\n" "$backup_dir"
    dc ps
    show_url
  else
    printf "${R}La actualización falló. Respaldo disponible en: $backup_dir${N}\n"
    return 1
  fi
}


integrate_hr_module(){
  title
  printf "${C}${B}Integrar Modulo de RRHH${N}\n\n"
  printf "${G}La base de datos y el volumen MySQL no se eliminan ni recrean.${N}\n"
  printf "${Y}No se ejecutan migraciones, db:push, seed ni scripts SQL.${N}\n\n"

  migrate_legacy_layout || return 1
  APP_DIR="$INSTALL_ROOT"
  cd "$APP_DIR" || return 1
  project_ready || {
    printf "${R}No se encontró una instalación válida en $INSTALL_ROOT.${N}\n"
    return 1
  }

  if ! has git || ! has rsync; then
    root apt-get update || return 1
    root apt-get install -y git rsync ca-certificates || return 1
  fi

  local temp_dir source_dir changes confirmation backup_dir db_before db_after
  temp_dir="$(mktemp -d /tmp/seguridpro-rrhh-XXXXXX)" || return 1
  source_dir="$temp_dir/$HHRR_SUBDIR"
  backup_dir="$INSTALL_ROOT/backups/antes_rrhh_$(date +%Y%m%d_%H%M%S)"

  printf "${B}Descargando solamente $HHRR_SUBDIR...${N}\n"
  git clone --depth 1 --filter=blob:none --no-checkout --branch main "$REPO_URL" "$temp_dir" || {
    rm -rf "$temp_dir"
    return 1
  }
  git -C "$temp_dir" sparse-checkout set --no-cone "/$HHRR_SUBDIR/" || {
    rm -rf "$temp_dir"
    return 1
  }
  git -C "$temp_dir" checkout main || {
    rm -rf "$temp_dir"
    return 1
  }

  [[ -f "$source_dir/docker-compose.yml" && -d "$source_dir/backend" && -d "$source_dir/frontend" ]] || {
    printf "${R}El módulo descargado no es válido.${N}\n"
    rm -rf "$temp_dir"
    return 1
  }

  changes="$(rsync -ainc --out-format='%i %n' \
    --exclude='.env' --exclude='.git/' --exclude='node_modules/' \
    --exclude='dist/' --exclude='build/' --exclude='uploads/' \
    "$source_dir/" "$APP_DIR/")"

  if [[ -z "$changes" ]]; then
    printf "${G}La instalación ya contiene todos los archivos de RRHH.${N}\n"
    rm -rf "$temp_dir"
    return 0
  fi

  printf "${B}Archivos nuevos o modificados:${N}\n\n%s\n\n" "$changes"
  printf "${Y}No se borrarán archivos ni se modificará .env.${N}\n\n"
  read -rp 'Escribe INTEGRAR RRHH para continuar: ' confirmation
  [[ "$confirmation" == 'INTEGRAR RRHH' ]] || {
    printf 'Operación cancelada.\n'
    rm -rf "$temp_dir"
    return 0
  }

  root mkdir -p "$backup_dir" || { rm -rf "$temp_dir"; return 1; }
  root rsync -a --exclude='.env' --exclude='node_modules/' --exclude='dist/' \
    --exclude='build/' --exclude='uploads/' "$APP_DIR/" "$backup_dir/" || {
    rm -rf "$temp_dir"
    return 1
  }

  db_before="$(dc ps -q db 2>/dev/null || dc ps -q mysql 2>/dev/null || true)"

  root rsync -a --checksum --exclude='.env' --exclude='.git/' \
    --exclude='node_modules/' --exclude='dist/' --exclude='build/' \
    --exclude='uploads/' "$source_dir/" "$APP_DIR/" || {
    rm -rf "$temp_dir"
    return 1
  }

  rm -rf "$temp_dir"
  prepare_env

  printf "\n${B}Construyendo backend y frontend sin tocar MySQL...${N}\n"
  dc build backend frontend || {
    printf "${R}La compilación falló. Respaldo: $backup_dir${N}\n"
    return 1
  }
  dc up -d --no-deps backend frontend || return 1

  db_after="$(dc ps -q db 2>/dev/null || dc ps -q mysql 2>/dev/null || true)"
  printf "\n${G}${B}Módulo RRHH integrado correctamente.${N}\n"
  printf "${B}Respaldo:${N} %s\n" "$backup_dir"
  if [[ -n "$db_before" && "$db_before" == "$db_after" ]]; then
    printf "${G}El contenedor de base de datos no fue recreado.${N}\n"
  else
    printf "${Y}No fue posible confirmar el identificador del contenedor de base de datos.${N}\n"
  fi
  dc ps
  show_url
}

uninstall_app(){
  title
  printf "${C}${B}Desinstalacion completa de SeguridPro${N}\n\n"
  printf "${R}Se eliminaran contenedores, imagenes, red, volumen MySQL y todos los archivos de esta instancia.${N}\n\n"
  local confirmation target
  read -rp 'Escribe ELIMINAR TODO para continuar: ' confirmation
  [[ "$confirmation" == 'ELIMINAR TODO' ]] || { printf 'Operacion cancelada.\n'; return; }
  target="$(realpath -m "$INSTALL_ROOT")"
  case "$target" in
    /opt/*|/root/*|/home/*/*)
      [[ -f "$target/docker-compose.yml" ]] || { printf "${R}No se encontro una instalacion valida en $target.${N}\n"; return; }
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
  printf "${Y}${G} INSTALACIÓN${N}\n"
  printf "  ${Y}1)${C} Instalar dependencias${N}\n"
  printf "  ${Y}2)${C} Instalar Control de Seguridad${N}\n\n"
  printf "${C}${G} ADMINISTRACIÓN${N}\n"
  printf "  ${Y}3)${C} Estado y control del servicio${N}\n"
  printf "  ${Y}4)${C} Cambiar puerto de Docker${N}\n"
  printf "  ${Y}5)${C} Ver URL y puerto${N}\n"
  printf "  ${Y}6)${C} Gestión de usuarios${N}\n\n"
  printf "${C}${G} MANTENIMIENTO${N}\n"
  printf "  ${Y}7)${C} Desinstalar y borrar todo${N}\n"
  printf "  ${Y}8)${C} Reparar base de datos${N}\n"
  printf "  ${Y}9)${Y} Ver credenciales iniciales${N}\n"
  printf "  ${Y}10)${C} Actualizar SeguridPro${N}\n"
  printf "  ${Y}11)${Y} Integrar Modulo de RRHH${N}\n"
  printf "  ${Y}0)${C} Salir${N}\n\n"
  read -rp 'Selecciona una opción: ' o
  if [[ "$o" == 8 ]]; then repair_database; pause; continue; fi
  case "$o" in 1) dependencies; pause;; 2) install_app; pause;; 3) services;; 4) port; pause;; 5) title; show_url; pause;; 6) users;; 7) uninstall_app; pause;; 9) show_initial_credentials; pause;; 10) update_app; pause;; 11) integrate_hr_module; pause;; 0) exit 0;; *) printf "${R}Opción inválida.${N}\n"; sleep 1;; esac
done
