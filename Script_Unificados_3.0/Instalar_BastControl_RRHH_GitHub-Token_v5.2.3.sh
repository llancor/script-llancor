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

  printf "${C}${B}Autenticación GitHub${N}

"
  local github_user github_token auth_repo_url

  read -rp "Usuario GitHub: " github_user </dev/tty
  read -rsp "Token GitHub (PAT): " github_token </dev/tty
  printf '
'

  if [[ -z "$github_user" || -z "$github_token" ]]; then
    printf "${R}Usuario o token vacío.${N}
"
    rm -rf -- "$temp_repo"
    unset github_token auth_repo_url
    return 1
  fi

  auth_repo_url="$REPO_URL"
  if [[ "$auth_repo_url" =~ ^https://github.com/(.+)$ ]]; then
    auth_repo_url="https://${github_user}:${github_token}@github.com/${BASH_REMATCH[1]}"
  else
    printf "${R}REPO_URL debe usar HTTPS de GitHub para autenticación con token.${N}
"
    rm -rf -- "$temp_repo"
    unset github_token auth_repo_url
    return 1
  fi

  if ! git clone --depth 1 --filter=blob:none --sparse --branch main "$auth_repo_url" "$temp_repo"; then
    printf "${R}No fue posible acceder al repositorio privado. Revisa usuario, token y permisos.${N}
"
    rm -rf -- "$temp_repo"
    unset github_token auth_repo_url
    return 1
  fi

  unset github_token auth_repo_url

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

verificar_pv(){
  if has pv; then return 0; fi
  printf "${Y}La herramienta pv es necesaria para mostrar el progreso del respaldo.${N}\n"
  printf "Instalando pv...\n"
  root apt-get update || return 1
  root apt-get install -y pv || return 1
  has pv || { printf "${R}No fue posible instalar pv.${N}\n"; return 1; }
}

listar_apps(){
  APPS=()

  while IFS= read -r APP; do
    APPS+=("$APP")
  done < <(find /opt -mindepth 1 -maxdepth 1 -type d | sort)

  if [ ${#APPS[@]} -eq 0 ]; then
    printf "\n${R}No se encontraron aplicaciones en /opt${N}\n\n"
    return 1
  fi

  printf "\n${C}${B}Aplicaciones encontradas:${N}\n\n"
  for i in "${!APPS[@]}"; do
    printf "  ${Y}%d)${C} %s${N}\n" "$((i+1))" "$(basename "${APPS[$i]}")"
  done
  printf "\n"
}

seleccionar_apps(){
  listar_apps || return 1

  printf "${Y}A)${C} Todas${N}\n\n"
  read -rp "Seleccione (ej: 1 3 5 o A): " RESP

  SELECCIONADAS=()

  if [[ "$RESP" =~ ^[Aa]$ ]]; then
    for APP in "${APPS[@]}"; do
      SELECCIONADAS+=("$APP")
    done
  else
    for NSEL in $RESP; do
      if ! [[ "$NSEL" =~ ^[0-9]+$ ]]; then
        printf "${Y}Selección ignorada: %s no es un número válido.${N}\n" "$NSEL"
        continue
      fi

      IDX=$((NSEL-1))
      if [ "$IDX" -ge 0 ] && [ "$IDX" -lt "${#APPS[@]}" ]; then
        SELECCIONADAS+=("${APPS[$IDX]}")
      fi
    done
  fi

  if [ ${#SELECCIONADAS[@]} -eq 0 ]; then
    printf "${R}Nada seleccionado.${N}\n"
    return 1
  fi

  return 0
}

exportar() {

    verificar_pv || return
    seleccionar_apps || return

    local FECHA
    local HOST
    local NOMBRE_BACKUP
    local BACKUP_BASE
    local DESTINO
    local TOTAL
    local ACTUAL

    FECHA=$(date +%Y%m%d-%H%M%S)
    HOST=$(hostname)

    echo
    read -rp "Nombre del backup [$HOST]: " NOMBRE_BACKUP

    NOMBRE_BACKUP=${NOMBRE_BACKUP:-$HOST}
    NOMBRE_BACKUP=$(echo "$NOMBRE_BACKUP" | tr ' /' '--')

    BACKUP_BASE="/root/docker-backups"
    DESTINO="${BACKUP_BASE}/${NOMBRE_BACKUP}-${FECHA}"

    mkdir -p "$DESTINO/apps"
    mkdir -p "$DESTINO/databases"
    mkdir -p "$DESTINO/volumes"
    mkdir -p "$DESTINO/info"

    > "$DESTINO/apps.list"
    > "$DESTINO/apps-paths.list"

    echo
    echo "══════════════════════════════════════════════"
    echo "       CREAR RESPALDO COMPLETO"
    echo "══════════════════════════════════════════════"
    echo
    echo "Destino:"
    echo "$DESTINO"
    echo

    TOTAL=${#SELECCIONADAS[@]}
    ACTUAL=0


    # ════════════════════════════════════════════════════════════════
    # RECORRER STACKS SELECCIONADOS
    # ════════════════════════════════════════════════════════════════

    for APP in "${SELECCIONADAS[@]}"
    do

        ACTUAL=$((ACTUAL + 1))

        local NOMBRE
        local COMPOSE=""
        local COMPOSE_REL=""
        local CONTENEDORES=""
        local SERVICIOS_ACTIVOS=""
        local VOLUMENES=""

        NOMBRE=$(basename "$APP")

        echo
        echo "══════════════════════════════════════════════"
        echo "[$ACTUAL/$TOTAL] RESPALDANDO: $NOMBRE"
        echo "══════════════════════════════════════════════"
        echo

        echo "$NOMBRE" >> "$DESTINO/apps.list"
        echo "$NOMBRE|$APP" >> "$DESTINO/apps-paths.list"

        mkdir -p "$DESTINO/databases/$NOMBRE"
        mkdir -p "$DESTINO/volumes/$NOMBRE"
        mkdir -p "$DESTINO/info/$NOMBRE"


        # ════════════════════════════════════════════════════════════
        # DETECTAR DOCKER COMPOSE
        # ════════════════════════════════════════════════════════════

        for ARCHIVO in \
            "$APP/docker-compose.yml" \
            "$APP/docker-compose.yaml" \
            "$APP/compose.yml" \
            "$APP/compose.yaml"
        do

            if [ -f "$ARCHIVO" ]; then
                COMPOSE="$ARCHIVO"
                COMPOSE_REL=$(basename "$ARCHIVO")
                break
            fi

        done


        echo "Proyecto:"
        echo "  $APP"
        echo

        if [ -n "$COMPOSE" ]; then

            echo "Docker Compose:"
            echo "  $COMPOSE_REL"

        else

            echo "Docker Compose:"
            echo "  No detectado"

        fi

        echo


        # ════════════════════════════════════════════════════════════
        # INFORMACIÓN DEL STACK
        # ════════════════════════════════════════════════════════════

        if [ -n "$COMPOSE" ]; then

            (
                cd "$APP" || exit 1

                docker compose -f "$COMPOSE_REL" ps \
                    > "$DESTINO/info/$NOMBRE/containers.txt" \
                    2>/dev/null || true

                docker compose -f "$COMPOSE_REL" config \
                    > "$DESTINO/info/$NOMBRE/compose-resolved.yml" \
                    2>/dev/null || true

                docker compose -f "$COMPOSE_REL" ps -aq \
                    > "$DESTINO/info/$NOMBRE/container-ids.txt" \
                    2>/dev/null || true
            )

            CONTENEDORES=$(
                cd "$APP" &&
                docker compose -f "$COMPOSE_REL" ps -aq 2>/dev/null
            )

            SERVICIOS_ACTIVOS=$(
                cd "$APP" &&
                docker compose -f "$COMPOSE_REL" ps \
                    --services \
                    --filter status=running \
                    2>/dev/null
            )

            printf '%s\n' "$SERVICIOS_ACTIVOS" \
                > "$DESTINO/info/$NOMBRE/running-services.txt"

        fi


        # ════════════════════════════════════════════════════════════
        # DETECTAR Y RESPALDAR BASES DE DATOS
        # ════════════════════════════════════════════════════════════

        echo
        echo "══════════════════════════════════════════════"
        echo " DETECTANDO BASES DE DATOS"
        echo "══════════════════════════════════════════════"
        echo

        local DB_DETECTADA=0

        for CONTENEDOR in $CONTENEDORES
        do

            [ -z "$CONTENEDOR" ] && continue

            local IMAGEN
            local CNOMBRE

            IMAGEN=$(docker inspect \
                --format '{{.Config.Image}}' \
                "$CONTENEDOR" 2>/dev/null)

            CNOMBRE=$(docker inspect \
                --format '{{.Name}}' \
                "$CONTENEDOR" 2>/dev/null | sed 's#^/##')


            # ────────────────────────────────────────────────────────
            # MYSQL / MARIADB
            # ────────────────────────────────────────────────────────

            if echo "$IMAGEN $CNOMBRE" | grep -Eqi 'mysql|mariadb'
            then

                DB_DETECTADA=1

                echo "[✓] MySQL / MariaDB"
                echo "    Contenedor : $CNOMBRE"
                echo "    Imagen     : $IMAGEN"

                local ROOT_PASS
                local MYSQL_USER
                local MYSQL_PASS
                local ARCHIVO_SQL

                ROOT_PASS=$(
                    docker inspect \
                        --format '{{range .Config.Env}}{{println .}}{{end}}' \
                        "$CONTENEDOR" 2>/dev/null |
                    grep -E '^(MYSQL_ROOT_PASSWORD|MARIADB_ROOT_PASSWORD)=' |
                    head -n1 |
                    cut -d= -f2-
                )

                MYSQL_USER=$(
                    docker inspect \
                        --format '{{range .Config.Env}}{{println .}}{{end}}' \
                        "$CONTENEDOR" 2>/dev/null |
                    grep -E '^(MYSQL_USER|MARIADB_USER)=' |
                    head -n1 |
                    cut -d= -f2-
                )

                MYSQL_PASS=$(
                    docker inspect \
                        --format '{{range .Config.Env}}{{println .}}{{end}}' \
                        "$CONTENEDOR" 2>/dev/null |
                    grep -E '^(MYSQL_PASSWORD|MARIADB_PASSWORD)=' |
                    head -n1 |
                    cut -d= -f2-
                )

                ARCHIVO_SQL="$DESTINO/databases/$NOMBRE/${CNOMBRE}-mysql-all.sql.gz"

                rm -f "$ARCHIVO_SQL"

                echo "    Creando dump SQL..."

                if [ -n "$ROOT_PASS" ]; then

                    if docker exec "$CONTENEDOR" \
                        sh -c 'command -v mariadb-dump >/dev/null 2>&1'
                    then

                        docker exec \
                            -e MYSQL_PWD="$ROOT_PASS" \
                            "$CONTENEDOR" \
                            mariadb-dump \
                            -uroot \
                            --all-databases \
                            --single-transaction \
                            --routines \
                            --events \
                            --triggers \
                            2>/dev/null |
                        gzip > "$ARCHIVO_SQL"

                    elif docker exec "$CONTENEDOR" \
                        sh -c 'command -v mysqldump >/dev/null 2>&1'
                    then

                        docker exec \
                            -e MYSQL_PWD="$ROOT_PASS" \
                            "$CONTENEDOR" \
                            mysqldump \
                            -uroot \
                            --all-databases \
                            --single-transaction \
                            --routines \
                            --events \
                            --triggers \
                            2>/dev/null |
                        gzip > "$ARCHIVO_SQL"

                    fi


                elif [ -n "$MYSQL_USER" ] && [ -n "$MYSQL_PASS" ]; then

                    if docker exec "$CONTENEDOR" \
                        sh -c 'command -v mariadb-dump >/dev/null 2>&1'
                    then

                        docker exec \
                            -e MYSQL_PWD="$MYSQL_PASS" \
                            "$CONTENEDOR" \
                            mariadb-dump \
                            -u"$MYSQL_USER" \
                            --all-databases \
                            --single-transaction \
                            --routines \
                            --events \
                            --triggers \
                            2>/dev/null |
                        gzip > "$ARCHIVO_SQL"

                    elif docker exec "$CONTENEDOR" \
                        sh -c 'command -v mysqldump >/dev/null 2>&1'
                    then

                        docker exec \
                            -e MYSQL_PWD="$MYSQL_PASS" \
                            "$CONTENEDOR" \
                            mysqldump \
                            -u"$MYSQL_USER" \
                            --all-databases \
                            --single-transaction \
                            --routines \
                            --events \
                            --triggers \
                            2>/dev/null |
                        gzip > "$ARCHIVO_SQL"

                    fi

                fi


                if [ -s "$ARCHIVO_SQL" ]; then

                    echo "    ✓ Dump SQL creado"

                else

                    rm -f "$ARCHIVO_SQL"

                    echo "    ⚠ No fue posible crear dump lógico."
                    echo "      Se respaldará igualmente el volumen."

                fi

                echo

            fi


            # ────────────────────────────────────────────────────────
            # POSTGRESQL
            # ────────────────────────────────────────────────────────

            if echo "$IMAGEN $CNOMBRE" | grep -Eqi 'postgres|postgresql'
            then

                DB_DETECTADA=1

                echo "[✓] PostgreSQL"
                echo "    Contenedor : $CNOMBRE"
                echo "    Imagen     : $IMAGEN"

                local POSTGRES_USER
                local POSTGRES_PASSWORD
                local ARCHIVO_POSTGRES

                POSTGRES_USER=$(
                    docker inspect \
                        --format '{{range .Config.Env}}{{println .}}{{end}}' \
                        "$CONTENEDOR" 2>/dev/null |
                    grep '^POSTGRES_USER=' |
                    head -n1 |
                    cut -d= -f2-
                )

                POSTGRES_PASSWORD=$(
                    docker inspect \
                        --format '{{range .Config.Env}}{{println .}}{{end}}' \
                        "$CONTENEDOR" 2>/dev/null |
                    grep '^POSTGRES_PASSWORD=' |
                    head -n1 |
                    cut -d= -f2-
                )

                POSTGRES_USER=${POSTGRES_USER:-postgres}

                ARCHIVO_POSTGRES="$DESTINO/databases/$NOMBRE/${CNOMBRE}-postgres-all.sql.gz"

                rm -f "$ARCHIVO_POSTGRES"

                echo "    Usuario    : $POSTGRES_USER"
                echo "    Creando pg_dumpall..."

                if [ -n "$POSTGRES_PASSWORD" ]; then

                    docker exec \
                        -e PGPASSWORD="$POSTGRES_PASSWORD" \
                        "$CONTENEDOR" \
                        pg_dumpall \
                        -U "$POSTGRES_USER" \
                        2>/dev/null |
                    gzip > "$ARCHIVO_POSTGRES"

                else

                    docker exec \
                        "$CONTENEDOR" \
                        pg_dumpall \
                        -U "$POSTGRES_USER" \
                        2>/dev/null |
                    gzip > "$ARCHIVO_POSTGRES"

                fi


                if [ -s "$ARCHIVO_POSTGRES" ]; then

                    echo "    ✓ Dump PostgreSQL creado"

                else

                    rm -f "$ARCHIVO_POSTGRES"

                    echo "    ⚠ No fue posible crear pg_dumpall."
                    echo "      Se respaldará igualmente el volumen."

                fi

                echo

            fi

        done


        if [ "$DB_DETECTADA" -eq 0 ]; then
            echo "No se detectaron bases MySQL, MariaDB o PostgreSQL."
            echo
        fi


        # ════════════════════════════════════════════════════════════
        # DETECTAR VOLÚMENES DEL STACK
        # ════════════════════════════════════════════════════════════

        for CONTENEDOR in $CONTENEDORES
        do

            docker inspect \
                --format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
                "$CONTENEDOR" \
                2>/dev/null

        done |
        sort -u |
        sed '/^$/d' \
            > "$DESTINO/info/$NOMBRE/volumes.list"


        VOLUMENES=$(cat "$DESTINO/info/$NOMBRE/volumes.list" 2>/dev/null)


        # ════════════════════════════════════════════════════════════
        # DETENER STACK PARA COPIA CONSISTENTE
        # ════════════════════════════════════════════════════════════

        if [ -n "$COMPOSE" ] && [ -n "$SERVICIOS_ACTIVOS" ]; then

            echo
            echo "Deteniendo temporalmente el stack..."
            echo

            (
                cd "$APP" || exit 1
                docker compose -f "$COMPOSE_REL" stop
            )

        fi


        # ════════════════════════════════════════════════════════════
        # RESPALDAR CARPETA COMPLETA
        # ════════════════════════════════════════════════════════════

        echo
        echo "Respaldando archivos del proyecto..."
        echo
        echo " ✓ Frontend"
        echo " ✓ Backend"
        echo " ✓ Docker Compose"
        echo " ✓ Archivo .env"
        echo " ✓ Dockerfile"
        echo " ✓ Configuración"
        echo " ✓ Código fuente"
        echo

        local SIZE_APP

        SIZE_APP=$(du -sb "$APP" 2>/dev/null | awk '{print $1}')
        SIZE_APP=${SIZE_APP:-0}

        tar cf - \
            -C "$(dirname "$APP")" \
            "$NOMBRE" \
        | pv -petrab -s "$SIZE_APP" \
        | gzip \
        > "$DESTINO/apps/${NOMBRE}.tar.gz"


        # ════════════════════════════════════════════════════════════
        # RESPALDAR VOLÚMENES DEL STACK
        # ════════════════════════════════════════════════════════════

        echo
        echo "══════════════════════════════════════════════"
        echo " RESPALDANDO VOLÚMENES DOCKER"
        echo "══════════════════════════════════════════════"
        echo

        if [ -n "$VOLUMENES" ]; then

            while IFS= read -r VOLUMEN
            do

                [ -z "$VOLUMEN" ] && continue

                local MOUNTPOINT
                local SIZE_VOL

                MOUNTPOINT=$(docker volume inspect \
                    "$VOLUMEN" \
                    --format '{{.Mountpoint}}' \
                    2>/dev/null)

                if [ -z "$MOUNTPOINT" ] || [ ! -d "$MOUNTPOINT" ]; then

                    echo " ⚠ No se pudo acceder al volumen: $VOLUMEN"
                    continue

                fi

                echo " → $VOLUMEN"

                SIZE_VOL=$(du -sb "$MOUNTPOINT" 2>/dev/null | awk '{print $1}')
                SIZE_VOL=${SIZE_VOL:-0}

                tar cf - \
                    -C "$MOUNTPOINT" \
                    . \
                | pv -petrab -s "$SIZE_VOL" \
                | gzip \
                > "$DESTINO/volumes/$NOMBRE/${VOLUMEN}.tar.gz"

            done < "$DESTINO/info/$NOMBRE/volumes.list"

        else

            echo "No se detectaron volúmenes Docker."

        fi


        # ════════════════════════════════════════════════════════════
        # VOLVER A LEVANTAR STACK
        # ════════════════════════════════════════════════════════════

        if [ -n "$COMPOSE" ] && [ -n "$SERVICIOS_ACTIVOS" ]; then

            echo
            echo "Reiniciando servicios..."
            echo

            (
                cd "$APP" || exit 1

                while IFS= read -r SERVICIO
                do
                    [ -z "$SERVICIO" ] && continue

                    docker compose \
                        -f "$COMPOSE_REL" \
                        start "$SERVICIO"

                done <<< "$SERVICIOS_ACTIVOS"
            )

        fi

        echo
        echo "✓ $NOMBRE respaldado correctamente."
        echo

    done


    # ════════════════════════════════════════════════════════════════
    # CONFIGURACIÓN GENERAL DOCKER
    # ════════════════════════════════════════════════════════════════

    echo
    echo "══════════════════════════════════════════════"
    echo " GUARDANDO CONFIGURACIÓN DOCKER"
    echo "══════════════════════════════════════════════"
    echo

    if [ -d /etc/docker ]; then

        tar czf \
            "$DESTINO/docker-config.tar.gz" \
            -C / \
            etc/docker

        echo "✓ /etc/docker"

    else

        echo "No existe /etc/docker"

    fi


    # ════════════════════════════════════════════════════════════════
    # LET'S ENCRYPT
    # ════════════════════════════════════════════════════════════════

    echo
    echo "══════════════════════════════════════════════"
    echo " GUARDANDO CERTIFICADOS SSL"
    echo "══════════════════════════════════════════════"
    echo

    if [ -d /etc/letsencrypt ]; then

        tar czf \
            "$DESTINO/letsencrypt.tar.gz" \
            -C / \
            etc/letsencrypt

        echo "✓ /etc/letsencrypt"

    else

        echo "No existe /etc/letsencrypt"

    fi


    # ════════════════════════════════════════════════════════════════
    # INFORMACIÓN DEL SERVIDOR
    # ════════════════════════════════════════════════════════════════

    docker network ls \
        > "$DESTINO/info/docker-networks.txt" \
        2>/dev/null || true

    docker volume ls \
        > "$DESTINO/info/docker-volumes.txt" \
        2>/dev/null || true

    docker ps -a \
        > "$DESTINO/info/docker-containers.txt" \
        2>/dev/null || true

    docker images \
        > "$DESTINO/info/docker-images.txt" \
        2>/dev/null || true

    docker version \
        > "$DESTINO/info/docker-version.txt" \
        2>/dev/null || true

    docker compose version \
        > "$DESTINO/info/docker-compose-version.txt" \
        2>/dev/null || true

    uname -a \
        > "$DESTINO/info/system-info.txt" \
        2>/dev/null || true

    hostname \
        > "$DESTINO/info/hostname.txt" \
        2>/dev/null || true

    date \
        > "$DESTINO/info/backup-date.txt" \
        2>/dev/null || true


    echo
    echo "══════════════════════════════════════════════"
    echo "       RESPALDO COMPLETADO"
    echo "══════════════════════════════════════════════"
    echo

    echo "Ubicación:"
    echo "$DESTINO"
    echo

    echo "Tamaño final:"
    du -sh "$DESTINO"
    echo
}
importar() {

    local BACKUP_BASE="/root/docker-backups"
    local RESPALDO
    local OPCION
    local CONFIRMAR

    # ════════════════════════════════════════════════════════════════
    # VERIFICAR BACKUPS
    # ════════════════════════════════════════════════════════════════

    if [ ! -d "$BACKUP_BASE" ]; then

        echo
        echo "No existe el directorio:"
        echo "$BACKUP_BASE"
        echo
        return 1

    fi


    mapfile -t BACKUPS < <(
        find "$BACKUP_BASE" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -printf '%f\n' \
            2>/dev/null |
        sort -r
    )


    if [ "${#BACKUPS[@]}" -eq 0 ]; then

        echo
        echo "No existen respaldos disponibles."
        echo
        return 1

    fi


    # ════════════════════════════════════════════════════════════════
    # MOSTRAR RESPALDOS
    # ════════════════════════════════════════════════════════════════

    echo
    echo "══════════════════════════════════════════════"
    echo "       RESPALDOS DISPONIBLES"
    echo "══════════════════════════════════════════════"
    echo

    local I=1

    for BACKUP in "${BACKUPS[@]}"
    do

        printf "[%02d] %s\n" "$I" "$BACKUP"

        I=$((I + 1))

    done

    echo
    echo "[0] Cancelar"
    echo

    read -rp "Seleccione respaldo: " OPCION


    if [ "$OPCION" = "0" ]; then
        return
    fi


    if ! [[ "$OPCION" =~ ^[0-9]+$ ]]; then

        echo
        echo "Opción inválida."
        return 1

    fi


    if [ "$OPCION" -lt 1 ] || \
       [ "$OPCION" -gt "${#BACKUPS[@]}" ]; then

        echo
        echo "Opción inválida."
        return 1

    fi


    RESPALDO="$BACKUP_BASE/${BACKUPS[$((OPCION - 1))]}"


    # ════════════════════════════════════════════════════════════════
    # VALIDAR BACKUP
    # ════════════════════════════════════════════════════════════════

    if [ ! -f "$RESPALDO/apps.list" ]; then

        echo
        echo "ERROR:"
        echo "El respaldo no contiene apps.list"
        echo
        return 1

    fi


    echo
    echo "══════════════════════════════════════════════"
    echo "       RESTAURAR RESPALDO COMPLETO"
    echo "══════════════════════════════════════════════"
    echo

    echo "Respaldo:"
    echo "$RESPALDO"
    echo

    echo "Stacks incluidos:"
    echo

    nl -w2 -s') ' "$RESPALDO/apps.list"

    echo

    read -rp "¿Continuar con la restauración? [s/N]: " CONFIRMAR


    case "$CONFIRMAR" in

        s|S|si|SI|Si)
            ;;

        *)
            echo
            echo "Restauración cancelada."
            return
            ;;

    esac


    # ════════════════════════════════════════════════════════════════
    # RESTAURAR STACKS
    # ════════════════════════════════════════════════════════════════

    while IFS= read -r NOMBRE
    do

        [ -z "$NOMBRE" ] && continue

        local DESTINO_APP="/opt/$NOMBRE"
        local ARCHIVO_APP="$RESPALDO/apps/${NOMBRE}.tar.gz"
        local COMPOSE=""
        local COMPOSE_REL=""
        local LISTA_VOL="$RESPALDO/info/$NOMBRE/volumes.list"


        # Intentar obtener la ruta original
        if [ -f "$RESPALDO/apps-paths.list" ]; then

            local RUTA_ORIGINAL

            RUTA_ORIGINAL=$(
                grep "^${NOMBRE}|" \
                    "$RESPALDO/apps-paths.list" |
                head -n1 |
                cut -d'|' -f2-
            )

            if [ -n "$RUTA_ORIGINAL" ]; then
                DESTINO_APP="$RUTA_ORIGINAL"
            fi

        fi


        echo
        echo "══════════════════════════════════════════════"
        echo " RESTAURANDO: $NOMBRE"
        echo "══════════════════════════════════════════════"
        echo

        echo "Destino:"
        echo "$DESTINO_APP"
        echo


        # ════════════════════════════════════════════════════════════
        # DETENER STACK EXISTENTE
        # ════════════════════════════════════════════════════════════

        if [ -d "$DESTINO_APP" ]; then

            for ARCHIVO in \
                "$DESTINO_APP/docker-compose.yml" \
                "$DESTINO_APP/docker-compose.yaml" \
                "$DESTINO_APP/compose.yml" \
                "$DESTINO_APP/compose.yaml"
            do

                if [ -f "$ARCHIVO" ]; then

                    COMPOSE="$ARCHIVO"
                    COMPOSE_REL=$(basename "$ARCHIVO")
                    break

                fi

            done


            if [ -n "$COMPOSE" ]; then

                echo "Deteniendo stack existente..."
                echo

                (
                    cd "$DESTINO_APP" || exit 1

                    docker compose \
                        -f "$COMPOSE_REL" \
                        down
                ) 2>/dev/null || true

            fi

        fi


        # ════════════════════════════════════════════════════════════
        # RESPALDAR INSTALACIÓN ACTUAL ANTES DE SOBRESCRIBIR
        # ════════════════════════════════════════════════════════════

        if [ -d "$DESTINO_APP" ]; then

            local ANTERIOR

            ANTERIOR="${DESTINO_APP}.antes-restauracion-$(date +%Y%m%d-%H%M%S)"

            echo "Guardando instalación actual:"
            echo "$ANTERIOR"
            echo

            mv "$DESTINO_APP" "$ANTERIOR"

        fi


        # ════════════════════════════════════════════════════════════
        # RESTAURAR FRONTEND / BACKEND / COMPOSE / ENV
        # ════════════════════════════════════════════════════════════

        if [ ! -f "$ARCHIVO_APP" ]; then

            echo "ERROR:"
            echo "No existe:"
            echo "$ARCHIVO_APP"
            echo

            continue

        fi


        echo "Restaurando archivos del proyecto..."
        echo

        mkdir -p "$(dirname "$DESTINO_APP")"


        # El tar contiene la carpeta con el nombre del stack
        tar xzf \
            "$ARCHIVO_APP" \
            -C "$(dirname "$DESTINO_APP")"


        echo "✓ Frontend"
        echo "✓ Backend"
        echo "✓ Docker Compose"
        echo "✓ Archivo .env"
        echo "✓ Configuración"
        echo


        # ════════════════════════════════════════════════════════════
        # DETECTAR COMPOSE RESTAURADO
        # ════════════════════════════════════════════════════════════

        COMPOSE=""
        COMPOSE_REL=""

        for ARCHIVO in \
            "$DESTINO_APP/docker-compose.yml" \
            "$DESTINO_APP/docker-compose.yaml" \
            "$DESTINO_APP/compose.yml" \
            "$DESTINO_APP/compose.yaml"
        do

            if [ -f "$ARCHIVO" ]; then

                COMPOSE="$ARCHIVO"
                COMPOSE_REL=$(basename "$ARCHIVO")
                break

            fi

        done


        # ════════════════════════════════════════════════════════════
        # CREAR VOLÚMENES QUE DEFINE COMPOSE
        # ════════════════════════════════════════════════════════════

        if [ -n "$COMPOSE" ]; then

            echo
            echo "Preparando volúmenes Docker..."
            echo

            (
                cd "$DESTINO_APP" || exit 1

                # Crea redes y volúmenes sin necesidad
                # de dejar permanentemente los servicios ejecutándose.
                docker compose \
                    -f "$COMPOSE_REL" \
                    create \
                    2>/dev/null || true
            )

        fi


        # ════════════════════════════════════════════════════════════
        # RESTAURAR VOLÚMENES
        # ════════════════════════════════════════════════════════════

        echo
        echo "══════════════════════════════════════════════"
        echo " RESTAURANDO VOLÚMENES"
        echo "══════════════════════════════════════════════"
        echo


        if [ -f "$LISTA_VOL" ]; then

            while IFS= read -r VOLUMEN
            do

                [ -z "$VOLUMEN" ] && continue

                local ARCHIVO_VOL
                local MOUNTPOINT

                ARCHIVO_VOL="$RESPALDO/volumes/$NOMBRE/${VOLUMEN}.tar.gz"


                if [ ! -f "$ARCHIVO_VOL" ]; then

                    echo "⚠ No existe backup del volumen:"
                    echo "  $VOLUMEN"
                    continue

                fi


                if ! docker volume inspect "$VOLUMEN" >/dev/null 2>&1; then

                    echo "Creando volumen:"
                    echo "  $VOLUMEN"

                    docker volume create "$VOLUMEN" >/dev/null

                fi


                MOUNTPOINT=$(docker volume inspect \
                    "$VOLUMEN" \
                    --format '{{.Mountpoint}}' \
                    2>/dev/null)


                if [ -z "$MOUNTPOINT" ] || [ ! -d "$MOUNTPOINT" ]; then

                    echo "⚠ No se pudo localizar:"
                    echo "  $VOLUMEN"
                    continue

                fi


                echo "Restaurando:"
                echo "  $VOLUMEN"


                # Limpiar contenido actual
                find "$MOUNTPOINT" \
                    -mindepth 1 \
                    -maxdepth 1 \
                    -exec rm -rf -- {} +


                # Restaurar contenido
                tar xzf \
                    "$ARCHIVO_VOL" \
                    -C "$MOUNTPOINT"


                echo "✓ $VOLUMEN"
                echo

            done < "$LISTA_VOL"

        else

            echo "No existe lista de volúmenes para este stack."

        fi


        # ════════════════════════════════════════════════════════════
        # MOSTRAR DUMPS DISPONIBLES
        # ════════════════════════════════════════════════════════════

        if [ -d "$RESPALDO/databases/$NOMBRE" ]; then

            local NUM_DUMPS

            NUM_DUMPS=$(
                find "$RESPALDO/databases/$NOMBRE" \
                    -type f \
                    -name '*.sql.gz' \
                    2>/dev/null |
                wc -l
            )


            if [ "$NUM_DUMPS" -gt 0 ]; then

                echo
                echo "Copias lógicas de base de datos disponibles:"
                echo

                find "$RESPALDO/databases/$NOMBRE" \
                    -type f \
                    -name '*.sql.gz' \
                    -printf '  ✓ %f\n'

                echo
                echo "La restauración completa utiliza los"
                echo "volúmenes Docker originales."
                echo
                echo "Los .sql.gz quedan como respaldo adicional."

            fi

        fi


        # ════════════════════════════════════════════════════════════
        # DESCARGAR / CONSTRUIR / INICIAR
        # ════════════════════════════════════════════════════════════

        if [ -n "$COMPOSE" ]; then

            echo
            echo "══════════════════════════════════════════════"
            echo " PREPARANDO IMÁGENES DOCKER"
            echo "══════════════════════════════════════════════"
            echo

            echo "Las imágenes que no existan serán descargadas."
            echo "Las imágenes con build: serán reconstruidas."
            echo


            (
                cd "$DESTINO_APP" || exit 1


                # Descargar imágenes remotas.
                # Si existen servicios build:, pull puede avisar
                # que no tiene imagen; eso no impide continuar.
                docker compose \
                    -f "$COMPOSE_REL" \
                    pull \
                    --ignore-buildable \
                    2>/dev/null || true


                echo
                echo "Construyendo imágenes locales..."
                echo

                docker compose \
                    -f "$COMPOSE_REL" \
                    build \
                    2>/dev/null || true


                echo
                echo "Iniciando stack..."
                echo

                docker compose \
                    -f "$COMPOSE_REL" \
                    up -d \
                    --build
            )


            echo
            echo "Esperando verificación inicial..."
            sleep 3

            echo
            echo "Estado:"
            echo

            (
                cd "$DESTINO_APP" || exit 1

                docker compose \
                    -f "$COMPOSE_REL" \
                    ps
            )

        else

            echo
            echo "⚠ No se encontró Docker Compose."
            echo "  Los archivos y volúmenes fueron restaurados,"
            echo "  pero el stack no pudo iniciarse automáticamente."

        fi


        echo
        echo "══════════════════════════════════════════════"
        echo " ✓ $NOMBRE RESTAURADO"
        echo "══════════════════════════════════════════════"
        echo

    done < "$RESPALDO/apps.list"


    # ════════════════════════════════════════════════════════════════
    # CONFIGURACIÓN DOCKER
    # ════════════════════════════════════════════════════════════════

    if [ -f "$RESPALDO/docker-config.tar.gz" ]; then

        echo
        echo "Existe respaldo de /etc/docker."
        echo

        read -rp "¿Restaurar configuración Docker? [s/N]: " RESP


        case "$RESP" in

            s|S|si|SI|Si)

                local DOCKER_ANTERIOR

                DOCKER_ANTERIOR="/root/docker-config-anterior-$(date +%Y%m%d-%H%M%S)"

                mkdir -p "$DOCKER_ANTERIOR"


                if [ -d /etc/docker ]; then

                    cp -a \
                        /etc/docker/. \
                        "$DOCKER_ANTERIOR/" \
                        2>/dev/null || true

                fi


                tar xzf \
                    "$RESPALDO/docker-config.tar.gz" \
                    -C /


                echo
                echo "✓ Configuración Docker restaurada."
                echo

                ;;

        esac

    fi


    # ════════════════════════════════════════════════════════════════
    # LET'S ENCRYPT
    # ════════════════════════════════════════════════════════════════

    if [ -f "$RESPALDO/letsencrypt.tar.gz" ]; then

        echo
        echo "Existe respaldo de certificados Let's Encrypt."
        echo

        read -rp "¿Restaurar certificados SSL? [s/N]: " RESP


        case "$RESP" in

            s|S|si|SI|Si)

                if [ -d /etc/letsencrypt ]; then

                    mv \
                        /etc/letsencrypt \
                        "/etc/letsencrypt.antes-restauracion-$(date +%Y%m%d-%H%M%S)"

                fi


                tar xzf \
                    "$RESPALDO/letsencrypt.tar.gz" \
                    -C /


                echo
                echo "✓ Certificados SSL restaurados."
                echo

                ;;

        esac

    fi


    echo
    echo "══════════════════════════════════════════════"
    echo "       RESTAURACIÓN COMPLETADA"
    echo "══════════════════════════════════════════════"
    echo

    echo "Contenedores actuales:"
    echo

    docker ps \
        --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

    echo
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
  exportar || { printf "${R}Actualización cancelada: falló el respaldo previo.${N}\n"; return 1; }

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
  printf "  ${Y}11)${G} Crear respaldo completo (frontend, backend, DB y volúmenes)${N}\n"
  printf "  ${Y}12)${G} Restaurar respaldo completo${N}\n"
  printf "  ${Y}0)${C} Salir${N}\n\n"
  read -rp 'Selecciona una opción: ' o
  if [[ "$o" == 8 ]]; then repair_database; pause; continue; fi
  case "$o" in 1) dependencies; pause;; 2) install_app; pause;; 3) services;; 4) port; pause;; 5) title; show_url; pause;; 6) users;; 7) uninstall_app; pause;; 9) show_initial_credentials; pause;; 10) update_app; pause;; 11) exportar; pause;; 12) importar; pause;; 0) exit 0;; *) printf "${R}Opción inválida.${N}\n"; sleep 1;; esac
done
