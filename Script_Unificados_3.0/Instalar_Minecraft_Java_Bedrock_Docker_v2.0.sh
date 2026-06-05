#!/bin/bash

# ==========================================================
# MINECRAFT SERVER MANAGER
# Java + Bedrock (Paper + Geyser)
# Debian 12 / Ubuntu
# ==========================================================

APP_DIR="/opt/minecraft"
CONTAINER_NAME="minecraft"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

header() {
    clear
    echo -e "${BLUE}"
    echo "========================================="
    echo "      MINECRAFT SERVER MANAGER"
    echo "========================================="
    echo -e "${NC}"
}

verificar_dependencias() {

    echo -e "${YELLOW}Verificando dependencias...${NC}"

    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}Docker no está instalado.${NC}"
        exit 1
    fi

    if docker compose version >/dev/null 2>&1; then
        COMPOSE="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE="docker-compose"
    else
        echo -e "${RED}Docker Compose no está instalado.${NC}"
        exit 1
    fi

    echo -e "${GREEN}Dependencias OK${NC}"
}

instalar() {

    verificar_dependencias

    echo
    read -rp "Puerto Java [25565]: " JAVA_PORT
    JAVA_PORT=${JAVA_PORT:-25565}

    read -rp "Puerto Bedrock [19132]: " BEDROCK_PORT
    BEDROCK_PORT=${BEDROCK_PORT:-19132}

    mkdir -p "$APP_DIR"

    cat > "$APP_DIR/docker-compose.yml" <<EOF
services:
  minecraft:
    image: itzg/minecraft-server:latest
    container_name: minecraft
    restart: unless-stopped

    ports:
      - "${JAVA_PORT}:25565"
      - "${BEDROCK_PORT}:19132/udp"

    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      MEMORY: "4G"
      VERSION: "LATEST"

      ONLINE_MODE: "FALSE"
      ENFORCE_SECURE_PROFILE: "FALSE"

      ENABLE_RCON: "TRUE"
      RCON_PASSWORD: "MinecraftAdmin123"

      MOTD: "Servidor Minecraft"

      PLUGINS: |
        https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot
        https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot

    volumes:
      - ./data:/data
EOF

    cd "$APP_DIR" || exit

    $COMPOSE pull
    $COMPOSE up -d

    echo "Esperando inicialización..."
    sleep 30

    if [ -f "$APP_DIR/data/server.properties" ]; then
        sed -i 's/^online-mode=.*/online-mode=false/' \
            "$APP_DIR/data/server.properties"

        sed -i 's/^enforce-secure-profile=.*/enforce-secure-profile=false/' \
            "$APP_DIR/data/server.properties" 2>/dev/null || true

        docker restart minecraft >/dev/null 2>&1
    fi

    echo
    echo -e "${GREEN}Servidor Minecraft instalado correctamente${NC}"
    echo
    echo "Java Edition:"
    echo "  Puerto: $JAVA_PORT"
    echo
    echo "Bedrock Edition:"
    echo "  Puerto UDP: $BEDROCK_PORT"
    echo
    echo "Directorio:"
    echo "  $APP_DIR"
}

desinstalar() {

    verificar_dependencias

    if [ -d "$APP_DIR" ]; then

        cd "$APP_DIR" || exit

        $COMPOSE down

        read -p "¿Eliminar también los mundos y datos? (s/n): " RESP

        if [[ "$RESP" =~ ^[sS]$ ]]; then
            rm -rf "$APP_DIR"
            echo -e "${GREEN}Datos eliminados.${NC}"
        fi

        echo -e "${GREEN}Servidor desinstalado.${NC}"
    else
        echo -e "${RED}No encontrado.${NC}"
    fi
}

estado() {

    echo
    docker ps -a --filter "name=$CONTAINER_NAME"
    echo
}

reiniciar() {

    docker restart "$CONTAINER_NAME"
}

iniciar() {

    docker start "$CONTAINER_NAME"
}

detener() {

    docker stop "$CONTAINER_NAME"
}

logs() {

    docker logs -f "$CONTAINER_NAME"
}
consola_minecraft() {

    while true; do

        read -rp "Minecraft> " CMD

        [ "$CMD" = "salir" ] && break
        [ -z "$CMD" ] && continue

        echo
        echo "Comando: $CMD"
        echo "--------------------------------"

        docker exec minecraft rcon-cli "$CMD"

        echo "--------------------------------"
        echo

    done
}
estado() {

    echo
    echo "========================================="
    echo "      ESTADO DEL SERVIDOR"
    echo "========================================="
    echo

    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "❌ Contenedor no encontrado"
        return
    fi

    ESTADO=$(docker inspect -f '{{.State.Status}}' ${CONTAINER_NAME} 2>/dev/null)
    IP_DOCKER=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${CONTAINER_NAME} 2>/dev/null)
    UPTIME=$(docker inspect -f '{{.State.StartedAt}}' ${CONTAINER_NAME} 2>/dev/null)

    IP_LOCAL=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo "Contenedor : ${CONTAINER_NAME}"
    echo "Estado     : ${ESTADO}"
    echo "IP Docker  : ${IP_DOCKER}"
    echo "IP Local   : ${IP_LOCAL}"
    echo "Iniciado   : ${UPTIME}"
    echo

    echo "========================================="
    echo "           PUERTOS"
    echo "========================================="
    docker port ${CONTAINER_NAME}
    echo

    echo "========================================="
    echo "     DATOS DE CONEXION"
    echo "========================================="
    echo
    echo "JAVA EDITION"
    echo "  Direccion : ${IP_LOCAL}"
    echo "  Puerto    : 8083/TCP"
    echo "  Conexion  : ${IP_LOCAL}:25565"
    echo

    echo "BEDROCK EDITION"
    echo "  Direccion : ${IP_LOCAL}"
    echo "  Puerto    : 8084/UDP"
    echo "  Conexion  : ${IP_LOCAL}:19132"
    echo

    echo "========================================="
    echo "           RECURSOS"
    echo "========================================="
    docker stats --no-stream ${CONTAINER_NAME}
    echo
}

menu() {

    while true
    do
        header

echo
echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}    MINECRAFT MANAGER - Java / Bedrock   ${NC}"
echo -e "${CYAN}=========================================${NC}"
echo

echo -e "${YELLOW}1)${NC} Instalar servidor"
echo -e "${YELLOW}2)${NC} Desinstalar servidor"
echo -e "${YELLOW}3)${NC} Ver estado"
echo -e "${YELLOW}4)${NC} Reiniciar"
echo -e "${YELLOW}5)${NC} Iniciar"
echo -e "${YELLOW}6)${NC} Detener"
echo -e "${YELLOW}7)${NC} Ver logs"
echo -e "${YELLOW}8)${NC} Estado del Servidor (Puerto/IP)"
echo -e "${YELLOW}9)${NC} Consola Minecraft"
echo
echo -e "${YELLOW}0)${NC} Salir"
echo

        read -p "Seleccione opción: " OPCION

        case $OPCION in
            1) instalar ;;
            2) desinstalar ;;
            3) estado ;;
            4) reiniciar ;;
            5) iniciar ;;
            6) detener ;;
            7) logs ;;
			8) estado ;;
			9) consola_minecraft ;;
            0) exit 0 ;;
            *) echo "Opción inválida" ;;
        esac

        echo
        read -p "ENTER para continuar..."
    done
}

menu
