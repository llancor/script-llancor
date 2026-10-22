#!/usr/bin/env bash
# BastControl HHRR Offline v5.3.1 - instala/actualiza desde GitHub (eligiendo un ZIP) o desde esta carpeta; respaldo opcional antes de actualizar offline
set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="${BASTCONTROL_REPO_URL:-https://github.com/llancor/Bast-Control-Acceso.git}"
DEFAULT_INSTALL_ROOT="/opt/bast-control"
DEFAULT_HTTP_PORT="8082"
INSTALL_ROOT="${BASTCONTROL_INSTALL_DIR:-$DEFAULT_INSTALL_ROOT}"
PROJECT_SUBDIR="Bast-Control"
APP_DIR="$SCRIPT_DIR"
PRISMA_SCHEMA_ENGINE_SHA256="cf5f99b0e589976a814655f4ed9c2f11f8e124a3ac2dabb8be8142c7784695d4"
PRISMA_QUERY_ENGINE_SHA256="00b82195745fa317411a0a7793769b3a53e631a30d82e27772ca13622b0b7a8e"

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
load_caddy_manager(){ local f; for f in "$SCRIPT_DIR/caddy-manager.sh" "$APP_DIR/caddy-manager.sh"; do [[ -f "$f" ]] && { . "$f"; return 0; }; done; printf "No se encontro caddy-manager.sh.\n"; return 1; }
load_caddy_manager >/dev/null 2>&1 || true
caddy_configure_action(){ load_caddy_manager && caddy_configure; }
caddy_remove_action(){ load_caddy_manager && caddy_remove; }
caddy_sync_action(){ load_caddy_manager && caddy_sync_route; }
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

resolve_prisma_engine_dir(){
  local source_dir="$1" candidate
  for candidate in \
    "${BASTCONTROL_PRISMA_ENGINES_DIR:-}" \
    "$source_dir/backend/prisma-engines" \
    "$source_dir/offline/prisma-engines" \
    "$(dirname "$source_dir")/offline/prisma-engines"; do
    [[ -n "$candidate" ]] || continue
    if [[ -f "$candidate/schema-engine.gz" && -f "$candidate/libquery_engine.so.node.gz" ]]; then
      realpath -m "$candidate"
      return 0
    fi
  done
  return 1
}

verify_prisma_offline_engines(){
  local engine_dir="$1"
  (
    cd "$engine_dir" || exit 1
    printf '%s  %s\n' "$PRISMA_SCHEMA_ENGINE_SHA256" 'schema-engine.gz' | sha256sum -c - >/dev/null \
      && printf '%s  %s\n' "$PRISMA_QUERY_ENGINE_SHA256" 'libquery_engine.so.node.gz' | sha256sum -c - >/dev/null
  )
}

stage_prisma_offline_engines(){
  local engine_dir="$1" target_root="$2" target_dir owner group
  target_dir="$target_root/backend/prisma-engines"
  owner="$(id -un)"
  group="$(id -gn)"
  root install -d -o "$owner" -g "$group" "$target_dir" || return 1
  if [[ "$(realpath -m "$engine_dir")" != "$(realpath -m "$target_dir")" ]]; then
    root install -m 0644 -o "$owner" -g "$group" "$engine_dir/schema-engine.gz" "$target_dir/schema-engine.gz" || return 1
    root install -m 0644 -o "$owner" -g "$group" "$engine_dir/libquery_engine.so.node.gz" "$target_dir/libquery_engine.so.node.gz" || return 1
  fi
  printf "${G}Motores Prisma offline preparados desde: %s${N}\n" "$engine_dir"
}

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

# ---------------------------------------------------------------------------
# Actualizaciones en ZIP
#
# Cada actualización se sube a GitHub como un archivo .zip dentro de la carpeta
# ZIP_SUBDIR del repositorio. Al instalar o actualizar, el script consulta la API
# de GitHub (sin clonar el repositorio ni bajar su historial), muestra los últimos
# ZIP por fecha de subida, propone el más reciente y descarga SOLO el que se elija.
# Dentro del ZIP puede venir la carpeta "Bast-Control" o el proyecto directamente:
# se usa la carpeta que contiene docker-compose.yml.
#
# Variables opcionales:
#   BASTCONTROL_ZIP_DIR    carpeta del repositorio con los ZIP (por defecto: Bast-Control, la misma del proyecto).
#                          Solo cuentan los .zip que estén directamente en esa carpeta, no en subcarpetas.
#   BASTCONTROL_BRANCH     rama del repositorio (por defecto: main)
#   BASTCONTROL_ZIP_COUNT  cuántos ZIP mostrar (por defecto: 5)
#   BASTCONTROL_ZIP        nombre exacto de un ZIP para instalarlo sin preguntar
# ---------------------------------------------------------------------------
ZIP_SUBDIR="${BASTCONTROL_ZIP_DIR:-$PROJECT_SUBDIR}"
ZIP_BRANCH="${BASTCONTROL_BRANCH:-main}"
ZIP_LIST_COUNT="${BASTCONTROL_ZIP_COUNT:-5}"
ZIP_MAX_FECHAS=40            # como máximo se consultan las fechas de 40 ZIP (los de nombre más reciente)
GH_API="${BASTCONTROL_API_URL:-https://api.github.com}"
GH_JSON='application/vnd.github+json'
GH_RAW='application/vnd.github.raw+json'
TTY_IN="${BASTCONTROL_TTY:-/dev/tty}"
ZIP_MARK_FILE=".zip_instalado"
GH_OWNER=""; GH_REPO=""; GH_HTTP=0; GH_CFG=""
ZIP_NAMES=(); ZIP_DATES=(); ZIP_SIZES=(); ZIP_SELECTED=""; ZIP_SELECTED_DATE=""

# Filtros de jq (JSON de la API de GitHub).
JQ_LISTA='.[]? | select(.type=="file" and (.name|ascii_downcase|endswith(".zip"))) | [.path,(.size|tostring)] | @tsv'
JQ_FECHA='.[0].commit.committer.date // empty'
JQ_MENSAJE='.message? // empty'

# unzip devuelve 1 cuando solo hay avisos (por ejemplo, ZIP creados en Windows con "\" en las
# rutas): el contenido es válido. Solo los códigos 2 o más son errores reales.
unzip_lenient(){ unzip "$@"; local rc=$?; (( rc <= 1 )); }

human_size(){
  local bytes="${1:-0}"
  if (( bytes >= 1048576 )); then printf '%d.%d MB' $((bytes/1048576)) $(( (bytes%1048576)*10/1048576 ))
  else printf '%d KB' $(( (bytes+1023)/1024 )); fi
}

# Codifica una ruta para la URL (deja pasar "/").
urlenc(){
  local LC_ALL=C s="$1" out="" c i
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in [a-zA-Z0-9.~_/-]) out+="$c";; *) out+="$(printf '%%%02X' "'$c")";; esac
  done
  printf '%s' "$out"
}

# Usuario y token se pasan a curl por un archivo temporal (modo 600) dentro de la carpeta de trabajo,
# no por la línea de comandos (así no se ven en la lista de procesos) ni dentro de una URL.
gh_config(){
  GH_CFG="$1/curl.cfg"
  ( umask 077; printf 'user = "%s:%s"\nheader = "X-GitHub-Api-Version: 2022-11-28"\nheader = "User-Agent: bastcontrol-installer"\n' "$2" "$3" >"$GH_CFG" )
}

# Consulta a la API de GitHub: gh_get RUTA ARCHIVO_SALIDA ACCEPT [opciones de curl...]
# Deja el código HTTP en GH_HTTP (0 = no hubo conexión).
gh_get(){
  local path="$1" out="$2" accept="$3"; shift 3
  local -a args=(-L --connect-timeout 15 --max-time "${GH_TIMEOUT:-60}" -K "$GH_CFG" -H "Accept: $accept" -o "$out" -w '%{http_code}' "$@" "$GH_API$path")
  if [[ "${GH_PROGRESS:-}" == 1 ]]; then
    GH_HTTP="$(curl -# "${args[@]}")" || true                 # la barra de avance se queda en pantalla
  else
    GH_HTTP="$(curl -sS "${args[@]}" 2>"$out.err")" || true   # los errores de curl se guardan para explicarlos
  fi
  [[ "$GH_HTTP" =~ ^[0-9]{3}$ && "$GH_HTTP" != 000 ]] || GH_HTTP=0
}

# Explica en claro por qué falló una consulta (el detalle de GitHub va entre paréntesis).
gh_explain(){
  local detail=""
  [[ -s "$1" ]] && detail="$(jq -r "$JQ_MENSAJE" "$1" 2>/dev/null | head -c 160)"
  [[ -n "$detail" ]] && detail=" (GitHub dice: $detail)"
  case "$GH_HTTP" in
    0)   printf "${R}No hubo conexión con GitHub. Revisa internet o DNS.%s${N}\n" "$(head -c 160 "$1.err" 2>/dev/null | sed 's/^/ /')";;
    401) printf "${R}GitHub rechazó el usuario o el token (401). Revisa que el token sea válido y no haya vencido.%s${N}\n" "$detail";;
    403) printf "${R}GitHub negó el acceso (403): el token no tiene permiso de lectura sobre el repositorio, o se alcanzó el límite de consultas.%s${N}\n" "$detail";;
    404) printf "${R}No se encontró el repositorio o la carpeta '%s' (404). Revisa que exista en la rama '%s' y que el token tenga acceso a %s/%s.%s${N}\n" "$ZIP_SUBDIR" "$ZIP_BRANCH" "$GH_OWNER" "$GH_REPO" "$detail";;
    *)   printf "${R}GitHub respondió con el código %s.%s${N}\n" "$GH_HTTP" "$detail";;
  esac
}

# Llena ZIP_NAMES / ZIP_DATES / ZIP_SIZES con los ZIP más recientes de ZIP_SUBDIR (el primero es el más nuevo).
# La fecha es la de la última subida del archivo. Devuelve 0 si hay ZIP, 1 si no hay ninguno, 2 si GitHub falló.
zip_list_repo(){
  local work="$1" listing="$1/listado.json" fechas="$1/fechas" i path size iso line when
  local -a rows=() ordered=()
  ZIP_NAMES=(); ZIP_DATES=(); ZIP_SIZES=()

  printf "  Leyendo la carpeta '%s' de GitHub... " "$ZIP_SUBDIR"
  gh_get "/repos/$GH_OWNER/$GH_REPO/contents/$(urlenc "$ZIP_SUBDIR")?ref=$(urlenc "$ZIP_BRANCH")" "$listing" "$GH_JSON"
  if [[ "$GH_HTTP" != 200 ]]; then printf '\n'; gh_explain "$listing"; return 2; fi
  mapfile -t rows < <(jq -r "$JQ_LISTA" "$listing" 2>/dev/null | sort -r)
  printf "%d ZIP encontrados.\n" "${#rows[@]}"
  (( ${#rows[@]} > 0 )) || return 1
  if (( ${#rows[@]} > ZIP_MAX_FECHAS )); then
    printf "  Hay muchos ZIP: se revisan las fechas de los %d de nombre más reciente.\n" "$ZIP_MAX_FECHAS"
    rows=("${rows[@]:0:ZIP_MAX_FECHAS}")
  fi

  # Fecha de la última subida de cada ZIP: consultas en paralelo (de 6 en 6).
  printf "  Consultando las fechas... "
  mkdir -p "$fechas"
  local -a pids=()
  for i in "${!rows[@]}"; do
    path="${rows[$i]%%$'\t'*}"
    ( gh_get "/repos/$GH_OWNER/$GH_REPO/commits" "$fechas/$i.json" "$GH_JSON" -G --data-urlencode "sha=$ZIP_BRANCH" --data-urlencode "path=$path" --data-urlencode "per_page=1" ) &
    pids+=($!)
    if (( (i+1) % 6 == 0 )); then wait "${pids[@]}"; pids=(); fi   # espera solo a sus consultas, no a otros procesos en segundo plano
  done
  (( ${#pids[@]} == 0 )) || wait "${pids[@]}"
  printf "listo.\n"

  for i in "${!rows[@]}"; do
    path="${rows[$i]%%$'\t'*}"; size="${rows[$i]#*$'\t'}"
    iso="$(jq -r "$JQ_FECHA" "$fechas/$i.json" 2>/dev/null)"
    [[ -n "$iso" ]] || iso="0000-00-00T00:00:00Z"
    ordered+=("$iso"$'\t'"$path"$'\t'"$size")
  done
  while IFS=$'\t' read -r iso path size; do
    if [[ "$iso" == 0000-* ]]; then when="sin fecha"; else when="$(date -d "$iso" '+%d-%m-%Y %H:%M' 2>/dev/null || echo "${iso:0:16}")"; fi
    ZIP_NAMES+=("$path"); ZIP_DATES+=("$when"); ZIP_SIZES+=("$size")
    (( ${#ZIP_NAMES[@]} >= ZIP_LIST_COUNT )) && break
  done < <(printf '%s\n' "${ordered[@]}" | sort -r)
  (( ${#ZIP_NAMES[@]} > 0 ))
}

# Muestra la lista numerada y deja elegir. Enter = el más reciente. Deja el elegido en ZIP_SELECTED.
zip_choose(){
  local i choice name installed=""
  [[ -f "$INSTALL_ROOT/$ZIP_MARK_FILE" ]] && installed="$(sed -n '1p' "$INSTALL_ROOT/$ZIP_MARK_FILE" 2>/dev/null)"
  printf "\n${B}Actualizaciones disponibles (las %d más recientes):${N}\n" "${#ZIP_NAMES[@]}"
  [[ -n "$installed" ]] && printf "Instalada actualmente: ${C}%s${N}\n" "$installed"
  printf '\n'
  for i in "${!ZIP_NAMES[@]}"; do
    name="${ZIP_NAMES[$i]##*/}"
    printf "  ${Y}%d)${N} %-46s %s  %9s" "$((i+1))" "$name" "${ZIP_DATES[$i]}" "$(human_size "${ZIP_SIZES[$i]}")"
    [[ $i -eq 0 ]] && printf " ${G}← más reciente${N}"
    [[ -n "$installed" && "$name" == "$installed" ]] && printf " ${C}(instalada)${N}"
    printf '\n'
  done
  printf "  ${Y}0)${N} Cancelar\n\n"
  while true; do
    read -rp "Elige el ZIP a instalar [1]: " choice <"$TTY_IN"
    choice="${choice:-1}"
    [[ "$choice" == 0 ]] && return 1
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ZIP_NAMES[@]} )); then
      ZIP_SELECTED="${ZIP_NAMES[$((choice-1))]}"
      ZIP_SELECTED_DATE="${ZIP_DATES[$((choice-1))]}"
      return 0
    fi
    printf "${R}Opción inválida. Escribe un número de la lista o 0 para cancelar.${N}\n"
  done
}

# Descarga solo el ZIP elegido (con barra de avance) y comprueba que sea válido.
zip_fetch(){
  local path="$1" out="$2"
  printf "\n${B}Descargando %s...${N}\n" "${path##*/}"
  GH_PROGRESS=1 GH_TIMEOUT=1800 gh_get "/repos/$GH_OWNER/$GH_REPO/contents/$(urlenc "$path")?ref=$(urlenc "$ZIP_BRANCH")" "$out" "$GH_RAW"
  if [[ "$GH_HTTP" != 200 ]]; then gh_explain "$out"; return 1; fi
  [[ -s "$out" ]] || { printf "${R}El archivo descargado está vacío.${N}\n"; return 1; }
  if head -c 200 "$out" | grep -q 'git-lfs'; then
    printf "${R}El ZIP está guardado con Git LFS y no se puede descargar así. Súbelo como archivo normal (máx. 100 MB).${N}\n"; return 1
  fi
  unzip_lenient -tq "$out" >/dev/null 2>&1 || { printf "${R}El archivo descargado no es un ZIP válido o está dañado.${N}\n"; return 1; }
}

# Devuelve la carpeta del proyecto dentro del ZIP extraído (la más cercana a la raíz con docker-compose.yml).
zip_find_project(){
  local compose
  compose="$(find "$1" -maxdepth 4 -type f -name docker-compose.yml -not -path '*/node_modules/*' 2>/dev/null | awk '{print length, $0}' | sort -n | head -n1 | cut -d' ' -f2-)"
  [[ -n "$compose" ]] && dirname -- "$compose"
}

download_project(){
  local work zip_file extract_dir source_dir wanted i rc
  local -a missing=()

  title
  printf "${B}Descargando actualización de BastControl desde GitHub...${N}\n\n"

  has curl  || missing+=(curl ca-certificates)
  has jq    || missing+=(jq)
  has rsync || missing+=(rsync)
  has unzip || missing+=(unzip)
  if (( ${#missing[@]} > 0 )); then
    root apt-get update || return 1
    root apt-get install -y "${missing[@]}" || return 1
  fi

  if [[ ! "$REPO_URL" =~ ^https://github\.com/([^/]+)/([^/]+)$ ]]; then
    printf "${R}REPO_URL debe ser una URL HTTPS de GitHub (https://github.com/usuario/repositorio).${N}\n"
    return 1
  fi
  GH_OWNER="${BASH_REMATCH[1]}"; GH_REPO="${BASH_REMATCH[2]%.git}"

  if [[ -e "$INSTALL_ROOT" && ! -d "$INSTALL_ROOT" ]]; then
    printf "${R}La ruta $INSTALL_ROOT existe pero no es una carpeta.${N}\n"
    return 1
  fi

  root install -d -o "$(id -un)" -g "$(id -gn)" "$INSTALL_ROOT" || return 1
  work="$(mktemp -d /tmp/bastcontrol.XXXXXX)" || return 1
  zip_file="$work/actualizacion.zip"; extract_dir="$work/contenido"

  printf "${C}${B}Autenticación GitHub${N}\n\n"
  local github_user github_token
  read -rp "Usuario GitHub: " github_user <"$TTY_IN"
  read -rsp "Token GitHub (PAT): " github_token <"$TTY_IN"
  printf '\n'

  if [[ -z "$github_user" || -z "$github_token" ]]; then
    printf "${R}Usuario o token vacío.${N}\n"
    rm -rf -- "$work"; unset github_token
    return 1
  fi
  if [[ "$github_user$github_token" =~ [\"\\[:space:][:cntrl:]] ]]; then
    printf "${R}El usuario o el token contiene caracteres no válidos (comillas, espacios o saltos de línea).${N}\n"
    rm -rf -- "$work"; unset github_token
    return 1
  fi
  gh_config "$work" "$github_user" "$github_token"
  unset github_token

  printf "\nConsultando las actualizaciones disponibles en %s/%s...\n" "$GH_OWNER" "$GH_REPO"
  zip_list_repo "$work"; rc=$?
  if (( rc == 2 )); then
    rm -rf -- "$work"
    return 1
  elif (( rc != 0 )); then
    printf "${R}No se encontró ningún archivo .zip en la carpeta '%s' (rama %s).${N}\n" "$ZIP_SUBDIR" "$ZIP_BRANCH"
    printf "Sube allí las actualizaciones, o indica otra carpeta con BASTCONTROL_ZIP_DIR.\n"
    rm -rf -- "$work"
    return 1
  fi

  ZIP_SELECTED=""; ZIP_SELECTED_DATE=""
  wanted="${BASTCONTROL_ZIP:-}"
  if [[ -n "$wanted" ]]; then
    for i in "${!ZIP_NAMES[@]}"; do
      if [[ "${ZIP_NAMES[$i]##*/}" == "${wanted##*/}" ]]; then ZIP_SELECTED="${ZIP_NAMES[$i]}"; ZIP_SELECTED_DATE="${ZIP_DATES[$i]}"; fi
    done
    if [[ -z "$ZIP_SELECTED" ]]; then
      printf "${R}El ZIP '%s' no está entre los últimos %d de la carpeta '%s'.${N}\n" "$wanted" "${#ZIP_NAMES[@]}" "$ZIP_SUBDIR"
      rm -rf -- "$work"
      return 1
    fi
  else
    if ! zip_choose; then
      printf "${Y}Operación cancelada. No se cambió nada.${N}\n"
      rm -rf -- "$work"
      return 1
    fi
  fi

  zip_fetch "$ZIP_SELECTED" "$zip_file" || { rm -rf -- "$work"; return 1; }

  mkdir -p "$extract_dir" && unzip_lenient -q -o "$zip_file" -d "$extract_dir" 2>/dev/null || { printf "${R}No se pudo descomprimir el ZIP.${N}\n"; rm -rf -- "$work"; return 1; }
  source_dir="$(zip_find_project "$extract_dir")"
  if [[ -z "$source_dir" || ! -f "$source_dir/docker-compose.yml" ]]; then
    printf "${R}El ZIP no contiene el proyecto (no se encontró docker-compose.yml).${N}\n"
    rm -rf -- "$work"
    return 1
  fi

  APP_DIR="$INSTALL_ROOT"
  migrate_legacy_env || { rm -rf -- "$work"; return 1; }

  # Copia el proyecto a la ruta final. Conserva .env y el marcador de la versión instalada
  # y elimina archivos obsoletos de versiones anteriores.
  if ! rsync -a --delete --exclude='.env' --exclude="$ZIP_MARK_FILE" "$source_dir/" "$INSTALL_ROOT/"; then
    rm -rf -- "$work"
    return 1
  fi
  printf '%s\n%s\n%s\n' "${ZIP_SELECTED##*/}" "$ZIP_SELECTED_DATE" "$(date '+%d-%m-%Y %H:%M')" >"$INSTALL_ROOT/$ZIP_MARK_FILE"

  rm -rf -- "$work"
  APP_DIR="$INSTALL_ROOT"
  cd "$APP_DIR" || return 1
  printf "${G}Actualización %s instalada en $APP_DIR.${N}\n" "${ZIP_SELECTED##*/}"
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
    # Sin clave inicial: el Super administrador se crea desde la página /setup (solo desde este servidor).
    setenv INITIAL_ADMIN_EMAIL "admin@bastcontrol.com"
    setenv INITIAL_ADMIN_PASSWORD ""
    setenv HTTP_PORT "${INSTALL_HTTP_PORT:-$DEFAULT_HTTP_PORT}"
    setenv COMPOSE_PROJECT_NAME "$(instance_name "$INSTALL_ROOT")"
    local server_ip
    server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [[ -n "$server_ip" ]] && setenv APP_URL "http://${server_ip}:$(getenv HTTP_PORT "$DEFAULT_HTTP_PORT")"
  fi
  # Código de configuración (SETUP_CODE): permite crear la primera cuenta desde otro equipo de la red,
  # sin pantalla en el servidor. Se crea si el .env no tiene clave inicial ni código (instalación nueva,
  # o .env que dejó una instalación anterior). Solo se usa mientras no exista ninguna cuenta.
  if [[ -z "$(getenv INITIAL_ADMIN_PASSWORD '')" && -z "$(getenv SETUP_CODE '')" ]]; then
    setenv SETUP_CODE "$(openssl rand -hex 8 | tr 'a-f' 'A-F' | sed 's/.\{4\}/&-/g;s/-$//')"
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
  root rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.sources
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

# Si algo no arranca, muestra lo mínimo para diagnosticarlo sin tener que buscar los registros a mano.
show_failure_diagnostics(){
  local svc
  printf "\n${Y}${B}Diagnóstico (copia esto si necesitas ayuda):${N}\n"
  printf "\n${B}Estado de los contenedores:${N}\n"; dc ps -a 2>&1 | cut -c1-200
  for svc in db backend; do
    printf "\n${B}Últimas líneas del registro de '%s':${N}\n" "$svc"; dc logs --no-color --tail=25 "$svc" 2>&1 | cut -c1-220
  done
  printf "\n${B}Memoria y disco:${N}\n"; free -h 2>/dev/null | sed -n '1,2p'; df -h "$APP_DIR" 2>/dev/null | tail -n1
  printf "\n${Y}Si la base de datos no llegó a iniciar y es una instalación NUEVA (sin datos), puedes borrar su volumen incompleto con:\n  cd %s && docker compose down -v\ny volver a intentar. No lo hagas si ya tenías datos.${N}\n" "$APP_DIR"
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
  printf "\n${B}Construyendo y arrancando BastControl...${N}\n"
  if dc up -d --build; then
    printf "${G}Instalación terminada.${N}\n"
    show_url
    print_initial_credentials
  else
    printf "${R}Falló la instalación. Revisa los registros desde el menú de estado.${N}\n"
    show_failure_diagnostics
  fi
}


install_offline(){
  title
  printf "${C}${B}Instalar BastControl OFFLINE${N}\n\n"

  local source_dir="$SCRIPT_DIR"
  local chosen port url

  if [[ ! -f "$source_dir/docker-compose.yml" || ! -d "$source_dir/backend" || ! -d "$source_dir/frontend" ]]; then
    printf "${R}No se encontró un proyecto válido en la carpeta del instalador:${N}\n"
    printf "${Y}%s${N}\n\n" "$source_dir"
    printf "Debes copiar este script dentro de la carpeta del proyecto BastControl,\n"
    printf "junto a docker-compose.yml, backend/ y frontend/.\n"
    return 1
  fi

  if ! has docker; then
    printf "${R}Docker no está instalado. Ejecuta primero la opción 1.${N}\n"
    return 1
  fi

  printf "Ruta de instalación [${C}%s${N}]: " "$DEFAULT_INSTALL_ROOT"
  read -r chosen </dev/tty
  chosen="${chosen:-$DEFAULT_INSTALL_ROOT}"

  if [[ "$chosen" != /* || "$chosen" == "/" || "$chosen" == "/opt" ]]; then
    printf "${R}La ruta debe ser absoluta y no puede ser / ni /opt.${N}\n"
    return 1
  fi

  INSTALL_ROOT="${chosen%/}"
  APP_DIR="$INSTALL_ROOT"

  printf "Puerto HTTP [${C}%s${N}]: " "$DEFAULT_HTTP_PORT"
  read -r port </dev/tty
  port="${port:-$DEFAULT_HTTP_PORT}"

  if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
    printf "${R}Puerto inválido. Debe estar entre 1 y 65535.${N}\n"
    return 1
  fi
  preflight "$chosen" "$port" || return 1

  if ! has rsync; then
    printf "${Y}Instalando rsync...${N}\n"
    root apt-get update || return 1
    root apt-get install -y rsync || return 1
  fi

  root install -d -o "$(id -un)" -g "$(id -gn)" "$INSTALL_ROOT" || return 1

  local backup_env=""
  if [[ -f "$INSTALL_ROOT/.env" ]]; then
    backup_env="$(mktemp /tmp/bastcontrol-env.XXXXXX)" || return 1
    cp "$INSTALL_ROOT/.env" "$backup_env" || return 1
  fi

  printf "\n${B}Copiando proyecto local a %s...${N}\n" "$INSTALL_ROOT"
  if ! rsync -a --delete \
      --exclude='.env' \
      --exclude="$(basename "$0")" \
      "$source_dir/" "$INSTALL_ROOT/"; then
    [[ -n "$backup_env" ]] && rm -f -- "$backup_env"
    printf "${R}No fue posible copiar el proyecto local.${N}\n"
    return 1
  fi

  if [[ -n "$backup_env" && -f "$backup_env" ]]; then
    cp "$backup_env" "$INSTALL_ROOT/.env"
    rm -f -- "$backup_env"
  fi

  cd "$APP_DIR" || return 1
  prepare_env

  INSTALL_HTTP_PORT="$port"
  setenv HTTP_PORT "$port"
  setenv COMPOSE_PROJECT_NAME "$(instance_name "$INSTALL_ROOT")"

  printf "URL actual: ${C}%s${N}\n" "$(getenv APP_URL '')"
  read -rp 'URL pública (Enter para conservar): ' url </dev/tty
  [[ -n "$url" ]] && setenv APP_URL "$url"

  printf "\n${B}Construyendo y arrancando BastControl desde archivos locales...${N}\n"

  if dc up -d --build; then
    printf "${G}Instalación OFFLINE terminada correctamente.${N}\n"
    show_url
    print_initial_credentials
  else
    printf "${R}Falló la instalación offline. Revisa los registros desde el menú de estado.${N}\n"
    show_failure_diagnostics
    return 1
  fi
}

update_offline(){
  title
  printf "${C}${B}Actualizar BastControl OFFLINE${N}\n\n"

  local source_dir="$SCRIPT_DIR"
  local chosen backup_env=""

  if [[ ! -f "$source_dir/docker-compose.yml" || ! -d "$source_dir/backend" || ! -d "$source_dir/frontend" ]]; then
    printf "${R}No se encontró un proyecto válido en la carpeta del instalador:${N}\n"
    printf "${Y}%s${N}\n\n" "$source_dir"
    printf "Debes ejecutar este script desde la carpeta que contiene docker-compose.yml, backend/ y frontend/.\n"
    return 1
  fi

  if ! has docker; then
    printf "${R}Docker no está instalado. Ejecuta primero la opción 1.${N}\n"
    return 1
  fi

  printf "Ruta instalada a actualizar [${C}%s${N}]: " "$INSTALL_ROOT"
  read -r chosen </dev/tty
  chosen="${chosen:-$INSTALL_ROOT}"

  if [[ "$chosen" != /* || "$chosen" == "/" || "$chosen" == "/opt" ]]; then
    printf "${R}La ruta debe ser absoluta y no puede ser / ni /opt.${N}\n"
    return 1
  fi

  INSTALL_ROOT="${chosen%/}"
  APP_DIR="$INSTALL_ROOT"

  if [[ ! -f "$INSTALL_ROOT/docker-compose.yml" ]]; then
    printf "${R}No se encontró una instalación válida en %s.${N}\n" "$INSTALL_ROOT"
    return 1
  fi

  cd "$APP_DIR" || return 1
  prepare_env

  printf "\n${C}${B}¿Desea crear un respaldo antes de actualizar?${N}\n\n"
  printf "${Y}1)${N} ${C}Sí, crear respaldo de BastControl${N}\n"
  printf "${Y}2)${N} ${C}No, actualizar directamente${N}\n"
  printf "${Y}3)${N} ${C}Cancelar${N}\n\n"

  local opcion_respaldo
  read -rp 'Seleccione una opción: ' opcion_respaldo </dev/tty

  case "$opcion_respaldo" in
    1)
      printf "\n${B}Creando respaldo preventivo de BastControl...${N}\n"
      exportar "$INSTALL_ROOT" || {
        printf "${R}Actualización cancelada: falló el respaldo previo.${N}\n"
        return 1
      }
      ;;
    2)
      printf "\n${Y}Se continuará sin crear respaldo previo.${N}\n"
      ;;
    3)
      printf "\n${Y}Actualización cancelada por el usuario.${N}\n"
      return 0
      ;;
    *)
      printf "\n${R}Opción inválida. Actualización cancelada.${N}\n"
      return 1
      ;;
  esac

  if ! has rsync; then
    printf "${Y}Instalando rsync...${N}\n"
    root apt-get update || return 1
    root apt-get install -y rsync || return 1
  fi

  if [[ -f "$INSTALL_ROOT/.env" ]]; then
    backup_env="$(mktemp /tmp/bastcontrol-env.XXXXXX)" || return 1
    cp "$INSTALL_ROOT/.env" "$backup_env" || return 1
  fi

  printf "\n${B}Actualizando archivos desde %s...${N}\n" "$source_dir"
  if ! rsync -a --delete \
      --exclude='.env' \
      --exclude="$(basename "$0")" \
      "$source_dir/" "$INSTALL_ROOT/"; then
    [[ -n "$backup_env" ]] && rm -f -- "$backup_env"
    printf "${R}No fue posible actualizar los archivos locales.${N}\n"
    return 1
  fi

  if [[ -n "$backup_env" && -f "$backup_env" ]]; then
    cp "$backup_env" "$INSTALL_ROOT/.env"
    rm -f -- "$backup_env"
  fi

  cd "$APP_DIR" || return 1
  prepare_env

  printf "\n${B}Reconstruyendo y reiniciando servicios sin borrar los datos...${N}\n"
  if dc -f "$APP_DIR/docker-compose.yml" up -d --build --remove-orphans; then
    printf "${G}Actualización OFFLINE terminada correctamente. La base de datos y configuración se conservaron.${N}\n"
    dc ps
    show_url
  else
    printf "${R}La actualización offline falló. Revisa los registros desde el menú de estado.${N}\n"
    show_failure_diagnostics
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
  if dc up -d --force-recreate frontend; then printf "${G}Puerto actualizado.${N}\n"; caddy_sync_action || printf "${Y}No se pudo sincronizar la ruta de Caddy.${N}\n"; show_url; fi
}

create_super_admin(){
  local name email pass confirm
  printf "\n${C}${B}Crear Super administrador${N}\nSolo funciona mientras no exista ninguna cuenta.\n\n"
  read -rp 'Nombre completo: ' name
  read -rp 'Correo electrónico: ' email
  read -rsp 'Contraseña (12 o más caracteres, con mayúscula, minúscula y número): ' pass; printf '\n'
  read -rsp 'Confirmar contraseña: ' confirm; printf '\n'
  if [[ "$pass" != "$confirm" ]]; then printf "${R}Las contraseñas no coinciden.${N}\n"
  else printf '%s\n%s\n%s\n' "$name" "$email" "$pass" | dc exec -T backend node dist/src/admin-cli.js create-admin
  fi
  unset pass confirm
}

users(){
  while true; do title; printf "${C}${B}Gestión de usuarios${N}\n\n${Y}1)${C} Listar usuarios${N}\n${Y}2)${C} Activar usuario${N}\n${Y}3)${C} Desactivar usuario${N}\n${Y}4)${C} Cambiar contraseña${N}\n${Y}5)${C} Quitar bloqueo por intentos fallidos${N}\n${Y}6)${C} Crear Super administrador (solo si aún no hay cuentas)${N}\n${Y}7)${C} Volver${N}\n\n"; read -rp 'Opción: ' o
    case "$o" in
      1) dc exec -T backend node dist/src/admin-cli.js list-users; pause;;
      2|3|4|5)
        dc exec -T backend node dist/src/admin-cli.js list-users; local selected; read -rp 'Número de usuario: ' selected
        if [[ "$o" == 2 ]]; then dc exec -T backend node dist/src/admin-cli.js set-enabled "$selected" true
        elif [[ "$o" == 3 ]]; then dc exec -T backend node dist/src/admin-cli.js set-enabled "$selected" false
        elif [[ "$o" == 5 ]]; then dc exec -T backend node dist/src/admin-cli.js unlock "$selected"
        else local pass confirm; read -rsp 'Nueva contraseña (mínimo 10 caracteres): ' pass; printf '\n'; read -rsp 'Confirmar contraseña: ' confirm; printf '\n'; if [[ ${#pass} -lt 10 ]]; then printf "${R}Debe tener al menos 10 caracteres.${N}\n"; elif [[ "$pass" != "$confirm" ]]; then printf "${R}Las contraseñas no coinciden.${N}\n"; else dc exec -T backend node dist/src/admin-cli.js reset-password "$selected" "$pass"; fi; fi; pause;;
      6) create_super_admin; pause;;
      7) return;; *) printf "${R}Opción inválida.${N}\n"; sleep 1;;
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
  local pass port ip
  pass="$(getenv INITIAL_ADMIN_PASSWORD '')"; port="$(getenv HTTP_PORT "$DEFAULT_HTTP_PORT")"; ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -n "$pass" ]]; then
    # Instalaciones antiguas que todavía tienen una clave inicial en el .env.
    printf "\n${C}${B}==================================================${N}\n"
    printf "${C}${B}              CREDENCIALES INICIALES             ${N}\n"
    printf "${C}${B}==================================================${N}\n\n"
    printf "${B}Usuario:${N}     %s\n" "$(getenv INITIAL_ADMIN_EMAIL 'admin@bastcontrol.com')"
    printf "${B}Contraseña temporal:${N}  %s\n\n" "$pass"
    printf "${Y}Por seguridad, cambia esta contraseña después del primer inicio de sesión.${N}\n"
    return
  fi
  printf "\n${C}${B}==================================================${N}\n"
  printf "${C}${B}          CUENTA DEL SUPER ADMINISTRADOR          ${N}\n"
  printf "${C}${B}==================================================${N}\n\n"
  local code; code="$(getenv SETUP_CODE '')"
  printf "La cuenta del Super administrador se crea una sola vez, de cualquiera de estas formas:\n\n"
  if [[ -n "$code" ]]; then
    printf "  ${B}A. Desde cualquier computador de la red${N} (el servidor no necesita pantalla):\n"
    printf "       Abre:  ${C}http://%s:%s/setup${N}\n" "${ip:-IP-del-servidor}" "$port"
    printf "       Código de configuración:  ${G}${B}%s${N}\n\n" "$code"
  fi
  printf "  ${B}B. Sin navegador, por esta terminal:${N} menú «Gestión de usuarios» → «Crear Super administrador».\n\n"
  printf "  ${B}C. En este mismo servidor${N} (si tiene pantalla): ${C}http://localhost:%s/setup${N} (sin código).\n\n" "$port"
  printf "${Y}El código solo sirve mientras no exista ninguna cuenta. Si ya creaste la cuenta, entra con tu correo y contraseña.${N}\n"
}

show_initial_credentials(){
  title
  print_initial_credentials
}

verificar_pv() {

    if command -v pv >/dev/null 2>&1; then

        printf "${G}✓ pv instalado${N}\n"
        return

    fi

    echo
    printf "${Y}Instalando pv...${N}\n"
    echo

    apt update
    apt install -y pv

    if ! command -v pv >/dev/null 2>&1; then

        echo "Error al instalar pv."
        return 1

    fi

}
listar_apps() {

    APPS=()

    while IFS= read -r APP
    do
        APPS+=("$APP")
    done < <(
        find /opt -mindepth 1 -maxdepth 1 -type d | sort
    )

    if [ ${#APPS[@]} -eq 0 ]; then

        echo
        echo "No se encontraron aplicaciones en /opt"
        echo

        read -rp "Presione Enter para continuar..." _
        return 0

    fi

    echo
    printf "${C}${B}APLICACIONES ENCONTRADAS:${N}\n"
    echo

    for i in "${!APPS[@]}"
    do
        printf "${Y}%s)${N} ${C}%s${N}\n" "$((i+1))" "$(basename "${APPS[$i]}")"
    done

    echo
}

seleccionar_apps() {

    listar_apps || return 1

    printf "${Y}A)${N} ${C}Todas${N}\n"
    echo

    read -rp "Seleccione (ej: 1 3 5 o A): " RESP

    SELECCIONADAS=()

    if [[ "$RESP" =~ ^[Aa]$ ]]; then

        for APP in "${APPS[@]}"
        do
            SELECCIONADAS+=("$APP")
        done

    else

        for N in $RESP
        do
            if ! [[ "$N" =~ ^[0-9]+$ ]]; then
                echo "Selección ignorada: $N no es un número válido."
                continue
            fi

            IDX=$((N-1))

            if [ "$IDX" -ge 0 ] && [ "$IDX" -lt "${#APPS[@]}" ]; then
                SELECCIONADAS+=("${APPS[$IDX]}")
            fi
        done

    fi

    if [ ${#SELECCIONADAS[@]} -eq 0 ]; then
        echo "Nada seleccionado."
        return 1
    fi

    return 0
}
# ══════════════════════════════════════════════════════════════════════════════
# BUSCAR ARCHIVO COMPOSE
# ══════════════════════════════════════════════════════════════════════════════

buscar_compose() {

    local APP="$1"

    for ARCHIVO in \
        "$APP/docker-compose.yml" \
        "$APP/docker-compose.yaml" \
        "$APP/compose.yml" \
        "$APP/compose.yaml"
    do
        if [ -f "$ARCHIVO" ]; then
            echo "$ARCHIVO"
            return 0
        fi
    done

    return 1
}

# ══════════════════════════════════════════════════════════════════════════════
# OBTENER CONTENEDORES DEL STACK
# ══════════════════════════════════════════════════════════════════════════════

obtener_contenedores_stack() {

    local APP="$1"
    local COMPOSE="$2"

    if [ -n "$COMPOSE" ]; then
        (
            cd "$APP" || exit 1
            docker compose -f "$COMPOSE" ps -aq 2>/dev/null
        )
    fi
}


# ══════════════════════════════════════════════════════════════════════════════
# OBTENER VOLÚMENES DEL STACK
# ══════════════════════════════════════════════════════════════════════════════

obtener_volumenes_stack() {

    local APP="$1"
    local COMPOSE="$2"

    local CONTENEDORES
    local CONTENEDOR

    CONTENEDORES=$(obtener_contenedores_stack "$APP" "$COMPOSE")

    for CONTENEDOR in $CONTENEDORES
    do

        docker inspect \
            --format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
            "$CONTENEDOR" 2>/dev/null

    done | sort -u
}


# ══════════════════════════════════════════════════════════════════════════════
# RESPALDAR MYSQL / MARIADB
# ══════════════════════════════════════════════════════════════════════════════

respaldar_base_datos() {

    local APP="$1"
    local COMPOSE="$2"
    local DESTINO="$3"

    mkdir -p "$DESTINO/databases"

    local CONTENEDORES
    local CONTENEDOR
    local IMAGEN
    local NOMBRE

    CONTENEDORES=$(obtener_contenedores_stack "$APP" "$COMPOSE")

    for CONTENEDOR in $CONTENEDORES
    do

        IMAGEN=$(docker inspect \
            --format '{{.Config.Image}}' \
            "$CONTENEDOR" 2>/dev/null)

        NOMBRE=$(docker inspect \
            --format '{{.Name}}' \
            "$CONTENEDOR" 2>/dev/null | sed 's#^/##')

        if echo "$IMAGEN $NOMBRE" | grep -Eqi 'mysql|mariadb'
        then

            echo
            echo "Base de datos detectada:"
            echo "  Contenedor : $NOMBRE"
            echo "  Imagen     : $IMAGEN"
            echo

            local ROOT_PASS
            local MYSQL_USER
            local MYSQL_PASS

            ROOT_PASS=$(docker inspect \
                --format '{{range .Config.Env}}{{println .}}{{end}}' \
                "$CONTENEDOR" 2>/dev/null \
                | grep -E '^(MYSQL_ROOT_PASSWORD|MARIADB_ROOT_PASSWORD)=' \
                | head -n1 \
                | cut -d= -f2-)

            MYSQL_USER=$(docker inspect \
                --format '{{range .Config.Env}}{{println .}}{{end}}' \
                "$CONTENEDOR" 2>/dev/null \
                | grep -E '^(MYSQL_USER|MARIADB_USER)=' \
                | head -n1 \
                | cut -d= -f2-)

            MYSQL_PASS=$(docker inspect \
                --format '{{range .Config.Env}}{{println .}}{{end}}' \
                "$CONTENEDOR" 2>/dev/null \
                | grep -E '^(MYSQL_PASSWORD|MARIADB_PASSWORD)=' \
                | head -n1 \
                | cut -d= -f2-)

            echo "Creando dump SQL completo..."

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
                        2>/dev/null \
                    | gzip \
                    > "$DESTINO/databases/${NOMBRE}-all.sql.gz"

                else

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
                        2>/dev/null \
                    | gzip \
                    > "$DESTINO/databases/${NOMBRE}-all.sql.gz"

                fi

            elif [ -n "$MYSQL_USER" ] && [ -n "$MYSQL_PASS" ]; then

                echo "No se encontró contraseña root."
                echo "Intentando respaldo con usuario $MYSQL_USER..."

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
                        2>/dev/null \
                    | gzip \
                    > "$DESTINO/databases/${NOMBRE}-all.sql.gz"

                else

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
                        2>/dev/null \
                    | gzip \
                    > "$DESTINO/databases/${NOMBRE}-all.sql.gz"

                fi

            else

                echo "ADVERTENCIA:"
                echo "No se encontraron credenciales MySQL/MariaDB."
                echo "La base igualmente quedará respaldada mediante su volumen Docker."

            fi

            if [ -s "$DESTINO/databases/${NOMBRE}-all.sql.gz" ]; then
                echo "✓ Dump SQL creado correctamente."
            else
                rm -f "$DESTINO/databases/${NOMBRE}-all.sql.gz"
            fi

        fi

    done
}

exportar() {

    verificar_pv || return

    # Si se entrega una ruta, respalda directamente esa aplicación sin mostrar el selector.
    # Sin argumento conserva el comportamiento normal del menú de respaldos.
    if [[ -n "${1:-}" ]]; then
        if [[ ! -d "$1" ]]; then
            printf "${R}No se encontró la aplicación a respaldar: %s${N}\n" "$1"
            return 1
        fi
        SELECCIONADAS=("$1")
    else
        seleccionar_apps || return
    fi

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
  printf "${C}${B}Actualizar BastControl desde GitHub${N}\n\n"

  if [[ ! -f "$INSTALL_ROOT/docker-compose.yml" ]]; then
    printf "${R}No se encontró una instalación válida en $INSTALL_ROOT.${N}\n"
    return 1
  fi

  APP_DIR="$INSTALL_ROOT"
  cd "$APP_DIR" || return 1
  prepare_env
  exportar || { printf "${R}Actualización cancelada: falló el respaldo previo.${N}\n"; return 1; }

  printf "${B}Buscando actualizaciones ZIP en GitHub...${N}\n"
  download_project || return 1
  prepare_env

  printf "\n${B}Reconstruyendo y reiniciando servicios sin borrar los datos...${N}\n"
  if dc up -d --build --remove-orphans; then
    printf "${G}BastControl fue actualizado correctamente. La base de datos y configuración se conservaron.${N}\n"
    dc ps
    show_url
  else
    printf "${R}La actualización falló. Revisa los registros desde la opción 4.${N}\n"
    show_failure_diagnostics
    return 1
  fi
}

uninstall_app(){
  title
  printf "${C}${B}Desinstalacion completa de BastControl${N}\n\n"
  printf "${R}Se eliminaran contenedores, imagenes, red y volumen MySQL de esta instancia.${N}\n"
  printf "${Y}La carpeta fuente donde está este script se conservará siempre.${N}\n\n"
  local confirmation target script_source default_target chosen
  script_source="$(realpath -m "$SCRIPT_DIR")"
  default_target="$INSTALL_ROOT"
  if [[ "$(realpath -m "$default_target")" == "$script_source" && -f "$DEFAULT_INSTALL_ROOT/docker-compose.yml" ]]; then
    default_target="$DEFAULT_INSTALL_ROOT"
  fi
  printf "Ruta de instalación a desinstalar [${C}%s${N}]: " "$default_target"
  read -r chosen </dev/tty
  chosen="${chosen:-$default_target}"
  INSTALL_ROOT="${chosen%/}"
  APP_DIR="$INSTALL_ROOT"
  read -rp 'Escribe ELIMINAR TODO para continuar: ' confirmation
  [[ "$confirmation" == 'ELIMINAR TODO' ]] || { printf 'Operacion cancelada.\n'; return; }
  target="$(realpath -m "$INSTALL_ROOT")"
  case "$target" in
    /opt/*|/root/*|/home/*/*)
      [[ -f "$target/docker-compose.yml" ]] || { printf "${R}No se encontro una instalacion valida en $target.${N}\n"; return; }
      dc down -v --rmi local --remove-orphans || return
      if [[ "$target" == "$script_source" ]]; then
        printf "${Y}No se borraron los archivos porque la instalación coincide con la carpeta del instalador: %s${N}\n" "$script_source"
        printf "${G}Contenedores, imágenes locales y volumen MySQL eliminados.${N}\n"
        return
      fi
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
  printf "  ${Y}2)${C} Instalar o migrar a BastControl (GitHub, elegir ZIP)${N}\n"
  printf "  ${Y}3)${Y} Instalar offline desde esta carpeta${N}\n\n"
  printf "${C}${G} ADMINISTRACIÓN${N}\n"
  printf "  ${Y}4)${C} Estado y control del servicio${N}\n"
  printf "  ${Y}5)${C} Cambiar puerto de Docker${N}\n"
  printf "  ${Y}6)${C} Ver URL y puerto${N}\n"
  printf "  ${Y}7)${C} Gestión de usuarios${N}\n\n"
  printf "${C}${G} MANTENIMIENTO${N}\n"
  printf "  ${Y}8)${C} Desinstalar y borrar todo${N}\n"
  printf "  ${Y}9)${C} Reparar base de datos${N}\n"
  printf "  ${Y}10)${Y} Ver credenciales iniciales${N}\n"
  printf "  ${Y}11)${Y} Actualizar BastControl desde GitHub (elegir ZIP)${N}\n"
  printf "  ${Y}12)${G} Crear respaldo completo (proyecto, DB y volúmenes)${N}\n"
  printf "  ${Y}13)${G} Restaurar respaldo completo${N}\n"
  printf "  ${Y}14)${Y} Actualizar offline desde esta carpeta${N}\n"
  printf "  ${Y}15)${C} Configurar dominio HTTPS con Caddy${N}\n"
  printf "  ${Y}16)${C} Eliminar dominio HTTPS de Caddy${N}\n"
  printf "  ${Y}0)${C} Salir${N}\n\n"
  read -rp 'Selecciona una opción: ' o </dev/tty
  case "$o" in
    1) dependencies; pause;;
    2) install_app; pause;;
    3) install_offline; pause;;
    4) services;;
    5) port; pause;;
    6) title; show_url; pause;;
    7) users;;
    8) uninstall_app; pause;;
    9) repair_database; pause;;
    10) show_initial_credentials; pause;;
    11) update_app; pause;;
    12) exportar; pause;;
    13) importar; pause;;
    14) update_offline; pause;;
    15) caddy_configure_action; pause;;
    16) caddy_remove_action; pause;;
    0) exit 0;;
    *) printf "${R}Opción inválida.${N}\n"; sleep 1;;
  esac
done
