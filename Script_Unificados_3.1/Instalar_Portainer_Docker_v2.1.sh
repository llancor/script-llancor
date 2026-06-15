#!/bin/bash
BLUE='\033[0;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}
question() {
    echo -e "${YELLOW}[?]${NC} $1"
}

title() {
    echo -e "${BLUE}=== $1 ===${NC}"
}
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}
PORTAINER_NAME=portainer
PORTAINER_PORT=9000

FALTANTES=()

header() {
clear
echo -e "${CYAN}"
echo "=================================================="
echo " PORTAINER MANAGER"
echo "=================================================="
echo -e "${NC}"
}

success() {
echo -e "${GREEN}[OK]${NC} $1"
}

warning() {
echo -e "${YELLOW}[AVISO]${NC} $1"
}

error() {
echo -e "${RED}[ERROR]${NC} $1"
}

pause() {
echo
read -rp "Presione ENTER para continuar..."
}

verificar_dependencias() {

FALTANTES=()

if [ "$EUID" -ne 0 ]; then
    error "Debe ejecutar este script como root"
    return 1
fi

success "Usuario root"

DEPENDENCIAS=(
    curl
    ca-certificates
    gnupg
	apparmor
    apparmor-utils
	nano
)

echo

for dep in "${DEPENDENCIAS[@]}"; do
    if dpkg -s "$dep" >/dev/null 2>&1; then
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
    FALTANTES+=(docker.io)
fi

echo

if [ ${#FALTANTES[@]} -gt 0 ]; then
    warning "Se instalarán:"
    printf ' - %s\n' "${FALTANTES[@]}"
else
    success "Todas las dependencias instaladas"
fi

echo

if command -v docker >/dev/null 2>&1; then
    if systemctl is-active --quiet docker; then
        success "Docker ejecutándose"
    else
        warning "Docker detenido"
    fi
fi

}

mostrar_url() {

IP=$(hostname -I | awk '{print $1}')

echo
echo "URL DE ACCESO"
echo
echo "http://$IP:$PORTAINER_PORT"
echo

}

instalar_portainer() {

    header

    verificar_dependencias || return

    echo
    read -rp "¿Continuar con la instalación? [S/n]: " RESP

    if [[ "$RESP" =~ ^[Nn]$ ]]; then
        return
    fi

    if [ ${#FALTANTES[@]} -gt 0 ]; then

        echo
        info "Instalando dependencias faltantes..."

        apt update || {
            error "Error al actualizar repositorios"
            pause
            return 1
        }

        apt install -y "${FALTANTES[@]}" || {
            error "Error al instalar dependencias"
            pause
            return 1
        }
    fi

    systemctl enable docker >/dev/null 2>&1
    systemctl start docker

    echo
    info "Verificando Docker..."

    if ! docker info >/dev/null 2>&1; then

        error "Docker no está funcionando correctamente"

        echo
        echo "Posibles causas:"
        echo "- Docker detenido"
        echo "- AppArmor incompleto"
        echo "- Error de configuración del daemon"
        echo

        pause
        return 1
    fi

    success "Docker operativo"

    if docker ps -a --format '{{.Names}}' | grep -q "^${PORTAINER_NAME}$"; then

        warning "Portainer ya está instalado"

        if docker ps --format '{{.Names}}' | grep -q "^${PORTAINER_NAME}$"; then
            success "Portainer está ejecutándose"
        else
            warning "Portainer existe pero está detenido"
        fi

        pause
        return
    fi

    echo
    info "Creando volumen..."

    docker volume create portainer_data >/dev/null 2>&1

    echo
    info "Instalando Portainer..."

    if ! docker run -d \
        --name "$PORTAINER_NAME" \
        --restart unless-stopped \
        -p 8000:8000 \
        -p "$PORTAINER_PORT":9000 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest
    then

        error "Error al crear el contenedor Portainer"

        echo
        echo "Verifique los mensajes de Docker."
        echo

        pause
        return 1
    fi

    sleep 5

    if docker ps --format '{{.Names}}' | grep -q "^${PORTAINER_NAME}$"; then

        success "Portainer instalado correctamente"

        mostrar_url

    else

        error "Portainer no inició correctamente"

        echo
        echo "Últimos logs:"
        echo "----------------------------------------"

        docker logs "$PORTAINER_NAME" --tail 30 2>/dev/null

        echo "----------------------------------------"

        pause
        return 1
    fi

    pause
}

desinstalar_portainer() {

header

docker stop $PORTAINER_NAME 2>/dev/null || true
docker rm $PORTAINER_NAME 2>/dev/null || true

read -rp "¿Eliminar también los datos? (s/N): " RESP

if [[ "$RESP" =~ ^[Ss]$ ]]; then
    docker volume rm portainer_data 2>/dev/null || true
fi

success "Portainer desinstalado"

pause

}

estado_portainer() {

header

docker ps -a --filter "name=$PORTAINER_NAME"

echo
systemctl status docker --no-pager

pause

}

reiniciar_portainer() {

header

docker restart $PORTAINER_NAME

success "Portainer reiniciado"

pause

}

reiniciar_docker() {

header

systemctl restart docker

success "Docker reiniciado"

pause

}

ver_logs() {

header

docker logs --tail 100 $PORTAINER_NAME

pause

}

actualizar_portainer() {

    header

    echo
    echo "Actualizando Portainer..."
    echo

    docker pull portainer/portainer-ce:latest || {

        echo
        echo "Error descargando la imagen."
        echo

        pause
        return 1

    }

    docker stop "$PORTAINER_NAME" 2>/dev/null || true
    docker rm "$PORTAINER_NAME" 2>/dev/null || true

    docker run -d \
        --name "$PORTAINER_NAME" \
        --restart unless-stopped \
        -p 8000:8000 \
        -p "$PORTAINER_PORT":9000 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest

    sleep 5

    if docker ps --format '{{.Names}}' | grep -q "^${PORTAINER_NAME}$"; then

        success "Portainer actualizado correctamente"

    else

        echo
        echo "Error al iniciar Portainer."
        echo

        docker logs "$PORTAINER_NAME" --tail 50

    fi

    pause

}

while true; do

header

echo
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}       GESTOR DE PORTAINER v2.1         ${NC}"
echo -e "${CYAN}========================================${NC}"
echo

echo -e "${YELLOW}[1]${NC} ${CYAN}Verificar dependencias${NC}"
echo -e "${YELLOW}[2]${NC} ${CYAN}Instalar Portainer${NC}"
echo -e "${YELLOW}[3]${NC} ${CYAN}Desinstalar Portainer${NC}"
echo -e "${YELLOW}[4]${NC} ${CYAN}Ver estado${NC}"
echo -e "${YELLOW}[5]${NC} ${CYAN}Reiniciar Portainer${NC}"
echo -e "${YELLOW}[6]${NC} ${CYAN}Ver logs${NC}"
echo -e "${YELLOW}[7]${NC} ${CYAN}Actualizar Portainer${NC}"
echo -e "${YELLOW}[8]${NC} ${CYAN}Reiniciar Docker${NC}"
echo -e "${YELLOW}[9]${NC} ${CYAN}Mostrar URL${NC}"
echo
echo -e "${YELLOW}[0]${NC} ${RED}Salir${NC}"
echo

read -rp "Seleccione una opción: " OPCION

case $OPCION in
    1) verificar_dependencias; pause ;;
    2) instalar_portainer ;;
    3) desinstalar_portainer ;;
    4) estado_portainer ;;
    5) reiniciar_portainer ;;
    6) ver_logs ;;
    7) actualizar_portainer ;;
    8) reiniciar_docker ;;
    9) mostrar_url; pause ;;
    0) exit 0 ;;
    *) error "Opción inválida"; sleep 2 ;;
esac

done