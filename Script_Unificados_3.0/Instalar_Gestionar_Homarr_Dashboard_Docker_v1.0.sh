#!/bin/bash

# ==========================================================
# HOMARR MANAGER v1.0
# Debian 12 / 13
# ==========================================================

HOMARR_DIR="/opt/homarr"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
CYAN="\e[1;36m"

header() {
    clear
    echo -e "${CYAN}"
    echo "========================================="
    echo "           HOMARR MANAGER"
    echo "========================================="
    echo -e "${NC}"
}

pause() {
    read -rp "Presione ENTER para continuar..."
}

instalar_dependencias() {

    header

    echo "Verificando dependencias..."
    echo

    if command -v docker >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Docker ya está instalado${NC}"
        DOCKER_OK=1
    else
        echo -e "${YELLOW}✗ Docker no encontrado${NC}"
        DOCKER_OK=0
    fi

    if docker compose version >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Docker Compose ya está instalado${NC}"
        COMPOSE_OK=1
    else
        echo -e "${YELLOW}✗ Docker Compose no encontrado${NC}"
        COMPOSE_OK=0
    fi

    if [ "$DOCKER_OK" = "1" ] && [ "$COMPOSE_OK" = "1" ]; then
        echo
        echo -e "${GREEN}Todas las dependencias ya están instaladas.${NC}"
        pause
        return
    fi

    echo
    echo -e "${YELLOW}Instalando dependencias faltantes...${NC}"

    apt update

    apt install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then

        install -m 0755 -d /etc/apt/keyrings

        curl -fsSL https://download.docker.com/linux/debian/gpg \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

        chmod a+r /etc/apt/keyrings/docker.gpg

    fi

    if [ ! -f /etc/apt/sources.list.d/docker.list ]; then

        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
          https://download.docker.com/linux/debian \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
          > /etc/apt/sources.list.d/docker.list

    fi

    apt update

    apt install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    echo
    docker --version
    docker compose version

    echo
    echo -e "${GREEN}Dependencias instaladas correctamente.${NC}"

    pause
}

instalar_homarr() {
instalar_dependencias
    header

    if docker ps -a --format '{{.Names}}' | grep -q "^homarr$"; then
        echo -e "${YELLOW}Homarr ya está instalado.${NC}"
        pause
        return
    fi

    mkdir -p "$HOMARR_DIR"

    SECRET_KEY=$(openssl rand -hex 32)

    cat > "$HOMARR_DIR/docker-compose.yml" <<EOF
services:
  homarr:
    image: ghcr.io/homarr-labs/homarr:latest
    container_name: homarr
    restart: unless-stopped

    ports:
      - "7575:7575"

    environment:
      SECRET_ENCRYPTION_KEY: "$SECRET_KEY"

    volumes:
      - homarr_appdata:/appdata

volumes:
  homarr_appdata:
EOF

    cd "$HOMARR_DIR" || exit 1

    docker compose up -d

    sleep 10

    IP=$(hostname -I | awk '{print $1}')

    echo
    echo -e "${GREEN}Homarr instalado correctamente.${NC}"
    echo
    echo "URL: http://$IP:7575"
    echo
    echo "SECRET_ENCRYPTION_KEY generada automáticamente."
    echo

    pause
}

estado_homarr() {

    header

    echo "Estado del contenedor:"
    echo

    docker ps -a --filter "name=homarr"

    echo
    echo "Uso de recursos:"
    echo

    docker stats homarr --no-stream 2>/dev/null

    echo

    pause
}

reiniciar_homarr() {

    header

    docker restart homarr

    echo
    echo -e "${GREEN}Servicio reiniciado.${NC}"

    pause
}

detener_homarr() {

    header

    docker stop homarr

    echo
    echo -e "${GREEN}Servicio detenido.${NC}"

    pause
}

iniciar_homarr() {

    header

    docker start homarr

    echo
    echo -e "${GREEN}Servicio iniciado.${NC}"

    pause
}

actualizar_homarr() {

    header

    cd "$HOMARR_DIR" || exit

    docker compose pull
    docker compose up -d

    echo
    echo -e "${GREEN}Homarr actualizado.${NC}"

    pause
}

desinstalar_homarr() {

    header

    read -rp "¿Eliminar Homarr completamente? (s/n): " RESP

    [[ ! "$RESP" =~ ^[Ss]$ ]] && return

    cd "$HOMARR_DIR" 2>/dev/null || true

    docker compose down -v 2>/dev/null

    rm -rf "$HOMARR_DIR"

    echo
    echo -e "${GREEN}Homarr eliminado.${NC}"

    pause
}

while true
do

    header

echo
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}         GESTOR DE HOMARR v1.0          ${NC}"
echo -e "${CYAN}========================================${NC}"
echo

echo -e "${YELLOW}[1]${NC} ${CYAN}Instalar dependencias${NC}"
echo -e "${YELLOW}[2]${NC} ${CYAN}Instalar Homarr${NC}"
echo -e "${YELLOW}[3]${NC} ${CYAN}Ver estado${NC}"
echo -e "${YELLOW}[4]${NC} ${CYAN}Reiniciar servicio${NC}"
echo -e "${YELLOW}[5]${NC} ${CYAN}Iniciar servicio${NC}"
echo -e "${YELLOW}[6]${NC} ${CYAN}Detener servicio${NC}"
echo -e "${YELLOW}[7]${NC} ${CYAN}Actualizar Homarr${NC}"
echo -e "${YELLOW}[8]${NC} ${CYAN}Desinstalar Homarr${NC}"
echo
echo -e "${YELLOW}[0]${NC} ${RED}Salir${NC}"
echo

    read -rp "Seleccione una opción: " OPCION

    case $OPCION in
        1) instalar_dependencias ;;
        2) instalar_homarr ;;
        3) estado_homarr ;;
        4) reiniciar_homarr ;;
        5) iniciar_homarr ;;
        6) detener_homarr ;;
        7) actualizar_homarr ;;
        8) desinstalar_homarr ;;
        0) exit 0 ;;
        *) echo "Opción inválida"; sleep 2 ;;
    esac

done