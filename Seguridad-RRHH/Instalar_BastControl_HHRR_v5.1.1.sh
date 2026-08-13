#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="${BASTCONTROL_REPO_URL:-https://github.com/llancor/Bast-Control-Acceso.git}"
DEFAULT_INSTALL_ROOT="/opt/bast-control"
DEFAULT_HTTP_PORT="8082"
INSTALL_ROOT="${BASTCONTROL_INSTALL_DIR:-$DEFAULT_INSTALL_ROOT}"
PROJECT_SUBDIR="Bast-Control"
APP_DIR="$SCRIPT_DIR"

# Si se ejecuta desde una copia instalada, administra esa instancia concreta.
if [[ -z "${BASTCONTROL_INSTALL_DIR:-}" && -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
  INSTALL_ROOT="$SCRIPT_DIR"
fi

# Si el instalador está separado del proyecto, reutiliza una instalación anterior.
if [[ ! -f "$APP_DIR/docker-compose.yml" && -f "$INSTALL_ROOT/docker-compose.yml" ]]; then
  APP_DIR="$INSTALL_ROOT"
fi
cd "$APP_DIR"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; B='\033[1m'; N='\033[0m'

title(){
  clear
  printf "${C}${B}==================================================\n"
  printf "                 BastControl                  \n"
  printf "              Instalador para Debian              \n"
  printf "==================================================${N}\n\n"
}
pause(){ printf '\nPresiona Enter para continuar...'; read -r </dev/tty; }
has(){ command -v "$1" >/dev/null 2>&1; }
root(){ if [[ ${EUID:-$(id -u)} -eq 0 ]]; then "$@"; else sudo "$@"; fi; }
instance_name(){
  local path="$1" base suffix
  base="$(basename "$path" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
  [[ -n "$base" ]] || base="bastcontrol"
  suffix="$(printf '%s' "$path" | sha256sum | cut -c1-8)"
  printf 'seguridad_%s_%s' "$base" "$suffix"
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
  local project_name
  project_name="$(getenv COMPOSE_PROJECT_NAME "$(instance_name "$INSTALL_ROOT")")"
  if docker info >/dev/null 2>&1; then
    docker compose --project-name "$project_name" "$@"
  elif root docker info >/dev/null 2>&1; then
    root docker compose --project-name "$project_name" "$@"
  else
    printf "${R}Docker no está iniciado o no está accesible ni siquiera con sudo.${N}\n"
    return 1
  fi
}

project_ready(){ [[ -f "$APP_DIR/docker-compose.yml" && -d "$APP_DIR/backend" && -d "$APP_DIR/frontend" ]]; }

adopt_existing_compose_project(){
  local configured project working_dir frontend_id app_path published_port ports
  configured="$(getenv COMPOSE_PROJECT_NAME "$(instance_name "$INSTALL_ROOT")")"
  app_path="$(realpath -m "$APP_DIR")"
  published_port="$(getenv HTTP_PORT "$DEFAULT_HTTP_PORT")"
  while IFS='|' read -r project ports; do
    [[ -n "$project" && "$ports" == *":${published_port}->"* ]] || continue
    if [[ "$project" != "$configured" ]]; then
      setenv COMPOSE_PROJECT_NAME "$project"
      printf "${Y}Se detectó por el puerto %s y reutilizará la instancia Docker existente: %s${N}\n" "$published_port" "$project"
    fi
    return 0
  done < <(if docker info >/dev/null 2>&1; then docker ps --filter 'label=com.docker.compose.service=frontend' --format '{{.Label "com.docker.compose.project"}}|{{.Ports}}'; else root docker ps --filter 'label=com.docker.compose.service=frontend' --format '{{.Label "com.docker.compose.project"}}|{{.Ports}}'; fi)
  while IFS='|' read -r project working_dir; do
    [[ -n "$project" && "$(realpath -m "$working_dir")" == "$app_path" ]] || continue
    if docker info >/dev/null 2>&1; then
      frontend_id="$(docker ps -aq --filter "label=com.docker.compose.project=$project" --filter 'label=com.docker.compose.service=frontend' | head -n1)"
    else
      frontend_id="$(root docker ps -aq --filter "label=com.docker.compose.project=$project" --filter 'label=com.docker.compose.service=frontend' | head -n1)"
    fi
    if [[ -n "$frontend_id" && "$project" != "$configured" ]]; then
      setenv COMPOSE_PROJECT_NAME "$project"
      printf "${Y}Se detectó y reutilizará la instancia Docker existente: %s${N}\n" "$project"
      return 0
    fi
  done < <(if docker info >/dev/null 2>&1; then docker ps -a --format '{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.project.working_dir"}}'; else root docker ps -a --format '{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.project.working_dir"}}'; fi)
}

configure_sparse_checkout(){
  local repository_root="$1"
  git -C "$repository_root" sparse-checkout init --cone || return 1
  git -C "$repository_root" sparse-checkout set "$PROJECT_SUBDIR" || return 1
}

migrate_legacy_env(){
  local target_env="$APP_DIR/.env" legacy_env
  [[ -f "$target_env" ]] && return 0
  for legacy_env in \
    "/opt/bast-control/bastcontrol/.env" \
    "/opt/bast-control/bastcontrol/.env" \
    "/opt/bast-control/BastControl/.env"; do
    if [[ -f "$legacy_env" ]]; then
      cp "$legacy_env" "$target_env" || return 1
      printf "${G}Configuración existente migrada desde %s.${N}\n" "$legacy_env"
      return 0
    fi
  done
}

download_project(){
  local temp_repo source_dir

  title
  printf "${B}Descargando BastControl desde GitHub...${N}\n\n"

  if ! has git; then
    root apt-get update || return 1
    root apt-get install -y git ca-certificates rsync || return 1
  elif ! has rsync; then
    root apt-get update || return 1
    root apt-get install -y rsync || return 1
  fi

  if [[ -e "$INSTALL_ROOT" && ! -d "$INSTALL_ROOT" ]]; then
    printf "${R}La ruta $INSTALL_ROOT existe pero no es una carpeta.${N}\n"
    return 1
  fi

  root install -d -o "$(id -un)" -g "$(id -gn)" "$INSTALL_ROOT" || return 1
  temp_repo="$(mktemp -d /tmp/bastcontrol.XXXXXX)" || return 1

  if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --filter=blob:none --sparse --branch main "$REPO_URL" "$temp_repo"; then
    rm -rf -- "$temp_repo"
    return 1
  fi

  configure_sparse_checkout "$temp_repo" || { rm -rf -- "$temp_repo"; return 1; }
  source_dir="$temp_repo/$PROJECT_SUBDIR"

  if [[ ! -f "$source_dir/docker-compose.yml" ]]; then
    printf "${R}No se encontró %s/docker-compose.yml en el repositorio.${N}\n" "$PROJECT_SUBDIR"
    rm -rf -- "$temp_repo"
    return 1
  fi

  APP_DIR="$INSTALL_ROOT"
  migrate_legacy_env || { rm -rf -- "$temp_repo"; return 1; }

  # Copia únicamente BastControl directamente en la ruta final.
  # Conserva .env y elimina archivos obsoletos de versiones anteriores.
  if ! rsync -a --delete --exclude='.env' "$source_dir/" "$INSTALL_ROOT/"; then
    rm -rf -- "$temp_repo"
    return 1
  fi

  rm -rf -- "$temp_repo"
  APP_DIR="$INSTALL_ROOT"
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
        'INITIAL_ADMIN_EMAIL=admin@bastcontrol.com' \
        'INITIAL_ADMIN_PASSWORD=' \
        'APP_URL=' \
        "HTTP_PORT=$DEFAULT_HTTP_PORT" \
        "COMPOSE_PROJECT_NAME=$(instance_name "$INSTALL_ROOT")" \
        'GOOGLE_CLIENT_ID=' \
        'SMTP_HOST=' \
        'SMTP_PORT=587' \
        'SMTP_USER=' \
        'SMTP_PASS=' \
        'MAIL_FROM=BastControl <no-reply@bastcontrol.local>' > .env
      printf "${Y}No se encontró .env.docker.example; se creó una configuración nueva.${N}\n"
    fi
    setenv MYSQL_PASSWORD "$(openssl rand -hex 24)"
    setenv MYSQL_ROOT_PASSWORD "$(openssl rand -hex 24)"
    setenv JWT_SECRET "$(openssl rand -hex 48)"
    setenv INITIAL_ADMIN_EMAIL "admin@bastcontrol.com"
    setenv INITIAL_ADMIN_PASSWORD "$(openssl rand -base64 24 | tr -d '\n=/+' | cut -c1-20)"
    setenv HTTP_PORT "${INSTALL_HTTP_PORT:-$DEFAULT_HTTP_PORT}"
    setenv COMPOSE_PROJECT_NAME "$(instance_name "$INSTALL_ROOT")"
    local server_ip
    server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [[ -n "$server_ip" ]] && setenv APP_URL "http://${server_ip}:$(getenv HTTP_PORT "$DEFAULT_HTTP_PORT")"
  fi
}

preflight(){
  local target="${1:-$DEFAULT_INSTALL_ROOT}" port="${2:-$DEFAULT_HTTP_PORT}" parent free
  parent="$(dirname "$target")"; free="$(df -Pk "$parent" 2>/dev/null|awk 'NR==2{print $4}')"
  [[ -n "$free" && "$free" -ge 2097152 ]] || { printf "${R}Se requieren al menos 2 GB libres en %s.${N}\n" "$parent"; return 1; }
  if command -v ss >/dev/null&&ss -ltnH|awk '{print $4}'|grep -Eq "(^|:)$port$"; then printf "${R}El puerto %s ya está ocupado.${N}\n" "$port"; return 1; fi
  if has docker; then docker version --format '{{.Server.Version}}' >/dev/null 2>&1||{ printf "${R}Docker no está operativo.${N}\n"; return 1; }; fi
  printf "${G}Comprobación previa correcta: espacio, puerto y Docker.${N}\n"
}

dependencies(){
  title; printf "${B}Instalando dependencias oficiales de Docker...${N}\n\n"
  if has docker && { docker compose version >/dev/null 2>&1 || root docker compose version >/dev/null 2>&1; }; then printf "${G}Docker y Compose ya están instalados.${N}\n"; return; fi
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
  preflight "$INSTALL_ROOT" "$INSTALL_HTTP_PORT" || return
  if ! has docker; then printf "${R}Primero usa la opción Instalar dependencias.${N}\n"; return; fi
  download_project || return
  title
  prepare_env; local url; printf "URL actual: ${C}%s${N}\n" "$(getenv APP_URL '')"; read -rp 'URL pública (Enter para conservar): ' url
  setenv HTTP_PORT "$INSTALL_HTTP_PORT"
  setenv COMPOSE_PROJECT_NAME "$(instance_name "$INSTALL_ROOT")"
  [[ -n "$url" ]] && setenv APP_URL "$url"
  printf "\n${B}Construyendo y arrancando BastControl...${N}\n"
  if dc up -d --build; then
    printf "${G}Instalación terminada.${N}\n"
    show_url
    print_initial_credentials
  else
    printf "${R}Falló la instalación. Revisa los registros desde el menú de estado.${N}\n"
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
  while true; do title; printf "${C}${B}Gestión de usuarios${N}\n\n${Y}1)${C} Listar usuarios${N}\n${Y}2)${C} Activar usuario${N}\n${Y}3)${C} Desactivar usuario${N}\n${Y}4)${C} Cambiar contraseña${N}\n${Y}5)${C} Quitar bloqueo por intentos fallidos${N}\n${Y}6)${C} Volver${N}\n\n"; read -rp 'Opción: ' o
    case "$o" in
      1) dc exec -T backend node dist/src/admin-cli.js list-users; pause;;
      2|3|4|5)
        dc exec -T backend node dist/src/admin-cli.js list-users; local selected; read -rp 'Número de usuario: ' selected
        if [[ "$o" == 2 ]]; then dc exec -T backend node dist/src/admin-cli.js set-enabled "$selected" true
        elif [[ "$o" == 3 ]]; then dc exec -T backend node dist/src/admin-cli.js set-enabled "$selected" false
        elif [[ "$o" == 5 ]]; then dc exec -T backend node dist/src/admin-cli.js unlock "$selected"
        else local pass confirm; read -rsp 'Nueva contraseña (mínimo 10 caracteres): ' pass; printf '\n'; read -rsp 'Confirmar contraseña: ' confirm; printf '\n'; if [[ ${#pass} -lt 10 ]]; then printf "${R}Debe tener al menos 10 caracteres.${N}\n"; elif [[ "$pass" != "$confirm" ]]; then printf "${R}Las contraseñas no coinciden.${N}\n"; else dc exec -T backend node dist/src/admin-cli.js reset-password "$selected" "$pass"; fi; fi; pause;;
      6) return;; *) printf "${R}Opción inválida.${N}\n"; sleep 1;;
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

print_initial_credentials(){
  printf "\n${C}${B}==================================================${N}\n"
  printf "${C}${B}              CREDENCIALES INICIALES             ${N}\n"
  printf "${C}${B}==================================================${N}\n\n"
  printf "${B}Usuario:${N}     %s\n" "$(getenv INITIAL_ADMIN_EMAIL 'admin@bastcontrol.com')"
  printf "${B}Contraseña temporal:${N}  %s\n\n" "$(getenv INITIAL_ADMIN_PASSWORD 'No disponible')"
  printf "${Y}Por seguridad, cambia esta contraseña después del primer inicio de sesión.${N}\n"
}

show_initial_credentials(){
  title
  print_initial_credentials
}

backup_app(){
  project_ready || { printf "${R}No se encontró una instalación válida en $APP_DIR.${N}\n"; return 1; }
  cd "$APP_DIR" || return 1; prepare_env
  adopt_existing_compose_project
  local backup_dir="${BASTCONTROL_BACKUP_DIR:-${INSTALL_ROOT}-backups}" stamp file attempt auth_mode="" database_url="" backup_user="" backup_password="" backup_database=""
  printf "${B}Preparando la base de datos para el respaldo...${N}\n"
  dc up -d db || { printf "${R}No fue posible iniciar el servicio de base de datos.${N}\n"; return 1; }
  database_url="$(dc exec -T backend printenv DATABASE_URL 2>/dev/null | tr -d '\r' || true)"
  if [[ "$database_url" =~ ^mysql://([^:]+):([^@]+)@[^/]+/(.+)$ ]]; then
    backup_user="${BASH_REMATCH[1]}"; backup_password="${BASH_REMATCH[2]}"; backup_database="${BASH_REMATCH[3]%%\?*}"
  fi
  for attempt in {1..30}; do
    if dc exec -T db sh -c 'mysql -h 127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD" -Nse "SELECT 1"' >/dev/null 2>&1; then auth_mode="root"; break; fi
    if dc exec -T db sh -c 'mysql -h 127.0.0.1 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -Nse "SELECT 1"' >/dev/null 2>&1; then auth_mode="app"; break; fi
    if [[ -n "$backup_user" ]] && dc exec -T -e BACKUP_USER="$backup_user" -e BACKUP_PASSWORD="$backup_password" -e BACKUP_DATABASE="$backup_database" db sh -c 'mysql -h 127.0.0.1 -u"$BACKUP_USER" -p"$BACKUP_PASSWORD" "$BACKUP_DATABASE" -Nse "SELECT 1"' >/dev/null 2>&1; then auth_mode="backend"; break; fi
    sleep 2
  done
  if [[ -z "$auth_mode" ]]; then
    printf "${R}MySQL respondió, pero ninguna credencial disponible coincide con la base instalada.${N}\n"
    printf "${Y}Revisa DATABASE_URL del backend y las variables MYSQL_ROOT_PASSWORD, MYSQL_USER y MYSQL_PASSWORD.${N}\n"
    return 1
  fi
  if [[ "$auth_mode" == "backend" ]]; then
    setenv MYSQL_PASSWORD "$backup_password"
    printf "${G}La contraseña operativa de MySQL fue recuperada del backend y sincronizada en .env.${N}\n"
  fi
  stamp="$(date +%Y%m%d-%H%M%S)"; file="$backup_dir/bastcontrol-$stamp.sql.gz"; mkdir -p "$backup_dir" || return 1
  if [[ "$auth_mode" == "root" ]]; then
    dc exec -T db sh -c 'exec mysqldump -h 127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --triggers --no-tablespaces "$MYSQL_DATABASE"' | gzip -9 >"$file" || { rm -f "$file"; return 1; }
  elif [[ "$auth_mode" == "app" ]]; then
    printf "${Y}La contraseña root histórica no coincide; el respaldo usará el usuario operativo de la aplicación.${N}\n"
    dc exec -T db sh -c 'exec mysqldump -h 127.0.0.1 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" --single-transaction --routines --triggers --no-tablespaces "$MYSQL_DATABASE"' | gzip -9 >"$file" || { rm -f "$file"; return 1; }
  else
    printf "${Y}El respaldo usará las credenciales verificadas del backend activo.${N}\n"
    dc exec -T -e BACKUP_USER="$backup_user" -e BACKUP_PASSWORD="$backup_password" -e BACKUP_DATABASE="$backup_database" db sh -c 'exec mysqldump -h 127.0.0.1 -u"$BACKUP_USER" -p"$BACKUP_PASSWORD" --single-transaction --routines --triggers --no-tablespaces "$BACKUP_DATABASE"' | gzip -9 >"$file" || { rm -f "$file"; return 1; }
  fi
  cp -p .env "$backup_dir/bastcontrol-$stamp.env"; chmod 600 "$file" "$backup_dir/bastcontrol-$stamp.env"; printf "${G}Respaldo completado: %s${N}\n" "$file"
}

restore_app(){
  local backup_dir="${BASTCONTROL_BACKUP_DIR:-${INSTALL_ROOT}-backups}" file confirmation
  find "$backup_dir" -maxdepth 1 -type f -name '*.sql.gz' -printf '%p\n' 2>/dev/null | sort -r | head -20
  read -rp 'Ruta completa del respaldo .sql.gz: ' file; [[ -f "$file" ]] || return 1
  read -rp 'Escribe RESTAURAR para reemplazar la base actual: ' confirmation; [[ "$confirmation" == 'RESTAURAR' ]] || return 1
  cd "$APP_DIR" || return 1; prepare_env; dc up -d db || return 1
  gunzip -c "$file" | dc exec -T db sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' || return 1
  dc restart backend frontend; printf "${G}Respaldo restaurado correctamente.${N}\n"
}

update_app(){
  title
  printf "${C}${B}Actualizar BastControl con el módulo RRHH${N}\n\n"

  if [[ ! -f "$INSTALL_ROOT/docker-compose.yml" ]]; then
    printf "${R}No se encontró una instalación válida en $INSTALL_ROOT.${N}\n"
    return 1
  fi

  APP_DIR="$INSTALL_ROOT"
  cd "$APP_DIR" || return 1
  prepare_env
  backup_app || { printf "${R}Actualización cancelada: falló el respaldo previo.${N}\n"; return 1; }

  printf "${B}Descargando únicamente la carpeta %s desde GitHub...${N}\n" "$PROJECT_SUBDIR"
  download_project || return 1
  prepare_env

  printf "\n${B}Reconstruyendo y reiniciando servicios sin borrar los datos...${N}\n"
  if dc up -d --build --remove-orphans; then
    printf "${G}BastControl fue actualizado correctamente. La base de datos y configuración se conservaron.${N}\n"
    dc ps
    show_url
  else
    printf "${R}La actualización falló. Revisa los registros desde la opción 3.${N}\n"
    return 1
  fi
}

uninstall_app(){
  title
  printf "${C}${B}Desinstalacion completa de BastControl${N}\n\n"
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
  printf "${C}${G} INSTALACIÓN${N}\n"
  printf "  ${Y}1)${C} Instalar dependencias${N}\n"
  printf "  ${Y}2)${C} Instalar o migrar a BastControl${N}\n\n"
  printf "${C}${G} ADMINISTRACIÓN${N}\n"
  printf "  ${Y}3)${C} Estado y control del servicio${N}\n"
  printf "  ${Y}4)${C} Cambiar puerto de Docker${N}\n"
  printf "  ${Y}5)${C} Ver URL y puerto${N}\n"
  printf "  ${Y}6)${C} Gestión de usuarios${N}\n\n"
  printf "${C}${G} MANTENIMIENTO${N}\n"
  printf "  ${Y}7)${C} Desinstalar y borrar todo${N}\n"
  printf "  ${Y}8)${C} Reparar base de datos${N}\n"
  printf "  ${Y}9)${Y} Ver credenciales iniciales${N}\n"
  printf "  ${Y}10)${Y} Actualizar BastControl${N}\n"
  printf "  ${Y}11)${C} Crear respaldo${N}\n"
  printf "  ${Y}12)${C} Restaurar respaldo${N}\n"
  printf "  ${Y}0)${C} Salir${N}\n\n"
  read -rp 'Selecciona una opción: ' o
  if [[ "$o" == 8 ]]; then repair_database; pause; continue; fi
  case "$o" in 1) dependencies; pause;; 2) install_app; pause;; 3) services;; 4) port; pause;; 5) title; show_url; pause;; 6) users;; 7) uninstall_app; pause;; 9) show_initial_credentials; pause;; 10) update_app; pause;; 11) backup_app; pause;; 12) restore_app; pause;; 0) exit 0;; *) printf "${R}Opción inválida.${N}\n"; sleep 1;; esac
done
