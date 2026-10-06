#!/usr/bin/env bash
# Seshat-Evaluaciones · Debian/Ubuntu · Docker + Apache/PHP + SQLite.
# Uso: sudo bash Instalar_Seshat_Evaluaciones_GitHub-Token_v5.2.7.sh
# v5.2.7: Docker también instala y actualiza desde la carpeta del script (código suelto,
#         Apache24/htdocs/web o un .zip), sin pasar por GitHub. El código se monta con escritura
#         para que funcione Ajustes → Actualizar Seshat (opción 19 para volver a solo lectura).
set -uo pipefail
MENU_CYAN='\033[1;36m'
MENU_AMARILLO='\033[1;33m'
MENU_RESET='\033[0m'
limpiar_consola(){ printf '\033[2J\033[H'; }
titulo_menu(){ printf '%b%s%b\n' "$MENU_CYAN" "$1" "$MENU_RESET"; }
opcion_menu(){ printf '%b%s)%b %s\n' "$MENU_AMARILLO" "$1" "$MENU_RESET" "$2"; }
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="${SESHAT_REPO_URL:-https://github.com/llancor/seshat.git}"
REPO_BRANCH="${SESHAT_REPO_BRANCH:-main}"
INSTALL_ROOT="${SESHAT_INSTALL_DIR:-/opt/seshat-evaluaciones}"
[[ -f "$SCRIPT_DIR/.seshat-instance" ]] && INSTALL_ROOT="$SCRIPT_DIR"
fail(){ printf 'Error: %s\n' "$*" >&2; return 1; }
ok(){ printf '\033[0;32m✔\033[0m %s\n' "$*"; }
pause(){ read -rp 'Presiona Enter para continuar...' _ || true; }
root(){ if (( EUID == 0 )); then "$@"; else sudo "$@"; fi; }
valid_root(){
  [[ "$INSTALL_ROOT" =~ ^/opt/[a-zA-Z0-9_-]+$ ]] || { fail 'Usa una carpeta directamente bajo /opt, por ejemplo /opt/seshat-evaluaciones.'; return 1; }
  [[ ! -L "$INSTALL_ROOT" ]] || fail 'La instalación no puede ser un enlace simbólico.'
}
ready(){ valid_root && [[ -f "$INSTALL_ROOT/.seshat-instance" && -f "$INSTALL_ROOT/compose.yaml" ]] || fail 'No hay una instancia Seshat instalada en esa ruta.'; }
dc(){ root docker compose --project-directory "$INSTALL_ROOT" -f "$INSTALL_ROOT/compose.yaml" "$@"; }
docker_env_set(){
  local key="$1" value="$2" file="$INSTALL_ROOT/.env" tmp
  root mkdir -p "$INSTALL_ROOT"
  tmp="$(mktemp /tmp/seshat-env.XXXXXX)" || return 1
  if [[ -f "$file" ]]; then root cp -- "$file" "$tmp" || { rm -f "$tmp"; return 1; }; fi
  if grep -qE "^${key}=" "$tmp" 2>/dev/null; then
    sed -i -E "s|^${key}=.*|${key}=${value}|" "$tmp"
  else
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  fi
  root install -m 600 "$tmp" "$file"; rm -f "$tmp"
}
php_limit_profile(){
  local selected="$1"
  case "$selected" in
    20) PHP_UPLOAD_MB=20; PHP_POST_MB=24; PHP_MEMORY_MB=128 ;;
    40) PHP_UPLOAD_MB=40; PHP_POST_MB=48; PHP_MEMORY_MB=256 ;;
    80) PHP_UPLOAD_MB=80; PHP_POST_MB=96; PHP_MEMORY_MB=256 ;;
    custom)
      read -rp 'Tamaño máximo de archivo (MB): ' PHP_UPLOAD_MB
      read -rp 'Memoria PHP (MB) [256]: ' PHP_MEMORY_MB
      PHP_MEMORY_MB="${PHP_MEMORY_MB:-256}"
      [[ "$PHP_UPLOAD_MB" =~ ^[1-9][0-9]*$ && "$PHP_MEMORY_MB" =~ ^[1-9][0-9]*$ ]] || { fail 'Los valores deben ser números enteros positivos.'; return 1; }
      PHP_POST_MB=$((PHP_UPLOAD_MB + 8))
      ;;
    *) fail 'Perfil de tamaño inválido.'; return 1 ;;
  esac
  (( PHP_POST_MB > PHP_UPLOAD_MB )) || PHP_POST_MB=$((PHP_UPLOAD_MB + 1))
}
choose_php_limit_profile(){
  printf '\nConfiguración de PHP para archivos y memoria\n'
  printf '  1) 20 MB de subida (memoria 128 MB)\n'
  printf '  2) 40 MB de subida (memoria 256 MB)\n'
  printf '  3) 80 MB de subida (memoria 256 MB)\n'
  printf '  4) Personalizado\n'
  read -rp 'Elige una opción [1]: ' choice
  case "${choice:-1}" in
    1) php_limit_profile 20;; 2) php_limit_profile 40;; 3) php_limit_profile 80;; 4) php_limit_profile custom;;
    *) fail 'Opción inválida.'; return 1;;
  esac
}
configure_php_limits_docker(){
  ready || return 1
  choose_php_limit_profile || return 1
  docker_env_set SESHAT_UPLOAD_MB "$PHP_UPLOAD_MB" || return 1
  docker_env_set SESHAT_POST_MB "$PHP_POST_MB" || return 1
  docker_env_set SESHAT_MEMORY_MB "$PHP_MEMORY_MB" || return 1
  write_runtime || return 1
  dc up -d --build || return 1
  ok "Docker configurado: subida ${PHP_UPLOAD_MB}M, POST ${PHP_POST_MB}M, memoria ${PHP_MEMORY_MB}M."
}
dependencies(){
  command -v apt-get >/dev/null || { fail 'Este instalador requiere Debian/Ubuntu.'; return 1; }
  root apt-get update && root apt-get install -y ca-certificates curl git rsync unzip || return 1
  if ! root docker compose version >/dev/null 2>&1; then
    local distro code arch
    distro="$(. /etc/os-release; printf '%s' "$ID")"
    code="$(. /etc/os-release; printf '%s' "$VERSION_CODENAME")"
    [[ "$distro" == debian || "$distro" == ubuntu ]] || return 1
    arch="$(dpkg --print-architecture)"
    root install -m 0755 -d /etc/apt/keyrings || return 1
    root curl -fsSL "https://download.docker.com/linux/$distro/gpg" -o /etc/apt/keyrings/docker.asc || return 1
    root chmod a+r /etc/apt/keyrings/docker.asc || return 1
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' "$arch" "$distro" "$code" | root tee /etc/apt/sources.list.d/seshat-docker.list >/dev/null || return 1
    root apt-get update && root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 1
  fi
  root systemctl enable --now docker
}
github_clone() (
  # El PAT se entrega por askpass, nunca en la URL ni en los argumentos de git.
  umask 077
  local temp user token url="$1" branch="$2" destination="$3"
  temp="$(mktemp -d /tmp/seshat.XXXXXX)" || exit 1
  trap 'rm -rf -- "$temp"' EXIT
  [[ "$url" =~ ^https://github\.com/[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]] || { fail 'Repositorio HTTPS de GitHub no válido.'; exit 1; }
  read -rp 'Usuario GitHub (Enter para repositorio público): ' user </dev/tty
  if [[ -n "$user" ]]; then
    read -rsp 'Token GitHub (PAT): ' token </dev/tty; printf '\n' >&2
    [[ -n "$token" ]] || exit 1
    printf '%s' "$user" > "$temp/user"
    printf '%s' "$token" > "$temp/token"
    unset token
    cat > "$temp/askpass" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in *Username*) cat "$SESHAT_AUTH_DIR/user";; *) cat "$SESHAT_AUTH_DIR/token";; esac
ASKPASS
    chmod 700 "$temp/askpass"
    export SESHAT_AUTH_DIR="$temp" GIT_ASKPASS="$temp/askpass"
  fi
  GIT_TERMINAL_PROMPT=0 git -c credential.helper= clone --quiet --depth 1 --branch "$branch" "$url" "$destination"
)
# Seshat viene comprimido en un .zip dentro del repositorio (GitHub no deja subir más de 100
# archivos sueltos desde la web). Si lo encuentra, lo extrae y escribe por stdout la carpeta con el
# código; si no hay ninguno, no escribe nada y se usa el código suelto del repositorio, como antes.
# Orden de búsqueda: SESHAT_REPO_ZIP (ruta relativa dentro del repositorio) o, si no se
# define, lista los .zip de Seshat_Evaluaciones y de la raíz para elegir. El último
# por orden numérico/versionado queda marcado y seleccionado por defecto.
REPO_ZIP_DEFECTO='Seshat_Evaluaciones/Seshat_Evaluaciones.zip'
seleccionar_zip_repositorio(){
  local repo="$1" relativo zip ultimo opcion i rel
  local -a zips=()
  if [[ -n "${SESHAT_REPO_ZIP:-}" ]]; then
    relativo="$SESHAT_REPO_ZIP"
    [[ "$relativo" != /* && "/$relativo/" != */../* ]] || { fail 'SESHAT_REPO_ZIP debe ser una ruta dentro del repositorio.'; return 1; }
    zip="$repo/$relativo"
    [[ -f "$zip" ]] || { fail "No existe $SESHAT_REPO_ZIP en el repositorio."; return 1; }
    printf '%s\n' "$zip"
    return 0
  fi
  while IFS= read -r zip; do zips+=("$zip"); done < <(
    {
      find "$repo/Seshat_Evaluaciones" -maxdepth 1 -type f -iname '*.zip' 2>/dev/null
      find "$repo" -maxdepth 1 -type f -iname '*.zip' 2>/dev/null
    } | sort -V
  )
  ((${#zips[@]} > 0)) || return 0
  ultimo="${#zips[@]}"
  printf '\nPaquetes ZIP disponibles en el repositorio:\n' >&2
  for i in "${!zips[@]}"; do
    rel="${zips[$i]#$repo/}"
    if (( i + 1 == ultimo )); then
      printf '  %d) %s  [último]\n' "$((i + 1))" "$rel" >&2
    else
      printf '  %d) %s\n' "$((i + 1))" "$rel" >&2
    fi
  done
  read -rp "Elige el ZIP a usar [$ultimo]: " opcion </dev/tty || opcion=''
  opcion="${opcion:-$ultimo}"
  [[ "$opcion" =~ ^[0-9]+$ && "$opcion" -ge 1 && "$opcion" -le "$ultimo" ]] || { fail 'Selección de ZIP inválida.'; return 1; }
  printf '%s\n' "${zips[$((opcion - 1))]}"
}
extraer_zip_repositorio(){
  # $2 (opcional): carpeta donde extraer. Por defecto, dentro del repositorio clonado; para una
  # carpeta local se usa una carpeta temporal, así no se escribe nada junto al script.
  local repo="$1" zip lista destino item rel
  zip="$(seleccionar_zip_repositorio "$repo")" || return 1
  [[ -n "$zip" ]] || return 0
  rel="${zip#$repo/}"
  printf 'Usando el paquete %s.\n' "$rel" >&2
  if ! command -v unzip >/dev/null 2>&1; then
    root apt-get install -y unzip >&2 || { fail 'No se pudo instalar unzip.'; return 1; }
  fi
  lista="$(unzip -Z1 "$zip" 2>/dev/null)" || { fail "$(basename "$zip") no es un .zip válido."; return 1; }
  # Los .zip hechos con Compress-Archive de Windows usan «\» como separador: se revisan ambos.
  if grep -Eq '(^|[/\\])\.\.([/\\]|$)|^[/\\]|^[A-Za-z]:' <<< "$lista"; then
    fail "$(basename "$zip") contiene rutas no permitidas."; return 1
  fi
  # El paquete es solo código: la configuración, la llave de cifrado y la base de datos de una
  # instalación nunca deben viajar en un archivo público del repositorio.
  if grep -Eiq '(^|[/\\])data[/\\](config\.php|secretos\.key|[^/\\]*\.sqlite[^/\\]*)$' <<< "$lista"; then
    fail "$(basename "$zip") trae datos privados de una instalación (data/config.php, data/secretos.key o la base SQLite). Quítalos del .zip y vuelve a subirlo."; return 1
  fi
  destino="${2:-$repo/.seshat-zip}"
  mkdir -p "$destino" || return 1
  # unzip termina con 1 cuando solo hubo advertencias (p. ej. separadores «\», que corrige solo).
  unzip -q -o "$zip" -d "$destino" >&2
  (( $? <= 1 )) || { fail "No se pudo extraer $(basename "$zip")."; return 1; }
  for item in "$destino" "$destino"/*/ "$destino/Apache24/htdocs/web" "$destino"/*/Apache24/htdocs/web; do
    item="${item%/}"
    if [[ -f "$item/database.php" && -f "$item/index.php" && -f "$item/seguridad.php" ]]; then
      printf '%s\n' "$item"; return 0
    fi
  done
  fail "No se encontró Seshat dentro de $(basename "$zip") (se busca database.php en la raíz, en una carpeta o en Apache24/htdocs/web)."
  return 1
}
download_project() (
  local temp source candidate
  temp="$(mktemp -d /tmp/seshat-codigo.XXXXXX)" || exit 1
  trap 'rm -rf -- "$temp"' EXIT
  github_clone "$REPO_URL" "$REPO_BRANCH" "$temp/repo" || exit 1
  source="$(extraer_zip_repositorio "$temp/repo")" || exit 1
  if [[ -z "$source" ]]; then
    for candidate in "$temp/repo/${SESHAT_REPO_SUBDIR:-.}" "$temp/repo/Apache24/htdocs/web"; do
      if [[ -f "$candidate/database.php" && -f "$candidate/index.php" && -f "$candidate/seguridad.php" ]]; then source="$candidate"; break; fi
    done
  fi
  [[ -n "$source" ]] || { fail 'No se encontró Seshat: ni un .zip en la raíz del repositorio, ni el código en la raíz o en Apache24/htdocs/web. Define SESHAT_REPO_SUBDIR.'; exit 1; }
  copy_project_source "$source" || exit 1
)
# Copia el código a $INSTALL_ROOT/app. Código separado de los datos: una actualización nunca
# reemplaza SQLite, configuración, pruebas guardadas ni imágenes subidas.
copy_project_source(){
  local source="$1"
  root mkdir -p "$INSTALL_ROOT/app" || return 1
  root rsync -a --delete --exclude='.git' --exclude='data' --exclude='pruebas' --exclude='assets/subidas' \
    --exclude='*.sh' --exclude='*.md' --exclude='Claude outputs' --exclude='.seshat-zip' --exclude='.seshat-instance' \
    "$source/" "$INSTALL_ROOT/app/" || return 1
  # Puntos de montaje vacíos: ./app se monta en solo lectura y Docker no puede crear dentro las
  # carpetas donde monta data, pruebas y subidas («read-only file system» al iniciar el contenedor).
  root mkdir -p "$INSTALL_ROOT/app/data" "$INSTALL_ROOT/app/pruebas" "$INSTALL_ROOT/app/assets/subidas"
}
# --- Instalar / actualizar desde una carpeta local (por defecto, la del script), sin GitHub.
# Busca el código suelto (database.php, index.php y seguridad.php) en la carpeta, en
# Apache24/htdocs/web o en web/; si no está, ofrece los .zip de la carpeta (y de Seshat_Evaluaciones/).
LOCAL_SOURCE_DIR=''
choose_local_dir(){
  local chosen
  read -rp "Carpeta con Seshat (código o .zip) [$SCRIPT_DIR]: " chosen </dev/tty || chosen=''
  LOCAL_SOURCE_DIR="${chosen:-$SCRIPT_DIR}"
  LOCAL_SOURCE_DIR="${LOCAL_SOURCE_DIR%/}"
  [[ "$LOCAL_SOURCE_DIR" == /* && -d "$LOCAL_SOURCE_DIR" ]] || { fail "No existe la carpeta $LOCAL_SOURCE_DIR (usa una ruta absoluta)."; return 1; }
  [[ "$LOCAL_SOURCE_DIR" != "$INSTALL_ROOT" && "$LOCAL_SOURCE_DIR" != "$INSTALL_ROOT/app" ]] || {
    fail 'Esa carpeta es la propia instancia instalada: indica la carpeta donde está el código nuevo de Seshat.'; return 1; }
}
local_project() (
  local temp source='' candidate
  temp="$(mktemp -d /tmp/seshat-local.XXXXXX)" || exit 1
  trap 'rm -rf -- "$temp"' EXIT
  for candidate in "$LOCAL_SOURCE_DIR" "$LOCAL_SOURCE_DIR/Apache24/htdocs/web" "$LOCAL_SOURCE_DIR/web"; do
    if [[ -f "$candidate/database.php" && -f "$candidate/index.php" && -f "$candidate/seguridad.php" ]]; then source="$candidate"; break; fi
  done
  if [[ -z "$source" ]]; then
    source="$(extraer_zip_repositorio "$LOCAL_SOURCE_DIR" "$temp/zip")" || exit 1
  fi
  [[ -n "$source" ]] || { fail "No se encontró Seshat en $LOCAL_SOURCE_DIR: ni el código (database.php, index.php y seguridad.php) en la carpeta, en Apache24/htdocs/web o en web/, ni un .zip."; exit 1; }
  printf 'Usando el código de %s\n' "$source" >&2
  copy_project_source "$source" || exit 1
)
# Origen del código: 'github' (por defecto) o 'local'.
get_project(){
  if [[ "${1:-github}" == local ]]; then
    choose_local_dir && local_project
  else
    download_project
  fi
}
write_runtime(){
  root mkdir -p "$INSTALL_ROOT/runtime" "$INSTALL_ROOT/data" "$INSTALL_ROOT/pruebas" "$INSTALL_ROOT/subidas" || return 1
  local docker_upload="${SESHAT_UPLOAD_MB:-20}" docker_post="${SESHAT_POST_MB:-24}" docker_memory="${SESHAT_MEMORY_MB:-128}"
  local solo_lectura=0 montaje_app
  if [[ -f "$INSTALL_ROOT/.env" ]]; then
    docker_upload="$(grep -E '^SESHAT_UPLOAD_MB=' "$INSTALL_ROOT/.env" | tail -1 | cut -d= -f2)"; docker_upload="${docker_upload:-20}"
    docker_post="$(grep -E '^SESHAT_POST_MB=' "$INSTALL_ROOT/.env" | tail -1 | cut -d= -f2)"; docker_post="${docker_post:-24}"
    docker_memory="$(grep -E '^SESHAT_MEMORY_MB=' "$INSTALL_ROOT/.env" | tail -1 | cut -d= -f2)"; docker_memory="${docker_memory:-128}"
    solo_lectura="$(grep -E '^SESHAT_CODIGO_SOLO_LECTURA=' "$INSTALL_ROOT/.env" | tail -1 | cut -d= -f2)"; solo_lectura="${solo_lectura:-0}"
  fi
  # Código con escritura (por defecto, como en la instalación tradicional): así funciona
  # Ajustes → Actualizar Seshat desde la web. Con SESHAT_CODIGO_SOLO_LECTURA=1 (opción 19 del menú)
  # el código queda en solo lectura y se actualiza únicamente con este instalador.
  montaje_app='./app:/var/www/html'
  [[ "$solo_lectura" == 1 ]] && montaje_app='./app:/var/www/html:ro'
  root tee "$INSTALL_ROOT/runtime/Dockerfile" >/dev/null <<DOCKERFILE
FROM php:8.4-apache
RUN apt-get update && apt-get install -y --no-install-recommends libonig-dev libsqlite3-dev libcurl4-openssl-dev libpng-dev libjpeg62-turbo-dev libfreetype6-dev libzip-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo_mysql pdo_sqlite mbstring curl gd zip \
    && a2enmod rewrite headers expires deflate && rm -rf /var/lib/apt/lists/*
COPY seshat.conf /etc/apache2/conf-enabled/seshat.conf
RUN printf 'upload_max_filesize=${docker_upload}M\npost_max_size=${docker_post}M\nmemory_limit=${docker_memory}M\n' > /usr/local/etc/php/conf.d/seshat.ini
DOCKERFILE
  root tee "$INSTALL_ROOT/runtime/seshat.conf" >/dev/null <<'APACHE'
DirectoryIndex index.php index.html
<Directory /var/www/html>
    AllowOverride All
    Require all granted
    Options -Indexes
    <FilesMatch "^(database|seguridad|plantilla|politica_pruebas|correo|nextcloud)\.php$">
        Require all denied
    </FilesMatch>
    <FilesMatch "\.(sqlite.*|key|sh|md|ejemplo)$">
        Require all denied
    </FilesMatch>
</Directory>
<Directory /var/www/html/data>
    Require all denied
</Directory>
<Directory /var/www/html/pruebas>
    <FilesMatch "\.php$">
        Require all denied
    </FilesMatch>
</Directory>
<Directory /var/www/html/assets/subidas>
    <FilesMatch "\.php$">
        Require all denied
    </FilesMatch>
</Directory>
APACHE
  root tee "$INSTALL_ROOT/compose.yaml" >/dev/null <<COMPOSE
services:
  web:
    build: ./runtime
    restart: unless-stopped
    ports:
      - "\${HTTP_PORT:-8081}:80"
    environment:
      SESHAT_DRIVER: sqlite
      SESHAT_SQLITE: /var/www/html/data/simce.sqlite
    volumes:
      - ${montaje_app}
      - ./data:/var/www/html/data
      - ./pruebas:/var/www/html/pruebas
      - ./subidas:/var/www/html/assets/subidas
COMPOSE
  root chown -R 33:33 "$INSTALL_ROOT/data" "$INSTALL_ROOT/pruebas" "$INSTALL_ROOT/subidas" || return 1
  # Con escritura, el código es de www-data (33) dentro del contenedor, para que el actualizador web
  # pueda reemplazarlo; en solo lectura se deja como está.
  if [[ "$solo_lectura" != 1 && -d "$INSTALL_ROOT/app" ]]; then
    root chown -R 33:33 "$INSTALL_ROOT/app" || return 1
  fi
  root chmod 750 "$INSTALL_ROOT/data" || return 1
  printf 'seshat-evaluaciones\n' | root tee "$INSTALL_ROOT/.seshat-instance" >/dev/null
}
show_url(){
  ready || return 1
  installation_summary "$INSTALL_ROOT" docker
}
set_port(){
  if [[ -f "/etc/apache2/sites-available/$(proxy_name "$INSTALL_ROOT").conf" ]]; then
    fail 'Esta instancia tiene proxy inverso. Cambia el puerto desde Crear VirtualHost con proxy inverso para mantener ambos sincronizados.'; return 1
  fi
  local port
  read -rp 'Puerto HTTP [8081]: ' port; port="${port:-8081}"
  [[ "$port" =~ ^[0-9]{1,5}$ ]] && ((10#$port >= 1 && 10#$port <= 65535)) || { fail 'Puerto inválido.'; return 1; }
  # Solo cambia HTTP_PORT (antes se reescribía el .env completo y se perdían los límites de PHP).
  docker_env_set HTTP_PORT "$((10#$port))"
}
# Permite o impide actualizar el código desde Ajustes → Actualizar Seshat (montaje con o sin escritura).
toggle_web_update(){
  ready || return 1
  local actual nuevo='' respuesta
  actual="$(grep -E '^SESHAT_CODIGO_SOLO_LECTURA=' "$INSTALL_ROOT/.env" 2>/dev/null | tail -1 | cut -d= -f2)"
  if [[ "$actual" == 1 ]]; then
    printf 'Ahora: el código está en SOLO LECTURA (se actualiza solo con este instalador).\n'
    read -rp '¿Permitir actualizar desde la web (Ajustes → Actualizar Seshat)? (s/N): ' respuesta
    [[ "$respuesta" =~ ^[sS]$ ]] && nuevo=0
  else
    printf 'Ahora: se PUEDE actualizar desde la web (Ajustes → Actualizar Seshat).\n'
    read -rp '¿Impedirlo y dejar el código en solo lectura (más seguro)? (s/N): ' respuesta
    [[ "$respuesta" =~ ^[sS]$ ]] && nuevo=1
  fi
  [[ -n "$nuevo" ]] || { printf 'Sin cambios.\n'; return 0; }
  docker_env_set SESHAT_CODIGO_SOLO_LECTURA "$nuevo" && write_runtime && dc up -d || return 1
  if [[ "$nuevo" == 1 ]]; then ok 'Código en solo lectura: actualiza con las opciones 4 o 5.'; else ok 'Listo: ya se puede actualizar desde Ajustes → Actualizar Seshat.'; fi
}
install_app(){
  local origen="${1:-github}" chosen
  read -rp "Ruta de instalación [$INSTALL_ROOT]: " chosen
  INSTALL_ROOT="${chosen:-$INSTALL_ROOT}"
  valid_root || return 1
  if [[ -d "$INSTALL_ROOT" ]] && [[ -n "$(ls -A "$INSTALL_ROOT")" ]]; then fail 'La carpeta debe estar vacía. Para una instancia existente usa Actualizar.'; return 1; fi
  root docker compose version >/dev/null || { fail 'Docker no está instalado: usa primero la opción 1 (Instalar dependencias).'; return 1; }
  get_project "$origen" && write_runtime && set_port || return 1
  root cp -- "${BASH_SOURCE[0]}" "$INSTALL_ROOT/$(basename -- "${BASH_SOURCE[0]}")" || return 1
  dc up -d --build && show_url
}
backup(){
  ready || return 1
  local target running status=0
  target="/opt/seshat-respaldos/$(basename "$INSTALL_ROOT")-$(date +%Y%m%d-%H%M%S)-$$.tar.gz"
  root install -d -m 700 /opt/seshat-respaldos || return 1
  running="$(dc ps --status running -q web)" || return 1
  dc stop web || return 1
  # Detener escrituras mantiene consistente SQLite, incluyendo sus archivos WAL.
  root tar -czf "$target" -C "$INSTALL_ROOT" . || status=$?
  root chmod 600 "$target" || status=$?
  if [[ -n "$running" ]]; then dc start web || status=$?; fi
  (( status == 0 )) || { fail 'No se completó el respaldo o el reinicio.'; return 1; }
  printf 'Respaldo: %s\n' "$target"
}
update_app(){
  local origen="${1:-github}"
  # La carpeta se elige antes del respaldo, para no detener Seshat si la ruta está mal.
  ready || return 1
  if [[ "$origen" == local ]]; then
    choose_local_dir || return 1
    backup && local_project || return 1
  else
    backup && download_project || return 1
  fi
  # Se regenera compose.yaml (aplica el montaje con o sin escritura y los dueños de los archivos).
  write_runtime || return 1
  dc up -d --build && show_url
}
restore(){
  ready || return 1
  local archive confirmation staging entry
  read -rp 'Ruta absoluta del respaldo creado por este instalador: ' archive
  [[ "$archive" == /* && -f "$archive" ]] || return 1
  # Solo respaldos propios y confiables: contienen código ejecutable y datos.
  root tar -tzf "$archive" >/dev/null || return 1
  if root tar -tvzf "$archive" | awk 'substr($0,1,1) != "-" && substr($0,1,1) != "d" {bad=1} END {exit !bad}'; then
    fail 'El respaldo contiene enlaces o archivos especiales no admitidos.'; return 1
  fi
  while IFS= read -r entry; do
    [[ "$entry" != /* && "/$entry/" != *'/../'* ]] || { fail 'Ruta inválida en el respaldo.'; return 1; }
  done < <(root tar -tzf "$archive")
  read -rp 'Se reemplazará esta instancia. Escribe RESTAURAR: ' confirmation
  [[ "$confirmation" == RESTAURAR ]] || return 1
  backup || return 1
  staging="$(mktemp -d /tmp/seshat-restaurar.XXXXXX)" || return 1
  if ! root tar -xzf "$archive" --no-same-owner -C "$staging" || [[ ! -f "$staging/.seshat-instance" || ! -f "$staging/compose.yaml" ]]; then
    root rm -rf -- "$staging"; fail 'El archivo no es un respaldo Seshat válido.'; return 1
  fi
  dc down || { root rm -rf -- "$staging"; return 1; }
  root rsync -a --delete "$staging/" "$INSTALL_ROOT/" || { root rm -rf -- "$staging"; return 1; }
  root rm -rf -- "$staging"
  root chown -R 33:33 "$INSTALL_ROOT/data" "$INSTALL_ROOT/pruebas" "$INSTALL_ROOT/subidas" || return 1
  dc up -d --build
}
diagnose(){
  ready || return 1
  dc ps
  dc exec -T --user www-data web php -r 'require "database.php"; db()->query("SELECT 1"); echo "Base de datos Seshat accesible\n";'
}
uninstall(){
  ready || return 1
  local confirmation
  read -rp "Se borrará $INSTALL_ROOT y sus datos. Escribe ELIMINAR SESHAT: " confirmation
  [[ "$confirmation" == 'ELIMINAR SESHAT' ]] || return 1
  backup && remove_proxy "$INSTALL_ROOT" && dc down --rmi local || return 1
  root rm -rf -- "$INSTALL_ROOT"
}
# BEGIN SESHAT HOST MANAGEMENT
disable_default_page(){
  local was_enabled=0
  command -v a2dissite >/dev/null && command -v apache2ctl >/dev/null || {
    fail 'No se encontró Apache de Debian/Ubuntu en este servidor.'; return 1;
  }
  if [[ -e /etc/apache2/sites-enabled/000-default.conf || -L /etc/apache2/sites-enabled/000-default.conf ]]; then
    was_enabled=1
    root a2dissite 000-default.conf >/dev/null || return 1
  fi
  printf 'Validando configuración y reiniciando Apache2...\n'
  if ! { root apache2ctl configtest && root systemctl restart apache2 && root systemctl is-active --quiet apache2; }; then
    if ((was_enabled)); then root a2ensite 000-default.conf >/dev/null; fi
    root apache2ctl configtest && root systemctl restart apache2
    fail 'Falló la aplicación del cambio; se intentó recuperar el estado anterior. Revisa systemctl status apache2.'; return 1
  fi
  if [[ -e /etc/apache2/sites-enabled/000-default.conf || -L /etc/apache2/sites-enabled/000-default.conf ]]; then
    fail 'Apache reinició, pero 000-default.conf sigue habilitado.'; return 1
  fi
  printf 'Verificado: 000-default.conf deshabilitado y Apache2 reiniciado y activo.\n'
  printf 'Los demás sitios y /var/www/html/index.html se conservan.\n'
  printf 'Si Seshat usa 8081, entra mediante http://IP-del-servidor:8081/.\n'
  printf 'Si aún aparece la bienvenida, revisa los otros VirtualHosts con sudo apache2ctl -S.\n'
}
service_status(){
  local state
  if command -v systemctl >/dev/null 2>&1; then
    state="$(systemctl is-active "$1" 2>/dev/null)" || true
    printf '%s' "${state:-no disponible}"
  else printf 'no disponible (sin systemd)'; fi
}
listening_port(){
  local sockets
  if ! command -v ss >/dev/null 2>&1; then printf 'no comprobado (falta ss)'; return; fi
  sockets="$(ss -ltnH 2>/dev/null)" || { printf 'no se pudo comprobar'; return; }
  if awk '{print $4}' <<< "$sockets" | grep -Eq ":${1}$"; then
    printf 'en escucha'
  else printf 'sin escucha'; fi
}
installation_summary(){
  local instance="$1" mode="${2:-traditional}" ip ips conf proxy port='' protocol=http name='' url http_code='' php_version modules driver db_info
  local cyan='\033[1;36m' reset='\033[0m'
  ip=''
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')"
  fi
  ips="$(hostname -I 2>/dev/null)" || ips=''
  [[ -n "$ip" ]] || ip="$(awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\./) {print $i; exit}}' <<< "$ips")"
  printf '\n%b========================================================%b\n' "$cyan" "$reset"
  printf '%b Seshat-Evaluaciones · Resumen de la instalación%b\n' "$cyan" "$reset"
  printf '%b========================================================%b\n' "$cyan" "$reset"
  printf 'Modalidad:       %s\nCarpeta:         %s\n' "$mode" "$instance"
  printf 'Servidor:        %s\nIP principal:    %s\nIP del equipo:   %s\n' "$(hostname 2>/dev/null || printf 'no disponible')" "${ip:-no detectada}" "${ips:-no detectadas}"
  proxy="/etc/apache2/sites-enabled/$(proxy_name "$instance").conf"
  conf=/etc/apache2/sites-enabled/seshat.conf
  if [[ -f "$proxy" ]]; then conf="$proxy"; fi
  if [[ "$mode" == docker && ! -f "$proxy" ]]; then
    port="$(root sed -n 's/^HTTP_PORT=//p' "$instance/.env" 2>/dev/null)"
    conf=''
  elif [[ -f "$conf" ]]; then
    port="$(awk '/^[[:space:]]*<VirtualHost / {v=$2; sub(/>$/, "", v); sub(/^.*:/, "", v); print v; exit}' "$conf")"
    name="$(awk '/^[[:space:]]*ServerName / {print $2; exit}' "$conf")"
    if grep -Eiq '^[[:space:]]*SSLEngine[[:space:]]+on' "$conf"; then protocol=https; fi
  fi
  if [[ "$port" =~ ^[0-9]+$ ]]; then
    printf 'Protocolo:       %s\nPuerto web:      %s (%s)\n' "$protocol" "$port" "$(listening_port "$port")"
    name="${name:-${ip:-localhost}}"
    url="$protocol://$name"
    if [[ "$protocol:$port" != http:80 && "$protocol:$port" != https:443 ]]; then url+=":$port"; fi
    url+='/'
    printf 'URL de acceso:   %s\nAcceso docente:  %sautenticacion.php\n' "$url" "$url"
    if [[ -n "$conf" ]]; then printf 'VirtualHost:     %s\n' "$conf"; fi
    if [[ -f "$proxy" ]]; then
      printf 'Proxy inverso:   %s\n' "$(awk '/^[[:space:]]*ProxyPass[[:space:]]/ {print $3; exit}' "$proxy")"
      printf 'Dominio/IP:      %s (debe resolver hacia este servidor)\n' "$name"
    else printf 'Proxy inverso:   no configurado por este instalador\n'; fi
    if command -v curl >/dev/null 2>&1; then
      # Comprobación local: no depende del DNS del dominio ni sigue redirecciones.
      http_code="$(curl --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 3 --max-time 8 --resolve "$name:$port:127.0.0.1" "$url" 2>/dev/null)" || http_code='000'
      case "$http_code" in
        2??) printf 'Prueba web local: HTTP %s (respuesta recibida)\n' "$http_code";;
        3??) printf 'Prueba web local: HTTP %s (redirección)\n' "$http_code";;
        000) printf 'Prueba web local: sin respuesta válida; revisar servicio, puerto o certificado\n';;
        *) printf 'Prueba web local: HTTP %s (revisar aplicación/vhost)\n' "$http_code";;
      esac
    else printf 'Prueba web local: no realizada (curl no instalado)\n'; fi
    [[ "$protocol" == https ]] || printf 'HTTPS/TLS:       no configurado en este acceso; actualmente usa HTTP\n'
  else printf 'URL y puerto:    no se encontró una configuración activa reconocible\n'; fi
  printf '\n%bServicios y componentes%b\n' "$cyan" "$reset"
  printf 'Apache del host: %s\n' "$(service_status apache2)"
  if [[ "$mode" == docker ]]; then
    printf 'Docker:          %s\n' "$(service_status docker)"
    dc ps
    php_version="$(dc exec -T web php -r 'echo PHP_VERSION;' 2>/dev/null)" || php_version='no disponible'
    printf 'PHP contenedor:  %s\n' "$php_version"
    printf 'Base de datos:   SQLite (%s/data/simce.sqlite)\n' "$instance"
    printf 'MariaDB:         no requerido por esta modalidad Docker\n'
    printf 'Registros:       opción 10 del menú Docker\n'
  else
    printf 'MariaDB:         %s\n' "$(service_status mariadb)"
    php_version="$(php -r 'echo PHP_VERSION;' 2>/dev/null)" || php_version='no disponible'
    printf 'PHP CLI:         %s\n' "$php_version"
    modules="$(apache2ctl -M 2>/dev/null)" || modules=''
    if grep -Eq 'php[0-9]*_module' <<< "$modules"; then printf 'PHP en Apache:   módulo PHP habilitado\n'
    elif grep -q proxy_fcgi_module <<< "$modules"; then printf 'PHP en Apache:   proxy_fcgi habilitado; revisar servicio PHP-FPM\n'
    else printf 'PHP en Apache:   integración no detectada\n'; fi
    db_info="$(php -r '$p=$argv[1]; $c=is_file($p."/data/config.php") ? include $p."/data/config.php" : []; if(!is_array($c)) exit(1); $d=$c["driver"]??"sqlite"; if($d==="sqlite") {$f=$c["sqlite_archivo"]??$p."/data/simce.sqlite"; echo "SQLite — ".$f." — ".(is_file($f)?"archivo presente":"se creará al primer ingreso");} elseif($d==="mysql") {echo "MariaDB/MySQL — base ".($c["base"]??"simce")." en ".($c["host"]??"127.0.0.1").":".($c["puerto"]??3306)." (conexión no verificada)";} else echo "motor no reconocido";' "$instance" 2>/dev/null)" || db_info='no se pudo leer la configuración'
    printf 'Base de datos:   %s\n' "$db_info"
    printf 'Registro Apache: /var/log/apache2/seshat-error.log\n'
    [[ ! -f "$proxy" ]] || printf 'Registro proxy:  /var/log/apache2/seshat-proxy-error.log\n'
    printf 'Gestión de BD:   opción 4 para elegir o cambiar el motor\n'
  fi
  printf 'Primer ingreso:  abre la URL y pulsa Acceso para crear el superadministrador, si aún no existe.\n'
  printf 'Alcance:         la prueba local no verifica acceso desde otros equipos ni reglas de firewall.\n\n'
}
valid_seshat_path(){
  local path="$1" resolved
  [[ "$path" =~ ^/opt/[a-zA-Z0-9_-]+$ || "$path" =~ ^/var/www/html/[a-zA-Z0-9_-]+$ ]] || { fail 'Ruta de instalación no permitida.'; return 1; }
  resolved="$(realpath -e -- "$path")" || return 1
  [[ "$resolved" == "$path" && ! -L "$path" ]] || { fail 'La ruta debe ser real, sin enlaces simbólicos.'; return 1; }
}
proxy_name(){ printf 'seshat-proxy-%s' "$(printf '%s' "$1" | sha256sum | cut -c1-12)"; }
valid_backend_port(){
  [[ "$1" =~ ^[0-9]{1,5}$ ]] && ((10#$1 >= 1024 && 10#$1 <= 65535))
}
render_proxy(){
  local name="$1" port="$2" instance="$3"
  cat <<EOF
# Seshat instance: $instance
<VirtualHost *:80>
    ServerName $name
    ProxyRequests Off
    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "http"
    ProxyPass / http://127.0.0.1:$port/
    ProxyPassReverse / http://127.0.0.1:$port/
    ErrorLog \${APACHE_LOG_DIR}/seshat-proxy-error.log
    CustomLog \${APACHE_LOG_DIR}/seshat-proxy-access.log combined
</VirtualHost>
EOF
}
render_initial_vhost(){
  local instance="$1"
  cat <<EOF
<VirtualHost *:80>
    DocumentRoot "$instance"
    <Directory "$instance">
        DirectoryIndex index.php index.html
        Options -Indexes
        AllowOverride All
        Require all granted
        <FilesMatch "^(database|seguridad|plantilla|politica_pruebas|correo|nextcloud)\\.php$">
            Require all denied
        </FilesMatch>
        <FilesMatch "\\.(sqlite.*|key|sh|md|ejemplo)$">
            Require all denied
        </FilesMatch>
    </Directory>
    <Directory "$instance/data">
        Require all denied
    </Directory>
    <Directory "$instance/pruebas">
        <FilesMatch "\\.php$">
            Require all denied
        </FilesMatch>
    </Directory>
    <Directory "$instance/assets/subidas">
        <FilesMatch "\\.php$">
            Require all denied
        </FilesMatch>
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/seshat-error.log
    CustomLog \${APACHE_LOG_DIR}/seshat-access.log combined
</VirtualHost>
EOF
}
render_direct_vhost(){
  local source="$1" port="$2"
  # El archivo pertenece solo a Seshat; conservar las reglas PHP y de acceso.
  printf 'Listen %s\n' "$port"
  sed -E '/^[[:space:]]*Listen[[:space:]]+/d; s/^[[:space:]]*<VirtualHost [^>]+>/<VirtualHost *:'"$port"'>/' "$source"
}
configure_direct_port() (
  local instance="$1" port conf=/etc/apache2/sites-available/seshat.conf temp proxy id enabled=0 proxy_enabled=0 occupied
  valid_seshat_path "$instance" || return 1
  [[ -f "$instance/database.php" && -f "$instance/index.php" ]] || { fail 'No se encontró Seshat en la carpeta.'; return 1; }
  command -v apache2ctl >/dev/null || { fail 'Apache no está instalado. Usa primero Instalar dependencias.'; return 1; }
  if [[ -e "$conf" ]]; then
    root grep -Fq "DocumentRoot \"$instance\"" "$conf" || { fail 'seshat.conf pertenece a otra instalación; no se reemplazó.'; return 1; }
  fi
  command -v ss >/dev/null || { fail 'Falta ss para comprobar puertos. Instala iproute2.'; return 1; }
  read -rp 'Puerto de acceso directo [8081]: ' port; port="${port:-8081}"
  valid_backend_port "$port" || { fail 'Elige un puerto entre 1024 y 65535; el puerto 80 queda reservado para los otros servicios.'; return 1; }
  port="$((10#$port))"
  occupied="$(ss -ltnH)" || return 1
  if awk '{print $4}' <<< "$occupied" | grep -Eq ":${port}$"; then
    if [[ ! -e /etc/apache2/sites-enabled/seshat.conf ]] || ! root grep -Eq "^[[:space:]]*Listen[[:space:]]+(127\\.0\\.0\\.1:)?${port}[[:space:]]*$" "$conf"; then
      fail "El puerto $port está ocupado. Elige otro."; return 1
    fi
  fi
  temp="$(mktemp -d /tmp/seshat-puerto.XXXXXX)" || return 1
  trap 'root rm -rf -- "$temp"' EXIT
  if [[ -f "$conf" ]]; then
    root cp "$conf" "$temp/anterior.conf" || return 1
    root cp "$conf" "$temp/base.conf" || return 1
  else
    printf 'No existe seshat.conf; se creará para esta instalación.\n'
    render_initial_vhost "$instance" > "$temp/base.conf" || return 1
  fi
  render_direct_vhost "$temp/base.conf" "$port" > "$temp/nuevo.conf" || return 1
  id="$(proxy_name "$instance")"; proxy="/etc/apache2/sites-available/$id.conf"
  [[ -e /etc/apache2/sites-enabled/seshat.conf ]] && enabled=1
  if [[ -e "/etc/apache2/sites-enabled/$id.conf" ]]; then
    root grep -Fxq "# Seshat instance: $instance" "$proxy" || { fail 'El proxy activo no pertenece a esta instalación.'; return 1; }
    proxy_enabled=1
  fi
  apply_direct_port(){
    root cp "$temp/nuevo.conf" "$conf" || return 1
    root a2ensite seshat.conf >/dev/null || return 1
    # Cambiar esta instancia de proxy a acceso directo sin alterar otros sitios.
    if ((proxy_enabled)); then root a2dissite "$id.conf" >/dev/null || return 1; fi
    root apache2ctl configtest && root systemctl reload apache2
  }
  if ! apply_direct_port; then
    if [[ -f "$temp/anterior.conf" ]]; then root cp "$temp/anterior.conf" "$conf"; else root rm -f -- "$conf"; fi
    ((enabled)) || root a2dissite seshat.conf >/dev/null
    if ((proxy_enabled)); then root a2ensite "$id.conf" >/dev/null; fi
    root apache2ctl configtest && root systemctl reload apache2
    fail 'No se pudo activar el puerto; se restauró la configuración anterior.'; return 1
  fi
  printf 'Seshat configurado para acceso directo por el puerto %s.\n' "$port"
  installation_summary "$instance" traditional
)
configure_proxy() (
  local mode="$1" instance="$2" port name default_port=8081 id file temp native old_default=0 was_enabled=0
  valid_seshat_path "$instance" || return 1
  command -v apache2ctl >/dev/null || { fail 'Instala Apache en el servidor (sudo apt-get install apache2) antes de configurar el proxy.'; return 1; }
  if [[ "$mode" == docker ]]; then
    default_port="$(root sed -n 's/^HTTP_PORT=//p' "$instance/.env")"
    default_port="${default_port:-8081}"
  fi
  read -rp 'Dominio o IP para acceder a Seshat [seshat.local]: ' name; name="${name:-seshat.local}"
  [[ ${#name} -le 253 && "$name" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && "$name" != *..* ]] || { fail 'Escribe solo el dominio o IPv4, sin http:// ni rutas.'; return 1; }
  read -rp "Puerto interno de Seshat [$default_port]: " port; port="${port:-$default_port}"
  valid_backend_port "$port" || { fail 'El puerto interno debe estar entre 1024 y 65535.'; return 1; }
  port="$((10#$port))"
  id="$(proxy_name "$instance")"; file="/etc/apache2/sites-available/$id.conf"
  native=/etc/apache2/sites-available/seshat.conf
  temp="$(mktemp -d /tmp/seshat-vhost.XXXXXX)" || return 1
  trap 'rm -rf -- "$temp"' EXIT
  if [[ -e "$file" ]]; then
    root grep -Fxq "# Seshat instance: $instance" "$file" || { fail 'El vhost existente no pertenece a esta instancia.'; return 1; }
    root cp "$file" "$temp/proxy" || return 1
  fi
  [[ -e "/etc/apache2/sites-enabled/$id.conf" ]] && was_enabled=1
  [[ -e /etc/apache2/sites-enabled/000-default.conf ]] && old_default=1
  if [[ "$mode" == traditional ]]; then
    [[ -f "$instance/database.php" && -f "$instance/index.php" ]] || { fail 'No se encontró Seshat en la carpeta.'; return 1; }
    root grep -Fq "DocumentRoot \"$instance\"" "$native" || { fail 'Primero configura el sitio Seshat de esta instalación.'; return 1; }
    if command -v ss >/dev/null && ss -ltnH | awk '{print $4}' | grep -Eq ":${port}$"; then
      [[ -e /etc/apache2/sites-enabled/seshat.conf ]] && root grep -Eq "^[[:space:]]*Listen[[:space:]]+(127\\.0\\.0\\.1:)?${port}[[:space:]]*$" "$native" || { fail 'Ese puerto está ocupado por otro servicio.'; return 1; }
    fi
    root cp "$native" "$temp/native" || return 1
    { printf 'Listen 127.0.0.1:%s\n' "$port"; sed -E '/^[[:space:]]*Listen[[:space:]]+/d; s/^<VirtualHost [^>]+>/<VirtualHost 127.0.0.1:'"$port"'>/' "$temp/native"; } > "$temp/new-native"
  else
    # El cambio se aplica también al puerto publicado por Docker.
    root cp "$instance/.env" "$temp/env" || return 1
  fi
  render_proxy "$name" "$port" "$instance" > "$temp/new-proxy"
  root a2enmod proxy proxy_http headers >/dev/null || return 1
  # Restaurar configuraciones anteriores si falla cualquier paso de activación.
  rollback_proxy(){
    if [[ -f "$temp/proxy" ]]; then root cp "$temp/proxy" "$file"; else root rm -f -- "$file"; fi
    (( was_enabled == 1 )) || root a2dissite "$id.conf" >/dev/null
    if [[ -f "$temp/native" ]]; then root cp "$temp/native" "$native"; fi
    if [[ -f "$temp/env" ]]; then root cp "$temp/env" "$instance/.env"; dc up -d; fi
    (( old_default == 0 )) || root a2ensite 000-default.conf >/dev/null
    root apache2ctl configtest && root systemctl reload apache2
  }
  apply_proxy(){
    root cp "$temp/new-proxy" "$file" || return 1
    if [[ "$mode" == traditional ]]; then root cp "$temp/new-native" "$native" || return 1
    else
      printf 'HTTP_PORT=%s\n' "$port" | root tee "$instance/.env" >/dev/null || return 1
      dc up -d || return 1
    fi
    root a2ensite "$id.conf" >/dev/null || return 1
    (( old_default == 0 )) || root a2dissite 000-default.conf >/dev/null || return 1
    root apache2ctl configtest && root systemctl reload apache2
  }
  if ! apply_proxy; then rollback_proxy; fail 'Falló la activación; se restauró la configuración anterior.'; return 1; fi
  printf 'Proxy creado: http://%s/ -> http://127.0.0.1:%s/\n' "$name" "$port"
  printf 'Si usas un dominio, apunta su DNS o archivo hosts a la IP de este servidor.\n'
  installation_summary "$instance" "$mode"
)
remove_proxy(){
  local instance="$1" id file
  id="$(proxy_name "$instance")"; file="/etc/apache2/sites-available/$id.conf"
  [[ -e "$file" ]] || return 0
  root grep -Fxq "# Seshat instance: $instance" "$file" || { fail 'No se puede eliminar un vhost ajeno.'; return 1; }
  root a2dissite "$id.conf" >/dev/null && root rm -f -- "$file" || return 1
  root apache2ctl configtest && root systemctl reload apache2
}
uninstall_traditional() (
  requiere_root || return 1
  local destino confirmation cfg driver host database user snapshot grants db_port sqlite_path drop_user=0
  destino="$(pedir_destino)" || return 1
  valid_seshat_path "$destino" || return 1
  [[ -f "$destino/database.php" && -f "$destino/seguridad.php" && -f "$destino/index.php" ]] || { fail 'La carpeta no contiene una instalación Seshat.'; return 1; }
  # Leer configuración sin abrir la aplicación ni ejecutar migraciones.
  cfg="$(php -r '$c=is_file($argv[1]."/data/config.php") ? include $argv[1]."/data/config.php" : []; if(!is_array($c)) exit(1); echo implode("|",[$c["driver"]??"sqlite",$c["host"]??"127.0.0.1",$c["base"]??"simce",$c["usuario"]??"simce",$c["puerto"]??3306,$c["sqlite_archivo"]??$argv[1]."/data/simce.sqlite"]);' "$destino")" || return 1
  IFS='|' read -r driver host database user db_port sqlite_path <<< "$cfg"
  if [[ "$driver" == mysql ]]; then
    [[ "$host" == 127.0.0.1 || "$host" == localhost ]] || { fail 'La base es remota: desinstalación cancelada para no borrar datos en otro servidor.'; return 1; }
    [[ "$database" =~ ^[a-zA-Z0-9_]+$ && "$user" =~ ^[a-zA-Z0-9_]+$ ]] || { fail 'Nombre de base o usuario no compatible con borrado automático.'; return 1; }
    case "$database" in mysql|sys|information_schema|performance_schema) fail 'Base del sistema: operación cancelada.'; return 1;; esac
    if ! mysql -u root -e 'SELECT 1' >/dev/null 2>&1; then
      read -rsp 'Contraseña de root de MariaDB: ' MYSQL_PWD; printf '\n'; export MYSQL_PWD
    fi
    mysql -u root -e 'SELECT 1' >/dev/null || return 1
    [[ "$(mysql -u root -BN -e 'SELECT @@port')" == "$db_port" ]] || { fail 'El servidor MariaDB local no coincide con el puerto configurado; no se borró nada.'; return 1; }
    # Solo borrar la cuenta cuando no tiene permisos sobre otras bases.
    if [[ "$user" != root ]]; then
      grants="$(mysql -u root -BN -e "SHOW GRANTS FOR '$user'@'127.0.0.1'" 2>/dev/null)" || grants=''
      if [[ -n "$grants" ]] && ! printf '%s\n' "$grants" | grep -Fv "GRANT USAGE ON *.*" | grep -Fv "GRANT ALL PRIVILEGES ON \`$database\`.*" | grep -q .; then drop_user=1; fi
    fi
    printf 'Se eliminará la base MariaDB %s.\n' "$database"
    if ((drop_user)); then printf 'Se eliminará la cuenta dedicada %s@127.0.0.1.\n' "$user"; else printf 'La cuenta MariaDB se conservará: no se confirmó que sea exclusiva de Seshat.\n'; fi
  elif [[ "$driver" == sqlite ]]; then
    [[ "$(realpath -m -- "$sqlite_path")" == "$destino/"* ]] || { fail 'SQLite está fuera de la instalación. Desinstalación cancelada; requiere tratar esa base por separado.'; return 1; }
  else fail 'Motor desconocido.'; return 1; fi
  printf 'Se eliminarán Seshat, SQLite local, pruebas, imágenes y vhosts de esta instalación: %s\n' "$destino"
  printf 'Apache, PHP y MariaDB permanecerán instalados. Se guardará un respaldo fuera de la aplicación.\n'
  read -rp 'Escribe ELIMINAR SESHAT para continuar: ' confirmation
  [[ "$confirmation" == 'ELIMINAR SESHAT' ]] || return 1
  snapshot="/opt/seshat-respaldos/$(basename "$destino")-desinstalacion-$(date +%Y%m%d-%H%M%S)-$$"
  umask 077
  mkdir -p "$snapshot" || return 1
  local proxy_file="/etc/apache2/sites-available/$(proxy_name "$destino").conf"
  if [[ -f "$proxy_file" ]]; then cp "$proxy_file" "$snapshot/proxy.conf" || return 1; fi
  # Deshabilitar solo los vhosts que apuntan a esta instalación.
  remove_proxy "$destino" || return 1
  if [[ -f /etc/apache2/sites-available/seshat.conf ]] && grep -Fq "DocumentRoot \"$destino\"" /etc/apache2/sites-available/seshat.conf; then
    cp /etc/apache2/sites-available/seshat.conf "$snapshot/seshat.conf" || return 1
    a2dissite seshat.conf >/dev/null || return 1
    apache2ctl configtest && systemctl reload apache2 || return 1
  fi
  tar -czf "$snapshot/archivos.tar.gz" -C "$destino" . || return 1
  if [[ "$driver" == mysql ]]; then
    mysqldump -u root --single-transaction --routines --triggers --events --databases "$database" > "$snapshot/base.sql" || return 1
    mysql -u root -e "DROP DATABASE \`$database\`;" || return 1
    if ((drop_user)); then mysql -u root -e "DROP USER '$user'@'127.0.0.1';" || return 1; fi
  fi
  valid_seshat_path "$destino" || return 1
  cd / || return 1
  rm -rf -- "$destino" || return 1
  [[ ! -f "$snapshot/seshat.conf" ]] || rm -f /etc/apache2/sites-available/seshat.conf
  if [[ -f "$MARCADOR_DESTINO" ]] && [[ "$(cat "$MARCADOR_DESTINO")" == "$destino" ]]; then rm -f -- "$MARCADOR_DESTINO"; fi
  printf 'Seshat desinstalado. Respaldo conservado en %s\n' "$snapshot"
)
# END SESHAT HOST MANAGEMENT
main(){
  local option
  while true; do
    limpiar_consola
    titulo_menu 'Seshat-Evaluaciones · Instalador GitHub-Token v5.2.7'
    printf 'Instancia: %s\n\n' "$INSTALL_ROOT"
    printf 'Instalación y actualización\n'
    opcion_menu 1 'Instalar dependencias'
    opcion_menu 2 'Instalar desde GitHub'
    opcion_menu 3 'Instalar desde esta carpeta (código o .zip local)'
    opcion_menu 4 'Actualizar desde GitHub'
    opcion_menu 5 'Actualizar desde esta carpeta (código o .zip local)'
    printf '\nEstado y servicios\n'
    opcion_menu 6 'Estado'
    opcion_menu 7 'Iniciar'
    opcion_menu 8 'Detener'
    opcion_menu 9 'Reiniciar'
    opcion_menu 10 'Registros'
    printf '\nAcceso web\n'
    opcion_menu 11 'Cambiar puerto'
    opcion_menu 12 'URL y acceso inicial'
    opcion_menu 13 'Crear VirtualHost con proxy inverso'
    opcion_menu 14 'Desactivar página predeterminada de Apache'
    opcion_menu 15 'Configurar memoria y tamaño de subida de PHP'
    printf '\nRespaldo y diagnóstico\n'
    opcion_menu 16 'Crear respaldo completo'
    opcion_menu 17 'Restaurar respaldo'
    opcion_menu 18 'Diagnóstico de base de datos'
    printf '\nMantenimiento\n'
    opcion_menu 19 'Permitir o impedir actualizar desde la web (Ajustes)'
    opcion_menu 20 'Desinstalar'
    opcion_menu 0 "${ETIQUETA_CERRAR:-Salir}"
    read -rp 'Opción: ' option || break
    case "$option" in
      1) dependencies;; 2) install_app;; 3) install_app local;;
      4) update_app;; 5) update_app local;;
      6) ready && dc ps;; 7) ready && dc up -d;; 8) ready && dc stop;;
      9) ready && dc restart;; 10) ready && dc logs --tail=150;;
      11) ready && set_port && dc up -d;; 12) show_url;;
      13) ready && configure_proxy docker "$INSTALL_ROOT";; 14) disable_default_page;;
      15) configure_php_limits_docker;;
      16) backup;; 17) restore;; 18) diagnose;;
      19) toggle_web_update;; 20) uninstall;; 0) break;; *) fail 'Opción inválida.';;
    esac
    pause
  done
}

# Modalidad tradicional incorporada: no necesita otro script junto al instalador.
traditional() (
#!/bin/bash
#
# Seshat · Plataforma de Ensayos SIMCE
# ---------------------------------------------------------------
# Gestion_Ensayo_SIMCE.sh — Instalador y herramienta de mantención
# para Debian/Ubuntu. Puede instalar/actualizar desde la propia
# carpeta del script (junto a database.php, index.php, etc.) o
# descargando el proyecto directamente desde GitHub.
#
# Uso:  sudo bash Gestion_Ensayo_SIMCE.sh
#
# Las opciones que instalan/actualizan sólo piden la ruta de destino;
# el repositorio de GitHub, la rama y la subcarpeta quedan fijos (se
# pueden cambiar exportando SESHAT_REPO_URL / SESHAT_REPO_BRANCH /
# SESHAT_REPO_SUBDIR antes de ejecutar el script, sin que el script
# pregunte nada por pantalla).
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARCADOR_DESTINO="$SCRIPT_DIR/.instalacion_destino"
DESTINO_DEFECTO="${SESHAT_INSTALL_DIR:-/var/www/html/seshat-evaluaciones}"
APACHE_USUARIO="www-data"
DB_NOMBRE_DEFECTO="seshat"
DB_USUARIO_DEFECTO="seshat"
REPO_URL_DEFECTO="${SESHAT_REPO_URL:-https://github.com/llancor/seshat}"
RAMA_DEFECTO="${SESHAT_REPO_BRANCH:-main}"
REPO_SUBCARPETA_DEFECTO="${SESHAT_REPO_SUBDIR:-}"
PAQUETES_BASE=(apache2 php php-sqlite3 php-mysql php-mbstring php-xml php-curl php-gd php-zip mariadb-server mariadb-client)

ROJO='\033[0;31m'; VERDE='\033[0;32m'; AMARILLO='\033[1;33m'; AZUL='\033[0;34m'; CIAN='\033[0;36m'; NEGRITA='\033[1m'; NC='\033[0m'
info()        { echo -e "${AZUL}➜${NC} $1"; }
ok()          { echo -e "${VERDE}✔${NC} $1"; }
error()       { echo -e "${ROJO}✘${NC} $1" >&2; }
advertencia() { echo -e "${AMARILLO}⚠${NC} $1"; }

requiere_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Esta opción necesita ejecutarse con sudo (sudo bash $(basename "$0"))."
        return 1
    fi
}

obtener_destino() {
    if [ -f "$MARCADOR_DESTINO" ]; then
        cat "$MARCADOR_DESTINO"
    else
        echo "$DESTINO_DEFECTO"
    fi
}

pedir_destino() {
    local defecto; defecto="$(obtener_destino)"
    read -rp "Carpeta de la instalación [$defecto]: " resp
    resp="${resp:-$defecto}"
    [[ "$resp" =~ ^/var/www/html/[a-zA-Z0-9_-]+$ || "$resp" =~ ^/opt/[a-zA-Z0-9_-]+$ ]] || {
        error 'Usa una carpeta propia bajo /var/www/html o /opt.'; return 1;
    }
    [[ ! -L "$resp" ]] || { error 'El destino no puede ser un enlace simbólico.'; return 1; }
    echo "$resp"
}

generar_clave() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
}

# Copia $1 -> $2 usando rsync si existe; si no, cp -r con exclusiones básicas.
copiar_arbol() {
    local origen="$1" destino="$2"; shift 2
    local excluir=("$@")   # nombres de carpeta a excluir (p.ej. data pruebas assets/subidas .git)
    verificar_git_rsync || return 1
    if command -v rsync >/dev/null 2>&1; then
        local args=(-a)
        for e in "${excluir[@]}"; do args+=(--exclude "$e/"); done
        rsync "${args[@]}" "$origen"/ "$destino"/
    else
        mkdir -p "$destino"
        for item in "$origen"/* "$origen"/.[!.]*; do
            [ -e "$item" ] || continue
            local base; base="$(basename "$item")"
            local saltar=0
            for e in "${excluir[@]}"; do [ "$base" = "$e" ] && saltar=1; done
            [ "$saltar" -eq 1 ] && continue
            cp -r "$item" "$destino"/
        done
    fi
}

# ===========================================================================
# Utilidades para instalar/actualizar desde GitHub
# ===========================================================================
verificar_git_rsync() {
    local faltan=()
    command -v git >/dev/null 2>&1 || faltan+=(git)
    command -v rsync >/dev/null 2>&1 || faltan+=(rsync)
    command -v unzip >/dev/null 2>&1 || faltan+=(unzip)
    if [ "${#faltan[@]}" -gt 0 ]; then
        info "Instalando dependencias necesarias (${faltan[*]})..." >&2
        apt-get update -y >&2 && apt-get install -y "${faltan[@]}" >&2 || return 1
    fi
}

# Clona $1 (rama $3, subcarpeta opcional $2) a una carpeta temporal y valida
# que contenga Seshat. Imprime "carpeta_temporal|carpeta_fuente" por stdout;
# quien la llame es responsable de borrar la carpeta temporal al terminar.
descargar_desde_github() {
    local url="$1" subcarpeta="$2" rama="$3" temp origen
    verificar_git_rsync >&2 || return 1
    temp="$(mktemp -d /tmp/seshat-github.XXXXXX)" || return 1
    github_clone "$url" "$rama" "$temp/repo" || { rm -rf -- "$temp"; return 1; }
    origen="$(extraer_zip_repositorio "$temp/repo")" || { rm -rf -- "$temp"; return 1; }
    if [[ -z "$origen" ]]; then
        origen="$temp/repo/${subcarpeta:-.}"
        if [[ -z "$subcarpeta" && ! -f "$origen/database.php" ]]; then origen="$temp/repo/Apache24/htdocs/web"; fi
    fi
    [[ -f "$origen/database.php" && -f "$origen/index.php" ]] || {
        rm -rf -- "$temp"; error 'No se encontró Seshat: ni un .zip en la raíz del repositorio, ni el código suelto. Define SESHAT_REPO_SUBDIR.'; return 1;
    }
    printf '%s|%s\n' "$temp" "$origen"
}
# ===========================================================================
# 1) Instalar dependencias
# ===========================================================================
paquete_instalado() { dpkg -s "$1" >/dev/null 2>&1; }

instalar_dependencias() {
    requiere_root || return 1

    local falta_alguno=0 pkg
    for pkg in "${PAQUETES_BASE[@]}"; do
        paquete_instalado "$pkg" || { falta_alguno=1; break; }
    done

    if [ "$falta_alguno" -eq 0 ]; then
        ok "Las dependencias ya estaban instaladas."
    else
        info "Instalando dependencias (Apache, PHP, MariaDB)..."
        apt-get update -y && apt-get install -y "${PAQUETES_BASE[@]}" || return 1
        systemctl enable mariadb >/dev/null 2>&1
        systemctl restart mariadb
        ok "Dependencias instaladas."
    fi

    a2enmod rewrite headers expires deflate >/dev/null
    systemctl enable apache2 >/dev/null 2>&1

    # Activa explícitamente las extensiones de PHP que necesita Seshat: apt no
    # siempre las deja habilitadas para Apache, sobre todo si el servidor tiene
    # más de una versión de PHP instalada. "phpenmod -s ALL" cubre Apache y la
    # CLI de una vez, y correr esto de nuevo sirve para reparar una instalación
    # donde el paquete ya está pero Apache sigue sin verlo activo.
    local ext
    for ext in zip mbstring curl gd; do
        phpenmod -s ALL "$ext" >/dev/null 2>&1 || true
    done

    # Debian trae upload_max_filesize=2M por defecto, muy poco para actualizar
    # Seshat con un .zip o restaurar un respaldo. Se deja en un archivo propio
    # (no se toca el php.ini original) y se aplica a mod_php y a PHP-FPM si
    # están presentes; perfil base: 20 MB de subida, POST 24 MB y memoria 128 MB.
    local phpver sapi_dir
    phpver="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)"
    if [ -n "$phpver" ]; then
        for sapi_dir in "/etc/php/$phpver/apache2/conf.d" "/etc/php/$phpver/fpm/conf.d"; do
            if [ -d "$sapi_dir" ]; then
                printf 'upload_max_filesize = 20M\npost_max_size = 24M\nmemory_limit = 128M\n' > "$sapi_dir/99-seshat.ini"
            fi
        done
    fi

    systemctl restart apache2

    # Si el servidor usa PHP-FPM en vez del módulo de Apache, reiniciar Apache
    # no recarga los workers de PHP: hace falta reiniciar cada php*-fpm encontrado.
    local fpm
    for fpm in $(systemctl list-units --type=service --state=running --no-legend 2>/dev/null | awk '{print $1}' | grep -E '^php[0-9.]*-fpm\.service$'); do
        systemctl restart "$fpm" && ok "Reiniciado $fpm" || advertencia "No se pudo reiniciar $fpm"
    done

    echo
    echo "Paquetes:"
    for pkg in "${PAQUETES_BASE[@]}"; do
        local version; version="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null)"
        if [ -n "$version" ]; then
            printf "  ${VERDE}✔${NC} %-16s %s\n" "$pkg" "$version"
        else
            printf "  ${ROJO}✘${NC} %-16s no instalado\n" "$pkg"
        fi
    done
}

php_limit_profile(){
    local selected="$1"
    case "$selected" in
        20) PHP_UPLOAD_MB=20; PHP_POST_MB=24; PHP_MEMORY_MB=128 ;;
        40) PHP_UPLOAD_MB=40; PHP_POST_MB=48; PHP_MEMORY_MB=256 ;;
        80) PHP_UPLOAD_MB=80; PHP_POST_MB=96; PHP_MEMORY_MB=256 ;;
        custom)
            read -rp 'Tamano maximo de archivo (MB): ' PHP_UPLOAD_MB
            read -rp 'Memoria PHP (MB) [256]: ' PHP_MEMORY_MB
            PHP_MEMORY_MB="${PHP_MEMORY_MB:-256}"
            [[ "$PHP_UPLOAD_MB" =~ ^[1-9][0-9]*$ && "$PHP_MEMORY_MB" =~ ^[1-9][0-9]*$ ]] || { error 'Los valores deben ser numeros enteros positivos.'; return 1; }
            PHP_POST_MB=$((PHP_UPLOAD_MB + 8))
            ;;
        *) error 'Perfil de tamano invalido.'; return 1 ;;
    esac
    (( PHP_POST_MB > PHP_UPLOAD_MB )) || PHP_POST_MB=$((PHP_UPLOAD_MB + 1))
}

choose_php_limit_profile(){
    printf '\nConfiguracion de PHP para archivos y memoria\n'
    printf '  1) 20 MB de subida (memoria 128 MB)\n'
    printf '  2) 40 MB de subida (memoria 256 MB)\n'
    printf '  3) 80 MB de subida (memoria 256 MB)\n'
    printf '  4) Personalizado\n'
    read -rp 'Elige una opcion [1]: ' choice
    case "${choice:-1}" in
        1) php_limit_profile 20 ;;
        2) php_limit_profile 40 ;;
        3) php_limit_profile 80 ;;
        4) php_limit_profile custom ;;
        *) error 'Opcion invalida.'; return 1 ;;
    esac
}

configurar_limites_php_tradicional(){
    requiere_root || return 1
    choose_php_limit_profile || return 1
    local phpver sapi_dir fpm
    phpver="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)"
    [[ "$phpver" =~ ^[0-9]+\.[0-9]+$ ]] || { error 'No se pudo detectar la version de PHP.'; return 1; }
    for sapi_dir in "/etc/php/$phpver/apache2/conf.d" "/etc/php/$phpver/fpm/conf.d"; do
        if [ -d "$sapi_dir" ]; then
            printf 'upload_max_filesize = %sM\npost_max_size = %sM\nmemory_limit = %sM\n' \
                "$PHP_UPLOAD_MB" "$PHP_POST_MB" "$PHP_MEMORY_MB" > "$sapi_dir/99-seshat.ini" || return 1
        fi
    done
    systemctl restart apache2 || return 1
    for fpm in $(systemctl list-units --type=service --state=running --no-legend 2>/dev/null | awk '{print $1}' | grep -E '^php[0-9.]*-fpm\.service$'); do
        systemctl restart "$fpm" || advertencia "No se pudo reiniciar $fpm"
    done
    ok "Apache/PHP configurado: subida ${PHP_UPLOAD_MB}M, POST ${PHP_POST_MB}M, memoria ${PHP_MEMORY_MB}M."
}

# ===========================================================================
# 2) Instalar/Desplegar desde esta carpeta
# ===========================================================================
desplegar_desde_carpeta() {
    requiere_root || return 1
    local destino; destino="$(pedir_destino)" || return 1

    mkdir -p "$destino"
    copiar_arbol "$SCRIPT_DIR" "$destino" data pruebas assets/subidas .git

    chown -R "$APACHE_USUARIO:$APACHE_USUARIO" "$destino"
    find "$destino" -type d -exec chmod 755 {} \;
    find "$destino" -type f -exec chmod 644 {} \;

    echo "$destino" > "$MARCADOR_DESTINO"

    configurar_virtualhost "$destino" || return 1

    ok "Seshat desplegado en $destino"
    installation_summary "$destino" traditional
}

# ===========================================================================
# 3) Instalar/Desplegar desde GitHub
# ===========================================================================
instalar_desde_github() {
    requiere_root || return 1
    local destino; destino="$(pedir_destino)" || return 1

    local resultado repo_temp repo_origen
    resultado="$(descargar_desde_github "$REPO_URL_DEFECTO" "$REPO_SUBCARPETA_DEFECTO" "$RAMA_DEFECTO")" || return 1
    IFS='|' read -r repo_temp repo_origen <<< "$resultado"

    mkdir -p "$destino"
    copiar_arbol "$repo_origen" "$destino" data pruebas assets/subidas .git || return 1
    rm -rf -- "$repo_temp"

    chown -R "$APACHE_USUARIO:$APACHE_USUARIO" "$destino"
    find "$destino" -type d -exec chmod 755 {} \;
    find "$destino" -type f -exec chmod 644 {} \;

    echo "$destino" > "$MARCADOR_DESTINO"

    configurar_virtualhost "$destino" || return 1

    ok "Seshat descargado desde GitHub e instalado en $destino"
    installation_summary "$destino" traditional
}

configurar_virtualhost() {
    local destino="$1"
    local conf="/etc/apache2/sites-available/seshat.conf"

    cat > "$conf" <<EOF
<VirtualHost *:80>
    DocumentRoot "$destino"
    <Directory "$destino">
        DirectoryIndex index.php index.html
        Options -Indexes
        AllowOverride All
        <FilesMatch "^(database|seguridad|plantilla|politica_pruebas|correo|nextcloud)\\.php$">
            Require all denied
        </FilesMatch>
        <FilesMatch "\\.(sqlite.*|key|sh|md|ejemplo)$">
            Require all denied
        </FilesMatch>
        Require all granted
    </Directory>
    <Directory "$destino/data">
        Require all denied
    </Directory>
    <Directory "$destino/pruebas">
        <FilesMatch "\\.php$">
            Require all denied
        </FilesMatch>
    </Directory>
    <Directory "$destino/assets/subidas">
        <FilesMatch "\\.php$">
            Require all denied
        </FilesMatch>
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/seshat-error.log
    CustomLog \${APACHE_LOG_DIR}/seshat-access.log combined
</VirtualHost>
EOF

    a2ensite seshat.conf >/dev/null || return 1
    disable_default_page || return 1
    ok "VirtualHost configurado y Apache reiniciado."
}

# ===========================================================================
# 4) Configurar la base de datos
# ===========================================================================
configurar_base_datos() {
    requiere_root || return 1
    local destino; destino="$(pedir_destino)" || return 1
    if [ ! -d "$destino" ]; then
        error "No existe la carpeta $destino. Despliega primero con la opción 2 o 3."
        return 1
    fi

    echo -e "${CIAN}¿Qué motor de base de datos quieres usar?${NC}"
    echo -e " ${AMARILLO}1)${NC} SQLite  — simple, para empezar"
    echo -e " ${AMARILLO}2)${NC} MariaDB — para más alumnos escribiendo a la vez"
    read -rp "Elige 1 o 2: " motor

    case "$motor" in
        1)
            if [ -f "$destino/data/config.php" ]; then
                mv "$destino/data/config.php" "$destino/data/config.php.deshabilitado-$(date +%Y%m%d%H%M%S)"
                ok "Se desactivó la configuración de MariaDB anterior."
            fi
            mkdir -p "$destino/data"
            chown -R "$APACHE_USUARIO:$APACHE_USUARIO" "$destino/data"
            ok "Listo para usar SQLite. La base (data/simce.sqlite) se crea sola al primer ingreso."
            ;;
        2)
            configurar_mariadb "$destino"
            ;;
        *)
            error "Opción no válida."
            return 1
            ;;
    esac
}

configurar_mariadb() {
    local destino="$1"
    read -rp "Nombre de la base de datos [$DB_NOMBRE_DEFECTO]: " db_nombre
    db_nombre="${db_nombre:-$DB_NOMBRE_DEFECTO}"
    read -rp "Usuario de la base de datos [$DB_USUARIO_DEFECTO]: " db_usuario
    db_usuario="${db_usuario:-$DB_USUARIO_DEFECTO}"
    local db_clave; db_clave="$(generar_clave)"

    local mysql_cmd=(mysql -u root)
    if ! "${mysql_cmd[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
        read -rsp "Contraseña de root de MariaDB: " root_clave; echo
        mysql_cmd=(mysql -u root -p"$root_clave")
    fi

    if ! "${mysql_cmd[@]}" <<SQL
CREATE DATABASE IF NOT EXISTS \`$db_nombre\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$db_usuario'@'127.0.0.1' IDENTIFIED BY '$db_clave';
CREATE USER IF NOT EXISTS '$db_usuario'@'localhost' IDENTIFIED BY '$db_clave';
ALTER USER '$db_usuario'@'127.0.0.1' IDENTIFIED BY '$db_clave';
ALTER USER '$db_usuario'@'localhost' IDENTIFIED BY '$db_clave';
GRANT ALL PRIVILEGES ON \`$db_nombre\`.* TO '$db_usuario'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`$db_nombre\`.* TO '$db_usuario'@'localhost';
FLUSH PRIVILEGES;
SQL
    then
        error "No se pudo conectar a MariaDB con esas credenciales."
        return 1
    fi

    mkdir -p "$destino/data"
    cat > "$destino/data/config.php" <<PHP
<?php
declare(strict_types=1);
return [
    'driver'       => 'mysql',
    'host'         => '127.0.0.1',
    'puerto'       => 3306,
    'base'         => '$db_nombre',
    'usuario'      => '$db_usuario',
    'clave'        => '$db_clave',
    'charset'      => 'utf8mb4',
    'zona_horaria' => 'America/Santiago',
    'debug'        => false,
];
PHP

    chown "$APACHE_USUARIO:$APACHE_USUARIO" "$destino/data/config.php"
    chmod 640 "$destino/data/config.php"

    ok "Base '$db_nombre' y usuario '$db_usuario' creados."
    advertencia "Clave generada: $db_clave  (también quedó guardada en data/config.php)"

    info "Probando la conexión y creando las tablas..."
    if php -r "chdir('$destino'); require 'database.php'; db()->query('SELECT 1'); echo \"Conexión y esquema OK\n\";" 2>/tmp/seshat_db_error.log; then
        ok "Base de datos lista."
    else
        error "La conexión falló. Detalle:"
        cat /tmp/seshat_db_error.log >&2
    fi
}

# ===========================================================================
# 5) Gestionar administradores
# ===========================================================================
gestionar_administradores() {
    local destino; destino="$(pedir_destino)" || return 1
    if [ ! -f "$destino/database.php" ]; then
        error "No parece haber una instalación de Seshat en $destino."
        return 1
    fi

    echo "  1) Listar administradores"
    echo "  2) Restablecer la contraseña de uno"
    read -rp "Elige 1 o 2: " opcion

    case "$opcion" in
        1)
            ejecutar_php_admin "$destino" listar ""
            ;;
        2)
            read -rp "Usuario a restablecer: " usuario
            [ -n "$usuario" ] || { error "Falta el usuario."; return 1; }
            ejecutar_php_admin "$destino" resetear "$usuario"
            ;;
        *)
            error "Opción no válida."
            ;;
    esac
}

# Nota: las contraseñas se guardan cifradas (bcrypt) y no se pueden leer de
# vuelta — por eso no existe una opción para "ver" la contraseña actual,
# sólo generar una nueva.
ejecutar_php_admin() {
    local destino="$1" accion="$2" usuario="$3"
    local temp; temp="$(mktemp /tmp/seshat_admin_XXXXXX.php)"

    cat > "$temp" <<'PHP'
<?php
declare(strict_types=1);
[$destino, $accion, $usuario] = [$argv[1], $argv[2], $argv[3] ?? ''];
chdir($destino);
require $destino . '/database.php';
$pdo = db();

if ($accion === 'listar') {
    $filas = $pdo->query('SELECT usuario, nombre, rol, activo FROM administradores ORDER BY rol, usuario')->fetchAll();
    if (!$filas) { echo "No hay administradores registrados todavía.\n"; exit; }
    printf("%-20s %-30s %-14s %s\n", 'USUARIO', 'NOMBRE', 'ROL', 'ESTADO');
    foreach ($filas as $f) {
        printf("%-20s %-30s %-14s %s\n", $f['usuario'], $f['nombre'], $f['rol'], $f['activo'] ? 'activo' : 'inactivo');
    }
} elseif ($accion === 'resetear') {
    $st = $pdo->prepare('SELECT id FROM administradores WHERE usuario = ?');
    $st->execute([$usuario]);
    $id = $st->fetchColumn();
    if (!$id) { fwrite(STDERR, "No existe el usuario '$usuario'.\n"); exit(1); }
    $nueva = bin2hex(random_bytes(6));
    $pdo->prepare('UPDATE administradores SET password_hash = ?, debe_cambiar_clave = 1 WHERE id = ?')
        ->execute([password_hash($nueva, PASSWORD_DEFAULT), $id]);
    echo "Nueva contraseña para '$usuario': $nueva\n";
    echo "Se le pedirá cambiarla la próxima vez que ingrese.\n";
}
PHP

    php "$temp" "$destino" "$accion" "$usuario"
    rm -f "$temp"
}

# ===========================================================================
# 6) Migrar datos de SQLite a MariaDB
# ===========================================================================
migrar_sqlite_a_mariadb() {
    local destino; destino="$(pedir_destino)" || return 1
    if [ ! -f "$destino/data/simce.sqlite" ]; then
        error "No se encontró $destino/data/simce.sqlite. No hay nada que migrar."
        return 1
    fi
    if [ ! -f "$destino/data/config.php" ]; then
        error "Primero configura MariaDB con la opción 4; recién ahí se puede migrar."
        return 1
    fi

    advertencia "Esto copia los datos de SQLite hacia la base MariaDB ya configurada."
    read -rp "¿Continuar? (s/N): " resp
    [[ "$resp" =~ ^[sS]$ ]] || { info "Cancelado."; return 0; }

    local temp; temp="$(mktemp /tmp/seshat_migrar_XXXXXX.php)"
    cat > "$temp" <<'PHP'
<?php
declare(strict_types=1);
$destino = $argv[1];
chdir($destino);
require $destino . '/database.php';

if (db_driver() !== 'mysql') {
    fwrite(STDERR, "data/config.php no está configurado para MariaDB.\n");
    exit(1);
}

$origen = new PDO('sqlite:' . $destino . '/data/simce.sqlite');
$origen->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

$destinoPdo = db();
esquema_asegurar($destinoPdo);

$orden = ['administradores', 'cursos', 'alumnos', 'pruebas', 'asignaciones', 'resultados',
          'tokens_prueba', 'actividades', 'actividades_asignaciones',
          'actividades_entregas', 'tokens_actividad', 'configuracion',
          'auditoria_administracion', 'importaciones_alumnos', 'intentos_login',
          'restablecimientos_clave'];

$tablasOrigen = $origen->query("SELECT name FROM sqlite_master WHERE type = 'table'")
    ->fetchAll(PDO::FETCH_COLUMN);

foreach ($orden as $tabla) {
    if (!in_array($tabla, $tablasOrigen, true)) {
        echo "  $tabla: no existe en SQLite, omitida.\n";
        continue;
    }
    $filas = $origen->query("SELECT * FROM $tabla")->fetchAll(PDO::FETCH_ASSOC);
    if (!$filas) { echo "  $tabla: sin filas.\n"; continue; }
    $columnas = array_keys($filas[0]);
    $marcadores = implode(',', array_fill(0, count($columnas), '?'));
    $sql = "INSERT INTO $tabla (" . implode(',', $columnas) . ") VALUES ($marcadores)";
    $st = $destinoPdo->prepare($sql);
    $n = 0;
    foreach ($filas as $fila) {
        try { $st->execute(array_values($fila)); $n++; } catch (Throwable $e) { /* fila ya existente u otro problema puntual */ }
    }
    echo "  $tabla: $n fila(s) migradas de " . count($filas) . ".\n";
}
echo "Migración completa.\n";
PHP

    if ! php "$temp" "$destino"; then
        rm -f "$temp"
        error "La migración falló. SQLite se conserva sin renombrar para poder reintentar."
        return 1
    fi
    rm -f "$temp"

    mv "$destino/data/simce.sqlite" "$destino/data/simce.sqlite.migrado-$(date +%Y%m%d%H%M%S)"
    ok "SQLite renombrado como respaldo; Seshat sigue leyendo MariaDB desde ahora."
}

# ===========================================================================
# 7) Actualizar una instalación existente (desde esta carpeta)
# ===========================================================================
actualizar_instalacion() {
    requiere_root || return 1
    local destino; destino="$(pedir_destino)" || return 1
    if [ ! -d "$destino" ]; then
        error "No existe $destino."
        return 1
    fi

    local respaldo="${destino%/}.respaldo-$(date +%Y%m%d-%H%M%S)"
    cp -r "$destino" "$respaldo" || return 1
    ok "Respaldo completo creado en $respaldo"

    copiar_arbol "$SCRIPT_DIR" "$destino" data pruebas assets/subidas .git

    chown -R "$APACHE_USUARIO:$APACHE_USUARIO" "$destino"
    ok "Código actualizado. data/ y pruebas/ se conservaron tal cual estaban."
    info "Si algo sale mal, el código anterior completo está en $respaldo"
}

# ===========================================================================
# 8) Actualizar una instalación existente desde GitHub
# ===========================================================================
actualizar_desde_github() {
    requiere_root || return 1
    local destino; destino="$(pedir_destino)" || return 1
    if [ ! -f "$destino/database.php" ]; then
        error "No parece haber una instalación de Seshat en $destino (falta database.php)."
        info "Instala primero con la opción 2 o 3."
        return 1
    fi

    local resultado repo_temp repo_origen
    resultado="$(descargar_desde_github "$REPO_URL_DEFECTO" "$REPO_SUBCARPETA_DEFECTO" "$RAMA_DEFECTO")" || return 1
    IFS='|' read -r repo_temp repo_origen <<< "$resultado"

    local respaldo="${destino%/}.respaldo-$(date +%Y%m%d-%H%M%S)"
    cp -r "$destino" "$respaldo" || return 1
    ok "Respaldo completo creado en $respaldo"

    copiar_arbol "$repo_origen" "$destino" data pruebas assets/subidas .git || return 1
    rm -rf -- "$repo_temp"

    chown -R "$APACHE_USUARIO:$APACHE_USUARIO" "$destino"

    ok "Código actualizado desde GitHub. data/ y pruebas/ se conservaron tal cual estaban."
    info "Si algo sale mal, el código anterior completo está en $respaldo"
}

# ===========================================================================
# 9) Diagnóstico
# ===========================================================================
diagnostico() {
    local destino; destino="$(pedir_destino)" || return 1

    echo -e "${CIAN}${NEGRITA}== Servicios ==${NC}"
    systemctl is-active --quiet apache2 && ok "Apache activo" || advertencia "Apache no está activo"
    systemctl is-active --quiet mariadb && ok "MariaDB activo" || advertencia "MariaDB no está activo (normal si usas SQLite)"

    echo -e "${CIAN}${NEGRITA}== Apache ==${NC}"
    if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
        ok "Sintaxis correcta"
    else
        error "Errores de configuración:"
        apache2ctl configtest
    fi

    echo -e "${CIAN}${NEGRITA}== PHP ==${NC}"
    php -v | head -n1
    for ext in pdo_sqlite pdo_mysql mbstring fileinfo zip; do
        php -m | grep -qi "^$ext\$" && ok "Extensión $ext cargada" || advertencia "Falta la extensión $ext"
    done
    # Lo anterior revisa la CLI de PHP: si el servidor usa PHP-FPM, Apache puede
    # estar usando una versión o pool distinta y no ver las mismas extensiones.
    local fpm_activos; fpm_activos="$(systemctl list-units --type=service --state=running --no-legend 2>/dev/null | awk '{print $1}' | grep -E '^php[0-9.]*-fpm\.service$')"
    if [ -n "$fpm_activos" ]; then
        advertencia "El servidor usa PHP-FPM (no el módulo de Apache). Lo de arriba es la CLI: si Apache no ve una extensión ya instalada, reinicia el/los servicio(s) de FPM:"
        printf '    %s\n' $fpm_activos
    fi

    echo -e "${CIAN}${NEGRITA}== Base de datos ($destino) ==${NC}"
    if [ -f "$destino/data/config.php" ]; then
        ok "Configurado para MariaDB"
        php -r "chdir('$destino'); require 'database.php'; try { db()->query('SELECT 1'); echo \"Conexión OK\n\"; } catch (Throwable \$e) { echo 'ERROR: ' . \$e->getMessage() . \"\n\"; }"
    elif [ -f "$destino/data/simce.sqlite" ]; then
        ok "Usando SQLite ($destino/data/simce.sqlite)"
    else
        advertencia "Todavía no hay base de datos creada (se crea sola al primer ingreso, o usa la opción 4)."
    fi

    echo -e "${CIAN}${NEGRITA}== Sitio ==${NC}"
    if command -v curl >/dev/null 2>&1; then
        curl -s -o /dev/null -w "http://localhost/ -> HTTP %{http_code}\n" http://localhost/ || advertencia "No se pudo contactar http://localhost/"
    fi
}

# ===========================================================================
# Menú
# ===========================================================================
while true; do
    limpiar_consola
    destino_actual="$(obtener_destino)"
    sufijo_instalado=""
    sufijo_bd=""
    if [ -f "$destino_actual/database.php" ]; then
        sufijo_instalado=" ${VERDE}[ya instalado en $destino_actual]${NC}"
    fi
    if [ -f "$destino_actual/data/config.php" ]; then
        sufijo_bd=" ${VERDE}[ya configurada: MariaDB]${NC}"
    elif [ -f "$destino_actual/data/simce.sqlite" ]; then
        sufijo_bd=" ${VERDE}[ya configurada: SQLite]${NC}"
    fi

    echo ""
    echo -e "${CIAN}${NEGRITA}========================================================${NC}"
    echo -e "${CIAN}${NEGRITA} Seshat · Instalador y mantención (Debian/Ubuntu)${NC}"
    echo -e "${CIAN}${NEGRITA}========================================================${NC}"
    echo -e " ${AMARILLO}1)${NC} Instalar dependencias"
    echo -e " ${AMARILLO}2)${NC} Instalar/Desplegar Seshat desde esta carpeta${sufijo_instalado}"
    echo -e " ${AMARILLO}3)${NC} Instalar/Desplegar Seshat desde GitHub${sufijo_instalado}"
    echo -e " ${AMARILLO}4)${NC} Configurar la base de datos${sufijo_bd}"
    echo -e " ${AMARILLO}5)${NC} Gestionar administradores (listar / restablecer clave)"
    echo -e " ${AMARILLO}6)${NC} Migrar datos de SQLite a MariaDB"
    echo -e " ${AMARILLO}7)${NC} Actualizar una instalación existente (desde esta carpeta)"
    echo -e " ${AMARILLO}8)${NC} Actualizar una instalación existente desde GitHub"
    echo -e " ${AMARILLO}9)${NC} Diagnóstico"
    echo -e "${AMARILLO}10)${NC} Desinstalar completamente Seshat-Evaluaciones"
    echo -e "${AMARILLO}11)${NC} Crear VirtualHost con proxy inverso (puerto 8081 o personalizado)"
    echo -e "${AMARILLO}12)${NC} Configurar acceso directo por puerto (8081 o personalizado)"
    echo -e "${AMARILLO}13)${NC} Desactivar página predeterminada de Apache"
    echo -e "${AMARILLO}14)${NC} Configurar memoria y tamaño de subida de PHP"
    echo -e " ${AMARILLO}0)${NC} ${ETIQUETA_CERRAR:-Salir}"
    read -rp "Elige una opción: " opcion
    echo ""
    case "$opcion" in
        1) instalar_dependencias ;;
        2) desplegar_desde_carpeta ;;
        3) instalar_desde_github ;;
        4) configurar_base_datos ;;
        5) gestionar_administradores ;;
        6) migrar_sqlite_a_mariadb ;;
        7) actualizar_instalacion ;;
        8) actualizar_desde_github ;;
        9) diagnostico ;;
        # traditional() corre en una subshell: este exit solo termina el submenú y
        # devuelve el control al menú principal (si se entró desde él).
        0) [ "${ETIQUETA_CERRAR:-Salir}" = "Salir" ] && echo "Hasta luego."; exit 0 ;;
        10) uninstall_traditional ;;
        11) destino_proxy="$(pedir_destino)" && configure_proxy traditional "$destino_proxy" ;;
        12) destino_puerto="$(pedir_destino)" && configure_direct_port "$destino_puerto" ;;
        13) disable_default_page ;;
        14) configurar_limites_php_tradicional ;;
        *) error "Opción no válida." ;;
    esac
    read -rp 'Presiona Enter para volver al menú...' _ || break
done

)
choose_mode(){
  case "${1:-}" in
    --docker) main;;
    --tradicional) traditional;;
    --help|-h) printf 'Uso: sudo bash %s [--docker|--tradicional]\n' "$(basename "$0")";;
    '')
      # Menú principal en bucle: al elegir 0 en Docker o Tradicional se vuelve aquí.
      local mode
      ETIQUETA_CERRAR='Volver al menú principal'
      while true; do
        limpiar_consola
        titulo_menu 'Seshat-Evaluaciones'
        opcion_menu 1 'Docker (Apache/PHP + SQLite, puerto 8081)'
        opcion_menu 2 'Tradicional (Apache/PHP + SQLite o MariaDB, puerto 80)'
        opcion_menu 0 'Salir'
        read -rp 'Modalidad: ' mode || return
        case "$mode" in
          1) main;;
          2) traditional;;
          0) printf 'Hasta luego.\n'; return;;
          *) printf 'Modalidad inválida.\n'; pause;;
        esac
      done
      ;;
    *) fail 'Argumento desconocido. Usa --help.';;
  esac
}
[[ "${BASH_SOURCE[0]}" != "$0" ]] || choose_mode "$@"
