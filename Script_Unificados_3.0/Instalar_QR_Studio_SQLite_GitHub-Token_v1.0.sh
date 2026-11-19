#!/usr/bin/env bash
# ===========================================================================
# QR Studio - Instalador v1.0 (Debian normal + Docker, todo en uno)
# ---------------------------------------------------------------------------
# Un solo script con menú para dos formas de instalar, con la MISMA configuración:
#   1) Normal: Python + servicio systemd
#        /opt/qr-studio/             código en app/, entorno de Python en venv/
#        /etc/qr-studio/qr-studio.env   configuración (puerto, host, cookies...)
#        /var/lib/qr-studio/app.db      base de datos SQLite (usuarios y sesiones)
#        servicio: qr-studio            respaldos: /var/backups/qr-studio
#   2) Docker: contenedor + docker compose
#        /opt/qr-studio-docker/      código en app/, base en datos/app.db, configuración en .env
#
# La base de datos es SQLite (un archivo). Actualizar = se respalda todo, se copia el código
# nuevo y la base de datos se CONSERVA. Normal: si la versión nueva no arranca, vuelve sola
# a la anterior.
#
# El código se toma de una carpeta o .zip (el que crea Crear_Paquete_GitHub.ps1 en Windows:
# QR_Studio_vDDMMAAAAHHMM.zip, solo con la carpeta web) o de GitHub:
#   https://github.com/llancor/qr_studio
# En GitHub baja solo el .zip más reciente (o el que elijas). Si el repositorio es privado
# pide usuario y token; si es público se dejan vacíos.
#
# Variables opcionales: QR_DIR, QR_DIR_DOCKER, QR_DATOS, QR_RESPALDOS, QR_RESPALDOS_DOCKER,
# QR_REPO_URL, QR_REPO_BRANCH, QR_REPO_CARPETA (carpeta del repositorio donde están los .zip;
# vacía = todo el repositorio).
# Uso:  sudo bash Instalar_QR_Studio_SQLite_GitHub-Token_v1.0.sh
# ===========================================================================
set -uo pipefail

VERSION_INSTALADOR='1.0.0'
INSTALL_ROOT="${QR_DIR:-/opt/qr-studio}"
ROOT_DOCKER="${QR_DIR_DOCKER:-/opt/qr-studio-docker}"
APP_DIR="$INSTALL_ROOT/app"
VENV="$INSTALL_ROOT/venv"
DATA_DIR="${QR_DATOS:-/var/lib/qr-studio}"
CONF_DIR='/etc/qr-studio'
ENV_FILE="$CONF_DIR/qr-studio.env"
RESPALDOS="${QR_RESPALDOS:-/var/backups/qr-studio}"
RESPALDOS_DOCKER="${QR_RESPALDOS_DOCKER:-/var/backups/qr-studio-docker}"
SERVICIO='qr-studio'
UNIDAD="/etc/systemd/system/$SERVICIO.service"
USUARIO='qrstudio'
PUERTO_DEFECTO=8000
REPO_URL="${QR_REPO_URL:-https://github.com/llancor/qr_studio.git}"
REPO_BRANCH="${QR_REPO_BRANCH:-main}"
REPO_CARPETA="${QR_REPO_CARPETA:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# La base de datos y sus archivos auxiliares nunca se copian junto con el código.
EXCLUIR=(--exclude 'app.db' --exclude 'app.db-wal' --exclude 'app.db-shm' --exclude 'app.db-journal'
         --exclude '__pycache__/' --exclude '.venv/' --exclude 'venv/' --exclude '*.pyc'
         --exclude '.git/' --exclude '.claude/')

# Si se carga con «source» (pruebas) no se pide root ni se abre el menú.
SOURCED=0
[[ "${BASH_SOURCE[0]}" != "$0" ]] && SOURCED=1

# --- Apariencia y utilidades -------------------------------------------------
if [[ -t 1 ]]; then
  C_CIAN=$'\e[1;36m'; C_AMAR=$'\e[1;33m'; C_VERDE=$'\e[1;32m'; C_ROJO=$'\e[1;31m'; C_GRIS=$'\e[0;37m'; C_FIN=$'\e[0m'
else
  C_CIAN=''; C_AMAR=''; C_VERDE=''; C_ROJO=''; C_GRIS=''; C_FIN=''
fi
info(){  printf '%s\n' "${C_CIAN}==>${C_FIN} $*" >&2; }
ok(){    printf '%s\n' "${C_VERDE}OK${C_FIN}  $*" >&2; }
aviso(){ printf '%s\n' "${C_AMAR}!!${C_FIN}  $*" >&2; }
fail(){  printf '%s\n' "${C_ROJO}ERROR${C_FIN} $*" >&2; }
pausa(){ read -rp 'Presiona Enter para volver al menú...' _ </dev/tty || true; }
preguntar(){ local r; read -rp "$1" r </dev/tty || r=''; printf '%s' "$r"; }
confirmar(){ [[ "$(preguntar "$1 (s/N): ")" =~ ^[sS]$ ]]; }
opcion_menu(){ printf '  %s%2s)%s %s\n' "$C_AMAR" "$1" "$C_FIN" "$2"; }

# Debe correr como root (escribe en /opt y crea el servicio). Si no, se relanza con sudo
# (para usar las variables QR_* ejecútalo directamente como root: sudo -E o su).
if (( SOURCED == 0 )) && [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then exec sudo -E bash "$0" "$@"; fi
  fail 'Ejecuta este instalador como root:  su -c "bash Instalar_QR_Studio_SQLite_GitHub-Token_v1.0.sh"'
  exit 1
fi

# Temporales: todos dentro de una carpeta de la sesión, creada aquí (proceso principal)
# para que también se borren los creados dentro de $( ... ). Se vacía tras cada opción.
SESION_TMP="$(mktemp -d /tmp/qr-studio-inst.XXXXXX)"
chmod 700 "$SESION_TMP"
nuevo_temporal(){ mktemp -d "$SESION_TMP/t.XXXXXX"; }
vaciar_temporales(){ find "$SESION_TMP" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true; }
trap 'rm -rf -- "$SESION_TMP"' EXIT

instalado(){ [[ -f "$APP_DIR/main.py" ]]; }
# (sin «| grep -q»: con pipefail, grep -q cierra la tubería y el resultado sería erróneo)
puerto_ocupado(){ [[ -n "$(ss -ltnH "sport = :$1" 2>/dev/null)" ]]; }
puerto_valido(){ [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }

# Borra una carpeta de instalación, pero nunca «/», vacía ni de un solo nivel (ej. /opt).
borrar_carpeta(){
  local ruta="$1"
  if [[ ! "$ruta" =~ ^/[^/]+/[^/]+ ]]; then fail "Por seguridad no se borra «$ruta»."; return 1; fi
  rm -rf -- "$ruta"
}

# --- Configuración (archivos clave=valor) ---------------------------------------------
# leer_env ARCHIVO CLAVE [defecto]
leer_env(){ local v; v="$(sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1)"; printf '%s' "${v:-${3:-}}"; }

# escribir_env ARCHIVO CLAVE VALOR  (crea el archivo si no existe; solo root puede leerlo)
escribir_env(){
  local f="$1" k="$2" v="$3"
  mkdir -p "$(dirname "$f")"; touch "$f"; chmod 600 "$f"
  grep -v "^$k=" "$f" > "$f.tmp" 2>/dev/null || true
  printf '%s=%s\n' "$k" "$v" >> "$f.tmp"
  mv -f "$f.tmp" "$f"; chmod 600 "$f"
}

leer_puerto(){ leer_env "$ENV_FILE" APP_PORT "$PUERTO_DEFECTO"; }
ruta_db(){ leer_env "$ENV_FILE" APP_DB_PATH "$DATA_DIR/app.db"; }
# Carpeta donde cada usuario guarda los QR que crea con «Masivo» (por defecto, junto a la base de datos).
ruta_qr(){ leer_env "$ENV_FILE" APP_FILES_PATH "$(dirname "$(ruta_db)")/qr"; }

# Crea qr-studio.env con los valores por defecto si todavía no existe.
asegurar_env(){
  local puerto="$1"
  if [[ ! -f "$ENV_FILE" ]]; then
    escribir_env "$ENV_FILE" APP_HOST 0.0.0.0
    escribir_env "$ENV_FILE" APP_PORT "$puerto"
    escribir_env "$ENV_FILE" APP_DB_PATH "$DATA_DIR/app.db"
    escribir_env "$ENV_FILE" APP_COOKIE_SECURE false
    escribir_env "$ENV_FILE" APP_SESSION_DAYS 14
    escribir_env "$ENV_FILE" APP_MIN_PASSWORD_LENGTH 8
    escribir_env "$ENV_FILE" APP_LOGIN_MAX_ATTEMPTS 5
    escribir_env "$ENV_FILE" APP_LOGIN_WINDOW_SECONDS 300
    escribir_env "$ENV_FILE" APP_QR_QUOTA_MB 200
    escribir_env "$ENV_FILE" APP_DYNAMIC_QR true        # false = apaga los QR dinámicos
    escribir_env "$ENV_FILE" APP_PUBLIC_URL ''          # dirección pública del sitio para los enlaces cortos (opcional)
  else
    escribir_env "$ENV_FILE" APP_PORT "$puerto"
  fi
}

# --- 1) Dependencias ---------------------------------------------------------
instalar_dependencias(){
  info 'Instalando dependencias del sistema...'
  info '[1/3] Actualizando la lista de paquetes (apt-get update)...'
  # Un repositorio ignorado (reloj desfasado, mirror caído) hace que update devuelva error aunque
  # los demás se actualicen: se avisa y se sigue; si falta algún paquete, el install lo dirá.
  if ! apt-get -o Dpkg::Progress-Fancy=0 update </dev/null; then
    aviso 'apt-get update dio errores (¿sin internet, repositorio caído o reloj desfasado? revisa «date»); se intenta seguir.'
  fi
  info '[2/3] Instalando: python3, venv, pip, unzip, git, rsync, curl, iproute2...'
  DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Progress-Fancy=0 install -y \
    python3 python3-venv python3-pip unzip git rsync curl ca-certificates iproute2 tar </dev/null \
    || { fail 'No se pudieron instalar las dependencias (ver el detalle arriba).'; return 1; }
  info '[3/3] Verificando...'
  local c falta=0
  for c in python3 unzip rsync curl git ss; do
    if command -v "$c" >/dev/null 2>&1; then ok "$c: disponible"; else aviso "$c: NO quedó instalado"; falta=1; fi
  done
  (( falta )) && return 1
  ok "Dependencias instaladas. $(python3 --version 2>&1)"
}

# Devuelve 0 (verdadero) si FALTA algo, para usar:  faltan_dependencias && return 1
faltan_dependencias(){
  local falta=() c
  for c in python3 unzip rsync curl tar; do command -v "$c" >/dev/null 2>&1 || falta+=("$c"); done
  [[ "${1:-}" == git ]] && { command -v git >/dev/null 2>&1 || falta+=(git); }
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import venv, ensurepip' >/dev/null 2>&1 || falta+=(python3-venv)
    if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'; then
      fail "QR Studio necesita Python 3.10 o superior ($(python3 --version 2>&1))."; return 0
    fi
  fi
  if ((${#falta[@]})); then fail "Faltan dependencias: ${falta[*]}. Usa primero la opción 1."; return 0; fi
  return 1
}

# --- Paquetes .zip de código ---------------------------------------------------
# Clave para ordenar QR_Studio_vDDMMAAAAHHMM.zip por fecha real (AAAAMMDDHHMM).
clave_zip(){
  local b; b="$(basename "$1")"
  if [[ "$b" =~ _v([0-9]{2})([0-9]{2})([0-9]{4})([0-9]{4})\.zip$ ]]; then
    printf '%s%s%s%s' "${BASH_REMATCH[3]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}" "${BASH_REMATCH[4]}"
  else
    printf '000000000000'
  fi
}

# Lista numerada (la primera es la recomendada) y devuelve la elegida por stdout.
elegir_de_lista(){
  local titulo="$1"; shift
  local lista=("$@") i opcion
  if ((${#lista[@]} == 1)); then printf '%s' "${lista[0]}"; return 0; fi
  printf '\n%s\n' "$titulo" >&2
  for i in "${!lista[@]}"; do printf '  %s%d)%s %s\n' "$C_AMAR" $((i + 1)) "$C_FIN" "$(basename "${lista[$i]}")" >&2; done
  opcion="$(preguntar 'Elige [1]: ')"; opcion="${opcion:-1}"
  if [[ "$opcion" =~ ^[0-9]+$ ]] && ((opcion >= 1 && opcion <= ${#lista[@]})); then
    printf '%s' "${lista[$((opcion - 1))]}"
  else
    fail 'Opción no válida.'; return 1
  fi
}

elegir_zip(){
  local ordenados=() z
  mapfile -t ordenados < <(for z in "$@"; do printf '%s\t%s\n' "$(clave_zip "$z")" "$z"; done | sort -r | cut -f2-)
  elegir_de_lista 'Paquetes encontrados (el más reciente primero):' "${ordenados[@]}"
}

# Carpeta (la de ruta más corta) que contiene app/main.py, app/static/index.html y requirements.txt.
buscar_codigo(){
  local base="$1" f d raiz mejor=''
  while IFS= read -r -d '' f; do
    d="$(dirname "$f")"
    [[ "$(basename "$d")" == app && -f "$d/static/index.html" ]] || continue
    raiz="$(dirname "$d")"
    [[ -f "$raiz/requirements.txt" ]] || continue
    if [[ -z "$mejor" || ${#raiz} -lt ${#mejor} ]]; then mejor="$raiz"; fi
  done < <(find "$base" -maxdepth 6 -type f -name main.py -not -path '*/.venv/*' -not -path '*/venv/*' -not -path '*/.git/*' -print0 2>/dev/null)
  [[ -n "$mejor" ]] && printf '%s' "$mejor"
}

rutas_peligrosas(){ grep -qE '(^/|(^|/)\.\.(/|$)|^[A-Za-z]:)' <<< "$1"; }

# Descomprime un .zip de forma segura y devuelve la carpeta con el código.
extraer_zip(){
  local zip="$1" destino lista codigo
  lista="$(unzip -Z1 "$zip" 2>/dev/null)" || { fail "$(basename "$zip") no es un .zip válido."; return 1; }
  if rutas_peligrosas "$lista"; then fail "$(basename "$zip") contiene rutas peligrosas; no se usa."; return 1; fi
  destino="$(nuevo_temporal)"
  # unzip termina con 1 cuando solo hubo advertencias (p. ej. separadores «\»).
  unzip -q -o "$zip" -d "$destino" >&2; (( $? <= 1 )) || { fail "No se pudo descomprimir $(basename "$zip")."; return 1; }
  codigo="$(buscar_codigo "$destino")"
  [[ -n "$codigo" ]] || { fail "$(basename "$zip") no contiene QR Studio (app/main.py, app/static/index.html y requirements.txt)."; return 1; }
  printf '%s' "$codigo"
}

# --- Obtener el código: carpeta o GitHub ----------------------------------------
# Ambas imprimen por stdout "carpeta_del_código<TAB>descripción".
codigo_desde_carpeta(){
  local ruta zips=() zip codigo
  ruta="$(preguntar "Carpeta o .zip con QR Studio [$SCRIPT_DIR]: ")"
  ruta="${ruta:-$SCRIPT_DIR}"; ruta="${ruta%/}"
  if [[ -f "$ruta" && "$ruta" == *.zip ]]; then
    zip="$ruta"
  elif [[ -d "$ruta" ]]; then
    codigo="$(buscar_codigo "$ruta")"
    mapfile -t zips < <(find "$ruta" -maxdepth 3 -type f -name 'QR_Studio_v*.zip' 2>/dev/null)
    if ((${#zips[@]} == 0)); then
      [[ -n "$codigo" ]] || { fail "No se encontró QR Studio (QR_Studio_v*.zip o app/main.py + requirements.txt) en $ruta"; return 1; }
      printf '%s\t%s' "$codigo" "carpeta $codigo"; return 0
    fi
    zip="$(elegir_zip "${zips[@]}")" || return 1
  else
    fail "No existe: $ruta"; return 1
  fi
  info "Paquete: $(basename "$zip")"
  codigo="$(extraer_zip "$zip")" || return 1
  printf '%s\t%s' "$codigo" "$(basename "$zip")"
}

# Descarga de github.com/llancor/qr_studio (rama main) SOLO el .zip elegido, no todo el
# repositorio: clona sin archivos (--filter=blob:none --no-checkout), lista los QR_Studio_v*.zip
# con «git ls-tree» y baja únicamente el elegido. Con un repositorio privado el token se
# entrega a git por GIT_ASKPASS: no queda en la URL, en el historial de la consola ni en disco,
# y se olvida al terminar. Con uno público se dejan usuario y token vacíos.
codigo_desde_github(){
  local usuario='' token='' tmp repo zips=() ruta sel raiz codigo mains=() p
  printf 'Repositorio: %s  (rama %s%s)\n' "${REPO_URL%.git}" "$REPO_BRANCH" "${REPO_CARPETA:+, carpeta $REPO_CARPETA}" >&2
  printf 'Si el repositorio es público deja el usuario vacío; si es privado escribe tu usuario y un token.\n' >&2
  usuario="$(preguntar 'Usuario de GitHub (Enter = sin usuario): ')"
  usuario="${usuario//[[:space:]]/}"
  if [[ -n "$usuario" ]]; then
    while [[ -z "$token" ]]; do
      read -rsp 'Token de GitHub (no se muestra ni se guarda): ' token </dev/tty || return 1
      printf '\n' >&2
    done
  fi

  tmp="$(nuevo_temporal)"; repo="$tmp/repo"
  if [[ -n "$token" ]]; then
    cat > "$tmp/askpass" <<'EOF'
#!/bin/sh
case "$1" in
  Username*) printf '%s\n' "$QR_GIT_USUARIO" ;;
  *)         printf '%s\n' "$QR_GIT_TOKEN" ;;
esac
EOF
    chmod 700 "$tmp/askpass"
  fi
  # Todas las llamadas a git de esta descarga usan el mismo usuario y token (si hay).
  git_github(){
    if [[ -n "$token" ]]; then
      GIT_ASKPASS="$tmp/askpass" GIT_TERMINAL_PROMPT=0 QR_GIT_USUARIO="$usuario" QR_GIT_TOKEN="$token" git "$@"
    else
      GIT_TERMINAL_PROMPT=0 git "$@"
    fi
  }

  info 'Consultando el repositorio en GitHub...'
  if ! git_github clone --quiet --depth 1 --filter=blob:none --no-checkout --branch "$REPO_BRANCH" "$REPO_URL" "$repo" >&2; then
    rm -f "$tmp/askpass"; token=''
    fail 'No se pudo consultar GitHub. Revisa:'
    fail '  - la conexión a internet y que la rama exista,'
    fail "  - si el repositorio es privado: el usuario y el token (que no esté vencido) con permiso de lectura de contenido (Contents: Read, o «repo» en un token clásico) sobre ${REPO_URL%.git}."
    return 1
  fi

  ruta="${REPO_CARPETA#/}"; ruta="${ruta%/}"; [[ -n "$ruta" ]] && ruta="$ruta/"
  while IFS= read -r p; do
    [[ "$p" == "$ruta"* && "$p" =~ (^|/)QR_Studio_v[0-9]{12}\.zip$ ]] && zips+=("$p")
  done < <(git_github -c core.quotepath=false -C "$repo" ls-tree -r --name-only HEAD 2>/dev/null)

  if ((${#zips[@]})); then
    sel="$(elegir_zip "${zips[@]}")" || { rm -f "$tmp/askpass"; token=''; return 1; }
    info "Descargando $sel..."
    if ! git_github -C "$repo" checkout --quiet HEAD -- "$sel" >&2; then
      rm -f "$tmp/askpass"; token=''
      fail "No se pudo descargar $sel."; return 1
    fi
    rm -f "$tmp/askpass"; token=''
    codigo="$(extraer_zip "$repo/$sel")" || return 1
    printf '%s\t%s' "$codigo" "GitHub $(basename "$sel")"
  else
    # Sin .zip: si el repositorio tiene el código suelto (app/main.py), se baja esa carpeta.
    while IFS= read -r p; do
      [[ "$p" == "$ruta"* && "$p" =~ (^|/)app/main\.py$ ]] && mains+=("$p")
    done < <(git_github -c core.quotepath=false -C "$repo" ls-tree -r --name-only HEAD 2>/dev/null)
    if ((${#mains[@]} == 0)); then
      rm -f "$tmp/askpass"; token=''
      fail "En el repositorio no hay ningún QR_Studio_v*.zip ni el código (app/main.py)${REPO_CARPETA:+ en $REPO_CARPETA}."; return 1
    fi
    raiz="$(dirname "$(dirname "${mains[0]}")")"
    info "Descargando el código de ${raiz#.}..."
    if ! git_github -C "$repo" checkout --quiet HEAD -- "$raiz" >&2; then
      rm -f "$tmp/askpass"; token=''
      fail 'No se pudo descargar el código.'; return 1
    fi
    rm -f "$tmp/askpass"; token=''
    codigo="$(buscar_codigo "$repo/$raiz")"
    [[ -n "$codigo" ]] || { fail 'El código descargado está incompleto (app/main.py, app/static/index.html y requirements.txt).'; return 1; }
    printf '%s\t%s' "$codigo" "GitHub ${REPO_URL%.git}"
  fi
}

# Imprime la carpeta con el código ("codigo<TAB>descripcion"); FUENTE = carpeta | github.
obtener_codigo(){
  local fuente="$1"
  if [[ "$fuente" == github ]]; then
    command -v git >/dev/null 2>&1 || { fail 'Falta git (apt-get install git).'; return 1; }
    codigo_desde_github
  else
    codigo_desde_carpeta
  fi
}

# Pregunta de dónde sacar el código (carpeta/.zip o GitHub) y devuelve "carpeta<TAB>descripción".
obtener_codigo_menu(){
  local fuente
  printf '1) Desde una carpeta o .zip\n2) Desde GitHub (%s)\n' "${REPO_URL%.git}" >&2
  fuente="$(preguntar 'Origen del código [1]: ')"; fuente="${fuente:-1}"
  if [[ "$fuente" == 2 ]]; then obtener_codigo github; else obtener_codigo carpeta; fi
}

# --- Servicio ---------------------------------------------------------------------
escribir_servicio(){
  cat > "$UNIDAD" <<EOF
[Unit]
Description=QR Studio (generador de códigos QR)
After=network.target

[Service]
Type=simple
User=$USUARIO
Group=$USUARIO
WorkingDirectory=$INSTALL_ROOT
EnvironmentFile=$ENV_FILE
ExecStart=$VENV/bin/uvicorn --factory app.main:create_app --host \${APP_HOST} --port \${APP_PORT}
Restart=on-failure
RestartSec=3

# Endurecimiento: solo puede escribir en el directorio de datos.
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ReadWritePaths=$DATA_DIR
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

esperar_servicio(){
  local puerto="$1" i
  for i in $(seq 1 40); do
    curl -fs -o /dev/null --max-time 2 "http://127.0.0.1:$puerto/healthz" && return 0
    systemctl is-failed --quiet "$SERVICIO" && return 1
    sleep 1
  done
  return 1
}

arrancar_y_verificar(){
  local puerto="$1"
  systemctl enable "$SERVICIO" >/dev/null 2>&1
  systemctl restart "$SERVICIO"
  info 'Iniciando QR Studio...'
  if esperar_servicio "$puerto"; then ok 'QR Studio está funcionando.'; return 0; fi
  fail 'QR Studio no arrancó. Últimas líneas del registro:'
  journalctl -u "$SERVICIO" -n 20 --no-pager 2>/dev/null | sed 's/^/    /' >&2
  return 1
}

instalar_librerias(){
  if [[ ! -x "$VENV/bin/python" ]]; then
    info 'Creando el entorno de Python...'
    python3 -m venv "$VENV" || { fail 'No se pudo crear el entorno (falta python3-venv: opción 1).'; return 1; }
  fi
  info 'Instalando librerías de requirements.txt (puede tardar unos minutos)...'
  "$VENV/bin/python" -m pip install --disable-pip-version-check --quiet --no-cache-dir -r "$INSTALL_ROOT/requirements.txt" >&2 \
    || { fail 'No se pudieron instalar las librerías (¿hay internet?).'; return 1; }
  # El código es de root y el servicio no puede escribir en él: se compila ahora.
  "$VENV/bin/python" -m compileall -q "$APP_DIR" >/dev/null 2>&1 || true
}

preparar_usuario_y_carpetas(){
  id "$USUARIO" >/dev/null 2>&1 || useradd --system --home-dir "$DATA_DIR" --no-create-home --shell /usr/sbin/nologin "$USUARIO"
  install -d -m 0755 "$INSTALL_ROOT"
  install -d -m 0750 -o "$USUARIO" -g "$USUARIO" "$DATA_DIR"
  install -d -m 0750 -o root -g "$USUARIO" "$CONF_DIR"
  install -d -m 0700 "$RESPALDOS"
}

# El código y el entorno son de root (el servicio solo los lee).
permisos_app(){ chown -R root:root "$INSTALL_ROOT"; chmod -R go-w "$INSTALL_ROOT"; }

# Copia el código de la carpeta $1 (con app/ y requirements.txt) a la instalación.
copiar_codigo(){
  local origen="$1"
  mkdir -p "$APP_DIR"
  rsync -a --delete "${EXCLUIR[@]}" "$origen/app/" "$APP_DIR/" || return 1
  cp -f "$origen/requirements.txt" "$INSTALL_ROOT/requirements.txt" || return 1
  if [[ -f "$origen/version.txt" ]]; then cp -f "$origen/version.txt" "$INSTALL_ROOT/version.txt"; fi
}

mostrar_acceso(){
  local puerto="$1" ip
  printf '\nAbre QR Studio en:\n  http://localhost:%s/\n' "$puerto"
  for ip in $(hostname -I 2>/dev/null); do [[ "$ip" == *:* ]] || printf '  http://%s:%s/\n' "$ip" "$puerto"; done
  if command -v ufw >/dev/null 2>&1 && [[ "$(ufw status 2>/dev/null)" == *'Status: active'* ]]; then
    aviso "El firewall (ufw) está activo. Para entrar desde otros equipos:  ufw allow $puerto/tcp"
  fi
}

# --- Respaldos (.tar.gz con código + base de datos + configuración) -----------------------
copiar_base(){  # copia consistente aunque el programa la esté usando (modo WAL)
  [[ -f "$1" ]] || return 0
  python3 - "$1" "$2" <<'EOF'
import sqlite3, sys
origen = sqlite3.connect(sys.argv[1]); destino = sqlite3.connect(sys.argv[2])
origen.backup(destino); destino.close(); origen.close()
EOF
}

# crear_respaldo MOTIVO [CARPETA]  -> imprime la ruta del .tar.gz
crear_respaldo(){
  local motivo="$1" carpeta="${2:-$RESPALDOS}" tmp archivo d
  instalado || { fail 'QR Studio no está instalado: no hay nada que respaldar.'; return 1; }
  mkdir -p "$carpeta" || { fail "No se pudo crear $carpeta"; return 1; }
  tmp="$(nuevo_temporal)"; d="$tmp/qr-studio"
  mkdir -p "$d/app"
  rsync -a "${EXCLUIR[@]}" "$APP_DIR/" "$d/app/" || { fail 'No se pudo copiar el código.'; return 1; }
  [[ -f "$INSTALL_ROOT/requirements.txt" ]] && cp "$INSTALL_ROOT/requirements.txt" "$d/requirements.txt"
  [[ -f "$ENV_FILE" ]] && cp "$ENV_FILE" "$d/qr-studio.env"
  copiar_base "$(ruta_db)" "$d/app.db" || { fail 'No se pudo copiar la base de datos.'; return 1; }
  if [[ -d "$(ruta_qr)" ]]; then
    mkdir -p "$d/qr"
    rsync -a "$(ruta_qr)/" "$d/qr/" || { fail 'No se pudieron copiar los QR guardados.'; return 1; }
  fi
  printf 'Fecha: %s\nMotivo: %s\nEquipo: %s\n' "$(date '+%F %T')" "$motivo" "$(hostname)" > "$d/info.txt"
  archivo="$carpeta/qr-studio_${motivo}_$(date +%Y-%m-%d_%H%M%S).tar.gz"
  tar -czf "$archivo" -C "$tmp" qr-studio || { fail 'No se pudo crear el respaldo.'; rm -f "$archivo"; return 1; }
  chmod 600 "$archivo"
  printf '%s' "$archivo"
}

# Extrae un respaldo de forma segura; imprime la carpeta qr-studio extraída.
extraer_respaldo(){
  local archivo="$1" lista tmp
  lista="$(tar -tzf "$archivo" 2>/dev/null)" || { fail "$(basename "$archivo") no es un respaldo válido."; return 1; }
  if rutas_peligrosas "$lista"; then fail "$(basename "$archivo") contiene rutas peligrosas; no se usa."; return 1; fi
  grep -qx 'qr-studio/app/main.py' <<< "$lista" || { fail "$(basename "$archivo") no es un respaldo de QR Studio."; return 1; }
  tmp="$(nuevo_temporal)"
  tar -xzf "$archivo" -C "$tmp" --no-same-owner || { fail 'No se pudo extraer el respaldo.'; return 1; }
  printf '%s' "$tmp/qr-studio"
}

# Deja la instalación exactamente como el respaldo (código y base de datos).
aplicar_respaldo(){
  local carpeta="$1" db
  mkdir -p "$APP_DIR"
  rsync -a --delete "${EXCLUIR[@]}" "$carpeta/app/" "$APP_DIR/" || return 1
  [[ -f "$carpeta/requirements.txt" ]] && cp -f "$carpeta/requirements.txt" "$INSTALL_ROOT/requirements.txt"
  db="$(ruta_db)"
  rm -f "$db-wal" "$db-shm" "$db-journal"
  if [[ -f "$carpeta/app.db" ]]; then
    cp -f "$carpeta/app.db" "$db"; chown "$USUARIO:$USUARIO" "$db"; chmod 640 "$db"
  else
    rm -f "$db"
  fi
  # QR guardados por los usuarios. Un respaldo antiguo (sin qr/) no toca los que hay ahora.
  if [[ -d "$carpeta/qr" ]]; then
    local qr; qr="$(ruta_qr)"
    mkdir -p "$qr"
    rsync -a --delete "$carpeta/qr/" "$qr/" || return 1
    chown -R "$USUARIO:$USUARIO" "$qr"
  fi
  permisos_app
}

# Si una actualización falla, vuelve sola al respaldo recién hecho.
revertir_automatico(){
  local archivo="$1" puerto="$2" carpeta
  [[ -n "$archivo" && -f "$archivo" ]] || return 0
  aviso 'Volviendo automáticamente a la versión anterior...'
  systemctl stop "$SERVICIO" 2>/dev/null || true
  carpeta="$(extraer_respaldo "$archivo")" || { fail "Restaura a mano con la opción 14: $archivo"; return 1; }
  aplicar_respaldo "$carpeta"
  "$VENV/bin/python" -m pip install --disable-pip-version-check --quiet --no-cache-dir -r "$INSTALL_ROOT/requirements.txt" >/dev/null 2>&1 || true
  if arrancar_y_verificar "$puerto"; then ok 'Se volvió a la versión anterior y está funcionando.'
  else fail 'Tampoco arrancó la versión anterior. Revisa la opción 10 (registros).'; fi
}

# --- Instalar / actualizar ------------------------------------------------------------
# instalar_o_actualizar MODO(instalar|actualizar) ORIGEN(carpeta|github)
instalar_o_actualizar(){
  local modo="$1" fuente="$2" linea origen descripcion puerto respaldo=''
  if [[ "$modo" == instalar ]] && instalado; then
    aviso "QR Studio ya está instalado en $INSTALL_ROOT. Usa «Actualizar» (opciones 4 y 5)."; return 1
  fi
  if [[ "$modo" == actualizar ]] && ! instalado; then
    aviso 'QR Studio no está instalado todavía. Usa «Instalar» (opciones 2 y 3).'; return 1
  fi
  if [[ "$fuente" == github ]]; then faltan_dependencias git && return 1; else faltan_dependencias && return 1; fi

  linea="$(obtener_codigo "$fuente")" || return 1
  origen="${linea%%$'\t'*}"; descripcion="${linea#*$'\t'}"
  [[ -f "$origen/app/main.py" && -f "$origen/app/static/index.html" && -f "$origen/requirements.txt" ]] \
    || { fail 'El origen no tiene app/main.py, app/static/index.html y requirements.txt.'; return 1; }

  printf '\n' >&2
  if [[ "$modo" == instalar ]]; then
    info "Instalación NUEVA en $INSTALL_ROOT desde: $descripcion"
    puerto="$(preguntar "Puerto para QR Studio [$PUERTO_DEFECTO]: ")"; puerto="${puerto:-$PUERTO_DEFECTO}"
    puerto_valido "$puerto" || { fail 'Puerto no válido.'; return 1; }
    if puerto_ocupado "$puerto"; then fail "El puerto $puerto ya está en uso por otro programa."; return 1; fi
  else
    puerto="$(leer_puerto)"
    info "ACTUALIZACIÓN (puerto $puerto) desde: $descripcion"
    info 'Antes se guarda un respaldo completo; la base de datos actual se conserva.'
  fi
  confirmar '¿Continuar?' || { aviso 'Cancelado.'; return 1; }

  preparar_usuario_y_carpetas
  if [[ "$modo" == actualizar ]]; then
    respaldo="$(crear_respaldo antes-actualizacion)" || { fail 'No se pudo respaldar. No se cambió nada.'; return 1; }
    ok "Respaldo: $respaldo"
    systemctl stop "$SERVICIO" 2>/dev/null || true
  fi

  info 'Copiando el código...'
  copiar_codigo "$origen" || { fail 'No se pudo copiar el código.'; revertir_automatico "$respaldo" "$puerto"; return 1; }
  asegurar_env "$puerto"
  permisos_app
  instalar_librerias || { revertir_automatico "$respaldo" "$puerto"; return 1; }
  permisos_app
  escribir_servicio
  arrancar_y_verificar "$puerto" || { revertir_automatico "$respaldo" "$puerto"; return 1; }
  mostrar_acceso "$puerto"
  if [[ "$modo" == instalar ]]; then
    printf '\nLa base de datos SQLite está en %s\n' "$(ruta_db)"
    aviso 'Cada persona crea su cuenta con «Crear cuenta» en la página (no hay cuenta administradora).'
    aviso 'Si la sirves por HTTPS con un proxy, usa la opción 12 para activar las cookies seguras.'
  fi
}

# --- Estado, servicio y registros --------------------------------------------------------
deb_resumen_estado(){
  if instalado; then
    if systemctl is-active --quiet "$SERVICIO"; then
      printf '%sEstado:%s instalado y %sfuncionando%s · puerto %s\n' "$C_GRIS" "$C_FIN" "$C_VERDE" "$C_FIN" "$(leer_puerto)"
    else
      printf '%sEstado:%s instalado, %sdetenido%s · puerto %s\n' "$C_GRIS" "$C_FIN" "$C_ROJO" "$C_FIN" "$(leer_puerto)"
    fi
  else
    printf '%sEstado:%s no instalado (%s)\n' "$C_GRIS" "$C_FIN" "$INSTALL_ROOT"
  fi
}

# Resumen de la base SQLite: usuarios y comprobación de integridad (solo lectura).
resumen_sqlite(){
  [[ -f "$1" ]] || { printf 'sin crear todavía (se crea al primer inicio)'; return 0; }
  python3 - "$1" <<'EOF' 2>&1 | tr '\n' ' '
import sqlite3, sys
try:
    c = sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True, timeout=5)
    usuarios = c.execute("select count(*) from users").fetchone()[0]
    integridad = c.execute("pragma integrity_check").fetchone()[0]
    print("%s usuarios · integridad: %s" % (usuarios, integridad))
except Exception as e:
    print("no se pudo leer: %s" % e)
EOF
}

ver_estado(){
  deb_resumen_estado
  instalado || return 0
  local puerto http n db
  puerto="$(leer_puerto)"; db="$(ruta_db)"
  http="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:$puerto/healthz" 2>/dev/null)"
  printf '\nCarpeta:          %s\n' "$INSTALL_ROOT"
  printf 'Respuesta web:    %s\n' "$([[ "$http" == 200 ]] && echo "OK (HTTP 200)" || echo "sin respuesta (HTTP ${http:-000})")"
  printf 'Arranque con el equipo: %s\n' "$(systemctl is-enabled "$SERVICIO" 2>/dev/null || echo no)"
  printf 'Base de datos:    %s (%s)\n' "$db" "$(resumen_sqlite "$db")"
  printf 'Configuración:    %s\n' "$ENV_FILE"
  [[ -f "$INSTALL_ROOT/version.txt" ]] && printf 'Versión del paquete: %s\n' "$(cat "$INSTALL_ROOT/version.txt")"
  printf 'Python:           %s\n' "$("$VENV/bin/python" --version 2>&1)"
  n="$(find "$RESPALDOS" -maxdepth 1 -name 'qr-studio_*.tar.gz' 2>/dev/null | wc -l)"
  printf 'Respaldos:        %s en %s\n' "$n" "$RESPALDOS"
  mostrar_acceso "$puerto"
}

servicio(){
  local accion="$1"
  instalado || { aviso 'QR Studio no está instalado.'; return 1; }
  case "$accion" in
    start)   systemctl enable "$SERVICIO" >/dev/null 2>&1; arrancar_y_verificar "$(leer_puerto)" ;;
    restart) arrancar_y_verificar "$(leer_puerto)" ;;
    stop)    systemctl stop "$SERVICIO" && ok 'QR Studio detenido.' ;;
  esac
}

ver_registros(){
  instalado || { aviso 'QR Studio no está instalado.'; return 1; }
  journalctl -u "$SERVICIO" -n 60 --no-pager
}

cambiar_puerto(){
  instalado || { aviso 'QR Studio no está instalado.'; return 1; }
  local actual nuevo; actual="$(leer_puerto)"
  nuevo="$(preguntar "Puerto nuevo (actual $actual): ")"
  [[ -n "$nuevo" && "$nuevo" != "$actual" ]] || { aviso 'Sin cambios.'; return 0; }
  puerto_valido "$nuevo" || { fail 'Puerto no válido.'; return 1; }
  if puerto_ocupado "$nuevo"; then fail "El puerto $nuevo ya está en uso."; return 1; fi
  escribir_env "$ENV_FILE" APP_PORT "$nuevo"
  if arrancar_y_verificar "$nuevo"; then mostrar_acceso "$nuevo"
  else aviso "Volviendo al puerto $actual..."; escribir_env "$ENV_FILE" APP_PORT "$actual"; arrancar_y_verificar "$actual"; fi
}

# Dirección de escucha y cookies seguras (instalación normal).
cambiar_opciones(){
  instalado || { aviso 'QR Studio no está instalado.'; return 1; }
  local host cookie nuevo
  host="$(leer_env "$ENV_FILE" APP_HOST 0.0.0.0)"; cookie="$(leer_env "$ENV_FILE" APP_COOKIE_SECURE false)"
  printf 'Dirección de escucha: %s   (127.0.0.1 = solo este equipo, útil con un proxy HTTPS delante)\n' "$host"
  printf 'Cookies seguras:      %s   (true SOLO si la página se sirve por HTTPS; con HTTP no se podría iniciar sesión)\n' "$cookie"
  nuevo="$(preguntar "Dirección de escucha [$host]: ")"; nuevo="${nuevo:-$host}"
  [[ "$nuevo" =~ ^[0-9A-Za-z.:-]+$ ]] || { fail 'Dirección no válida.'; return 1; }
  host="$nuevo"
  nuevo="$(preguntar "Cookies seguras (true/false) [$cookie]: ")"; nuevo="${nuevo:-$cookie}"
  [[ "$nuevo" == true || "$nuevo" == false ]] || { fail 'Escribe true o false.'; return 1; }
  escribir_env "$ENV_FILE" APP_HOST "$host"; escribir_env "$ENV_FILE" APP_COOKIE_SECURE "$nuevo"
  arrancar_y_verificar "$(leer_puerto)"
}

# --- Respaldo manual / restaurar / desinstalar ---------------------------------------------
respaldo_manual(){
  instalado || { aviso 'QR Studio no está instalado.'; return 1; }
  local carpeta archivo
  carpeta="$(preguntar "Carpeta donde guardar el respaldo [$RESPALDOS]: ")"; carpeta="${carpeta:-$RESPALDOS}"
  archivo="$(crear_respaldo manual "$carpeta")" || return 1
  ok "Respaldo creado: $archivo ($(du -h "$archivo" | cut -f1))"
  printf '\nIncluye el código, la base de datos (usuarios, sesiones y QR dinámicos), los QR guardados con «Masivo» y la configuración.\n'
  printf 'Para reinstalar en otro equipo: copia este .tar.gz y este instalador, usa la\n'
  printf 'opción 1 y luego la 14. Guárdalo en un lugar seguro: contiene las cuentas de los usuarios.\n'
}

restaurar_respaldo(){
  faltan_dependencias && return 1
  local lista=() archivo carpeta puerto actual='' p
  mapfile -t lista < <(find "$RESPALDOS" "$SCRIPT_DIR" -maxdepth 1 -type f -name 'qr-studio_*.tar.gz' -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2-)
  if ((${#lista[@]})); then
    archivo="$(elegir_de_lista 'Respaldos encontrados (el más reciente primero):' "${lista[@]}")" || return 1
  else
    archivo="$(preguntar 'Ruta del respaldo (.tar.gz): ')"
  fi
  [[ -f "$archivo" ]] || { fail "No existe: $archivo"; return 1; }
  carpeta="$(extraer_respaldo "$archivo")" || return 1
  sed -n 's/^/  /p' "$carpeta/info.txt" 2>/dev/null >&2

  if instalado; then
    puerto="$(leer_puerto)"
    aviso 'Se reemplazarán el código Y la base de datos actuales por los del respaldo.'
    aviso 'Lo registrado después de ese respaldo se pierde (antes se guarda un respaldo del estado actual).'
    [[ "$(preguntar 'Escribe RESTAURAR para continuar: ')" == RESTAURAR ]] || { aviso 'Cancelado.'; return 1; }
    actual="$(crear_respaldo antes-de-restaurar)" || { fail 'No se pudo respaldar el estado actual. No se cambió nada.'; return 1; }
    ok "Estado actual guardado en: $actual"
    systemctl stop "$SERVICIO" 2>/dev/null || true
  else
    p="$(leer_env "$carpeta/qr-studio.env" APP_PORT "$PUERTO_DEFECTO")"
    puerto="$(preguntar "Reinstalación desde el respaldo. Puerto [$p]: ")"; puerto="${puerto:-$p}"
    puerto_valido "$puerto" || { fail 'Puerto no válido.'; return 1; }
    if puerto_ocupado "$puerto"; then fail "El puerto $puerto ya está en uso por otro programa."; return 1; fi
    confirmar '¿Continuar?' || { aviso 'Cancelado.'; return 1; }
  fi

  preparar_usuario_y_carpetas
  if [[ ! -f "$ENV_FILE" && -f "$carpeta/qr-studio.env" ]]; then
    cp "$carpeta/qr-studio.env" "$ENV_FILE"; chmod 600 "$ENV_FILE"
    escribir_env "$ENV_FILE" APP_DB_PATH "$DATA_DIR/app.db"
  fi
  asegurar_env "$puerto"
  aplicar_respaldo "$carpeta" || { fail 'No se pudo copiar el respaldo.'; revertir_automatico "$actual" "$puerto"; return 1; }
  instalar_librerias || { revertir_automatico "$actual" "$puerto"; return 1; }
  permisos_app
  escribir_servicio
  arrancar_y_verificar "$puerto" || { revertir_automatico "$actual" "$puerto"; return 1; }
  ok "Restaurado desde $(basename "$archivo")."
  mostrar_acceso "$puerto"
}

desinstalar(){
  instalado || [[ -f "$UNIDAD" ]] || { aviso 'QR Studio no está instalado.'; return 1; }
  local final=''
  aviso "Se eliminará QR Studio: servicio, $INSTALL_ROOT (código), $DATA_DIR (base de datos con las cuentas), $CONF_DIR y el usuario $USUARIO."
  if instalado && confirmar '¿Guardar antes un respaldo final? (recomendado)'; then
    final="$(crear_respaldo antes-de-desinstalar)" || { fail 'No se pudo crear el respaldo final. No se eliminó nada.'; return 1; }
    ok "Respaldo final: $final"
  fi
  [[ "$(preguntar 'Escribe ELIMINAR QR STUDIO para continuar: ')" == 'ELIMINAR QR STUDIO' ]] || { aviso 'Cancelado.'; return 1; }
  systemctl disable --now "$SERVICIO" >/dev/null 2>&1 || true
  rm -f "$UNIDAD"; systemctl daemon-reload
  borrar_carpeta "$INSTALL_ROOT"; borrar_carpeta "$DATA_DIR"; borrar_carpeta "$CONF_DIR"
  id "$USUARIO" >/dev/null 2>&1 && userdel "$USUARIO" >/dev/null 2>&1
  ok 'QR Studio desinstalado.'
  if [[ -d "$RESPALDOS" ]]; then
    printf 'Los respaldos se conservan en %s (sirven para reinstalar con la opción 14).\n' "$RESPALDOS"
    if confirmar '¿Borrar también TODOS los respaldos? (no se puede deshacer)'; then
      borrar_carpeta "$RESPALDOS" && ok 'Respaldos eliminados.'
    fi
  fi
}

# --- Docker ---------------------------------------------------------------------------------
docker_instalado(){ [[ -f "$ROOT_DOCKER/docker-compose.yml" ]]; }

dc(){   # docker compose (plugin) o docker-compose (clásico)
  if docker compose version >/dev/null 2>&1; then docker compose "$@"
  else docker-compose "$@"; fi
}
docker_disponible(){ command -v docker >/dev/null 2>&1 && { docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; }; }

docker_puerto(){ leer_env "$ROOT_DOCKER/.env" APP_PORT "$PUERTO_DEFECTO"; }

resumen_general(){
  local n=0
  if instalado; then
    printf '%sNormal (Debian):%s instalado, servicio %s, puerto %s\n' "$C_GRIS" "$C_FIN" "$(systemctl is-active "$SERVICIO" 2>/dev/null || echo detenido)" "$(leer_puerto)"
  else printf '%sNormal (Debian):%s no instalado\n' "$C_GRIS" "$C_FIN"; fi
  if docker_instalado; then
    docker_disponible && n="$(cd "$ROOT_DOCKER" && dc ps -q 2>/dev/null | wc -l)"
    printf '%sDocker:%s instalado, contenedores activos: %s, puerto %s\n' "$C_GRIS" "$C_FIN" "$n" "$(docker_puerto)"
  else printf '%sDocker:%s no instalado\n' "$C_GRIS" "$C_FIN"; fi
  printf '%sBase de datos:%s SQLite (un archivo; usuarios y sesiones)\n' "$C_GRIS" "$C_FIN"
}

# Opción «Instalar dependencias (Docker)»: instala Docker, compose y las herramientas que usa
# la instalación. La salida de apt va a un registro (sin barras de progreso) para que, si algo
# falla, se vea el motivo en vez de quedar la pantalla cortada.
docker_dependencias(){
  local log="$SESION_TMP/apt-docker.log" paquetes_compose
  info 'Instalando dependencias de Docker (puede tardar unos minutos)...'
  # Cada paso muestra su avance en pantalla (sangrado) y lo guarda también en $log.
  # --force-confdef/--force-confold: ante un conffile modificado o borrado (p. ej. containerd
  # config.toml) dpkg decide solo y conserva lo actual, en vez de preguntar sin stdin y fallar.
  paso_apt(){ DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Progress-Fancy=0 \
      -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@" </dev/null 2>&1 \
      | tee -a "$log" | sed -u 's/^/    /' >&2; }

  info '[1/4] Actualizando la lista de paquetes (apt-get update)...'
  if ! paso_apt update; then
    aviso 'apt-get update dio errores (repositorio caído o reloj del sistema desfasado: revisa «date»); se intenta seguir.'
  fi
  # Repara instalaciones interrumpidas (paquetes «not fully installed») antes de continuar.
  DEBIAN_FRONTEND=noninteractive dpkg --force-confdef --force-confold --configure -a </dev/null 2>&1 \
    | tee -a "$log" | sed -u 's/^/    /' >&2 || true

  # 1) Docker y las herramientas, SIN compose: así un problema de compose no bloquea lo demás.
  # apparmor: Docker lo usa para aislar los contenedores; sin «apparmor_parser» no puede crearlos.
  info '[2/4] Instalando Docker y herramientas (docker.io, apparmor, python3, unzip, rsync, curl, ca-certificates, git)...'
  if ! paso_apt -y install docker.io apparmor python3 unzip rsync curl ca-certificates git iproute2 tar; then
    fail 'No se pudo instalar Docker (ver el detalle arriba).'
    return 1
  fi
  if [[ -d /sys/kernel/security/apparmor ]] && ! command -v apparmor_parser >/dev/null 2>&1; then
    fail 'AppArmor está activo pero falta apparmor_parser. Instala el paquete «apparmor» y reintenta.'
    return 1
  fi
  systemctl enable --now docker >/dev/null 2>&1 || true
  if docker info >/dev/null 2>&1; then ok "Docker listo: $(docker --version 2>/dev/null)"
  else fail 'Docker se instaló pero el servicio no responde (revisa: systemctl status docker).'; return 1; fi

  # 2) Compose por apt, del más nuevo al más antiguo (el primero que se pueda instalar).
  info '[3/4] Instalando docker compose (por apt)...'
  if ! docker_disponible; then
    for paquetes_compose in docker-compose-v2 docker-compose-plugin docker-compose; do
      if ! apt-cache show "$paquetes_compose" >/dev/null 2>&1; then
        info "    $paquetes_compose: no existe en los repositorios, se salta."; continue
      fi
      info "    Probando el paquete $paquetes_compose..."
      if paso_apt -y install "$paquetes_compose" && docker_disponible; then ok "compose instalado con $paquetes_compose."; break; fi
      aviso "No se pudo con $paquetes_compose (dependencias rotas en los repositorios)."
    done
  fi
  # 3) Alternativa: el plugin oficial de compose v2 (binario de github.com/docker/compose).
  if ! docker_disponible; then
    info '[4/4] Alternativa: descargar el plugin oficial de compose (docker/compose en GitHub)...'
    compose_binario || return 1
  else
    info '[4/4] No hace falta la descarga alternativa.'
  fi
  if docker_disponible; then ok "Compose listo: $(dc version --short 2>/dev/null || dc --version 2>/dev/null | head -n1)"
  else fail 'No quedó disponible docker compose.'; return 1; fi
}

# Descarga el plugin «docker compose» v2 desde las publicaciones oficiales de GitHub y verifica su
# suma SHA-256 antes de instalarlo en /usr/local/lib/docker/cli-plugins/.
compose_binario(){
  local arq url destino="/usr/local/lib/docker/cli-plugins/docker-compose" tmp esperado real
  case "$(uname -m)" in
    x86_64) arq=x86_64 ;; aarch64|arm64) arq=aarch64 ;; armv7l) arq=armv7 ;;
    *) fail "Arquitectura no soportada para la descarga: $(uname -m)"; return 1 ;;
  esac
  url="https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$arq"
  printf 'Se descargará: %s\n' "$url" >&2
  confirmar '¿Descargar e instalar?' || { aviso 'Cancelado.'; return 1; }
  tmp="$SESION_TMP/docker-compose"
  info 'Descargando (barra de progreso)...'
  curl -fL --progress-bar --max-time 300 -o "$tmp" "$url" || { fail 'No se pudo descargar (¿hay internet y acceso a github.com?).'; return 1; }
  info 'Verificando la suma SHA-256...'
  esperado="$(curl -fsSL --max-time 60 "$url.sha256" 2>/dev/null | awk '{print $1}' | head -n1)"
  real="$(sha256sum "$tmp" | awk '{print $1}')"
  if [[ -z "$esperado" || "$esperado" != "$real" ]]; then
    fail 'La suma SHA-256 no coincide (o no se pudo obtener). No se instaló.'; return 1
  fi
  if ! { mkdir -p "$(dirname "$destino")" && install -m 0755 "$tmp" "$destino"; }; then
    fail 'No se pudo instalar el plugin.'; return 1
  fi
  ok 'Plugin de compose instalado y verificado.'
}

# Escribe Dockerfile, docker-compose.yml y .dockerignore (el paquete de GitHub solo trae el código).
escribir_archivos_docker(){   # escribir_archivos_docker PUERTO
  local puerto="$1"
  cat > "$ROOT_DOCKER/Dockerfile" <<'EOF'
# QR Studio · imagen Docker. Misma versión de Python que Debian 12 (3.11).
FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_DB_PATH=/data/app.db

WORKDIR /srv/qr-studio

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Usuario sin privilegios y directorio de datos (aquí vive el archivo SQLite).
RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin qrstudio \
    && mkdir /data \
    && chown qrstudio:qrstudio /data
USER qrstudio
VOLUME /data

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=4)" || exit 1

CMD ["uvicorn", "--factory", "app.main:create_app", "--host", "0.0.0.0", "--port", "8000"]
EOF
  cat > "$ROOT_DOCKER/docker-compose.yml" <<'EOF'
# QR Studio con Docker. La base de datos SQLite queda en ./datos (se respalda con el menú del
# instalador). Las variables APP_* se leen del archivo .env de esta carpeta.
name: qr-studio

services:
  web:
    build: .
    image: qr-studio:latest
    container_name: qr-studio
    restart: unless-stopped
    ports:
      - "${APP_PORT:-8000}:8000"
    environment:
      APP_DB_PATH: /data/app.db
      APP_COOKIE_SECURE: "${APP_COOKIE_SECURE:-false}"
      APP_SESSION_DAYS: "${APP_SESSION_DAYS:-14}"
      APP_MIN_PASSWORD_LENGTH: "${APP_MIN_PASSWORD_LENGTH:-8}"
      APP_LOGIN_MAX_ATTEMPTS: "${APP_LOGIN_MAX_ATTEMPTS:-5}"
      APP_LOGIN_WINDOW_SECONDS: "${APP_LOGIN_WINDOW_SECONDS:-300}"
      APP_QR_QUOTA_MB: "${APP_QR_QUOTA_MB:-200}"
      APP_DYNAMIC_QR: "${APP_DYNAMIC_QR:-true}"
      APP_PUBLIC_URL: "${APP_PUBLIC_URL:-}"
    volumes:
      - ./datos:/data
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
EOF
  printf '%s\n' '*.pyc' '__pycache__/' '.venv/' 'venv/' '*.db' '*.db-wal' '*.db-shm' 'datos/' '.env' > "$ROOT_DOCKER/.dockerignore"
  local f="$ROOT_DOCKER/.env"
  escribir_env "$f" APP_PORT "$puerto"
  [[ -n "$(leer_env "$f" APP_COOKIE_SECURE)" ]] || escribir_env "$f" APP_COOKIE_SECURE false
}

# Copia el código de la carpeta $1 (con app/ y requirements.txt) a la carpeta de Docker.
copiar_codigo_docker(){
  mkdir -p "$ROOT_DOCKER/app" "$ROOT_DOCKER/datos"
  rsync -a --delete "${EXCLUIR[@]}" "$1/app/" "$ROOT_DOCKER/app/" || return 1
  cp -f "$1/requirements.txt" "$ROOT_DOCKER/requirements.txt" || return 1
  if [[ -f "$1/version.txt" ]]; then cp -f "$1/version.txt" "$ROOT_DOCKER/version.txt"; fi
  # El contenedor corre como el usuario 10001 y escribe la base en ./datos.
  chown 10001:10001 "$ROOT_DOCKER/datos"; chmod 750 "$ROOT_DOCKER/datos"
}

esperar_docker(){   # esperar_docker PUERTO
  local i
  for i in $(seq 1 60); do
    curl -fs -o /dev/null --max-time 2 "http://127.0.0.1:$1/healthz" && return 0
    sleep 1
  done
  return 1
}

docker_instalar_o_actualizar(){   # docker_instalar_o_actualizar instalar|actualizar
  local modo="$1" linea codigo descripcion puerto respaldo
  if [[ "$modo" == instalar ]] && docker_instalado; then aviso 'Docker ya está instalado. Usa «Actualizar».'; return 1; fi
  if [[ "$modo" == actualizar ]] && ! docker_instalado; then aviso 'Docker no está instalado todavía.'; return 1; fi
  if ! docker_disponible || ! docker info >/dev/null 2>&1 || ! command -v rsync >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    fail 'Faltan las dependencias de Docker. Primero usa la opción «Instalar dependencias (Docker)» del menú.'
    return 1
  fi
  linea="$(obtener_codigo_menu)" || return 1
  codigo="${linea%%$'\t'*}"; descripcion="${linea#*$'\t'}"
  [[ -f "$codigo/app/main.py" && -f "$codigo/app/static/index.html" && -f "$codigo/requirements.txt" ]] \
    || { fail 'El origen no tiene app/main.py, app/static/index.html y requirements.txt.'; return 1; }

  if [[ "$modo" == instalar ]]; then
    puerto="$(preguntar "Puerto [$PUERTO_DEFECTO]: ")"; puerto="${puerto:-$PUERTO_DEFECTO}"
    puerto_valido "$puerto" || { fail 'Puerto no válido.'; return 1; }
    if puerto_ocupado "$puerto"; then fail "El puerto $puerto ya está en uso."; return 1; fi
    confirmar "Instalar en $ROOT_DOCKER con el código de: $descripcion. ¿Continuar?" || return 1
    mkdir -p "$ROOT_DOCKER"
  else
    puerto="$(docker_puerto)"
    confirmar "Actualizar (puerto $puerto) con el código de: $descripcion. La base de datos se conserva. ¿Continuar?" || return 1
    respaldo="$(docker_respaldo antes-actualizacion)" || { fail 'No se pudo respaldar. No se cambió nada.'; return 1; }
    ok "Respaldo: $respaldo"
    (cd "$ROOT_DOCKER" && dc down >/dev/null 2>&1)
  fi
  copiar_codigo_docker "$codigo" || { fail 'No se pudo copiar el código.'; return 1; }
  escribir_archivos_docker "$puerto"
  info 'Construyendo y levantando el contenedor (la primera vez tarda unos minutos)...'
  if (cd "$ROOT_DOCKER" && dc up -d --build) && esperar_docker "$puerto"; then
    ok "QR Studio con Docker está funcionando: http://$(hostname -I 2>/dev/null | awk '{print $1}'):$puerto"
    [[ "$modo" == instalar ]] && aviso 'Cada persona crea su cuenta con «Crear cuenta» en la página (no hay cuenta administradora).'
  else
    fail 'No se pudo construir o arrancar el contenedor (el motivo está en las líneas de arriba).'
    if grep -qx qr-studio <<< "$(docker ps -a --format '{{.Names}}' 2>/dev/null)"; then
      info 'Últimas líneas del registro del contenedor:'; (cd "$ROOT_DOCKER" && dc logs --tail 20) >&2
    fi
    aviso 'Si ves «apparmor_parser not found», usa la opción «Instalar dependencias (Docker)» y reintenta.'
    aviso 'Si este equipo es un contenedor LXC (por ejemplo Proxmox/TurnKey), activa «nesting» en sus opciones.'
    return 1
  fi
}

docker_respaldo(){   # imprime la ruta del respaldo (código + base de datos consistente + configuración)
  local motivo="${1:-manual}" archivo tmp d
  mkdir -p "$RESPALDOS_DOCKER"; chmod 700 "$RESPALDOS_DOCKER"
  tmp="$(nuevo_temporal)"; d="$tmp/qr-studio"
  mkdir -p "$d"
  cp -a "$ROOT_DOCKER/app" "$d/app" || return 1
  [[ -f "$ROOT_DOCKER/requirements.txt" ]] && cp "$ROOT_DOCKER/requirements.txt" "$d/requirements.txt"
  [[ -f "$ROOT_DOCKER/.env" ]] && cp "$ROOT_DOCKER/.env" "$d/qr-studio.env"
  copiar_base "$ROOT_DOCKER/datos/app.db" "$d/app.db" || return 1
  if [[ -d "$ROOT_DOCKER/datos/qr" ]]; then cp -a "$ROOT_DOCKER/datos/qr" "$d/qr" || return 1; fi   # QR guardados
  printf 'Fecha: %s\nMotivo: %s\nEquipo: %s\n' "$(date '+%F %T')" "$motivo" "$(hostname)" > "$d/info.txt"
  archivo="$RESPALDOS_DOCKER/qr-studio-docker_${motivo}_$(date +%Y-%m-%d_%H%M%S).tar.gz"
  tar -czf "$archivo" -C "$tmp" qr-studio || { rm -f "$archivo"; return 1; }
  chmod 600 "$archivo"; printf '%s' "$archivo"
}

docker_respaldo_manual(){
  docker_instalado || { aviso 'Docker no está instalado.'; return 1; }
  local r
  if r="$(docker_respaldo manual)"; then ok "Respaldo: $r"; else fail 'No se pudo crear el respaldo.'; return 1; fi
}

docker_accion(){   # docker_accion start|stop|restart|logs|ps
  docker_instalado || { aviso 'Docker no está instalado.'; return 1; }
  case "$1" in
    logs) (cd "$ROOT_DOCKER" && dc logs --tail 100 -f) ;;
    ps)   (cd "$ROOT_DOCKER" && dc ps) ;;
    *)    (cd "$ROOT_DOCKER" && dc "$1") ;;
  esac
}

docker_cambiar_puerto(){
  docker_instalado || { aviso 'Docker no está instalado.'; return 1; }
  local actual nuevo; actual="$(docker_puerto)"
  nuevo="$(preguntar "Puerto nuevo (actual $actual): ")"
  [[ -n "$nuevo" && "$nuevo" != "$actual" ]] || { aviso 'Sin cambios.'; return 0; }
  puerto_valido "$nuevo" || { fail 'Puerto no válido.'; return 1; }
  if puerto_ocupado "$nuevo"; then fail "El puerto $nuevo ya está en uso."; return 1; fi
  escribir_env "$ROOT_DOCKER/.env" APP_PORT "$nuevo"
  if (cd "$ROOT_DOCKER" && dc up -d) && esperar_docker "$nuevo"; then ok "Ahora en el puerto $nuevo."; else fail 'No arrancó con el puerto nuevo.'; fi
}

docker_cambiar_cookies(){
  docker_instalado || { aviso 'Docker no está instalado.'; return 1; }
  local actual nuevo; actual="$(leer_env "$ROOT_DOCKER/.env" APP_COOKIE_SECURE false)"
  printf 'Cookies seguras: %s   (true SOLO si la página se sirve por HTTPS; con HTTP no se podría iniciar sesión)\n' "$actual"
  nuevo="$(preguntar "Cookies seguras (true/false) [$actual]: ")"; nuevo="${nuevo:-$actual}"
  [[ "$nuevo" == true || "$nuevo" == false ]] || { fail 'Escribe true o false.'; return 1; }
  escribir_env "$ROOT_DOCKER/.env" APP_COOKIE_SECURE "$nuevo"
  (cd "$ROOT_DOCKER" && dc up -d) && ok 'Configuración aplicada.'
}

docker_desinstalar(){
  docker_instalado || { aviso 'Docker no está instalado.'; return 1; }
  aviso "Se eliminará el contenedor, la imagen y $ROOT_DOCKER (código Y base de datos con las cuentas)."
  if confirmar '¿Guardar antes un respaldo final? (recomendado)'; then
    local r; r="$(docker_respaldo antes-de-desinstalar)" || { fail 'No se pudo respaldar. No se eliminó nada.'; return 1; }
    ok "Respaldo final: $r"
  fi
  [[ "$(preguntar 'Escribe DESINSTALAR para continuar: ')" == DESINSTALAR ]] || { aviso 'Cancelado.'; return 1; }
  (cd "$ROOT_DOCKER" && dc down --rmi local >/dev/null 2>&1)
  borrar_carpeta "$ROOT_DOCKER" && ok 'Docker desinstalado.'
}

# --- Menús ---------------------------------------------------------------------------------
menu_debian(){
  local opcion
  while true; do
    clear 2>/dev/null || true
    printf '%s\n' "${C_CIAN}QR Studio · Instalación normal (Debian)${C_FIN}"
    deb_resumen_estado
    printf '\n%sInstalación%s\n' "$C_GRIS" "$C_FIN"
    opcion_menu 1  'Instalar dependencias'
    opcion_menu 2  'Instalar desde la carpeta (código o .zip)'
    opcion_menu 3  'Instalar desde GitHub'
    opcion_menu 4  'Actualizar desde la carpeta (código o .zip)'
    opcion_menu 5  'Actualizar desde GitHub'
    printf '%sServicio%s\n' "$C_GRIS" "$C_FIN"
    opcion_menu 6  'Ver estado'
    opcion_menu 7  'Iniciar'
    opcion_menu 8  'Detener'
    opcion_menu 9  'Reiniciar'
    opcion_menu 10 'Ver registros'
    opcion_menu 11 'Cambiar puerto'
    opcion_menu 12 'Dirección de escucha y cookies seguras (HTTPS)'
    printf '%sRespaldos%s\n' "$C_GRIS" "$C_FIN"
    opcion_menu 13 'Crear respaldo completo (código + base de datos)'
    opcion_menu 14 'Restaurar respaldo / reinstalar desde respaldo'
    opcion_menu 15 'Desinstalar'
    opcion_menu 0  'Volver'
    printf '\n'
    read -rp 'Opción: ' opcion </dev/tty || break
    printf '\n'
    case "$opcion" in
      1)  instalar_dependencias ;;
      2)  instalar_o_actualizar instalar carpeta ;;
      3)  instalar_o_actualizar instalar github ;;
      4)  instalar_o_actualizar actualizar carpeta ;;
      5)  instalar_o_actualizar actualizar github ;;
      6)  ver_estado ;;
      7)  servicio start ;;
      8)  servicio stop ;;
      9)  servicio restart ;;
      10) ver_registros ;;
      11) cambiar_puerto ;;
      12) cambiar_opciones ;;
      13) respaldo_manual ;;
      14) restaurar_respaldo ;;
      15) desinstalar ;;
      0|q|Q) break ;;
      *) continue ;;
    esac
    vaciar_temporales
    printf '\n'; pausa
  done
}

menu_docker(){
  local opcion
  while true; do
    clear 2>/dev/null || true
    printf '%s\n' "${C_CIAN}QR Studio · Instalación con Docker${C_FIN}"
    resumen_general
    printf '\n'
    printf '%sPrimero%s\n' "$C_GRIS" "$C_FIN"
    opcion_menu 1 'Instalar dependencias (Docker, compose, git, rsync)'
    printf '%sInstalación%s\n' "$C_GRIS" "$C_FIN"
    opcion_menu 2 'Instalar con Docker (carpeta, .zip o GitHub)'
    opcion_menu 3 'Actualizar (carpeta, .zip o GitHub)'
    printf '%sServicio y respaldos%s\n' "$C_GRIS" "$C_FIN"
    opcion_menu 4 'Iniciar'
    opcion_menu 5 'Detener'
    opcion_menu 6 'Reiniciar'
    opcion_menu 7 'Ver registros (Ctrl+C para salir)'
    opcion_menu 8 'Cambiar puerto'
    opcion_menu 9 'Cookies seguras (HTTPS)'
    opcion_menu 10 'Crear respaldo'
    opcion_menu 11 'Desinstalar'
    opcion_menu 0 'Volver'
    printf '\n'
    read -rp 'Opción: ' opcion </dev/tty || break
    printf '\n'
    case "$opcion" in
      1) docker_dependencias ;;
      2) docker_instalar_o_actualizar instalar ;;
      3) docker_instalar_o_actualizar actualizar ;;
      4) docker_accion start ;;
      5) docker_accion stop ;;
      6) docker_accion restart ;;
      7) docker_accion logs ;;
      8) docker_cambiar_puerto ;;
      9) docker_cambiar_cookies ;;
      10) docker_respaldo_manual ;;
      11) docker_desinstalar ;;
      0|q|Q) break ;;
      *) continue ;;
    esac
    vaciar_temporales
    printf '\n'; pausa
  done
}

menu_principal(){
  local principal
  while true; do
    clear 2>/dev/null || true
    printf '%s\n' "${C_CIAN}QR Studio · Instalador v$VERSION_INSTALADOR${C_FIN}"
    resumen_general
    printf '\n'
    opcion_menu 1 'Instalación normal (Python + servicio en Debian)'
    opcion_menu 2 'Instalación con Docker'
    opcion_menu 0 'Salir'
    printf '\n'
    read -rp 'Opción: ' principal </dev/tty || break
    printf '\n'
    case "$principal" in
      1) menu_debian ;;
      2) menu_docker ;;
      0|q|Q) break ;;
      *) continue ;;
    esac
  done
}

if (( SOURCED == 0 )); then menu_principal; fi
