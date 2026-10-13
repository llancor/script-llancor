#!/usr/bin/env bash
# ===========================================================================
# Seshat Inventario - Instalador v4.0 (Debian normal + Docker, todo en uno)
# ---------------------------------------------------------------------------
# Un solo script con menú para dos formas de instalar, con la MISMA configuración:
#   1) Normal: Python + servicio systemd
#        /opt/seshat-inventario/          código en app/, base en app/inventario_colegio.db
#        servicio: seshat-inventario      respaldos: /var/backups/seshat-inventario
#   2) Docker: contenedor + docker compose
#        /opt/seshat-inventario-docker/   código en app/, base en datos/inventario_colegio.db
#   3) Base de datos: SQLite (por defecto) o datos de conexión a MariaDB
#
# Configuración compartida: archivo seshat.env en cada carpeta de instalación
# (SESHAT_DB_MOTOR, SESHAT_MARIADB_*). El servicio de Debian y el contenedor lo leen igual.
# SESHAT_DB_MOTOR=sqlite (archivo local) o mysql (MariaDB/MySQL, con los datos SESHAT_MARIADB_*).
# Con MariaDB, los respaldos guardan un volcado de las tablas (no hace falta mysqldump) y
# «Base de datos» (menú) copia los datos de SQLite al servidor al cambiar de motor.
#
# Actualizar = se respalda todo, se copia el código nuevo y la base de datos se CONSERVA.
# Normal: si la versión nueva no arranca, vuelve sola a la anterior.
#
# GitHub: https://github.com/llancor/seshat/tree/main/Seshat_Inventario (pide usuario y token).
# Variables opcionales: SESHAT_DIR, SESHAT_DIR_DOCKER, SESHAT_RESPALDOS, SESHAT_REPO_URL,
# SESHAT_REPO_BRANCH, SESHAT_REPO_CARPETA.
# Uso:  sudo bash Instalar_Seshat_Inventario_v4.0.sh
# ===========================================================================
set -uo pipefail

VERSION_INSTALADOR='4.0.0'
INSTALL_ROOT="${SESHAT_DIR:-/opt/seshat-inventario}"
ROOT_DEBIAN="$INSTALL_ROOT"
ROOT_DOCKER="${SESHAT_DIR_DOCKER:-/opt/seshat-inventario-docker}"
APP_DIR="$INSTALL_ROOT/app"
VENV="$INSTALL_ROOT/venv"
CONFIG="$INSTALL_ROOT/seshat.conf"
RESPALDOS="${SESHAT_RESPALDOS:-/var/backups/seshat-inventario}"
SERVICIO='seshat-inventario'
UNIDAD="/etc/systemd/system/$SERVICIO.service"
USUARIO='seshat'
PUERTO_DEFECTO=8000
REPO_URL="${SESHAT_REPO_URL:-https://github.com/llancor/seshat.git}"
REPO_BRANCH="${SESHAT_REPO_BRANCH:-main}"
REPO_CARPETA="${SESHAT_REPO_CARPETA:-Seshat_Inventario}"   # https://github.com/llancor/seshat/tree/main/Seshat_Inventario
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE='inventario_colegio.db'
# La base de datos y sus archivos auxiliares nunca se copian junto con el código.
EXCLUIR=(--exclude "$BASE" --exclude "$BASE-wal" --exclude "$BASE-shm" --exclude "$BASE-journal"
         --exclude '__pycache__/' --exclude '.venv/' --exclude 'venv/' --exclude '*.pyc'
         --exclude '.git/' --exclude '.claude/' --exclude 'respaldos_migracion/')

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
# (para usar las variables SESHAT_* ejecútalo directamente como root: sudo -E o su).
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then exec sudo -E bash "$0" "$@"; fi
  fail 'Ejecuta este instalador como root:  su -c "bash Instalar_Seshat_Inventario_Debian.sh"'
  exit 1
fi

# Temporales: todos dentro de una carpeta de la sesión, creada aquí (proceso principal)
# para que también se borren los creados dentro de $( ... ). Se vacía tras cada opción.
SESION_TMP="$(mktemp -d /tmp/seshat-inv.XXXXXX)"
chmod 700 "$SESION_TMP"
nuevo_temporal(){ mktemp -d "$SESION_TMP/t.XXXXXX"; }
vaciar_temporales(){ find "$SESION_TMP" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true; }
trap 'rm -rf -- "$SESION_TMP"' EXIT

instalado(){ [[ -f "$APP_DIR/main.py" ]]; }
leer_puerto(){ local p=''; [[ -f "$CONFIG" ]] && p="$(sed -n 's/^PUERTO=\([0-9]\+\)$/\1/p' "$CONFIG" | head -n1)"; printf '%s' "${p:-$PUERTO_DEFECTO}"; }
puerto_ocupado(){ ss -ltnH "sport = :$1" 2>/dev/null | grep -q .; }
puerto_valido(){ [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }

# --- 1) Dependencias ---------------------------------------------------------
instalar_dependencias(){
  info 'Instalando dependencias del sistema...'
  info '[1/3] Actualizando la lista de paquetes (apt-get update)...'
  # Un repositorio ignorado (reloj desfasado, mirror caído) hace que update devuelva error aunque
  # los demás se actualicen: se avisa y se sigue; si falta algún paquete, el install lo dirá.
  if ! apt-get -o Dpkg::Progress-Fancy=0 update </dev/null; then
    aviso 'apt-get update dio errores (¿sin internet, repositorio caído o reloj desfasado? revisa «date»); se intenta seguir.'
  fi
  info '[2/3] Instalando: python3, venv, pip, unzip, git, rsync, curl, sqlite3, iproute2, iputils-ping, ieee-data...'
  DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Progress-Fancy=0 install -y \
    python3 python3-venv python3-pip unzip git rsync curl ca-certificates sqlite3 iproute2 iputils-ping tar ieee-data </dev/null \
    || { fail 'No se pudieron instalar las dependencias (ver el detalle arriba).'; return 1; }
  info '[3/3] Verificando...'
  local c falta=0
  for c in python3 unzip rsync curl git sqlite3 ip ping; do
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
      fail "Seshat Inventario necesita Python 3.10 o superior ($(python3 --version 2>&1))."; return 0
    fi
  fi
  if ((${#falta[@]})); then fail "Faltan dependencias: ${falta[*]}. Usa primero la opción 1."; return 0; fi
  return 1
}

# --- Paquetes .zip de código ---------------------------------------------------
# Clave para ordenar Seshat_Inventario_vDDMMAAAAHHMM.zip por fecha real (AAAAMMDDHHMM).
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
  local ordenados=()
  mapfile -t ordenados < <(for z in "$@"; do printf '%s\t%s\n' "$(clave_zip "$z")" "$z"; done | sort -r | cut -f2-)
  elegir_de_lista 'Paquetes encontrados (el más reciente primero):' "${ordenados[@]}"
}

# Carpeta (la de ruta más corta) que contiene main.py e index.html.
buscar_codigo(){
  local base="$1" f d mejor=''
  while IFS= read -r -d '' f; do
    d="$(dirname "$f")"
    [[ -f "$d/index.html" ]] || continue
    if [[ -z "$mejor" || ${#d} -lt ${#mejor} ]]; then mejor="$d"; fi
  done < <(find "$base" -maxdepth 5 -type f -name main.py -not -path '*/.venv/*' -not -path '*/venv/*' -not -path '*/.git/*' -print0 2>/dev/null)
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
  [[ -n "$codigo" ]] || { fail "$(basename "$zip") no contiene Seshat Inventario (main.py e index.html)."; return 1; }
  printf '%s' "$codigo"
}

# --- Obtener el código: carpeta o GitHub ----------------------------------------
# Ambas imprimen por stdout "carpeta_del_código<TAB>descripción".
codigo_desde_carpeta(){
  local ruta zips=() zip codigo
  ruta="$(preguntar "Carpeta o .zip con Seshat Inventario [$SCRIPT_DIR]: ")"
  ruta="${ruta:-$SCRIPT_DIR}"; ruta="${ruta%/}"
  if [[ -f "$ruta" && "$ruta" == *.zip ]]; then
    zip="$ruta"
  elif [[ -d "$ruta" ]]; then
    if [[ -f "$ruta/main.py" && -f "$ruta/index.html" ]]; then printf '%s\t%s' "$ruta" "carpeta $ruta"; return 0; fi
    mapfile -t zips < <(find "$ruta" -maxdepth 3 -type f -name 'Seshat_Inventario_v*.zip' 2>/dev/null)
    if ((${#zips[@]} == 0)); then
      codigo="$(buscar_codigo "$ruta")"
      [[ -n "$codigo" ]] || { fail "No se encontró Seshat Inventario (Seshat_Inventario_v*.zip o main.py + index.html) en $ruta"; return 1; }
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

# Descarga solo la carpeta $REPO_CARPETA de github.com/llancor/seshat (rama main) con
# usuario y token. El token se entrega a git por GIT_ASKPASS: no queda en la URL, en el
# historial de la consola ni en disco, y se olvida al terminar.
codigo_desde_github(){
  local usuario='' token='' tmp repo origen zips=() zip codigo
  printf 'Repositorio: %s  (rama %s, carpeta %s)\n' "${REPO_URL%.git}" "$REPO_BRANCH" "$REPO_CARPETA" >&2
  while [[ -z "$usuario" ]]; do
    usuario="$(preguntar 'Usuario de GitHub: ')"
    usuario="${usuario//[[:space:]]/}"
  done
  while [[ -z "$token" ]]; do
    read -rsp 'Token de GitHub (no se muestra ni se guarda): ' token </dev/tty || return 1
    printf '\n' >&2
  done

  tmp="$(nuevo_temporal)"; repo="$tmp/repo"
  cat > "$tmp/askpass" <<'EOF'
#!/bin/sh
case "$1" in
  Username*) printf '%s\n' "$SESHAT_GIT_USUARIO" ;;
  *)         printf '%s\n' "$SESHAT_GIT_TOKEN" ;;
esac
EOF
  chmod 700 "$tmp/askpass"
  # Todas las llamadas a git de esta descarga usan el mismo usuario y token.
  git_github(){ GIT_ASKPASS="$tmp/askpass" GIT_TERMINAL_PROMPT=0 SESHAT_GIT_USUARIO="$usuario" SESHAT_GIT_TOKEN="$token" git "$@"; }

  info "Descargando $REPO_CARPETA desde GitHub..."
  # --sparse + sparse-checkout: se baja solo la carpeta de Inventario, no todo el repositorio.
  if ! git_github clone --quiet --depth 1 --filter=blob:none --sparse --branch "$REPO_BRANCH" "$REPO_URL" "$repo" >&2 \
     || ! git_github -C "$repo" sparse-checkout set "$REPO_CARPETA" >&2; then
    rm -f "$tmp/askpass"; token=''
    fail 'No se pudo descargar desde GitHub. Revisa:'
    fail '  - el usuario y el token (que no esté vencido),'
    fail "  - que el token tenga acceso a ${REPO_URL%.git} con permiso de lectura de contenido (Contents: Read, o «repo» en un token clásico)."
    return 1
  fi
  rm -f "$tmp/askpass"; token=''

  origen="$repo/$REPO_CARPETA"
  [[ -d "$origen" ]] || { fail "El repositorio no tiene la carpeta $REPO_CARPETA."; return 1; }
  mapfile -t zips < <(find "$origen" -type f -name 'Seshat_Inventario_v*.zip' 2>/dev/null)
  if ((${#zips[@]})); then
    zip="$(elegir_zip "${zips[@]}")" || return 1
    info "Paquete: ${zip#"$repo"/}"
    codigo="$(extraer_zip "$zip")" || return 1
    printf '%s\t%s' "$codigo" "GitHub $(basename "$zip")"
  else
    codigo="$(buscar_codigo "$origen")"
    [[ -n "$codigo" ]] || { fail "En $REPO_CARPETA no hay un Seshat_Inventario_v*.zip ni el código (main.py + index.html)."; return 1; }
    info "Código: ${codigo#"$repo"/}"
    printf '%s\t%s' "$codigo" "GitHub ${REPO_URL%.git}/$REPO_CARPETA"
  fi
}

# --- Servicio ---------------------------------------------------------------------
escribir_servicio(){
  local puerto="$1"
  cat > "$UNIDAD" <<EOF
[Unit]
Description=Seshat Inventario
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USUARIO
Group=$USUARIO
WorkingDirectory=$APP_DIR
EnvironmentFile=-$INSTALL_ROOT/seshat.env
ExecStart=$VENV/bin/python -m uvicorn main:app --host 0.0.0.0 --port $puerto
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF
  printf 'PUERTO=%s\n' "$puerto" > "$CONFIG"
  systemctl daemon-reload
}

# Herramientas de «Equipos en red» (se ejecuta al instalar Y al actualizar):
#  - ping sin ser root: el servicio corre como usuario sin privilegios, y Debian por defecto
#    solo deja hacer ping a root. net.ipv4.ping_group_range permite el ping por socket ICMP
#    de datagramas a todos los grupos (el escaneo de la red lo usa para ver quién está en línea).
#  - ieee-data: lista de fabricantes por MAC (la «Marca» de los equipos encontrados).
#  - iproute2 / iputils-ping: «ip neigh» (tabla ARP para la MAC) y «ping».
configurar_red(){
  local f=/etc/sysctl.d/99-seshat-ping.conf
  printf '# Seshat Inventario: permite el ping sin privilegios (escaneo de la red)\nnet.ipv4.ping_group_range = 0 2147483647\n' > "$f"
  sysctl -q -p "$f" >/dev/null 2>&1 || sysctl -q -w net.ipv4.ping_group_range="0 2147483647" >/dev/null 2>&1 \
    || aviso 'No se pudo activar el ping sin privilegios; el escaneo usará los puertos y la tabla ARP.'
  local falta=() p
  for p in ieee-data iputils-ping iproute2; do dpkg -s "$p" >/dev/null 2>&1 || falta+=("$p"); done
  if (( ${#falta[@]} )); then
    info "Instalando herramientas de red: ${falta[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${falta[@]}" >/dev/null 2>&1 \
      || aviso "No se pudo instalar ${falta[*]} (¿hay internet?). El escaneo funciona igual, pero sin marca o sin ping."
  fi
}

esperar_servicio(){
  local puerto="$1" i
  for i in $(seq 1 40); do
    curl -fs -o /dev/null --max-time 2 "http://127.0.0.1:$puerto/" && return 0
    systemctl is-failed --quiet "$SERVICIO" && return 1
    sleep 1
  done
  return 1
}

arrancar_y_verificar(){
  local puerto="$1"
  systemctl enable "$SERVICIO" >/dev/null 2>&1
  systemctl restart "$SERVICIO"
  info 'Iniciando Seshat Inventario...'
  if esperar_servicio "$puerto"; then ok 'Seshat Inventario está funcionando.'; return 0; fi
  fail 'Seshat Inventario no arrancó. Últimas líneas del registro:'
  journalctl -u "$SERVICIO" -n 20 --no-pager 2>/dev/null | sed 's/^/    /' >&2
  return 1
}

instalar_librerias(){
  if [[ ! -x "$VENV/bin/python" ]]; then
    info 'Creando el entorno de Python...'
    python3 -m venv "$VENV" || { fail 'No se pudo crear el entorno (falta python3-venv: opción 1).'; return 1; }
  fi
  info 'Instalando librerías de requirements.txt (puede tardar unos minutos)...'
  "$VENV/bin/python" -m pip install --disable-pip-version-check --quiet -r "$APP_DIR/requirements.txt" >&2 \
    || { fail 'No se pudieron instalar las librerías (¿hay internet?).'; return 1; }
}

preparar_usuario_y_carpetas(){
  id "$USUARIO" >/dev/null 2>&1 || useradd --system --home-dir "$INSTALL_ROOT" --no-create-home --shell /usr/sbin/nologin "$USUARIO"
  mkdir -p "$APP_DIR" "$RESPALDOS"
  chmod 700 "$RESPALDOS"
  # Respaldo automático que hace la página antes de importar una migración (módulo Migración).
  mkdir -p "$INSTALL_ROOT/respaldos_migracion"
  chown "$USUARIO:$USUARIO" "$INSTALL_ROOT/respaldos_migracion"
  chmod 700 "$INSTALL_ROOT/respaldos_migracion"
}

permisos_app(){ chown -R "$USUARIO:$USUARIO" "$APP_DIR"; chmod 750 "$APP_DIR"; }

mostrar_acceso(){
  local puerto="$1" ip
  printf '\nAbre Seshat Inventario en:\n  http://localhost:%s/\n' "$puerto"
  for ip in $(hostname -I 2>/dev/null); do [[ "$ip" == *:* ]] || printf '  http://%s:%s/\n' "$ip" "$puerto"; done
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    aviso "El firewall (ufw) está activo. Para entrar desde otros equipos:  ufw allow $puerto/tcp"
  fi
}

# --- Respaldos (.tar.gz con código + base de datos + puerto) --------------------------
copiar_base(){  # copia consistente aunque el programa la esté usando
  [[ -f "$1" ]] || return 0
  python3 - "$1" "$2" <<'EOF'
import sqlite3, sys
origen = sqlite3.connect(sys.argv[1]); destino = sqlite3.connect(sys.argv[2])
origen.backup(destino); destino.close(); origen.close()
EOF
}

# crear_respaldo MOTIVO [CARPETA]  -> imprime la ruta del .tar.gz
crear_respaldo(){
  local motivo="$1" carpeta="${2:-$RESPALDOS}" tmp archivo
  instalado || { fail 'Seshat Inventario no está instalado: no hay nada que respaldar.'; return 1; }
  mkdir -p "$carpeta" || { fail "No se pudo crear $carpeta"; return 1; }
  tmp="$(nuevo_temporal)"
  mkdir -p "$tmp/seshat-inventario/app"
  rsync -a "${EXCLUIR[@]}" "$APP_DIR/" "$tmp/seshat-inventario/app/" || { fail 'No se pudo copiar el código.'; return 1; }
  if [[ "$(motor_debian)" == mysql ]]; then
    seshat_db volcar "$tmp/seshat-inventario/app/volcado_mysql.json.gz" >&2       || { fail 'No se pudo copiar la base de datos de MariaDB (¿responde el servidor?).'; return 1; }
  else
    copiar_base "$APP_DIR/$BASE" "$tmp/seshat-inventario/app/$BASE" || { fail 'No se pudo copiar la base de datos.'; return 1; }
  fi
  printf 'PUERTO=%s\n' "$(leer_puerto)" > "$tmp/seshat-inventario/seshat.conf"
  printf 'Fecha: %s\nMotivo: %s\nEquipo: %s\n' "$(date '+%F %T')" "$motivo" "$(hostname)" > "$tmp/seshat-inventario/info.txt"
  archivo="$carpeta/seshat-inventario_${motivo}_$(date +%Y-%m-%d_%H%M%S).tar.gz"
  tar -czf "$archivo" -C "$tmp" seshat-inventario || { fail 'No se pudo crear el respaldo.'; rm -f "$archivo"; return 1; }
  chmod 600 "$archivo"
  printf '%s' "$archivo"
}

# Extrae un respaldo de forma segura; imprime la carpeta seshat-inventario extraída.
extraer_respaldo(){
  local archivo="$1" lista tmp
  lista="$(tar -tzf "$archivo" 2>/dev/null)" || { fail "$(basename "$archivo") no es un respaldo válido."; return 1; }
  if rutas_peligrosas "$lista"; then fail "$(basename "$archivo") contiene rutas peligrosas; no se usa."; return 1; fi
  grep -qx 'seshat-inventario/app/main.py' <<< "$lista" || { fail "$(basename "$archivo") no es un respaldo de Seshat Inventario."; return 1; }
  tmp="$(nuevo_temporal)"
  tar -xzf "$archivo" -C "$tmp" --no-same-owner || { fail 'No se pudo extraer el respaldo.'; return 1; }
  printf '%s' "$tmp/seshat-inventario"
}

# Deja la instalación exactamente como el respaldo (código y base de datos).
aplicar_respaldo(){
  local carpeta="$1"
  rsync -a --delete "${EXCLUIR[@]}" "$carpeta/app/" "$APP_DIR/" || return 1
  rm -f "$APP_DIR/$BASE-wal" "$APP_DIR/$BASE-shm" "$APP_DIR/$BASE-journal"
  local volcado="$APP_DIR/volcado_mysql.json.gz"
  if [[ "$(motor_debian)" == mysql ]]; then
    # MariaDB: se recargan las tablas desde el volcado (o desde el .db si el respaldo es de SQLite).
    if [[ -f "$volcado" ]]; then seshat_db cargar "$volcado" >&2 || { fail 'No se pudo restaurar la base en MariaDB.'; rm -f "$volcado"; return 1; }
    elif [[ -f "$carpeta/app/$BASE" ]]; then seshat_db desde-sqlite "$carpeta/app/$BASE" >&2 || { fail 'No se pudo copiar la base a MariaDB.'; return 1; }
    fi
  else
    [[ -f "$volcado" ]] && aviso 'El respaldo es de MariaDB y esta instalación usa SQLite: se restaura solo el código.'
    if [[ -f "$carpeta/app/$BASE" ]]; then cp -f "$carpeta/app/$BASE" "$APP_DIR/$BASE"; else rm -f "$APP_DIR/$BASE"; fi
  fi
  rm -f "$volcado"
  permisos_app
}

# Si una actualización falla, vuelve sola al respaldo recién hecho.
revertir_automatico(){
  local archivo="$1" puerto="$2" carpeta
  [[ -n "$archivo" && -f "$archivo" ]] || return 0
  aviso 'Volviendo automáticamente a la versión anterior...'
  systemctl stop "$SERVICIO" 2>/dev/null || true
  carpeta="$(extraer_respaldo "$archivo")" || { fail "Restaura a mano con la opción 13: $archivo"; return 1; }
  aplicar_respaldo "$carpeta"
  "$VENV/bin/python" -m pip install --disable-pip-version-check --quiet -r "$APP_DIR/requirements.txt" >/dev/null 2>&1 || true
  if arrancar_y_verificar "$puerto"; then ok 'Se volvió a la versión anterior y está funcionando.'
  else fail "Tampoco arrancó la versión anterior. Revisa la opción 10 (registros)."; fi
}

# --- Instalar / actualizar ------------------------------------------------------------
# instalar_o_actualizar MODO(instalar|actualizar) ORIGEN(carpeta|github)
instalar_o_actualizar(){
  local modo="$1" fuente="$2" linea origen descripcion puerto respaldo='' salida
  if [[ "$modo" == instalar ]] && instalado; then
    aviso "Seshat Inventario ya está instalado en $INSTALL_ROOT. Usa «Actualizar» (opciones 4 y 5)."; return 1
  fi
  if [[ "$modo" == actualizar ]] && ! instalado; then
    aviso 'Seshat Inventario no está instalado todavía. Usa «Instalar» (opciones 2 y 3).'; return 1
  fi
  if [[ "$fuente" == github ]]; then faltan_dependencias git && return 1; else faltan_dependencias && return 1; fi

  if [[ "$fuente" == github ]]; then linea="$(codigo_desde_github)" || return 1
  else linea="$(codigo_desde_carpeta)" || return 1; fi
  origen="${linea%%$'\t'*}"; descripcion="${linea#*$'\t'}"
  [[ -f "$origen/main.py" && -f "$origen/index.html" && -f "$origen/requirements.txt" ]] \
    || { fail 'El origen no tiene main.py, index.html y requirements.txt.'; return 1; }

  printf '\n' >&2
  if [[ "$modo" == instalar ]]; then
    info "Instalación NUEVA en $INSTALL_ROOT desde: $descripcion"
    puerto="$(preguntar "Puerto para Seshat Inventario [$PUERTO_DEFECTO]: ")"; puerto="${puerto:-$PUERTO_DEFECTO}"
    puerto_valido "$puerto" || { fail 'Puerto no válido.'; return 1; }
    if puerto_ocupado "$puerto"; then fail "El puerto $puerto ya está en uso por otro programa."; return 1; fi
    elegir_motor_docker sin-contenedor
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
  rsync -a "${EXCLUIR[@]}" "$origen/" "$APP_DIR/" || { fail 'No se pudo copiar el código.'; revertir_automatico "$respaldo" "$puerto"; return 1; }
  permisos_app
  instalar_librerias || { revertir_automatico "$respaldo" "$puerto"; return 1; }
  if [[ "$modo" == instalar ]]; then
    guardar_motor "$INSTALL_ROOT/seshat.env"
    if [[ "$MOTOR_ELEGIDO" != sqlite ]]; then
      info 'Probando la conexión a MariaDB/MySQL...'
      if salida="$(seshat_db probar 2>&1)"; then ok "$salida"
      else
        fail "No se pudo conectar a MariaDB/MySQL: $(tail -n1 <<< "$salida")"
        aviso 'Seshat se instala con SQLite para que funcione. Cuando el servidor esté listo, usa el menú «Base de datos».'
        escribir_env "$INSTALL_ROOT/seshat.env" SESHAT_DB_MOTOR sqlite
      fi
    fi
  fi
  escribir_servicio "$puerto"
  configurar_red
  arrancar_y_verificar "$puerto" || { revertir_automatico "$respaldo" "$puerto"; return 1; }
  mostrar_acceso "$puerto"
  if [[ "$modo" == instalar ]]; then
    aviso 'Abre la dirección de arriba: aparecerá la «Configuración inicial» para crear la cuenta administradora.'
    aviso 'Hazlo de inmediato: mientras no exista esa cuenta, cualquiera que abra la página podría crearla.'
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

ver_estado(){
  deb_resumen_estado
  instalado || return 0
  local puerto http n
  puerto="$(leer_puerto)"
  http="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:$puerto/" 2>/dev/null)"
  printf '\nCarpeta:          %s\n' "$INSTALL_ROOT"
  printf 'Respuesta web:    %s\n' "$([[ "$http" == 200 ]] && echo "OK (HTTP 200)" || echo "sin respuesta (HTTP ${http:-000})")"
  printf 'Arranque con el equipo: %s\n' "$(systemctl is-enabled "$SERVICIO" 2>/dev/null || echo no)"
  [[ -f "$APP_DIR/$BASE" ]] && printf 'Base de datos:    %s (%s)\n' "$APP_DIR/$BASE" "$(du -h "$APP_DIR/$BASE" | cut -f1)"
  printf 'Python:           %s\n' "$("$VENV/bin/python" --version 2>&1)"
  n="$(find "$RESPALDOS" -maxdepth 1 -name 'seshat-inventario_*.tar.gz' 2>/dev/null | wc -l)"
  printf 'Respaldos:        %s en %s\n' "$n" "$RESPALDOS"
  mostrar_acceso "$puerto"
}

servicio(){
  local accion="$1"
  instalado || { aviso 'Seshat Inventario no está instalado.'; return 1; }
  case "$accion" in
    start)   systemctl enable "$SERVICIO" >/dev/null 2>&1; arrancar_y_verificar "$(leer_puerto)" ;;
    restart) arrancar_y_verificar "$(leer_puerto)" ;;
    stop)    systemctl stop "$SERVICIO" && ok 'Seshat Inventario detenido.' ;;
  esac
}

ver_registros(){
  instalado || { aviso 'Seshat Inventario no está instalado.'; return 1; }
  journalctl -u "$SERVICIO" -n 60 --no-pager
}

cambiar_puerto(){
  instalado || { aviso 'Seshat Inventario no está instalado.'; return 1; }
  local actual nuevo; actual="$(leer_puerto)"
  nuevo="$(preguntar "Puerto nuevo (actual $actual): ")"
  [[ -n "$nuevo" && "$nuevo" != "$actual" ]] || { aviso 'Sin cambios.'; return 0; }
  puerto_valido "$nuevo" || { fail 'Puerto no válido.'; return 1; }
  if puerto_ocupado "$nuevo"; then fail "El puerto $nuevo ya está en uso."; return 1; fi
  escribir_servicio "$nuevo"
  if arrancar_y_verificar "$nuevo"; then mostrar_acceso "$nuevo"
  else aviso "Volviendo al puerto $actual..."; escribir_servicio "$actual"; arrancar_y_verificar "$actual"; fi
}

# --- Respaldo manual / restaurar / desinstalar ---------------------------------------------
respaldo_manual(){
  instalado || { aviso 'Seshat Inventario no está instalado.'; return 1; }
  local carpeta archivo
  carpeta="$(preguntar "Carpeta donde guardar el respaldo [$RESPALDOS]: ")"; carpeta="${carpeta:-$RESPALDOS}"
  archivo="$(crear_respaldo manual "$carpeta")" || return 1
  ok "Respaldo creado: $archivo ($(du -h "$archivo" | cut -f1))"
  printf '\nIncluye el código, la base de datos (inventario y usuarios) y el puerto.\n'
  printf 'Para reinstalar en otro equipo: copia este .tar.gz y este instalador, usa la\n'
  printf 'opción 1 y luego la 13. Guárdalo en un lugar seguro: contiene datos del colegio.\n'
}

restaurar_respaldo(){
  faltan_dependencias && return 1
  local lista=() archivo carpeta puerto actual='' p
  mapfile -t lista < <(find "$RESPALDOS" "$SCRIPT_DIR" -maxdepth 1 -type f -name 'seshat-inventario_*.tar.gz' -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2-)
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
    p="$(sed -n 's/^PUERTO=\([0-9]\+\)$/\1/p' "$carpeta/seshat.conf" 2>/dev/null | head -n1)"
    puerto="$(preguntar "Reinstalación desde el respaldo. Puerto [${p:-$PUERTO_DEFECTO}]: ")"; puerto="${puerto:-${p:-$PUERTO_DEFECTO}}"
    puerto_valido "$puerto" || { fail 'Puerto no válido.'; return 1; }
    if puerto_ocupado "$puerto"; then fail "El puerto $puerto ya está en uso por otro programa."; return 1; fi
    confirmar '¿Continuar?' || { aviso 'Cancelado.'; return 1; }
  fi

  preparar_usuario_y_carpetas
  aplicar_respaldo "$carpeta" || { fail 'No se pudo copiar el respaldo.'; revertir_automatico "$actual" "$puerto"; return 1; }
  instalar_librerias || { revertir_automatico "$actual" "$puerto"; return 1; }
  escribir_servicio "$puerto"
  configurar_red
  arrancar_y_verificar "$puerto" || { revertir_automatico "$actual" "$puerto"; return 1; }
  ok "Restaurado desde $(basename "$archivo")."
  mostrar_acceso "$puerto"
}

desinstalar(){
  instalado || [[ -f "$UNIDAD" ]] || { aviso 'Seshat Inventario no está instalado.'; return 1; }
  local final=''
  aviso "Se eliminará Seshat Inventario: servicio, $INSTALL_ROOT (código y base de datos) y el usuario $USUARIO."
  if instalado && confirmar '¿Guardar antes un respaldo final? (recomendado)'; then
    final="$(crear_respaldo antes-de-desinstalar)" || { fail 'No se pudo crear el respaldo final. No se eliminó nada.'; return 1; }
    ok "Respaldo final: $final"
  fi
  [[ "$(preguntar 'Escribe ELIMINAR SESHAT para continuar: ')" == 'ELIMINAR SESHAT' ]] || { aviso 'Cancelado.'; return 1; }
  systemctl disable --now "$SERVICIO" >/dev/null 2>&1 || true
  rm -f "$UNIDAD"; systemctl daemon-reload
  rm -rf -- "$INSTALL_ROOT"
  id "$USUARIO" >/dev/null 2>&1 && userdel "$USUARIO" >/dev/null 2>&1
  ok 'Seshat Inventario desinstalado.'
  if [[ -d "$RESPALDOS" ]]; then
    printf 'Los respaldos se conservan en %s (sirven para reinstalar con la opción 13).\n' "$RESPALDOS"
    if confirmar '¿Borrar también TODOS los respaldos? (no se puede deshacer)'; then
      rm -rf -- "$RESPALDOS"; ok 'Respaldos eliminados.'
    fi
  fi
}

# --- Configuración compartida (seshat.env) --------------------------------------------
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

# Motor en uso de la instalación de Debian (sqlite | mysql) y utilidad de base de datos de la app.
motor_debian(){ leer_env "$INSTALL_ROOT/seshat.env" SESHAT_DB_MOTOR sqlite; }
# seshat_db ORDEN [ARCHIVO]: ejecuta seshat_db.py de la app con el seshat.env de la instalación.
seshat_db(){ ( cd "$APP_DIR" && "$VENV/bin/python" -B seshat_db.py --env "$INSTALL_ROOT/seshat.env" "$@" ); }

# Archivos seshat.env de las instalaciones que existan (la configuración se aplica a todas).
archivos_env(){
  [[ -d "$ROOT_DEBIAN" ]] && printf '%s\n' "$ROOT_DEBIAN/seshat.env"
  [[ -d "$ROOT_DOCKER" ]] && printf '%s\n' "$ROOT_DOCKER/seshat.env"
  return 0
}

# --- Estado ----------------------------------------------------------------------------
docker_instalado(){ [[ -f "$ROOT_DOCKER/docker-compose.yml" ]]; }

dc(){   # docker compose (plugin) o docker-compose (clásico)
  if docker compose version >/dev/null 2>&1; then docker compose "$@"
  else docker-compose "$@"; fi
}
docker_disponible(){ command -v docker >/dev/null 2>&1 && { docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; }; }

resumen_general(){
  local motor n=0
  motor="$(leer_env "$ROOT_DEBIAN/seshat.env" SESHAT_DB_MOTOR "$(leer_env "$ROOT_DOCKER/seshat.env" SESHAT_DB_MOTOR sqlite)")"
  if instalado; then
    printf '%sNormal (Debian):%s instalado, servicio %s, puerto %s\n' "$C_GRIS" "$C_FIN" "$(systemctl is-active "$SERVICIO" 2>/dev/null || echo detenido)" "$(leer_puerto)"
  else printf '%sNormal (Debian):%s no instalado\n' "$C_GRIS" "$C_FIN"; fi
  if docker_instalado; then
    docker_disponible && n="$(cd "$ROOT_DOCKER" && dc ps -q 2>/dev/null | wc -l)"
    printf '%sDocker:%s instalado, contenedores activos: %s, puerto %s\n' "$C_GRIS" "$C_FIN" "$n" "$(leer_env "$ROOT_DOCKER/seshat.env" PUERTO "$PUERTO_DEFECTO")"
  else printf '%sDocker:%s no instalado\n' "$C_GRIS" "$C_FIN"; fi
  printf '%sBase de datos configurada:%s %s\n' "$C_GRIS" "$C_FIN" "$motor"
}

# El código se obtiene con las mismas funciones que la instalación normal
# (carpeta, .zip o GitHub); imprime la carpeta con main.py + index.html.
obtener_codigo(){
  local fuente linea
  printf '1) Desde una carpeta o .zip\n2) Desde GitHub (pide usuario y token)\n' >&2
  fuente="$(preguntar 'Origen del código [1]: ')"; fuente="${fuente:-1}"
  if [[ "$fuente" == 2 ]]; then
    command -v git >/dev/null 2>&1 || { fail 'Falta git (apt-get install git).'; return 1; }
    linea="$(codigo_desde_github)" || return 1
  else
    linea="$(codigo_desde_carpeta)" || return 1
  fi
  printf '%s' "${linea%%$'\t'*}"
}

# --- Instalación con Docker ---------------------------------------------------------------
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
  info '[2/4] Instalando Docker y herramientas (docker.io, apparmor, rsync, curl, ca-certificates, git)...'
  if ! paso_apt -y install docker.io apparmor rsync curl ca-certificates git; then
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
  mkdir -p "$(dirname "$destino")" && install -m 0755 "$tmp" "$destino" || { fail 'No se pudo instalar el plugin.'; return 1; }
  ok 'Plugin de compose instalado y verificado.'
}

# crear_base_mariadb HOST PUERTO BASE USUARIO CLAVE
# Crea la base y el usuario de Seshat en un servidor MariaDB/MySQL, pidiendo el usuario
# administrador (root) y su contraseña; no se guardan. Se puede repetir sin problema: si el
# usuario ya existe, solo se le fija la contraseña y los permisos.
crear_base_mariadb(){
  local host="$1" puerto="$2" base="$3" usuario="$4" clave="$5" cli admin clave_admin conexion origenes o sql version salida
  if [[ ! "$base" =~ ^[A-Za-z0-9_]+$ || ! "$usuario" =~ ^[A-Za-z0-9_]+$ ]]; then
    fail 'Para crearlos desde aquí, la base y el usuario solo pueden llevar letras, números y «_».'; return 1
  fi
  if [[ "$clave" == *\'* || "$clave" == *\\* ]]; then
    fail 'La contraseña de Seshat no puede llevar comilla simple ni barra invertida para crearla desde aquí.'; return 1
  fi
  cli="$(command -v mariadb || command -v mysql || true)"
  if [[ -z "$cli" ]]; then
    confirmar 'Falta el cliente de MariaDB. ¿Instalarlo (mariadb-client)?' || return 1
    DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-client </dev/null >&2 || { fail 'No se pudo instalar mariadb-client.'; return 1; }
    cli="$(command -v mariadb || command -v mysql || true)"; [[ -n "$cli" ]] || { fail 'No quedó el cliente de MariaDB.'; return 1; }
  fi
  admin="$(preguntar 'Usuario administrador de MariaDB [root]: ')"; admin="${admin:-root}"
  read -rsp "Contraseña de $admin (Enter si entra sin contraseña): " clave_admin </dev/tty; printf '\n' >&2
  # En el mismo equipo se usa el socket local (sirve con o sin contraseña); si no, red.
  if [[ "$host" == 127.0.0.1 || "$host" == localhost ]]; then
    conexion=(-h localhost -u "$admin"); origenes=(localhost 127.0.0.1)
  else
    conexion=(-h "$host" -P "$puerto" -u "$admin"); origenes=('%')
  fi
  version="$(MYSQL_PWD="$clave_admin" "$cli" "${conexion[@]}" -N -e 'SELECT VERSION()' 2>&1)" \
    || { fail "No se pudo entrar como $admin: $(tail -n1 <<< "$version")"; return 1; }
  sql="CREATE DATABASE IF NOT EXISTS \`$base\` CHARACTER SET utf8mb4;"
  for o in "${origenes[@]}"; do
    sql+=" CREATE USER IF NOT EXISTS '$usuario'@'$o' IDENTIFIED BY '$clave';"
    if grep -qi mariadb <<< "$version"; then   # reemplaza también el acceso por socket del sistema (error 1698)
      sql+=" ALTER USER '$usuario'@'$o' IDENTIFIED VIA mysql_native_password USING PASSWORD('$clave');"
    else
      sql+=" ALTER USER '$usuario'@'$o' IDENTIFIED BY '$clave';"
    fi
    sql+=" GRANT ALL ON \`$base\`.* TO '$usuario'@'$o';"
  done
  sql+=" FLUSH PRIVILEGES;"
  if salida="$(printf '%s' "$sql" | MYSQL_PWD="$clave_admin" "$cli" "${conexion[@]}" 2>&1)"; then
    ok "Base «$base» y usuario «$usuario» listos en $host."
  else
    fail "No se pudieron crear: $(tail -n1 <<< "$salida")"; return 1
  fi
}

# Pregunta qué base de datos usar y deja la elección en variables globales (MOTOR_ELEGIDO,
# MARIADB_*). Con MariaDB/MySQL la aplicación usa SESHAT_DB_MOTOR=mysql y los datos de
# conexión de seshat.env (se crea el contenedor si se pide).
MOTOR_ELEGIDO=sqlite
MARIADB_HOST=''; MARIADB_PORT=3306; MARIADB_NOMBRE=''; MARIADB_USUARIO=''; MARIADB_CLAVE=''; MARIADB_ROOT_CLAVE=''
# Con el argumento «sin-contenedor» (instalación normal) no se ofrece la opción 3.
elegir_motor_docker(){
  local op
  MOTOR_ELEGIDO=sqlite
  printf '\nBase de datos:\n' >&2
  printf '  1) SQLite (recomendado: archivo local, no hay que configurar nada)\n' >&2
  printf '  2) MariaDB / MySQL que ya existe (servidor aparte)\n' >&2
  [[ "${1:-}" == sin-contenedor ]] || printf '  3) MariaDB nueva en un contenedor (se crea junto a Seshat)\n' >&2
  op="$(preguntar 'Opción [1]: ')"; op="${op:-1}"
  [[ "${1:-}" == sin-contenedor && "$op" == 3 ]] && op=1
  case "$op" in
    2)
      MOTOR_ELEGIDO=mariadb-externo
      MARIADB_HOST="$(preguntar 'Servidor [127.0.0.1]: ')"; MARIADB_HOST="${MARIADB_HOST:-127.0.0.1}"
      MARIADB_PORT="$(preguntar 'Puerto [3306]: ')"; MARIADB_PORT="${MARIADB_PORT:-3306}"
      MARIADB_NOMBRE="$(preguntar 'Nombre de la base [seshat_inventario]: ')"; MARIADB_NOMBRE="${MARIADB_NOMBRE:-seshat_inventario}"
      MARIADB_USUARIO="$(preguntar 'Usuario [seshat]: ')"; MARIADB_USUARIO="${MARIADB_USUARIO:-seshat}"
      read -rsp 'Contraseña (no se muestra): ' MARIADB_CLAVE </dev/tty; printf '\n' >&2
      [[ -n "$MARIADB_CLAVE" ]] || aviso 'La contraseña quedó VACÍA: la conexión se intentará sin contraseña.' ;;
    3)
      MOTOR_ELEGIDO=mariadb-contenedor
      MARIADB_HOST=127.0.0.1; MARIADB_PORT=3306; MARIADB_NOMBRE=seshat_inventario; MARIADB_USUARIO=seshat
      MARIADB_CLAVE="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
      MARIADB_ROOT_CLAVE="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)" ;;
    *) MOTOR_ELEGIDO=sqlite ;;
  esac
  if [[ "$MOTOR_ELEGIDO" == mariadb-externo ]]; then
    if confirmar "¿Crear ahora la base «$MARIADB_NOMBRE» y el usuario «$MARIADB_USUARIO»? (pide la contraseña de administrador de MariaDB)"; then
      crear_base_mariadb "$MARIADB_HOST" "$MARIADB_PORT" "$MARIADB_NOMBRE" "$MARIADB_USUARIO" "$MARIADB_CLAVE" \
        || aviso 'No se crearon. Deben existir en el servidor antes de usar MariaDB (Seshat crea las tablas).'
    else
      aviso "La base «$MARIADB_NOMBRE» y el usuario «$MARIADB_USUARIO» deben existir en el servidor (Seshat crea las tablas)."
    fi
  fi
}

escribir_archivos_docker(){   # escribir_archivos_docker PUERTO
  local puerto="$1"
  cat > "$ROOT_DOCKER/Dockerfile" <<'EOF'
FROM python:3.12-slim
# ping, tabla ARP y lista de fabricantes (escaneo de la red)
RUN apt-get update && apt-get install -y --no-install-recommends iputils-ping iproute2 ieee-data \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ .
ENV SESHAT_DB=/datos/inventario_colegio.db
CMD ["sh", "-c", "exec python -m uvicorn main:app --host 0.0.0.0 --port ${PUERTO:-8000}"]
EOF
  cat > "$ROOT_DOCKER/docker-compose.yml" <<'EOF'
# Seshat Inventario con Docker. La base de datos queda en ./datos (se respalda copiando esa carpeta).
# network_mode: host => el contenedor ve la red del equipo (necesario para escanear la red,
# leer MAC y enviar el paquete mágico). El puerto se cambia en seshat.env (PUERTO).
services:
  seshat:
    build: .
    container_name: seshat-inventario
    restart: unless-stopped
    network_mode: host
    env_file: seshat.env
    volumes:
      - ./datos:/datos
EOF
  # MariaDB en contenedor (solo si se eligió al instalar): datos en ./datos_mariadb, accesible
  # únicamente desde este equipo (127.0.0.1:3306). Las claves están en seshat.env.
  if [[ "$(leer_env "$ROOT_DOCKER/seshat.env" SESHAT_DB_MOTOR_PREFERIDO)" == mariadb-contenedor ]]; then
    cat >> "$ROOT_DOCKER/docker-compose.yml" <<'EOF'
  mariadb:
    image: mariadb:11
    container_name: seshat-mariadb
    restart: unless-stopped
    env_file: seshat.env
    ports:
      - "127.0.0.1:3306:3306"
    volumes:
      - ./datos_mariadb:/var/lib/mysql
EOF
  fi
  printf '%s\n' '*.pyc' '__pycache__/' '.venv/' 'venv/' '*.db' '*.db-wal' '*.db-shm' > "$ROOT_DOCKER/.dockerignore"
  escribir_env "$ROOT_DOCKER/seshat.env" PUERTO "$puerto"
  # Motor en uso: lo fijó guardar_motor_docker; si aún no hay ninguno, SQLite.
  [[ -n "$(leer_env "$ROOT_DOCKER/seshat.env" SESHAT_DB_MOTOR)" ]] || escribir_env "$ROOT_DOCKER/seshat.env" SESHAT_DB_MOTOR sqlite
}

# Guarda en seshat.env la base elegida (se llama antes de escribir_archivos_docker).
guardar_motor_docker(){ guardar_motor "$ROOT_DOCKER/seshat.env"; }

# guardar_motor ARCHIVO_ENV: guarda la base elegida (MOTOR_ELEGIDO, MARIADB_*) en ese seshat.env.
guardar_motor(){
  local f="$1"
  escribir_env "$f" SESHAT_DB_MOTOR_PREFERIDO "$MOTOR_ELEGIDO"
  # Motor en uso: mysql si se eligió MariaDB/MySQL (externo o contenedor); si no, sqlite.
  if [[ "$MOTOR_ELEGIDO" == sqlite ]]; then escribir_env "$f" SESHAT_DB_MOTOR sqlite
  else escribir_env "$f" SESHAT_DB_MOTOR mysql; fi
  [[ "$MOTOR_ELEGIDO" == sqlite ]] && return 0
  escribir_env "$f" SESHAT_MARIADB_HOST "$MARIADB_HOST"; escribir_env "$f" SESHAT_MARIADB_PORT "$MARIADB_PORT"
  escribir_env "$f" SESHAT_MARIADB_NOMBRE "$MARIADB_NOMBRE"; escribir_env "$f" SESHAT_MARIADB_USUARIO "$MARIADB_USUARIO"
  escribir_env "$f" SESHAT_MARIADB_CLAVE "$MARIADB_CLAVE"
  if [[ "$MOTOR_ELEGIDO" == mariadb-contenedor ]]; then   # variables que lee la imagen de MariaDB
    escribir_env "$f" MARIADB_DATABASE "$MARIADB_NOMBRE"; escribir_env "$f" MARIADB_USER "$MARIADB_USUARIO"
    escribir_env "$f" MARIADB_PASSWORD "$MARIADB_CLAVE"; escribir_env "$f" MARIADB_ROOT_PASSWORD "$MARIADB_ROOT_CLAVE"
  fi
}

copiar_codigo_docker(){   # copiar_codigo_docker CARPETA
  mkdir -p "$ROOT_DOCKER/app" "$ROOT_DOCKER/datos"
  rsync -a --delete --exclude "$BASE" --exclude "$BASE-wal" --exclude "$BASE-shm" --exclude '__pycache__/' \
        --exclude '.venv/' --exclude 'venv/' --exclude '*.pyc' --exclude '.git/' "$1/" "$ROOT_DOCKER/app/"
}

esperar_docker(){   # esperar_docker PUERTO
  local i
  for i in $(seq 1 60); do
    curl -fs -o /dev/null --max-time 2 "http://127.0.0.1:$1/" && return 0
    sleep 1
  done
  return 1
}

docker_instalar_o_actualizar(){   # docker_instalar_o_actualizar instalar|actualizar
  local modo="$1" codigo puerto respaldo
  if [[ "$modo" == instalar ]] && docker_instalado; then aviso 'Docker ya está instalado. Usa «Actualizar».'; return 1; fi
  if [[ "$modo" == actualizar ]] && ! docker_instalado; then aviso 'Docker no está instalado todavía.'; return 1; fi
  if ! docker_disponible || ! docker info >/dev/null 2>&1 || ! command -v rsync >/dev/null 2>&1; then
    fail 'Faltan las dependencias de Docker. Primero usa la opción «Instalar dependencias (Docker)» del menú.'
    return 1
  fi
  codigo="$(obtener_codigo)" || return 1

  if [[ "$modo" == instalar ]]; then
    puerto="$(preguntar "Puerto [$PUERTO_DEFECTO]: ")"; puerto="${puerto:-$PUERTO_DEFECTO}"
    puerto_valido "$puerto" || { fail 'Puerto no válido.'; return 1; }
    if puerto_ocupado "$puerto"; then fail "El puerto $puerto ya está en uso."; return 1; fi
    elegir_motor_docker
    confirmar "Instalar en $ROOT_DOCKER con el código de $codigo (base: $MOTOR_ELEGIDO). ¿Continuar?" || return 1
    mkdir -p "$ROOT_DOCKER"
    guardar_motor_docker
  else
    puerto="$(leer_env "$ROOT_DOCKER/seshat.env" PUERTO "$PUERTO_DEFECTO")"
    confirmar "Actualizar (puerto $puerto) con el código de $codigo. La base de datos se conserva. ¿Continuar?" || return 1
    respaldo="$(docker_respaldo antes-actualizacion)" || { fail 'No se pudo respaldar. No se cambió nada.'; return 1; }
    ok "Respaldo: $respaldo"
    (cd "$ROOT_DOCKER" && dc down >/dev/null 2>&1)
  fi
  copiar_codigo_docker "$codigo" || { fail 'No se pudo copiar el código.'; return 1; }
  escribir_archivos_docker "$puerto"
  info 'Construyendo y levantando el contenedor (la primera vez tarda unos minutos)...'
  if (cd "$ROOT_DOCKER" && dc up -d --build) && esperar_docker "$puerto"; then
    ok "Seshat Inventario con Docker está funcionando: http://$(hostname -I 2>/dev/null | awk '{print $1}'):$puerto"
    [[ "$modo" == instalar ]] && aviso 'Abre esa dirección y crea de inmediato la cuenta administradora.'
  else
    fail 'No se pudo construir o arrancar el contenedor (el motivo está en las líneas de arriba).'
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx seshat-inventario; then
      info 'Últimas líneas del registro del contenedor:'; (cd "$ROOT_DOCKER" && dc logs --tail 20) >&2
    fi
    aviso 'Si ves «apparmor_parser not found», usa la opción «Instalar dependencias (Docker)» y reintenta.'
    aviso 'Si este equipo es un contenedor LXC (por ejemplo Proxmox/TurnKey), activa «nesting» en sus opciones.'
    return 1
  fi
}

docker_respaldo(){   # imprime la ruta del respaldo de ./datos y el código
  local destino="${1:-manual}" dir="${SESHAT_RESPALDOS_DOCKER:-/var/backups/seshat-inventario-docker}" archivo
  mkdir -p "$dir"
  archivo="$dir/seshat-docker_${destino}_$(date +%Y-%m-%d_%H%M%S).tar.gz"
  tar -czf "$archivo" -C "$ROOT_DOCKER" datos app seshat.env 2>/dev/null || return 1
  chmod 600 "$archivo"; printf '%s' "$archivo"
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
  local actual nuevo; actual="$(leer_env "$ROOT_DOCKER/seshat.env" PUERTO "$PUERTO_DEFECTO")"
  nuevo="$(preguntar "Puerto nuevo (actual $actual): ")"
  [[ -n "$nuevo" && "$nuevo" != "$actual" ]] || { aviso 'Sin cambios.'; return 0; }
  puerto_valido "$nuevo" || { fail 'Puerto no válido.'; return 1; }
  if puerto_ocupado "$nuevo"; then fail "El puerto $nuevo ya está en uso."; return 1; fi
  escribir_env "$ROOT_DOCKER/seshat.env" PUERTO "$nuevo"
  (cd "$ROOT_DOCKER" && dc up -d) && esperar_docker "$nuevo" && ok "Ahora en el puerto $nuevo." || fail 'No arrancó con el puerto nuevo.'
}

docker_desinstalar(){
  docker_instalado || { aviso 'Docker no está instalado.'; return 1; }
  aviso "Se eliminará el contenedor, la imagen y $ROOT_DOCKER (código Y base de datos)."
  if confirmar '¿Guardar antes un respaldo final? (recomendado)'; then
    local r; r="$(docker_respaldo antes-de-desinstalar)" || { fail 'No se pudo respaldar. No se eliminó nada.'; return 1; }
    ok "Respaldo final: $r"
  fi
  [[ "$(preguntar 'Escribe DESINSTALAR para continuar: ')" == DESINSTALAR ]] || { aviso 'Cancelado.'; return 1; }
  (cd "$ROOT_DOCKER" && dc down --rmi local >/dev/null 2>&1)
  rm -rf -- "$ROOT_DOCKER"; ok 'Docker desinstalado.'
}

# --- Base de datos: SQLite (defecto) o MariaDB ---------------------------------------------
aplicar_a_todos(){   # aplicar_a_todos CLAVE VALOR
  local f hecho=0
  while read -r f; do [[ -n "$f" ]] && { escribir_env "$f" "$1" "$2"; hecho=1; }; done < <(archivos_env)
  (( hecho )) || aviso 'No hay ninguna instalación todavía: la configuración se guardará cuando instales.'
}

menu_base_datos(){
  local opcion host puerto nombre usuario clave f respaldo salida
  f="$(archivos_env | head -n1)"
  printf '%sBase de datos actual: %s%s\n\n' "$C_CIAN" "$(leer_env "${f:-/nonexistent}" SESHAT_DB_MOTOR sqlite)" "$C_FIN"
  opcion_menu 1 'Usar SQLite (archivo local, sin configurar nada)'
  opcion_menu 2 'Configurar y probar la conexión a MariaDB / MySQL'
  opcion_menu 3 'Probar la conexión a MariaDB / MySQL guardada'
  opcion_menu 4 'Usar MariaDB / MySQL (copia los datos actuales de SQLite)'
  opcion_menu 0 'Volver'
  opcion="$(preguntar $'\nOpción: ')"
  case "$opcion" in
    1)
      aviso 'Lo que se haya guardado mientras se usaba MariaDB queda allí; SQLite conserva sus datos anteriores.'
      confirmar '¿Volver a SQLite?' || return 0
      aplicar_a_todos SESHAT_DB_MOTOR sqlite
      instalado && arrancar_y_verificar "$(leer_puerto)"
      ok 'Base de datos: SQLite.' ;;
    2)
      host="$(preguntar 'Servidor MariaDB [127.0.0.1]: ')"; host="${host:-127.0.0.1}"
      puerto="$(preguntar 'Puerto [3306]: ')"; puerto="${puerto:-3306}"
      nombre="$(preguntar 'Nombre de la base [seshat_inventario]: ')"; nombre="${nombre:-seshat_inventario}"
      usuario="$(preguntar 'Usuario [seshat]: ')"; usuario="${usuario:-seshat}"
      read -rsp 'Contraseña (no se muestra): ' clave </dev/tty; printf '\n'
      [[ -n "$clave" ]] || aviso 'La contraseña quedó VACÍA: la conexión se intentará sin contraseña.'
      aplicar_a_todos SESHAT_MARIADB_HOST "$host"; aplicar_a_todos SESHAT_MARIADB_PORT "$puerto"
      aplicar_a_todos SESHAT_MARIADB_NOMBRE "$nombre"; aplicar_a_todos SESHAT_MARIADB_USUARIO "$usuario"
      aplicar_a_todos SESHAT_MARIADB_CLAVE "$clave"
      ok 'Datos de MariaDB guardados (seshat.env, solo legible por root). Para usarla elige la opción 4.'
      if confirmar "¿Crear ahora la base «$nombre» y el usuario «$usuario» en el servidor? (pide la contraseña de administrador)"; then
        crear_base_mariadb "$host" "$puerto" "$nombre" "$usuario" "$clave" || true
      fi
      probar_mariadb "$host" "$puerto" ;;
    3)
      [[ -n "$f" ]] || { aviso 'No hay instalación.'; return 0; }
      host="$(leer_env "$f" SESHAT_MARIADB_HOST)"; puerto="$(leer_env "$f" SESHAT_MARIADB_PORT 3306)"
      [[ -n "$host" ]] || { aviso 'Todavía no configuraste MariaDB.'; return 0; }
      probar_mariadb "$host" "$puerto" ;;
    4)
      instalado || { aviso 'Instala Seshat Inventario (normal) antes de cambiar de base.'; return 0; }
      [[ -n "$(leer_env "$INSTALL_ROOT/seshat.env" SESHAT_MARIADB_HOST)" ]] \
        || { aviso 'Primero configura la conexión (opción 2).'; return 0; }
      [[ "$(motor_debian)" == mysql ]] && { aviso 'Ya se está usando MariaDB / MySQL.'; return 0; }
      info 'Probando la conexión...'
      if ! salida="$(SESHAT_DB_MOTOR=mysql seshat_db probar 2>&1)"; then
        fail "No se pudo conectar: $(tail -n1 <<< "$salida")"; return 0
      fi
      ok "$salida"
      aviso 'Se copiarán los datos de SQLite a MariaDB. Lo que MariaDB tenga en las tablas de Seshat se REEMPLAZA.'
      confirmar '¿Continuar?' || { aviso 'Cancelado.'; return 0; }
      respaldo="$(crear_respaldo antes-de-cambiar-base)" || { fail 'No se pudo respaldar. No se cambió nada.'; return 0; }
      ok "Respaldo: $respaldo"
      systemctl stop "$SERVICIO" 2>/dev/null || true
      if [[ -f "$APP_DIR/$BASE" ]]; then
        SESHAT_DB_MOTOR=mysql seshat_db desde-sqlite "$APP_DIR/$BASE" >&2 \
          || { fail 'No se pudieron copiar los datos. Se sigue usando SQLite.'; arrancar_y_verificar "$(leer_puerto)"; return 0; }
      fi
      escribir_env "$INSTALL_ROOT/seshat.env" SESHAT_DB_MOTOR mysql
      if arrancar_y_verificar "$(leer_puerto)"; then ok 'Seshat ahora usa MariaDB / MySQL. El archivo SQLite anterior se conserva como copia.'
      else
        aviso 'No arrancó con MariaDB: se vuelve a SQLite.'
        escribir_env "$INSTALL_ROOT/seshat.env" SESHAT_DB_MOTOR sqlite
        arrancar_y_verificar "$(leer_puerto)"
      fi ;;
  esac
}

probar_mariadb(){   # probar_mariadb HOST PUERTO: con Seshat instalado prueba usuario y base; si no, solo el puerto
  local salida
  if instalado; then
    if salida="$(SESHAT_DB_MOTOR=mysql seshat_db probar 2>&1)"; then ok "$salida"
    else fail "No se pudo conectar: $(tail -n1 <<< "$salida")"; fi
  elif timeout 5 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; then ok "El servidor $1:$2 responde."
  else fail "No se pudo conectar a $1:$2 (revisa servidor, puerto y firewall)."; fi
}

# --- Menús ---------------------------------------------------------------------------------
menu_debian(){
while true; do
  clear 2>/dev/null || true
  printf '%s\n' "${C_CIAN}Seshat Inventario · Instalación normal (Debian)${C_FIN}"
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
  printf '%sRespaldos%s\n' "$C_GRIS" "$C_FIN"
  opcion_menu 12 'Crear respaldo completo (código + base de datos)'
  opcion_menu 13 'Restaurar respaldo / reinstalar desde respaldo'
  opcion_menu 14 'Desinstalar'
  opcion_menu 0  'Salir'
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
    12) respaldo_manual ;;
    13) restaurar_respaldo ;;
    14) desinstalar ;;
    0|q|Q) break ;;
    *) continue ;;
  esac
  vaciar_temporales
  printf '\n'; pausa
done
}

menu_docker(){
  while true; do
    clear 2>/dev/null || true
    printf '%s\n' "${C_CIAN}Seshat Inventario · Instalación con Docker${C_FIN}"
    resumen_general
    printf '\n'
    printf '%sPrimero%s\n' "$C_GRIS" "$C_FIN"
    opcion_menu 1 'Instalar dependencias (Docker, compose, git, rsync)'
    printf '%sInstalación%s\n' "$C_GRIS" "$C_FIN"
    opcion_menu 2 'Instalar con Docker (pregunta SQLite o MariaDB)'
    opcion_menu 3 'Actualizar'
    printf '%sServicio y respaldos%s\n' "$C_GRIS" "$C_FIN"
    opcion_menu 4 'Iniciar'
    opcion_menu 5 'Detener'
    opcion_menu 6 'Reiniciar'
    opcion_menu 7 'Ver registros (Ctrl+C para salir)'
    opcion_menu 8 'Cambiar puerto'
    opcion_menu 9 'Crear respaldo'
    opcion_menu 10 'Desinstalar'
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
      9) if docker_instalado; then r="$(docker_respaldo manual)" && ok "Respaldo: $r" || fail 'No se pudo crear el respaldo.'; else aviso 'Docker no está instalado.'; fi ;;
      10) docker_desinstalar ;;
      0|q|Q) break ;;
      *) continue ;;
    esac
    vaciar_temporales
    printf '\n'; pausa
  done
}

while true; do
  clear 2>/dev/null || true
  printf '%s\n' "${C_CIAN}Seshat Inventario · Instalador v$VERSION_INSTALADOR${C_FIN}"
  resumen_general
  printf '\n'
  opcion_menu 1 'Instalación normal (Python + servicio en Debian)'
  opcion_menu 2 'Instalación con Docker'
  opcion_menu 3 'Base de datos: SQLite (defecto) / conexión a MariaDB'
  opcion_menu 0 'Salir'
  printf '\n'
  read -rp 'Opción: ' principal </dev/tty || break
  printf '\n'
  case "$principal" in
    1) menu_debian ;;
    2) menu_docker ;;
    3) menu_base_datos; vaciar_temporales; printf '\n'; pausa ;;
    0|q|Q) break ;;
    *) continue ;;
  esac
done
