#!/usr/bin/env bash
set -Eeuo pipefail

# Instalador de Ollama para Seshat en Debian 12.
# Permite instalar dependencias, levantar Ollama con Docker o instalarlo
# como servicio tradicional en el host.

MODEL="qwen3.5:9b"
MODE=""
SESHAT_DIR="/opt/seshat-evaluaciones"
OLLAMA_PORT="11434"
DEPS_READY="0"
FORCE="0"          # --forzar: instala aunque el procesador no sea compatible
CPU_STATUS="0"     # resultado de check_cpu: 0 compatible, 1 con limitaciones, 2 no compatible
CANCELADO="0"      # la instalacion se cancelo por CPU no compatible
OPENWEBUI_PORT="3000"                       # puerto web del chat Open WebUI
OPENWEBUI_NAME="seshat-open-webui"          # nombre del contenedor
OPENWEBUI_IMAGE="ghcr.io/open-webui/open-webui:main"

RESET='\033[0m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'

log() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[AVISO]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

usage() {
  cat <<USAGE
Uso:
  sudo bash instalar_ollama_seshat_debian12.sh
  sudo bash instalar_ollama_seshat_debian12.sh --docker --modelo qwen3.5:9b
  sudo bash instalar_ollama_seshat_debian12.sh --tradicional --modelo llama3.1:8b
  bash instalar_ollama_seshat_debian12.sh --verificar-cpu

Opciones:
  --docker         Instala Ollama en Docker Compose
  --tradicional    Instala Ollama como servicio systemd
  --modelo NAME    Modelo inicial. Por defecto: qwen3.5:9b
  --verificar-cpu  Solo revisa si el procesador es compatible con Ollama y sale
                   (codigo de salida: 0 compatible, 1 con limitaciones, 2 no compatible)
  --forzar         Instala aunque el procesador no sea compatible (no recomendado)
  --openwebui      Instala Open WebUI (chat web para Ollama, en Docker) y sale
  --help           Muestra esta ayuda
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --docker)
      MODE="docker"
      shift
      ;;
    --tradicional|--traditional)
      MODE="tradicional"
      shift
      ;;
    --modelo|--model)
      MODEL="${2:-}"
      if [ -z "$MODEL" ]; then
        err "Falta el nombre del modelo despues de $1"
        exit 1
      fi
      shift 2
      ;;
    --verificar-cpu|--check-cpu)
      MODE="verificar-cpu"
      shift
      ;;
    --forzar|--force)
      FORCE="1"
      shift
      ;;
    --openwebui|--open-webui)
      MODE="openwebui"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      err "Opcion desconocida: $1"
      usage
      exit 1
      ;;
  esac
done

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Ejecuta este script con sudo."
    exit 1
  fi
}

detect_debian() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    if [ "${ID:-}" != "debian" ] || [ "${VERSION_ID:-}" != "12" ]; then
      warn "Este script fue pensado para Debian 12. Detectado: ${PRETTY_NAME:-desconocido}."
    fi
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# Tipo de virtualizacion (kvm, lxc, ...) o "none".
virt_actual() {
  local v=""
  if need_cmd systemd-detect-virt; then
    v="$(systemd-detect-virt 2>/dev/null || true)"
  fi
  printf '%s' "${v:-none}"
}

# Instrucciones del procesador (linea flags en x86, Features en ARM).
CPU_FLAGS=""
cpu_flag() {
  [[ " $CPU_FLAGS " == *" $1 "* ]]
}

cpu_si_no() {
  if cpu_flag "$1"; then printf 'si'; else printf 'no'; fi
}

# Verifica si el procesador puede ejecutar Ollama y deja el resultado en CPU_STATUS:
#   0 = compatible, 1 = funciona con limitaciones (mas lento), 2 = no compatible.
# Ollama (llama.cpp) necesita un procesador de 64 bits; en x86_64 usa AVX/AVX2 y sin AVX
# el contenedor suele caerse al arrancar (codigo 139). Parametro opcional: tipo de virtualizacion.
check_cpu() {
  local virt="${1:-none}" arch modelo hilos nucleos
  CPU_STATUS="0"
  arch="$(uname -m)"
  CPU_FLAGS="$(awk -F: '/^(flags|Features)[[:space:]]*:/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
  modelo="$(awk -F: '/^(model name|Hardware|Model)[[:space:]]*:/ {sub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
  [ -n "$modelo" ] || modelo="desconocido"
  hilos="$(nproc 2>/dev/null || echo 1)"
  nucleos="$(awk -F: '/^cpu cores/ {gsub(/ /, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"

  printf '  Procesador: %s\n' "$modelo"
  printf '  Arquitectura: %s | Hilos: %s%s\n' "$arch" "$hilos" "${nucleos:+ | Nucleos fisicos por zocalo: $nucleos}"

  case "$arch" in
    x86_64|amd64)
      printf '  Instrucciones: AVX=%s AVX2=%s FMA=%s F16C=%s AVX-512=%s SSE4.2=%s\n' \
        "$(cpu_si_no avx)" "$(cpu_si_no avx2)" "$(cpu_si_no fma)" "$(cpu_si_no f16c)" \
        "$(cpu_si_no avx512f)" "$(cpu_si_no sse4_2)"
      if ! cpu_flag avx; then
        CPU_STATUS="2"
        err "El procesador NO muestra instrucciones AVX: Ollama suele caerse al arrancar (codigo 139)."
        if cpu_flag hypervisor || [ "$virt" = "kvm" ] || [ "$virt" = "qemu" ]; then
          err "Es una maquina virtual: el tipo de CPU virtual oculta AVX (por ejemplo kvm64 o qemu64)."
          err "En Proxmox: VM -> Hardware -> Procesadores -> Tipo: host (o x86-64-v3),"
          err "guarda y APAGA/ENCIENDE la VM (un reinicio desde dentro no basta)."
        fi
      elif ! cpu_flag avx2; then
        CPU_STATUS="1"
        warn "El procesador tiene AVX pero no AVX2: Ollama funcionara, pero mas lento."
      else
        ok "El procesador tiene AVX y AVX2."
        if ! cpu_flag fma || ! cpu_flag f16c; then
          warn "Falta FMA o F16C: funcionara, con algo menos de rendimiento."
        fi
        if cpu_flag avx512f; then
          ok "Tiene AVX-512: mejor rendimiento en CPU."
        fi
      fi
      ;;
    aarch64|arm64)
      if cpu_flag asimd; then
        ok "Procesador ARM64 con NEON (asimd): compatible con Ollama."
      else
        CPU_STATUS="1"
        warn "Procesador ARM64 sin NEON (asimd) visible: podria funcionar muy lento."
      fi
      ;;
    *)
      CPU_STATUS="2"
      err "Arquitectura $arch no soportada: Ollama necesita un procesador de 64 bits (x86_64 o ARM64)."
      ;;
  esac

  if [ "$CPU_STATUS" -lt 2 ] && [ "$hilos" -lt 4 ]; then
    CPU_STATUS="1"
    warn "Solo $hilos hilo(s) de CPU: las respuestas seran lentas. Se recomiendan 4 o mas."
  fi

  case "$CPU_STATUS" in
    0) ok "Veredicto CPU: COMPATIBLE con Ollama." ;;
    1) warn "Veredicto CPU: COMPATIBLE CON LIMITACIONES (funciona, pero mas lento). Prefiere modelos livianos (qwen3.5:4b)." ;;
    *) err "Veredicto CPU: NO COMPATIBLE con Ollama en este servidor." ;;
  esac
}

# Antes de instalar: si el procesador no es compatible, pide confirmacion (o --forzar).
# Devuelve 1 (y marca CANCELADO) si no se debe seguir.
cpu_confirmado() {
  CANCELADO="0"
  [ "$CPU_STATUS" -ge 2 ] || return 0
  if [ "$FORCE" = "1" ]; then
    warn "Se instala igual porque se uso --forzar."
    return 0
  fi
  if [ -t 0 ]; then
    local resp
    read -r -p "El procesador no es compatible y Ollama probablemente no arrancara. ¿Instalar de todas formas? [s/N]: " resp
    case "$resp" in
      s|S|si|SI|Si) return 0 ;;
    esac
  else
    err "Para instalar igual sin preguntar, agrega --forzar."
  fi
  CANCELADO="1"
  err "Instalacion cancelada: el procesador no es compatible."
  return 1
}

# Revisa el servidor antes de instalar y avisa lo que suele hacer fallar a Ollama (contenedor
# que se reinicia con codigo 139 = falla de segmentacion). Solo un CPU no compatible detiene la
# instalacion (ver cpu_confirmado); lo demas son avisos.
check_host() {
  printf '\n'
  log "Revisando el servidor para Ollama..."

  local virt
  virt="$(virt_actual)"
  printf '  Virtualizacion: %s\n' "$virt"
  if [ "$virt" = "lxc" ]; then
    warn "El servidor es un contenedor LXC (por ejemplo TurnKey en Proxmox)."
    warn "Docker dentro de LXC suele fallar con Ollama. Mejor: instalacion tradicional (opcion 3)"
    warn "o una maquina virtual (VM) en vez de LXC. Si usas Docker en LXC, activa en Proxmox"
    warn "las opciones nesting=1 y keyctl=1 del contenedor."
  fi

  check_cpu "$virt"

  local mem_kb mem_gb
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  mem_gb=$(( mem_kb / 1024 / 1024 ))
  printf '  RAM: %s GB\n' "$mem_gb"
  if [ "$mem_gb" -lt 8 ]; then
    warn "Menos de 8 GB de RAM: los modelos de 7-9B pueden no caber. Prueba qwen3.5:4b (opcion 3 del menu de modelos)."
  fi

  if need_cmd ss && ss -ltn 2>/dev/null | grep -q ":${OLLAMA_PORT} "; then
    if ! { need_cmd docker && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx seshat-ollama; }; then
      warn "El puerto ${OLLAMA_PORT} ya esta ocupado (quizas un Ollama tradicional ya instalado)."
      warn "No instales Ollama dos veces: usa solo Docker o solo tradicional."
    fi
  fi

  if need_cmd lspci && lspci 2>/dev/null | grep -qi nvidia; then
    ok "Se detecto una tarjeta NVIDIA."
    warn "Para usarla desde Docker hace falta nvidia-container-toolkit; la instalacion tradicional la usa sola"
    warn "si el driver NVIDIA esta instalado (paquete nvidia-driver de Debian non-free)."
  fi
  printf '\n'
}

# Explica por que el contenedor se reinicia, segun su codigo de salida.
explain_container_exit() {
  local code
  code="$(docker inspect -f '{{.State.ExitCode}}' seshat-ollama 2>/dev/null || echo '?')"
  case "$code" in
    139)
      err "El contenedor se cae al arrancar con codigo 139 (falla de segmentacion)."
      err "Causas habituales: procesador sin AVX (en Proxmox, tipo de CPU de la VM distinto de 'host')"
      err "o Docker dentro de un contenedor LXC. Revisa el diagnostico de abajo:"
      check_host
      ;;
    137)
      err "El contenedor se detuvo por falta de memoria (codigo 137). Usa un modelo mas liviano o agrega RAM."
      ;;
    *)
      warn "Codigo de salida del contenedor: $code"
      ;;
  esac
}

# Distribucion y version para el repositorio oficial de Docker: "debian bookworm", "ubuntu noble"...
# Los derivados de Ubuntu (Zorin, Mint) usan el repositorio de Ubuntu con UBUNTU_CODENAME.
docker_repo_destino() {
  (
    . /etc/os-release
    distro="debian"
    codename="${VERSION_CODENAME:-}"
    case " ${ID:-} ${ID_LIKE:-} " in
      *" ubuntu "*) distro="ubuntu"; codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}" ;;
    esac
    if [ "$distro" = "debian" ] && [ -z "$codename" ] && [ -r /etc/debian_version ]; then
      case "$(cut -d. -f1 /etc/debian_version)" in
        11) codename="bullseye" ;;
        12) codename="bookworm" ;;
        13) codename="trixie" ;;
      esac
    fi
    printf '%s %s\n' "$distro" "$codename"
  )
}

# Desactiva repositorios de Docker que no corresponden a este sistema (por ejemplo «debian focal»
# de una instalacion anterior: focal es Ubuntu 20.04). Con ellos «apt-get update» falla y el script
# se detiene antes de poder corregirlos. Los archivos se renombran, no se borran.
limpiar_repos_docker() {
  local distro codename f sufijo
  read -r distro codename < <(docker_repo_destino)
  if [ -z "$codename" ]; then
    warn "No se pudo determinar la version del sistema; no se revisan los repositorios de Docker."
    return 0
  fi
  sufijo="desactivado-$(date +%Y%m%d%H%M)"

  for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    grep -q 'download\.docker\.com' "$f" || continue
    if grep -q "download\.docker\.com/linux/${distro}" "$f" && grep -qw "$codename" "$f"; then
      continue
    fi
    mv "$f" "$f.$sufijo"
    warn "Repositorio de Docker que no corresponde a ${distro} ${codename}: $f"
    warn "  quedo desactivado como $f.$sufijo"
  done

  if [ -f /etc/apt/sources.list ] && grep -Eq '^[[:space:]]*deb.*download\.docker\.com' /etc/apt/sources.list; then
    cp /etc/apt/sources.list "/etc/apt/sources.list.$sufijo"
    sed -i '/download\.docker\.com/ s/^[[:space:]]*deb/# &/' /etc/apt/sources.list
    warn "Se comentaron las lineas de Docker en /etc/apt/sources.list (copia: /etc/apt/sources.list.$sufijo)."
  fi
}

install_base_packages() {
  log "Instalando dependencias base..."
  limpiar_repos_docker
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release iproute2
  DEPS_READY="1"
  ok "Dependencias base instaladas."
}

install_docker_packages() {
  if need_cmd docker && docker compose version >/dev/null 2>&1; then
    ok "Docker y Docker Compose ya estan disponibles."
    return
  fi

  log "Instalando Docker Engine y Compose plugin..."
  install_base_packages

  local distro codename
  read -r distro codename < <(docker_repo_destino)
  if [ -z "$codename" ]; then
    err "No se pudo determinar la version del sistema (VERSION_CODENAME) para el repositorio de Docker."
    return 1
  fi
  log "Repositorio de Docker: ${distro} ${codename}"

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${distro}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${distro} ${codename} stable
EOF

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  ok "Docker instalado y activo."
}

compose_base_args() {
  if [ -f "$SESHAT_DIR/compose.yaml" ]; then
    printf '%s\n' "-f" "$SESHAT_DIR/compose.yaml"
  elif [ -f "$SESHAT_DIR/docker-compose.yml" ]; then
    printf '%s\n' "-f" "$SESHAT_DIR/docker-compose.yml"
  fi
}

write_seshat_hint() {
  local endpoint="$1"
  local hint_dir="$SESHAT_DIR"
  local prompt_dir="$SESHAT_DIR/ollama-prompts"

  mkdir -p "$hint_dir" "$prompt_dir"
  cat > "$hint_dir/ollama-seshat.env" <<EOF
# Configuracion sugerida para integrar Seshat con Ollama.
SESHAT_OLLAMA_URL=$endpoint
SESHAT_OLLAMA_MODEL=$MODEL
SESHAT_OLLAMA_PROMPT_CREAR_PRUEBA=$prompt_dir/crear_prueba_seshat.txt
EOF

  cat > "$prompt_dir/crear_prueba_seshat.txt" <<'EOF'
Eres un asistente pedagogico para Seshat. Tu tarea es crear una prueba escolar
usando solamente la base curricular y las instrucciones que entrega el docente.

Reglas:
- Responde siempre en espanol de Chile.
- No inventes objetivos, contenidos ni habilidades que no esten en la base entregada.
- Si falta informacion critica, pide los datos faltantes antes de crear la prueba.
- Genera preguntas claras, evaluables y adecuadas al nivel indicado.
- Incluye pauta de correccion y justificacion breve por pregunta.
- Devuelve la respuesta en JSON valido, sin texto fuera del JSON.

Formato JSON esperado:
{
  "titulo": "",
  "nivel": "",
  "asignatura": "",
  "objetivos": [],
  "instrucciones_estudiante": "",
  "preguntas": [
    {
      "tipo": "alternativas|vf|respuesta_corta|desarrollo",
      "enunciado": "",
      "puntaje": 1,
      "alternativas": [
        {"texto": "", "correcta": false}
      ],
      "respuesta_correcta": "",
      "justificacion": "",
      "objetivo_asociado": ""
    }
  ],
  "puntaje_total": 0,
  "pauta_general": ""
}
EOF

  ok "Configuracion guardada en $hint_dir/ollama-seshat.env"
  ok "Prompt guardado en $prompt_dir/crear_prueba_seshat.txt"
}

wait_ollama() {
  log "Esperando API de Ollama..."
  for _ in $(seq 1 45); do
    if curl -fsS "http://127.0.0.1:${OLLAMA_PORT}/api/tags" >/dev/null 2>&1; then
      ok "API de Ollama disponible."
      return
    fi
    sleep 2
  done
  err "La API de Ollama no responde en http://127.0.0.1:${OLLAMA_PORT}"
  return 1
}

wait_ollama_docker() {
  log "Esperando Ollama dentro del contenedor..."
  for _ in $(seq 1 60); do
    if docker exec seshat-ollama ollama list >/dev/null 2>&1; then
      ok "Ollama responde dentro del contenedor."
      if curl -fsS "http://127.0.0.1:${OLLAMA_PORT}/api/tags" >/dev/null 2>&1; then
        ok "API disponible tambien desde el host en http://127.0.0.1:${OLLAMA_PORT}"
      else
        warn "El contenedor responde, pero el host aun no conecta a http://127.0.0.1:${OLLAMA_PORT}."
        warn "Seshat en Docker debe usar http://ollama:11434, por eso la instalacion puede continuar."
      fi
      return
    fi
    sleep 2
  done

  err "Ollama no respondio dentro del contenedor."
  docker ps -a --filter "name=seshat-ollama" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true
  printf '\nUltimas lineas del registro del contenedor:\n'
  docker logs --tail 80 seshat-ollama 2>&1 || true
  explain_container_exit
  return 1
}

docker_compose_ollama() {
  mapfile -t base_args < <(compose_base_args)
  if [ "${#base_args[@]}" -gt 0 ]; then
    docker compose --project-directory "$SESHAT_DIR" "${base_args[@]}" -f "$SESHAT_DIR/compose.ollama.yaml" "$@"
  else
    docker compose --project-directory "$SESHAT_DIR" -f "$SESHAT_DIR/compose.ollama.yaml" "$@"
  fi
}

# ===================== ACCESO DESDE LA RED (LAN) =====================
# Por defecto Ollama solo atiende en 127.0.0.1 (este mismo servidor). Para que Seshat u otro
# equipo de la red lo use (http://IP-LAN:11434) hay que abrirlo: en Docker se publica el puerto
# en todas las interfaces; en la instalacion tradicional se fija OLLAMA_HOST=0.0.0.0.
# Ollama no tiene contrasena: abrir solo a la red local, nunca a internet.

OLLAMA_LAN_DROPIN="/etc/systemd/system/ollama.service.d/red.conf"

# IP de este servidor en la red local (la de la ruta por defecto; no las 172.x de Docker).
ip_lan() {
  local ip
  ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  [ -n "$ip" ] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s' "$ip"
}

# Subred local en formato CIDR (ej. 192.168.0.0/24), para la regla del firewall.
subred_lan() {
  local ip="$1"
  ip -o -4 route show scope link 2>/dev/null | awk -v ip="$ip" '$0 ~ ("src " ip) {print $1; exit}'
}

# 0 si Ollama escucha en alguna direccion distinta de 127.0.0.1 / ::1 (abierto a la red).
ollama_en_lan() {
  need_cmd ss || return 1
  ss -ltn 2>/dev/null | awk -v p=":${OLLAMA_PORT}" '$4 ~ (p "$") {print $4}' \
    | grep -Evq '^(127\.0\.0\.1|\[::1\]):'
}

ollama_modo_instalado() {
  if need_cmd docker && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx seshat-ollama; then
    printf 'docker'
  elif need_cmd systemctl && systemctl list-unit-files ollama.service >/dev/null 2>&1 \
       && systemctl list-unit-files ollama.service 2>/dev/null | grep -q '^ollama\.service'; then
    printf 'tradicional'
  else
    printf 'ninguno'
  fi
}

show_lan_status() {
  local ip
  ip="$(ip_lan)"
  if ollama_en_lan; then
    ok "Ollama esta ABIERTO a la red: otros equipos usan http://${ip}:${OLLAMA_PORT}"
  else
    warn "Ollama esta SOLO LOCAL (127.0.0.1): desde otros equipos http://${ip}:${OLLAMA_PORT} no conecta."
    warn "Usa la opcion 'Acceso desde la red (LAN)' del menu para abrirlo."
  fi
}

habilitar_lan() {
  local modo ip subred resp
  modo="$(ollama_modo_instalado)"
  ip="$(ip_lan)"
  printf '\n'
  log "Abriendo Ollama a la red local (instalacion: $modo)..."

  case "$modo" in
    docker)
      if [ ! -f "$SESHAT_DIR/compose.ollama.yaml" ]; then
        err "No existe $SESHAT_DIR/compose.ollama.yaml."
        return 0
      fi
      cp "$SESHAT_DIR/compose.ollama.yaml" "$SESHAT_DIR/compose.ollama.yaml.bak-$(date +%Y%m%d%H%M)"
      sed -i "s/\"127\.0\.0\.1:${OLLAMA_PORT}:11434\"/\"${OLLAMA_PORT}:11434\"/" "$SESHAT_DIR/compose.ollama.yaml"
      docker_compose_ollama up -d ollama
      wait_ollama_docker || true
      ;;
    tradicional)
      mkdir -p "$(dirname "$OLLAMA_LAN_DROPIN")"
      cat > "$OLLAMA_LAN_DROPIN" <<EOF
# Creado por instalar_ollama_seshat_debian12.sh: Ollama escucha en la red local.
[Service]
Environment="OLLAMA_HOST=0.0.0.0:${OLLAMA_PORT}"
EOF
      systemctl daemon-reload
      systemctl restart ollama
      wait_ollama || true
      ;;
    *)
      err "No se encontro Ollama instalado (ni Docker seshat-ollama ni servicio ollama)."
      return 0
      ;;
  esac

  # Firewall: si ufw esta activo, se permite solo la subred local.
  if need_cmd ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    subred="$(subred_lan "$ip")"
    read -r -p "ufw esta activo. ¿Permitir el puerto ${OLLAMA_PORT} desde ${subred:-la red local}? [S/n]: " resp
    case "$resp" in
      n|N|no|NO) warn "No se cambio ufw: otros equipos podrian no conectar." ;;
      *)
        if [ -n "$subred" ]; then
          ufw allow from "$subred" to any port "$OLLAMA_PORT" proto tcp comment 'Ollama LAN'
          ok "ufw: puerto ${OLLAMA_PORT} permitido desde ${subred}."
        else
          warn "No se pudo determinar la subred; agrega la regla a mano: ufw allow from 192.168.X.0/24 to any port ${OLLAMA_PORT} proto tcp"
        fi
        ;;
    esac
  fi

  if curl -fsS "http://${ip}:${OLLAMA_PORT}" >/dev/null 2>&1; then
    ok "Listo: Ollama responde en http://${ip}:${OLLAMA_PORT}"
    ok "En Seshat usa esa direccion (Ajustes del sistema -> Inteligencia artificial -> Ollama)."
  else
    err "Ollama todavia no responde en http://${ip}:${OLLAMA_PORT}. Revisa con la opcion 'Ver estado'."
  fi
  warn "Ollama no tiene contrasena: NO reenvies el puerto ${OLLAMA_PORT} en el router hacia internet."
}

deshabilitar_lan() {
  local modo
  modo="$(ollama_modo_instalado)"
  printf '\n'
  log "Dejando Ollama solo local (127.0.0.1)..."
  case "$modo" in
    docker)
      if [ -f "$SESHAT_DIR/compose.ollama.yaml" ]; then
        sed -i "s/\"${OLLAMA_PORT}:11434\"/\"127.0.0.1:${OLLAMA_PORT}:11434\"/" "$SESHAT_DIR/compose.ollama.yaml"
        docker_compose_ollama up -d ollama
        wait_ollama_docker || true
      fi
      ;;
    tradicional)
      rm -f "$OLLAMA_LAN_DROPIN"
      systemctl daemon-reload
      systemctl restart ollama
      wait_ollama || true
      ;;
    *)
      err "No se encontro Ollama instalado."
      return 0
      ;;
  esac
  if need_cmd ufw && ufw status 2>/dev/null | grep -q "${OLLAMA_PORT}/tcp.*Ollama LAN"; then
    ufw status numbered 2>/dev/null | grep 'Ollama LAN' | sed -n 's/^\[ *\([0-9]*\)\].*/\1/p' | sort -rn \
      | while read -r n; do ufw --force delete "$n" >/dev/null; done
    ok "Reglas ufw 'Ollama LAN' eliminadas."
  fi
  show_lan_status
}

menu_lan() {
  while true; do
    printf '\n'
    printf "${CYAN}=== Acceso desde la red (LAN) ===${RESET}\n"
    show_lan_status
    printf "${YELLOW}1)${RESET} ${CYAN}Permitir conexion desde la red local${RESET}\n"
    printf "${YELLOW}2)${RESET} ${CYAN}Volver a solo local (127.0.0.1)${RESET}\n"
    printf "${YELLOW}0)${RESET} ${CYAN}Volver${RESET}\n"
    local op
    read -r -p "Elige una opcion: " op
    case "$op" in
      1) habilitar_lan ;;
      2) deshabilitar_lan ;;
      0|"") return 0 ;;
      *) warn "Opcion no valida." ;;
    esac
  done
}

show_network_status() {
  local ip
  ip="$(ip_lan)"
  printf '\nRed del servidor:\n'
  if need_cmd hostname; then
    printf '  IPs del servidor: %s  (172.17/172.18 son redes internas de Docker)\n' "$(hostname -I 2>/dev/null | xargs || true)"
  fi
  printf '  Puerto Ollama host: %s\n' "$OLLAMA_PORT"
  printf '  URL en este mismo servidor: http://127.0.0.1:%s\n' "$OLLAMA_PORT"
  printf '  URL desde otros equipos (Seshat en otro servidor): http://%s:%s\n' "$ip" "$OLLAMA_PORT"
  printf '  URL para Seshat Docker (mismo compose): http://ollama:11434\n'
  show_lan_status

  if need_cmd ss; then
    printf '\nPuertos escuchando en %s:\n' "$OLLAMA_PORT"
    ss -ltnp 2>/dev/null | grep ":${OLLAMA_PORT} " || warn "No se ve ningun proceso escuchando en ${OLLAMA_PORT}."
  fi
}

show_ollama_api_status() {
  printf '\nAPI Ollama:\n'
  if curl -fsS "http://127.0.0.1:${OLLAMA_PORT}/api/tags" >/tmp/seshat-ollama-tags.json 2>/dev/null; then
    ok "API responde en http://127.0.0.1:${OLLAMA_PORT}"
    if need_cmd sed; then
      sed -n '1,12p' /tmp/seshat-ollama-tags.json
      printf '\n'
    fi
  else
    warn "La API no responde en http://127.0.0.1:${OLLAMA_PORT}"
    if need_cmd docker && docker ps --filter "name=seshat-ollama" --format "{{.Names}}" | grep -qx "seshat-ollama"; then
      if docker exec seshat-ollama ollama list >/dev/null 2>&1; then
        ok "El contenedor seshat-ollama responde internamente."
        warn "Para Seshat Docker usa http://ollama:11434."
      fi
    fi
  fi
}

show_docker_status() {
  printf '\nEstado Docker:\n'
  if ! need_cmd docker; then
    warn "Docker no esta instalado."
    return
  fi

  docker ps -a --filter "name=seshat-ollama" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true
  if docker ps --filter "name=seshat-ollama" --format "{{.Names}}" | grep -qx "seshat-ollama"; then
    printf '\nModelos en contenedor:\n'
    docker exec seshat-ollama ollama list || true
  fi
}

show_traditional_status() {
  printf '\nEstado tradicional/systemd:\n'
  if need_cmd systemctl; then
    systemctl status ollama --no-pager || true
  fi

  if need_cmd ollama; then
    printf '\nModelos locales:\n'
    ollama list || true
  else
    warn "Comando ollama no esta instalado en el host."
  fi
}

show_status_menu() {
  check_host
  show_network_status
  show_ollama_api_status
  show_docker_status
  show_traditional_status
}

show_docker_diagnostics() {
  printf '\nDiagnostico Docker Ollama:\n'
  check_host
  if ! need_cmd docker; then
    warn "Docker no esta instalado."
    return
  fi

  printf '\nContenedor:\n'
  docker ps -a --filter "name=seshat-ollama" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true

  printf '\nPrueba interna:\n'
  docker exec seshat-ollama ollama list || true

  printf '\nLogs recientes:\n'
  docker logs --tail 80 seshat-ollama 2>&1 || true
  if docker ps -a --filter "name=seshat-ollama" --format '{{.Status}}' 2>/dev/null | grep -q '^Restarting'; then
    explain_container_exit
  fi

  printf '\nPuerto host:\n'
  if need_cmd ss; then
    ss -ltnp 2>/dev/null | grep ":${OLLAMA_PORT} " || warn "No se ve ${OLLAMA_PORT} publicado en el host."
  fi
}

restart_docker_mode() {
  if [ ! -f "$SESHAT_DIR/compose.ollama.yaml" ]; then
    err "No existe $SESHAT_DIR/compose.ollama.yaml. Instala primero en modo Docker."
    return 1
  fi
  if ! need_cmd docker; then
    err "Docker no esta disponible."
    return 1
  fi

  log "Reiniciando Ollama Docker..."
  docker_compose_ollama restart ollama || docker restart seshat-ollama
  wait_ollama_docker
  ok "Ollama Docker reiniciado."
}

restart_traditional_mode() {
  if ! need_cmd systemctl; then
    err "systemctl no esta disponible."
    return 1
  fi

  log "Reiniciando servicio ollama..."
  systemctl restart ollama
  wait_ollama
  ok "Servicio ollama reiniciado."
}

uninstall_docker_mode() {
  if ! need_cmd docker; then
    warn "Docker no esta disponible; no hay servicio Docker que detener."
    return
  fi

  log "Deteniendo Ollama Docker..."
  if [ -f "$SESHAT_DIR/compose.ollama.yaml" ]; then
    docker_compose_ollama down || true
  else
    docker rm -f seshat-ollama >/dev/null 2>&1 || true
  fi

  read -r -p "¿Borrar modelos/datos Docker en $SESHAT_DIR/ollama? [s/N]: " borrar_datos
  case "$borrar_datos" in
    s|S|si|SI|Si)
      rm -rf "$SESHAT_DIR/ollama"
      ok "Datos Docker de Ollama eliminados."
      ;;
    *)
      ok "Datos Docker conservados en $SESHAT_DIR/ollama."
      ;;
  esac

  read -r -p "¿Borrar archivo $SESHAT_DIR/compose.ollama.yaml? [s/N]: " borrar_compose
  case "$borrar_compose" in
    s|S|si|SI|Si)
      rm -f "$SESHAT_DIR/compose.ollama.yaml"
      ok "compose.ollama.yaml eliminado."
      ;;
    *)
      ok "compose.ollama.yaml conservado."
      ;;
  esac
}

uninstall_traditional_mode() {
  log "Desinstalando Ollama tradicional..."

  if need_cmd systemctl; then
    systemctl stop ollama >/dev/null 2>&1 || true
    systemctl disable ollama >/dev/null 2>&1 || true
  fi

  rm -f /etc/systemd/system/ollama.service
  rm -f /usr/local/bin/ollama
  rm -f /usr/bin/ollama
  if need_cmd systemctl; then
    systemctl daemon-reload || true
  fi

  read -r -p "¿Borrar modelos/datos tradicionales en /usr/share/ollama y /var/lib/ollama? [s/N]: " borrar_datos
  case "$borrar_datos" in
    s|S|si|SI|Si)
      rm -rf /usr/share/ollama /var/lib/ollama
      ok "Datos tradicionales de Ollama eliminados."
      ;;
    *)
      ok "Datos tradicionales conservados."
      ;;
  esac

  ok "Ollama tradicional desinstalado."
}

install_docker_mode() {
  check_host
  if ! cpu_confirmado; then return 0; fi
  install_docker_packages
  mkdir -p "$SESHAT_DIR/ollama"

  cat > "$SESHAT_DIR/compose.ollama.yaml" <<EOF
services:
  ollama:
    image: ollama/ollama:latest
    container_name: seshat-ollama
    restart: unless-stopped
    ports:
      - "127.0.0.1:${OLLAMA_PORT}:11434"
    volumes:
      - ./ollama:/root/.ollama
EOF

  log "Levantando Ollama con Docker Compose..."
  docker_compose_ollama up -d ollama

  wait_ollama_docker
  log "Descargando modelo inicial: $MODEL"
  docker exec seshat-ollama ollama pull "$MODEL"
  write_seshat_hint "http://ollama:11434"

  ok "Ollama quedo instalado con Docker."
  ok "Host: http://127.0.0.1:${OLLAMA_PORT}"
  ok "Seshat en Docker debe usar: http://ollama:11434"
}

install_traditional_mode() {
  check_host
  if ! cpu_confirmado; then return 0; fi
  install_base_packages

  log "Instalando Ollama con el instalador oficial..."
  curl -fsSL https://ollama.com/install.sh | sh
  systemctl enable --now ollama

  wait_ollama
  log "Descargando modelo inicial: $MODEL"
  sudo -u ollama ollama pull "$MODEL" || ollama pull "$MODEL"
  write_seshat_hint "http://127.0.0.1:11434"

  ok "Ollama quedo instalado como servicio tradicional."
}

show_final_notes() {
  cat <<EOF

Resumen:
  Modelo: $MODEL
  Configuracion Seshat: $SESHAT_DIR/ollama-seshat.env
  Prompt de pruebas: $SESHAT_DIR/ollama-prompts/crear_prueba_seshat.txt

Pruebas utiles:
  curl http://127.0.0.1:${OLLAMA_PORT}/api/tags
  ollama list

Conectar Seshat (version con Ollama, 04-10-2026 o posterior):
  Ajustes del sistema -> Inteligencia artificial -> Ollama (servidor propio)
    Direccion: http://127.0.0.1:${OLLAMA_PORT}  (Seshat tradicional en este servidor)
               http://ollama:11434        (Seshat en Docker, mismo compose)
               http://IP-de-este-servidor:${OLLAMA_PORT}  (Seshat en otro servidor;
               en ese caso Ollama debe escuchar en la red y el puerto abrirse solo a esa IP)
    Modelo:    $MODEL
  Luego pulsa "Probar conexion".
EOF
}

# ===================== PROTEGER CON TOKEN (proxy nginx) =====================
# Ollama no tiene usuario ni contrasena. Este proxy nginx escucha en la red (puerto 11435) y solo
# deja pasar las peticiones con "Authorization: Bearer <token>"; Ollama sigue solo en 127.0.0.1.
# En Seshat: Ajustes del sistema -> Inteligencia artificial -> Ollama:
#   Direccion http://IP-del-servidor:11435  +  Token (el que muestra este script).

TOKEN_PORT="11435"
TOKEN_DIR="/etc/ollama-seshat"
TOKEN_FILE="$TOKEN_DIR/token"
TOKEN_NGINX_CONF="/etc/nginx/conf.d/ollama-seshat-token.conf"
TOKEN_NGINX_MARCA="$TOKEN_DIR/nginx-instalado-por-script"

token_generar() {
  # 48 caracteres hexadecimales aleatorios (sin tuberias que puedan cortar con pipefail).
  od -An -tx1 -N24 /dev/urandom | tr -d ' \n'
}

token_actual() {
  [ -r "$TOKEN_FILE" ] && cat "$TOKEN_FILE"
  return 0
}

token_escribir_nginx() {
  local token="$1"
  umask 077
  cat > "$TOKEN_NGINX_CONF" <<EOF
# Proxy con token para Ollama (creado por instalar_ollama_seshat_debian12.sh).
# Solo pasan las peticiones con "Authorization: Bearer <token>"; Ollama queda en 127.0.0.1.
server {
    listen ${TOKEN_PORT};
    server_name _;
    client_max_body_size 20m;

    location / {
        if (\$http_authorization != "Bearer ${token}") {
            return 401;
        }
        proxy_pass http://127.0.0.1:${OLLAMA_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host 127.0.0.1:${OLLAMA_PORT};
        proxy_set_header Authorization "";
        # Un modelo local sin GPU puede tardar varios minutos en responder.
        proxy_connect_timeout 10s;
        proxy_send_timeout 600s;
        proxy_read_timeout 600s;
        proxy_buffering off;
    }
}
EOF
  chmod 600 "$TOKEN_NGINX_CONF"
  umask 022
}

# Instala nginx sin que arranque solo: si Apache (Seshat) ya usa el puerto 80, el sitio por
# defecto de nginx chocaria y la instalacion quedaria con error.
token_instalar_nginx() {
  if need_cmd nginx; then
    return 0
  fi
  log "Instalando nginx..."
  install_base_packages
  printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
  chmod 755 /usr/sbin/policy-rc.d
  apt-get install -y nginx || { rm -f /usr/sbin/policy-rc.d; err "No se pudo instalar nginx."; return 1; }
  rm -f /usr/sbin/policy-rc.d
  # El sitio por defecto (puerto 80) no se usa: se desactiva para no chocar con Apache.
  rm -f /etc/nginx/sites-enabled/default
  mkdir -p "$TOKEN_DIR"
  touch "$TOKEN_NGINX_MARCA"
  ok "nginx instalado (sin sitio por defecto)."
}

token_firewall_permitir() {
  local ip subred resp
  need_cmd ufw && ufw status 2>/dev/null | grep -q '^Status: active' || return 0
  ip="$(ip_lan)"
  subred="$(subred_lan "$ip")"
  read -r -p "ufw esta activo. ¿Permitir el puerto ${TOKEN_PORT} desde ${subred:-la red local}? [S/n]: " resp
  case "$resp" in
    n|N|no|NO) warn "No se cambio ufw: otros equipos podrian no conectar." ;;
    *)
      if [ -n "$subred" ]; then
        ufw allow from "$subred" to any port "$TOKEN_PORT" proto tcp comment 'Ollama token'
        ok "ufw: puerto ${TOKEN_PORT} permitido desde ${subred}."
      else
        warn "No se pudo determinar la subred: ufw allow from 192.168.X.0/24 to any port ${TOKEN_PORT} proto tcp"
      fi
      ;;
  esac
}

token_mostrar() {
  local token ip
  token="$(token_actual)"
  ip="$(ip_lan)"
  if [ -z "$token" ]; then
    warn "Aun no hay token: activa la proteccion primero."
    return 0
  fi
  cat <<EOF

Datos para Seshat (Ajustes del sistema -> Inteligencia artificial -> Ollama):
  Direccion: http://${ip}:${TOKEN_PORT}
  Token:     ${token}
  Modelo:    el que descargaste (ej. ${MODEL})
Luego pulsa "Probar conexion". Guarda el token en un lugar seguro y no lo compartas.
EOF
}

token_probar() {
  local token ip sin con
  token="$(token_actual)"
  ip="$(ip_lan)"
  printf '\n'
  if [ ! -f "$TOKEN_NGINX_CONF" ]; then
    warn "La proteccion con token no esta activa."
    return 0
  fi
  if need_cmd systemctl && systemctl is-active --quiet nginx; then
    ok "nginx esta activo."
  else
    err "nginx no esta activo: systemctl status nginx"
  fi
  sin="$(curl -s -o /dev/null -w '%{http_code}' "http://${ip}:${TOKEN_PORT}/api/tags" || true)"
  con="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${token}" "http://${ip}:${TOKEN_PORT}/api/tags" || true)"
  if [ "$sin" = "401" ]; then ok "Sin token: rechazado (401), correcto."; else warn "Sin token respondio $sin (se esperaba 401)."; fi
  if [ "$con" = "200" ]; then
    ok "Con token: Ollama responde (200) en http://${ip}:${TOKEN_PORT}"
  elif [ "$con" = "502" ]; then
    err "Con token: 502. nginx funciona, pero Ollama no responde en 127.0.0.1:${OLLAMA_PORT}."
  else
    err "Con token respondio $con."
  fi
  if ollama_en_lan; then
    warn "Ollama tambien esta abierto SIN token en el puerto ${OLLAMA_PORT}."
    warn "Para que solo se entre con token, deja Ollama solo local (opcion 14 -> 2)."
  fi
}

token_activar() {
  local token resp
  printf '\n'
  log "Protegiendo Ollama con token (proxy nginx en el puerto ${TOKEN_PORT})..."

  if [ -f "$TOKEN_NGINX_CONF" ]; then
    warn "La proteccion con token ya esta activa."
    token_mostrar
    return 0
  fi
  if ! curl -fsS "http://127.0.0.1:${OLLAMA_PORT}/api/tags" >/dev/null 2>&1; then
    err "Ollama no responde en http://127.0.0.1:${OLLAMA_PORT}. Instalalo o reinicialo primero."
    return 0
  fi
  if need_cmd ss && ss -ltn 2>/dev/null | grep -q ":${TOKEN_PORT} "; then
    err "El puerto ${TOKEN_PORT} ya esta en uso."
    return 0
  fi

  token_instalar_nginx || return 0
  mkdir -p "$TOKEN_DIR"
  chmod 700 "$TOKEN_DIR"
  token="$(token_actual)"
  [ -n "$token" ] || token="$(token_generar)"
  ( umask 077; printf '%s\n' "$token" > "$TOKEN_FILE" )

  token_escribir_nginx "$token"
  if ! nginx -t >/dev/null 2>&1; then
    err "La configuracion de nginx tiene errores:"
    nginx -t || true
    rm -f "$TOKEN_NGINX_CONF"
    return 0
  fi
  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl restart nginx
  token_firewall_permitir

  if ollama_en_lan; then
    read -r -p "Ollama tambien esta abierto SIN token en el puerto ${OLLAMA_PORT}. ¿Dejarlo solo local? [S/n]: " resp
    case "$resp" in
      n|N|no|NO) warn "Ollama sigue abierto sin token en ${OLLAMA_PORT}." ;;
      *) deshabilitar_lan ;;
    esac
  fi

  token_probar
  token_mostrar
}

token_cambiar() {
  local token
  if [ ! -f "$TOKEN_NGINX_CONF" ]; then
    warn "La proteccion con token no esta activa."
    return 0
  fi
  token="$(token_generar)"
  ( umask 077; printf '%s\n' "$token" > "$TOKEN_FILE" )
  token_escribir_nginx "$token"
  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx
    ok "Token cambiado. El anterior ya no sirve: actualizalo en Seshat."
    token_mostrar
  else
    err "nginx rechazo la configuracion nueva:"
    nginx -t || true
  fi
}

token_quitar() {
  local resp
  if [ ! -f "$TOKEN_NGINX_CONF" ]; then
    warn "La proteccion con token no esta activa."
    return 0
  fi
  rm -f "$TOKEN_NGINX_CONF"
  if need_cmd nginx && nginx -t >/dev/null 2>&1; then
    systemctl reload nginx || true
  fi
  if need_cmd ufw && ufw status 2>/dev/null | grep -q 'Ollama token'; then
    ufw status numbered 2>/dev/null | grep 'Ollama token' | sed -n 's/^\[ *\([0-9]*\)\].*/\1/p' | sort -rn \
      | while read -r n; do ufw --force delete "$n" >/dev/null; done
  fi
  ok "Proxy con token quitado (puerto ${TOKEN_PORT} cerrado)."
  if [ -f "$TOKEN_NGINX_MARCA" ]; then
    read -r -p "nginx lo instalo este script. ¿Desinstalarlo tambien? [s/N]: " resp
    case "$resp" in
      s|S|si|SI|Si)
        systemctl stop nginx >/dev/null 2>&1 || true
        apt-get remove -y nginx nginx-common >/dev/null 2>&1 || true
        rm -f "$TOKEN_NGINX_MARCA"
        ok "nginx desinstalado."
        ;;
    esac
  fi
  rm -f "$TOKEN_FILE"
  warn "Si Seshat usaba http://IP:${TOKEN_PORT}, cambia la direccion en Ajustes."
}

menu_token() {
  while true; do
    printf '\n'
    printf "${CYAN}=== Proteger Ollama con token (proxy nginx) ===${RESET}\n"
    if [ -f "$TOKEN_NGINX_CONF" ]; then
      ok "Proteccion activa: http://$(ip_lan):${TOKEN_PORT} (con token)"
    else
      warn "Proteccion con token: NO activa."
    fi
    printf "${YELLOW}1)${RESET} ${CYAN}Activar proteccion con token${RESET}\n"
    printf "${YELLOW}2)${RESET} ${CYAN}Probar (con y sin token)${RESET}\n"
    printf "${YELLOW}3)${RESET} ${CYAN}Mostrar token y datos para Seshat${RESET}\n"
    printf "${YELLOW}4)${RESET} ${CYAN}Cambiar token${RESET}\n"
    printf "${YELLOW}5)${RESET} ${CYAN}Quitar proteccion con token${RESET}\n"
    printf "${YELLOW}0)${RESET} ${CYAN}Volver${RESET}\n"
    local op
    read -r -p "Elige una opcion: " op
    case "$op" in
      1) token_activar ;;
      2) token_probar ;;
      3) token_mostrar ;;
      4) token_cambiar ;;
      5) token_quitar ;;
      0|"") return 0 ;;
      *) warn "Opcion no valida." ;;
    esac
  done
}

# ===================== OPEN WEBUI (chat web para Ollama) =====================
# Open WebUI es una pagina tipo ChatGPT que usa el Ollama de este servidor. Corre en Docker
# y guarda usuarios y chats en $SESHAT_DIR/open-webui. La primera cuenta que se crea es la
# del administrador.

openwebui_existe() {
  need_cmd docker && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$OPENWEBUI_NAME"
}

openwebui_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

install_openwebui() {
  printf '\n'
  log "Instalando Open WebUI (chat web para Ollama)..."

  if openwebui_existe; then
    warn "Open WebUI ya esta instalado (contenedor $OPENWEBUI_NAME). Usa 'Actualizar' o 'Estado'."
    return 0
  fi

  install_docker_packages

  local puerto resp ollama_url red=""
  read -r -p "Puerto web para Open WebUI [${OPENWEBUI_PORT}]: " puerto
  puerto="${puerto:-$OPENWEBUI_PORT}"
  if ! [[ "$puerto" =~ ^[0-9]{2,5}$ ]] || [ "$puerto" -gt 65535 ]; then
    err "Puerto invalido: $puerto"
    return 0
  fi
  if need_cmd ss && ss -ltn 2>/dev/null | grep -q ":${puerto} "; then
    err "El puerto $puerto ya esta en uso. Elige otro."
    return 0
  fi
  OPENWEBUI_PORT="$puerto"

  # Donde esta Ollama:
  #  - Ollama en Docker (seshat-ollama): Open WebUI se une a su red y usa http://seshat-ollama:11434
  #  - Ollama tradicional en este servidor: Open WebUI usa la red del host y http://127.0.0.1:11434
  #  - Otro servidor: se escribe la direccion.
  if need_cmd docker && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx seshat-ollama; then
    red="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' seshat-ollama 2>/dev/null | awk '{print $1}')"
    ollama_url="http://seshat-ollama:11434"
    log "Ollama detectado en Docker (red: ${red:-desconocida})."
  elif curl -fsS "http://127.0.0.1:${OLLAMA_PORT}/api/tags" >/dev/null 2>&1; then
    ollama_url="http://127.0.0.1:${OLLAMA_PORT}"
    log "Ollama detectado en este servidor (instalacion tradicional)."
  else
    warn "No se detecto Ollama en este servidor."
    read -r -p "Direccion de Ollama (ej. http://192.168.0.136:11434): " ollama_url
    if ! [[ "$ollama_url" =~ ^https?://[A-Za-z0-9._-]+(:[0-9]+)?/?$ ]]; then
      err "Direccion invalida."
      return 0
    fi
  fi

  mkdir -p "$SESHAT_DIR/open-webui"
  log "Descargando la imagen de Open WebUI (puede pesar varios GB y tardar)..."
  docker pull "$OPENWEBUI_IMAGE"

  if [ -n "$red" ]; then
    docker run -d --name "$OPENWEBUI_NAME" --restart unless-stopped \
      --network "$red" -p "${OPENWEBUI_PORT}:8080" \
      -e OLLAMA_BASE_URL="$ollama_url" \
      -v "$SESHAT_DIR/open-webui:/app/backend/data" \
      "$OPENWEBUI_IMAGE" >/dev/null
  elif [[ "$ollama_url" == http://127.0.0.1:* ]]; then
    # Red del host: asi llega a Ollama aunque este escuche solo en 127.0.0.1.
    docker run -d --name "$OPENWEBUI_NAME" --restart unless-stopped \
      --network host -e PORT="$OPENWEBUI_PORT" \
      -e OLLAMA_BASE_URL="$ollama_url" \
      -v "$SESHAT_DIR/open-webui:/app/backend/data" \
      "$OPENWEBUI_IMAGE" >/dev/null
  else
    docker run -d --name "$OPENWEBUI_NAME" --restart unless-stopped \
      -p "${OPENWEBUI_PORT}:8080" \
      -e OLLAMA_BASE_URL="$ollama_url" \
      -v "$SESHAT_DIR/open-webui:/app/backend/data" \
      "$OPENWEBUI_IMAGE" >/dev/null
  fi
  printf '%s\n' "$OPENWEBUI_PORT" > "$SESHAT_DIR/open-webui/.puerto"

  log "Esperando que Open WebUI arranque (la primera vez puede tardar 1-2 minutos)..."
  for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${OPENWEBUI_PORT}" >/dev/null 2>&1; then
      break
    fi
    sleep 3
  done

  if curl -fsS "http://127.0.0.1:${OPENWEBUI_PORT}" >/dev/null 2>&1; then
    ok "Open WebUI instalado y funcionando."
  else
    warn "Open WebUI aun no responde; revisa el estado en unos minutos (opcion Estado)."
  fi
  show_openwebui_notes
}

show_openwebui_notes() {
  local puerto="$OPENWEBUI_PORT"
  [ -r "$SESHAT_DIR/open-webui/.puerto" ] && puerto="$(cat "$SESHAT_DIR/open-webui/.puerto")"
  cat <<EOF

Open WebUI:
  Abrir en el navegador: http://$(openwebui_ip):${puerto}
  1) La PRIMERA cuenta que crees sera la del administrador: creala de inmediato.
  2) Luego, en Panel de administracion -> Configuracion -> General, puedes desactivar
     el registro de nuevos usuarios.
  Datos (usuarios y chats): $SESHAT_DIR/open-webui
  No abras este puerto a internet sin un proxy con HTTPS.
EOF
}

status_openwebui() {
  printf '\nOpen WebUI:\n'
  if ! openwebui_existe; then
    warn "Open WebUI no esta instalado."
    return 0
  fi
  docker ps -a --filter "name=^${OPENWEBUI_NAME}$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$OPENWEBUI_NAME" 2>/dev/null | grep -E '^OLLAMA_BASE_URL=' || true
  show_openwebui_notes
}

update_openwebui() {
  if ! openwebui_existe; then
    warn "Open WebUI no esta instalado."
    return 0
  fi
  local puerto="$OPENWEBUI_PORT" url red
  [ -r "$SESHAT_DIR/open-webui/.puerto" ] && puerto="$(cat "$SESHAT_DIR/open-webui/.puerto")"
  url="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$OPENWEBUI_NAME" | sed -n 's/^OLLAMA_BASE_URL=//p')"
  red="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$OPENWEBUI_NAME")"

  log "Actualizando Open WebUI (los usuarios y chats se conservan)..."
  docker pull "$OPENWEBUI_IMAGE"
  docker rm -f "$OPENWEBUI_NAME" >/dev/null
  if [ "$red" = "host" ]; then
    docker run -d --name "$OPENWEBUI_NAME" --restart unless-stopped --network host -e PORT="$puerto" \
      -e OLLAMA_BASE_URL="$url" -v "$SESHAT_DIR/open-webui:/app/backend/data" "$OPENWEBUI_IMAGE" >/dev/null
  elif [ "$red" != "default" ] && [ "$red" != "bridge" ]; then
    docker run -d --name "$OPENWEBUI_NAME" --restart unless-stopped --network "$red" -p "${puerto}:8080" \
      -e OLLAMA_BASE_URL="$url" -v "$SESHAT_DIR/open-webui:/app/backend/data" "$OPENWEBUI_IMAGE" >/dev/null
  else
    docker run -d --name "$OPENWEBUI_NAME" --restart unless-stopped -p "${puerto}:8080" \
      -e OLLAMA_BASE_URL="$url" -v "$SESHAT_DIR/open-webui:/app/backend/data" "$OPENWEBUI_IMAGE" >/dev/null
  fi
  ok "Open WebUI actualizado."
}

uninstall_openwebui() {
  if ! openwebui_existe; then
    warn "Open WebUI no esta instalado."
    return 0
  fi
  log "Deteniendo y eliminando el contenedor $OPENWEBUI_NAME..."
  docker rm -f "$OPENWEBUI_NAME" >/dev/null || true
  local borrar
  read -r -p "¿Borrar usuarios y chats de Open WebUI en $SESHAT_DIR/open-webui? [s/N]: " borrar
  case "$borrar" in
    s|S|si|SI|Si)
      rm -rf "$SESHAT_DIR/open-webui"
      ok "Datos de Open WebUI eliminados."
      ;;
    *)
      ok "Datos conservados en $SESHAT_DIR/open-webui (se reutilizan si lo instalas de nuevo)."
      ;;
  esac
  read -r -p "¿Borrar tambien la imagen descargada (libera varios GB)? [s/N]: " borrar
  case "$borrar" in
    s|S|si|SI|Si) docker rmi "$OPENWEBUI_IMAGE" >/dev/null 2>&1 || true; ok "Imagen eliminada." ;;
  esac
}

menu_openwebui() {
  while true; do
    printf '\n'
    printf "${CYAN}=== Open WebUI (chat web para Ollama) ===${RESET}\n"
    printf "${YELLOW}1)${RESET} ${CYAN}Instalar Open WebUI${RESET}\n"
    printf "${YELLOW}2)${RESET} ${CYAN}Ver estado y direccion web${RESET}\n"
    printf "${YELLOW}3)${RESET} ${CYAN}Actualizar Open WebUI${RESET}\n"
    printf "${YELLOW}4)${RESET} ${CYAN}Desinstalar Open WebUI${RESET}\n"
    printf "${YELLOW}0)${RESET} ${CYAN}Volver${RESET}\n"
    local op
    read -r -p "Elige una opcion: " op
    case "$op" in
      1) install_openwebui ;;
      2) status_openwebui ;;
      3) update_openwebui ;;
      4) uninstall_openwebui ;;
      0|"") return 0 ;;
      *) warn "Opcion no valida." ;;
    esac
  done
}

# ===================== GESTIONAR MODELOS (Ollama ya instalado) =====================
# Descarga, prueba, borra y libera modelos en el Ollama que ya funciona (Docker o tradicional),
# sin reinstalar. Recomienda modelos segun la RAM del equipo.

# Ejecuta "ollama ..." donde corresponda (contenedor seshat-ollama o servicio del host).
ollama_exec() {
  case "$(ollama_modo_instalado)" in
    docker)
      if [ -t 0 ] && [ -t 1 ]; then
        docker exec -it seshat-ollama ollama "$@"
      else
        docker exec -i seshat-ollama ollama "$@"
      fi
      ;;
    tradicional) ollama "$@" ;;
    *) err "No se encontro Ollama instalado (ni Docker seshat-ollama ni servicio ollama)."; return 1 ;;
  esac
}

ram_gb() {   # $1 = MemTotal o MemAvailable -> GB con un decimal
  awk -v k="$1" '$1 == k":" {printf "%.1f", $2 / 1024 / 1024}' /proc/meminfo 2>/dev/null
}

# Lista los nombres de los modelos instalados en MODELOS_INSTALADOS (array).
modelos_cargar_lista() {
  MODELOS_INSTALADOS=()
  local salida
  salida="$(ollama_exec list 2>/dev/null || true)"
  mapfile -t MODELOS_INSTALADOS < <(printf '%s\n' "$salida" | awk 'NR > 1 && $1 != "" {print $1}')
}

# Muestra los modelos instalados numerados y deja el elegido en MODELO_ELEGIDO ("" si cancela).
modelos_elegir_instalado() {
  MODELO_ELEGIDO=""
  modelos_cargar_lista
  if [ "${#MODELOS_INSTALADOS[@]}" -eq 0 ]; then
    warn "No hay modelos instalados."
    return 0
  fi
  local i n
  for i in "${!MODELOS_INSTALADOS[@]}"; do
    printf "${YELLOW}%d)${RESET} ${CYAN}%s${RESET}\n" "$((i + 1))" "${MODELOS_INSTALADOS[$i]}"
  done
  read -r -p "Numero del modelo (ENTER = cancelar): " n
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#MODELOS_INSTALADOS[@]}" ]; then
    MODELO_ELEGIDO="${MODELOS_INSTALADOS[$((n - 1))]}"
  fi
}

modelos_listar() {
  printf '\n'
  printf '  RAM total: %s GB | disponible ahora: %s GB\n\n' "$(ram_gb MemTotal)" "$(ram_gb MemAvailable)"
  log "Modelos instalados:"
  ollama_exec list || true
  printf '\n'
  log "Modelos cargados en memoria ahora:"
  ollama_exec ps || true
}

# Guarda el modelo elegido como el sugerido para Seshat (ollama-seshat.env).
modelos_marcar_para_seshat() {
  local m="$1"
  MODEL="$m"
  if [ -f "$SESHAT_DIR/ollama-seshat.env" ]; then
    sed -i "s|^SESHAT_OLLAMA_MODEL=.*|SESHAT_OLLAMA_MODEL=${m}|" "$SESHAT_DIR/ollama-seshat.env"
  fi
  ok "Modelo para Seshat: $m  (en Seshat: Ajustes -> Inteligencia artificial -> Ollama -> Modelo)"
}

modelos_descargar() {
  local total op m necesita
  total="$(ram_gb MemTotal)"
  printf '\n'
  printf "${CYAN}Descargar modelo (RAM de este equipo: %s GB; deja ~2 GB para el sistema)${RESET}\n" "$total"
  printf "${YELLOW}1)${RESET} ${CYAN}qwen2.5:1.5b   ~1.5 GB RAM  muy liviano, el mas rapido${RESET}\n"
  printf "${YELLOW}2)${RESET} ${CYAN}qwen2.5:3b     ~2.5 GB RAM  liviano, buen espanol (equipos de 8 GB)${RESET}\n"
  printf "${YELLOW}3)${RESET} ${CYAN}llama3.2:3b    ~2.5 GB RAM  liviano${RESET}\n"
  printf "${YELLOW}4)${RESET} ${CYAN}qwen3.5:4b     ~3.5 GB RAM  equilibrado (equipos de 8 GB)${RESET}\n"
  printf "${YELLOW}5)${RESET} ${CYAN}qwen3:4b       ~3.5 GB RAM  equilibrado (alternativa a qwen3.5:4b)${RESET}\n"
  printf "${YELLOW}6)${RESET} ${CYAN}llama3.1:8b    ~6 GB RAM    mejor calidad (16 GB recomendado)${RESET}\n"
  printf "${YELLOW}7)${RESET} ${CYAN}qwen3.5:9b     ~7 GB RAM    mejor calidad (16 GB recomendado)${RESET}\n"
  printf "${YELLOW}8)${RESET} ${CYAN}Escribir otro modelo${RESET}\n"
  printf "${YELLOW}0)${RESET} ${CYAN}Volver${RESET}\n"
  read -r -p "Elige modelo: " op
  case "$op" in
    1) m="qwen2.5:1.5b"; necesita=1.5 ;;
    2) m="qwen2.5:3b";   necesita=2.5 ;;
    3) m="llama3.2:3b";  necesita=2.5 ;;
    4) m="qwen3.5:4b";   necesita=3.5 ;;
    5) m="qwen3:4b";     necesita=3.5 ;;
    6) m="llama3.1:8b";  necesita=6 ;;
    7) m="qwen3.5:9b";   necesita=7 ;;
    8)
      read -r -p "Nombre del modelo (ver ollama.com/library): " m
      if ! [[ "$m" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]{1,119}$ ]]; then
        err "Nombre de modelo invalido."
        return 0
      fi
      necesita=0
      ;;
    *) return 0 ;;
  esac

  if awk -v t="$total" -v n="$necesita" 'BEGIN {exit !(n > 0 && n + 2 > t)}'; then
    warn "$m necesita ~${necesita} GB de RAM y este equipo tiene ${total} GB en total: puede no cargar o ir muy lento."
    local resp
    read -r -p "¿Descargarlo de todas formas? [s/N]: " resp
    case "$resp" in s|S|si|SI|Si) ;; *) return 0 ;; esac
  fi

  log "Descargando $m (puede tardar varios minutos)..."
  if ollama_exec pull "$m"; then
    ok "Modelo $m descargado."
    modelos_marcar_para_seshat "$m"
    local probar
    read -r -p "¿Probar su velocidad ahora? [S/n]: " probar
    case "$probar" in n|N|no|NO) ;; *) modelos_probar_nombre "$m" ;; esac
  else
    err "No se pudo descargar $m."
    case "$m" in
      qwen3.5:*) warn "Si el nombre no existe, prueba la alternativa qwen3:4b (opcion 5)." ;;
    esac
  fi
}

# Prueba de velocidad: pide un saludo corto y mide carga, palabras (tokens) por segundo y tiempo total.
modelos_probar_nombre() {
  local m="$1" resp tokens eval_ns load_ns total_ns tps texto
  printf '\n'
  log "Probando $m (la primera vez carga el modelo en memoria; espera hasta 10 minutos)..."
  resp="$(curl -sS --max-time 600 "http://127.0.0.1:${OLLAMA_PORT}/api/generate" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${m}\",\"prompt\":\"Hola, responde en una sola frase corta en espanol.\",\"stream\":false,\"options\":{\"num_predict\":60}}" 2>&1 || true)"

  if ! printf '%s' "$resp" | grep -q '"eval_count"'; then
    err "El modelo no respondio a tiempo o fallo:"
    printf '  %s\n' "$(printf '%s' "$resp" | head -c 300)"
    warn "Revisa la RAM disponible (opcion 1 de este menu) y el registro de Ollama."
    return 0
  fi

  tokens="$(printf '%s' "$resp" | grep -o '"eval_count":[0-9]*' | head -1 | cut -d: -f2)"
  eval_ns="$(printf '%s' "$resp" | grep -o '"eval_duration":[0-9]*' | head -1 | cut -d: -f2)"
  load_ns="$(printf '%s' "$resp" | grep -o '"load_duration":[0-9]*' | head -1 | cut -d: -f2)"
  total_ns="$(printf '%s' "$resp" | grep -o '"total_duration":[0-9]*' | head -1 | cut -d: -f2)"
  texto="$(printf '%s' "$resp" | sed -n 's/.*"response":"\([^"]*\)".*/\1/p' | head -c 200)"
  tps="$(awk -v t="${tokens:-0}" -v d="${eval_ns:-1}" 'BEGIN {printf "%.1f", (d > 0 ? t / (d / 1e9) : 0)}')"

  printf '  Respuesta: %s\n' "${texto:-(sin texto)}"
  printf '  Carga del modelo: %s s | Tiempo total: %s s | Velocidad: %s tokens/s\n' \
    "$(awk -v n="${load_ns:-0}" 'BEGIN {printf "%.1f", n / 1e9}')" \
    "$(awk -v n="${total_ns:-0}" 'BEGIN {printf "%.1f", n / 1e9}')" "$tps"

  if awk -v v="$tps" 'BEGIN {exit !(v >= 5)}'; then
    ok "Velocidad adecuada para Seshat (pruebas de 5-10 preguntas en 1-3 minutos)."
  elif awk -v v="$tps" 'BEGIN {exit !(v >= 2)}'; then
    warn "Lento: en Seshat pide pocas preguntas (3-5) por generacion, o usa un modelo mas liviano."
  else
    err "Demasiado lento para Seshat: usa un modelo mas liviano (qwen2.5:3b o qwen2.5:1.5b)."
  fi
}

modelos_probar() {
  printf '\n'
  log "Elige el modelo a probar:"
  modelos_elegir_instalado
  [ -n "$MODELO_ELEGIDO" ] || return 0
  modelos_probar_nombre "$MODELO_ELEGIDO"
  local usar
  read -r -p "¿Usar $MODELO_ELEGIDO como modelo para Seshat? [s/N]: " usar
  case "$usar" in s|S|si|SI|Si) modelos_marcar_para_seshat "$MODELO_ELEGIDO" ;; esac
}

modelos_borrar() {
  printf '\n'
  log "Elige el modelo a BORRAR (libera espacio en disco):"
  modelos_elegir_instalado
  [ -n "$MODELO_ELEGIDO" ] || return 0
  local resp
  read -r -p "¿Borrar $MODELO_ELEGIDO? Si Seshat lo usa, dejara de funcionar hasta cambiar el modelo. [s/N]: " resp
  case "$resp" in
    s|S|si|SI|Si)
      if ollama_exec rm "$MODELO_ELEGIDO"; then
        ok "Modelo $MODELO_ELEGIDO borrado."
      else
        err "No se pudo borrar $MODELO_ELEGIDO."
      fi
      ;;
  esac
}

# Saca de la RAM los modelos cargados (vuelven a cargarse solos en el siguiente uso).
modelos_liberar_memoria() {
  printf '\n'
  local cargados m
  cargados="$(ollama_exec ps 2>/dev/null | awk 'NR > 1 && $1 != "" {print $1}' || true)"
  if [ -z "$cargados" ]; then
    ok "No hay modelos cargados en memoria."
  else
    for m in $cargados; do
      ollama_exec stop "$m" >/dev/null 2>&1 && ok "Modelo $m descargado de la memoria." || warn "No se pudo descargar $m de la memoria."
    done
  fi
  printf '  RAM disponible ahora: %s GB\n' "$(ram_gb MemAvailable)"
}

menu_modelos() {
  if [ "$(ollama_modo_instalado)" = "ninguno" ]; then
    err "No se encontro Ollama instalado. Instalalo primero (opcion 2 o 3)."
    return 0
  fi
  while true; do
    printf '\n'
    printf "${CYAN}=== Gestionar modelos de Ollama (%s) ===${RESET}\n" "$(ollama_modo_instalado)"
    printf "${YELLOW}1)${RESET} ${CYAN}Ver modelos instalados y RAM${RESET}\n"
    printf "${YELLOW}2)${RESET} ${CYAN}Descargar / cambiar modelo${RESET}\n"
    printf "${YELLOW}3)${RESET} ${CYAN}Probar velocidad de un modelo${RESET}\n"
    printf "${YELLOW}4)${RESET} ${CYAN}Borrar un modelo${RESET}\n"
    printf "${YELLOW}5)${RESET} ${CYAN}Liberar memoria (descargar modelos de la RAM)${RESET}\n"
    printf "${YELLOW}0)${RESET} ${CYAN}Volver${RESET}\n"
    local op
    read -r -p "Elige una opcion: " op
    case "$op" in
      1) modelos_listar ;;
      2) modelos_descargar ;;
      3) modelos_probar ;;
      4) modelos_borrar ;;
      5) modelos_liberar_memoria ;;
      0|"") return 0 ;;
      *) warn "Opcion no valida." ;;
    esac
  done
}

menu_modelo() {
  printf '\n'
  printf "${CYAN}Modelo actual: %s${RESET}\n" "$MODEL"
  printf "${YELLOW}1)${RESET} ${CYAN}qwen3.5:9b   recomendado para crear pruebas con base curricular${RESET}\n"
  printf "${YELLOW}2)${RESET} ${CYAN}llama3.1:8b  mas liviano, buen contexto largo${RESET}\n"
  printf "${YELLOW}3)${RESET} ${CYAN}qwen3.5:4b   mas liviano para servidores modestos${RESET}\n"
  printf "${YELLOW}4)${RESET} ${CYAN}escribir otro modelo${RESET}\n"
  printf "${YELLOW}0)${RESET} ${CYAN}Volver${RESET}\n"
  read -r -p "Elige modelo: " choice

  case "$choice" in
    1) MODEL="qwen3.5:9b" ;;
    2) MODEL="llama3.1:8b" ;;
    3) MODEL="qwen3.5:4b" ;;
    4)
      read -r -p "Nombre del modelo Ollama: " custom_model
      if [ -n "$custom_model" ]; then MODEL="$custom_model"; fi
      ;;
    0|"") ;;
    *) warn "Opcion no valida; se mantiene $MODEL." ;;
  esac
}

interactive_menu() {
  while true; do
    printf '\n'
    printf "${CYAN}=================================================${RESET}\n"
    printf "${CYAN}  Instalador de Ollama para Seshat - Debian 12${RESET}\n"
    printf "${CYAN}=================================================${RESET}\n"
    printf "${CYAN}Modelo actual: %s${RESET}\n\n" "$MODEL"
    printf "${YELLOW}1)${RESET} ${CYAN}Instalar dependencias base${RESET}\n"
    printf "${YELLOW}2)${RESET} ${CYAN}Instalar con Docker para Seshat${RESET}\n"
    printf "${YELLOW}3)${RESET} ${CYAN}Instalar tradicional en Debian${RESET}\n"
    printf "${YELLOW}4)${RESET} ${CYAN}Elegir modelo para la proxima instalacion${RESET}\n"
    printf "${YELLOW}5)${RESET} ${CYAN}Ver estado, IP y puerto${RESET}\n"
    printf "${YELLOW}6)${RESET} ${CYAN}Reiniciar Ollama Docker${RESET}\n"
    printf "${YELLOW}7)${RESET} ${CYAN}Reiniciar Ollama tradicional${RESET}\n"
    printf "${YELLOW}8)${RESET} ${CYAN}Desinstalar Ollama Docker${RESET}\n"
    printf "${YELLOW}9)${RESET} ${CYAN}Desinstalar Ollama tradicional${RESET}\n"
    printf "${YELLOW}10)${RESET} ${CYAN}Diagnostico Docker Ollama${RESET}\n"
    printf "${YELLOW}11)${RESET} ${CYAN}Ver ayuda${RESET}\n"
    printf "${YELLOW}12)${RESET} ${CYAN}Verificar compatibilidad del CPU${RESET}\n"
    printf "${YELLOW}13)${RESET} ${CYAN}Open WebUI (chat web para Ollama)${RESET}\n"
    printf "${YELLOW}14)${RESET} ${CYAN}Acceso desde la red (LAN): abrir / dejar solo local${RESET}\n"
    printf "${YELLOW}15)${RESET} ${CYAN}Proteger con token (proxy nginx, puerto ${TOKEN_PORT})${RESET}\n"
    printf "${YELLOW}16)${RESET} ${CYAN}Gestionar modelos (ver / descargar / probar / borrar)${RESET}\n"
    printf "${YELLOW}0)${RESET} ${CYAN}Salir${RESET}\n"
    read -r -p "Elige una opcion: " option

    case "$option" in
      1) install_base_packages ;;
      2) menu_modelo; install_docker_mode; [ "$CANCELADO" = "1" ] || show_final_notes ;;
      3) menu_modelo; install_traditional_mode; [ "$CANCELADO" = "1" ] || show_final_notes ;;
      4) menu_modelo ;;
      5) show_status_menu ;;
      6) restart_docker_mode ;;
      7) restart_traditional_mode ;;
      8) uninstall_docker_mode ;;
      9) uninstall_traditional_mode ;;
      10) show_docker_diagnostics ;;
      11) usage ;;
      12) printf '\n'; check_cpu "$(virt_actual)"; printf '\n' ;;
      13) menu_openwebui ;;
      14) menu_lan ;;
      15) menu_token ;;
      16) menu_modelos ;;
      0) exit 0 ;;
      *) warn "Opcion no valida." ;;
    esac
  done
}

main() {
  # Verificar el CPU no requiere sudo ni instala nada.
  if [ "$MODE" = "verificar-cpu" ]; then
    printf '\n'
    log "Verificando compatibilidad del procesador con Ollama..."
    check_cpu "$(virt_actual)"
    exit "$CPU_STATUS"
  fi

  require_root
  detect_debian

  if [ -z "$MODE" ]; then
    interactive_menu
  fi

  case "$MODE" in
    openwebui)
      install_openwebui
      exit 0
      ;;
    docker)
      install_docker_mode
      ;;
    tradicional)
      install_traditional_mode
      ;;
    *)
      err "Modo invalido: $MODE"
      exit 1
      ;;
  esac

  if [ "$CANCELADO" = "1" ]; then
    exit 2
  fi
  show_final_notes
}

main "$@"
