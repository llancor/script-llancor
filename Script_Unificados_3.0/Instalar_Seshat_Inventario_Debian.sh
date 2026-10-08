#!/usr/bin/env bash
# ===========================================================================
# Seshat Inventario - Instalador para Debian (12 / 13) y derivados
# ---------------------------------------------------------------------------
# Queda instalado como servicio de systemd que arranca solo con el equipo:
#   /opt/seshat-inventario/app          código + base de datos (inventario_colegio.db)
#   /opt/seshat-inventario/venv         entorno de Python con las librerías
#   /var/backups/seshat-inventario      respaldos .tar.gz (código + base de datos)
#   servicio: seshat-inventario         usuario del sistema: seshat
#
# Actualizar = se respalda todo, se copia el código nuevo y la base de datos se
# CONSERVA. Si la versión nueva no arranca, se vuelve sola a la anterior.
# Un respaldo (.tar.gz) sirve para reinstalar en este u otro equipo (opción 13).
#
# GitHub: https://github.com/llancor/seshat/tree/main/Seshat_Inventario (pide usuario y token).
# Variables opcionales: SESHAT_DIR, SESHAT_RESPALDOS, SESHAT_REPO_URL, SESHAT_REPO_BRANCH,
# SESHAT_REPO_CARPETA.
# Uso:  sudo bash Instalar_Seshat_Inventario_Debian.sh
# ===========================================================================
set -uo pipefail

VERSION_INSTALADOR='1.0.0'
INSTALL_ROOT="${SESHAT_DIR:-/opt/seshat-inventario}"
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

# Debe correr como root (escribe en /opt y crea el servicio). Si no, se relanza con sudo
# (para usar las variables SESHAT_* ejecútalo directamente como root: sudo -E o su).
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then exec sudo bash "$0" "$@"; fi
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
  apt-get update || { fail 'apt-get update falló (¿hay internet?).'; return 1; }
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-venv python3-pip unzip git rsync curl ca-certificates sqlite3 iproute2 tar \
    || { fail 'No se pudieron instalar las dependencias.'; return 1; }
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
  copiar_base "$APP_DIR/$BASE" "$tmp/seshat-inventario/app/$BASE" || { fail 'No se pudo copiar la base de datos.'; return 1; }
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
  if [[ -f "$carpeta/app/$BASE" ]]; then cp -f "$carpeta/app/$BASE" "$APP_DIR/$BASE"; else rm -f "$APP_DIR/$BASE"; fi
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
  local modo="$1" fuente="$2" linea origen descripcion puerto respaldo=''
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
  escribir_servicio "$puerto"
  arrancar_y_verificar "$puerto" || { revertir_automatico "$respaldo" "$puerto"; return 1; }
  mostrar_acceso "$puerto"
  if [[ "$modo" == instalar ]]; then
    aviso 'Abre la dirección de arriba: aparecerá la «Configuración inicial» para crear la cuenta administradora.'
    aviso 'Hazlo de inmediato: mientras no exista esa cuenta, cualquiera que abra la página podría crearla.'
  fi
}

# --- Estado, servicio y registros --------------------------------------------------------
resumen_estado(){
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
  resumen_estado
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

# --- Menú -------------------------------------------------------------------------------
opcion_menu(){ printf '  %s%2s)%s %s\n' "$C_AMAR" "$1" "$C_FIN" "$2"; }

while true; do
  clear 2>/dev/null || true
  printf '%s\n' "${C_CIAN}Seshat Inventario · Instalador Debian v$VERSION_INSTALADOR${C_FIN}"
  resumen_estado
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
