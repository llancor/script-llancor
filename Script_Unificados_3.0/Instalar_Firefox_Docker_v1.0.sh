#!/bin/bash

# ==================================================
# COLORES
# ==================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

# ==================================================
# FUNCIONES BASE DE LOGS
# ==================================================

success() { echo -e "${GREEN}[OK] $1${NC}"; }
error()   { echo -e "${RED}[ERROR] $1${NC}"; }
warning() { echo -e "${YELLOW}[WARN] $1${NC}"; }
info()    { echo -e "${CYAN}[INFO] $1${NC}"; }

# ==================================================
# CONFIG
# ==================================================

CONTAINER="firefox"
IMAGE="jlesage/firefox"
PORT="3456"
TZ="America/Santiago"

FALTANTES=()

DEPENDENCIAS=(
    curl
    wget
    ca-certificates
    gnupg
    nano
    tar
    gzip
    apparmor
    apparmor-utils
)

# ==================================================
# VERIFICAR DEPENDENCIAS
# ==================================================

verificar_dependencias() {

    FALTANTES=()

    echo
    info "Verificando dependencias..."

    for dep in "${DEPENDENCIAS[@]}"; do
        if dpkg -l 2>/dev/null | grep -q "ii  $dep "; then
            success "$dep"
        else
            warning "$dep no instalado"
            FALTANTES+=("$dep")
        fi
    done

    if command -v docker >/dev/null 2>&1; then
        success "docker"
    else
        warning "docker no instalado"
        FALTANTES+=("docker.io")
    fi

    echo

    if [ ${#FALTANTES[@]} -gt 0 ]; then
        warning "Faltan dependencias:"
        printf ' - %s\n' "${FALTANTES[@]}"
    else
        success "Todas las dependencias instaladas"
    fi

    echo
}

# ==================================================
# INSTALAR DOCKER
# ==================================================

instalar_docker() {

    if command -v docker >/dev/null 2>&1; then
        success "Docker ya está instalado"
        return
    fi

    info "Instalando Docker..."

    curl -fsSL https://get.docker.com | sh || {
        error "Error instalando Docker"
        return 1
    }

    success "Docker instalado"
}

# ==================================================
# INSTALAR DEPENDENCIAS
# ==================================================

instalar_dependencias() {

    if ! command -v docker >/dev/null 2>&1; then
        instalar_docker || return 1
    fi

    if [ ${#FALTANTES[@]} -eq 0 ]; then
        success "No hay dependencias para instalar"
        return
    fi

    info "Actualizando repositorios..."
    apt update -y || return 1

    info "Instalando dependencias..."
    apt install -y "${FALTANTES[@]}" || {
        error "Error instalando dependencias"
        return 1
    }

    success "Dependencias instaladas"
}

start_docker_if_needed() {

    if ! systemctl is-active --quiet docker; then
        info "Docker no está activo. Iniciando..."
        systemctl start docker || {
            error "No se pudo iniciar Docker"
            return 1
        }
    fi

    success "Docker activo"
}
# ==================================================
# INSTALAR FIREFOX
# ==================================================

install_firefox() {
start_docker_if_needed
    info "Verificando dependencias..."
    verificar_dependencias
    instalar_dependencias

    if ! command -v docker >/dev/null 2>&1; then
        error "Docker no disponible"
        return 1
    fi

    if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER$"; then
        warning "Eliminando contenedor existente..."
        docker rm -f "$CONTAINER" >/dev/null 2>&1
    fi

    info "Instalando Firefox..."

    docker run -d \
      --name="$CONTAINER" \
      -p "$PORT:5800" \
      -e TZ="$TZ" \
      --restart unless-stopped \
      "$IMAGE" || {
        error "Error al crear contenedor"
        return 1
    }

    success "Firefox instalado"

    IP=$(hostname -I | awk '{print $1}')
    echo
    success "URL: http://$IP:$PORT"
    echo
}

function uninstall_firefox() {
    echo "🗑️ Eliminando Firefox..."
    docker rm -f $CONTAINER 2>/dev/null
    echo "✅ Firefox eliminado"
}

function start_firefox() {
    docker start $CONTAINER
    echo "▶️ Firefox iniciado"
}

function stop_firefox() {
    docker stop $CONTAINER
    echo "⏹️ Firefox detenido"
}

function restart_firefox() {
    docker restart $CONTAINER
    echo "🔄 Firefox reiniciado"
}

function status_firefox() {
    echo "📊 Estado de Firefox:"
    docker ps -a | grep $CONTAINER

    echo ""
    if docker ps | grep -q $CONTAINER; then
        echo "🟢 Estado: EN EJECUCIÓN"
    else
        echo "🔴 Estado: DETENIDO"
    fi
}

function url_firefox() {
    IP=$(hostname -I | awk '{print $1}')
    echo "🌐 URL Firefox:"
    echo "http://$IP:$PORT"
}

function logs_firefox() {
    docker logs -f $CONTAINER
}

while true; do
    clear
echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}        FIREFOX DOCKER MANAGER        ${NC}"
echo -e "${CYAN}======================================${NC}"

echo -e "${YELLOW}1) ${NC}Instalar Dependencias / Firefox${NC}"
echo -e "${YELLOW}2) ${NC}Desinstalar Firefox${NC}"
echo -e "${YELLOW}3) ${NC}Iniciar Firefox${NC}"
echo -e "${YELLOW}4) ${NC}Detener Firefox${NC}"
echo -e "${YELLOW}5) ${NC}Reiniciar Firefox${NC}"
echo -e "${YELLOW}6) ${NC}Estado${NC}"
echo -e "${YELLOW}7) ${NC}Ver URL${NC}"
echo -e "${YELLOW}8) ${NC}Ver logs${NC}"
echo -e "${YELLOW}0) ${CYAN}Salir${NC}"

echo -e "${CYAN}======================================${NC}"
    read -p "Seleccione opción: " opt

    case $opt in
        1) install_firefox ;;
        2) uninstall_firefox ;;
        3) start_firefox ;;
        4) stop_firefox ;;
        5) restart_firefox ;;
        6) status_firefox ;;
        7) url_firefox ;;
        8) logs_firefox ;;
        0) exit 0 ;;
        *) echo "❌ Opción inválida"; sleep 1 ;;
    esac

    read -p "Enter para continuar..."
done
