#!/bin/bash

# ==========================================================
# MINECRAFT SERVER MANAGER
# Java + Bedrock (Paper + Geyser)
# Debian 12 / Ubuntu
# ==========================================================

APP_DIR="/opt/minecraft"
CONTAINER_NAME="minecraft"

# Colores
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

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
#                     #
#  Instalar Minecraft #
#                     #     
instalar() {
check_pass    
    verificar_dependencias

    if command -v docker-compose >/dev/null 2>&1; then
        COMPOSE="docker-compose"
    else
        echo "ERROR: docker-compose no está instalado"
        return 1
    fi

    echo
    read -rp "Puerto Java [25565]: " JAVA_PORT
    JAVA_PORT=${JAVA_PORT:-25565}

    read -rp "Puerto Bedrock [19132]: " BEDROCK_PORT
    BEDROCK_PORT=${BEDROCK_PORT:-19132}

    mkdir -p "$APP_DIR"

    cat > "$APP_DIR/docker-compose.yml" <<EOF
version: "3.8"

services:
  minecraft:
    image: itzg/minecraft-server:latest
    container_name: minecraft
    ports:
      - "${JAVA_PORT}:25565"
      - "${BEDROCK_PORT}:19132/udp"

    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "1.20.4"
      MEMORY: "4G"

      ENABLE_RCON: "true"
      RCON_PASSWORD: "minecraft"
      RCON_PORT: 25575

      ONLINE_MODE: "FALSE"

    volumes:
      - ./data:/data
      - ./plugins:/plugins

    restart: unless-stopped
EOF

    cd "$APP_DIR" || return 1

    docker rm -f minecraft >/dev/null 2>&1 || true

    docker pull itzg/minecraft-server:java21

    $COMPOSE up -d

    echo
    echo "Esperando inicio del servidor..."
    sleep 30

    echo
    docker ps | grep minecraft

    echo
    echo "Plugins instalados:"
    echo " - ViaVersion"
    echo " - ViaBackwards"
    echo " - Geyser"
    echo " - Floodgate"

    echo
    echo "Java:"
    echo "  IP:PUERTO -> ${JAVA_PORT}"

    echo
    echo "Bedrock:"
    echo "  IP:PUERTO -> ${BEDROCK_PORT}"

    echo
    echo "Ver logs:"
    echo "docker logs -f minecraft"
}

desinstalar() {
check_pass
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

    echo "📡 Iniciando logs de $CONTAINER_NAME..."
    echo "⏳ Esperando que el servidor esté listo..."
    echo

    docker logs -f "$CONTAINER_NAME" | while read line
    do
        echo "$line"

        # Detecta cuando Minecraft está listo
        echo "$line" | grep -q "Done (" && {
            echo
            echo "🟢 SERVIDOR LISTO PARA CONECTARSE"
            echo
        }
    done
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

    # Verificar existencia del contenedor
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "❌ Contenedor no encontrado"
        return 1
    fi

    # Estado real del contenedor
    ESTADO=$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null)
    RESTARTS=$(docker inspect -f '{{.RestartCount}}' "${CONTAINER_NAME}" 2>/dev/null)
    IMAGE=$(docker inspect -f '{{.Config.Image}}' "${CONTAINER_NAME}" 2>/dev/null)
    UPTIME=$(docker inspect -f '{{.State.StartedAt}}' "${CONTAINER_NAME}" 2>/dev/null)

    echo "Contenedor : ${CONTAINER_NAME}"
    echo "Estado     : ${ESTADO}"
    echo "Imagen     : ${IMAGE}"
    echo "Reinicios  : ${RESTARTS}"
    echo "Iniciado   : ${UPTIME}"
    echo

    echo "========================================="
    echo "           PUERTOS REALES"
    echo "========================================="
    docker port "${CONTAINER_NAME}" 2>/dev/null || echo "Sin puertos expuestos"
    echo

    echo "========================================="
    echo "      IP REAL DEL CONTENEDOR"
    echo "========================================="

    IP_DOCKER=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CONTAINER_NAME}" 2>/dev/null)

    if [ -n "$IP_DOCKER" ]; then
        echo "IP Docker  : ${IP_DOCKER}"
    else
        echo "IP Docker  : No disponible (modo host o bridge sin IP)"
    fi

    echo

    echo "========================================="
    echo "     PUERTO REAL PUBLICADO (HOST)"
    echo "========================================="

    # Extrae puertos reales del host
    docker inspect -f '{{json .NetworkSettings.Ports}}' "${CONTAINER_NAME}" | jq '.' 2>/dev/null || \
    docker port "${CONTAINER_NAME}"

    echo

    echo "========================================="
    echo "     DATOS REALES DE CONEXION"
    echo "========================================="

    HOST_IP=$(hostname -I | awk '{print $1}')

    # Java real (detectado desde docker port)
    JAVA_PORT=$(docker port "${CONTAINER_NAME}" 2>/dev/null | grep 25565 | head -n1 | cut -d: -f2)

    # Bedrock real
    BEDROCK_PORT=$(docker port "${CONTAINER_NAME}" 2>/dev/null | grep 19132 | head -n1 | cut -d: -f2)

    echo "JAVA EDITION"
    echo "  Conexion : ${HOST_IP}:${JAVA_PORT:-NO_DETECTADO}"
    echo

    echo "BEDROCK EDITION"
    echo "  Conexion : ${HOST_IP}:${BEDROCK_PORT:-NO_DETECTADO}"
    echo

    echo "========================================="
    echo "           RECURSOS"
    echo "========================================="
    docker stats --no-stream "${CONTAINER_NAME}"
    echo
}
ver_minecraft() {

    CONTAINER="minecraft"

    echo
    echo "====================================="
    echo "     VERSION MINECRAFT SERVER"
    echo "====================================="
    echo

    # Verificar si el contenedor existe
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        echo "❌ Contenedor no encontrado"
        return 1
    fi

    # Verificar si está corriendo
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        echo "⚠️ El servidor está detenido o reiniciando"
    fi

    echo "📦 Intentando obtener versión..."

    # MÉTODO 1: desde logs (el más confiable)
    VERSION_LOG=$(docker logs "$CONTAINER" 2>&1 | grep -i "Starting minecraft server version" | tail -n 1)

    if [ -n "$VERSION_LOG" ]; then
        echo
        echo "🟢 Versión detectada:"
        echo "$VERSION_LOG" | awk -F'version ' '{print $2}'
    else
        echo "⚠️ No se pudo detectar versión en logs"
    fi

    echo

    # MÉTODO 2: variable de entorno (si existe)
    VERSION_ENV=$(docker exec "$CONTAINER" printenv VERSION 2>/dev/null)

    if [ -n "$VERSION_ENV" ]; then
        echo "📌 VERSION env: $VERSION_ENV"
    fi

    echo

    # MÉTODO 3: Paper / server.properties fallback
    if docker exec "$CONTAINER" test -f /data/version.json 2>/dev/null; then
        echo "📄 version.json encontrado:"
        docker exec "$CONTAINER" cat /data/version.json 2>/dev/null
    fi

    echo
    echo "====================================="
}
verificar() {

    echo
    echo "====================================="
    echo "    ESTADO SERVIDOR MINECRAFT"
    echo "====================================="
    echo

    echo -n "Docker: "
    if systemctl is-active --quiet docker; then
        echo "OK"
    else
        echo "ERROR"
    fi

    echo -n "Contenedor: "
    if docker ps --format '{{.Names}}' | grep -q '^minecraft$'; then
        echo "EJECUTANDOSE"
    else
        echo "DETENIDO"
    fi

    echo

    echo "Puertos:"
    ss -tulpn | grep -E '25565|19132|25575|8083|8084'

    echo

    echo "Version:"
    docker logs minecraft 2>/dev/null | grep "Starting minecraft server version" | tail -1

    echo

    echo "Estado:"
    docker logs minecraft 2>/dev/null | grep "Done (" | tail -1

    echo

    echo "Plugins:"
    docker logs minecraft 2>/dev/null | grep -E "ViaVersion|ViaBackwards|Geyser|Floodgate" | tail -10

    echo

    echo "IP:"
    hostname -I

    echo
    read -rp "Presione Enter para continuar..."
}
verificar_docker() {

    # Verificar si Docker existe
    if ! command -v docker >/dev/null 2>&1; then
        echo "❌ Docker no está instalado"
        return 1
    fi

    # Verificar si el servicio está activo
    if ! systemctl is-active --quiet docker; then
        echo "❌ El servicio Docker no está activo"
        return 1
    fi

    echo "✅ Docker está instalado y activo"
    echo

    # Mostrar contenedores activos
    echo "📦 Contenedores en ejecución:"
    docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"

    echo
    echo "📦 Todos los contenedores (incluye detenidos):"
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"

    return 0
}
check_pass() {

    read -rsp "🔐 Password admin: " PASS
    echo

    # define tu password fija (NO recomendado en producción)
    if [ "$PASS" != "1234" ]; then
        echo "❌ Incorrecto"
        return 1
    fi

    echo "✅ Autorizado"
}

CONTAINER_NAME="minecraft"

panel_minecraft() {

    while true; do
        clear   # 👈 LIMPIA LA PANTALLA EN CADA CICLO

echo
echo -e "${CYAN}=========================================${RESET}"
echo -e "${BOLD}${GREEN}       PANEL ADMIN MINECRAFT PRO${RESET}"
echo -e "${CYAN}=========================================${RESET}"
echo

echo -e "${YELLOW}1)${RESET} Estado del servidor"
echo -e "${YELLOW}2)${RESET} Backup mundo"
echo -e "${YELLOW}3)${RESET} Reiniciar servidor"
echo -e "${YELLOW}4)${RESET} Logs en vivo"
echo -e "${YELLOW}5)${RESET} Dar OP"
echo -e "${YELLOW}6)${RESET} Quitar OP"
echo -e "${YELLOW}7)${RESET} Whitelist agregar"
echo -e "${YELLOW}8)${RESET} Whitelist remover"
echo -e "${YELLOW}9)${RESET} Broadcast mensaje"
echo -e "${YELLOW}10)${RESET} Ejecutar comando custom"
echo -e "${RED}0)${RESET} Salir"
echo
        read -rp "Opción: " opt

        case $opt in

        1)
            docker ps --filter name="$CONTAINER_NAME"
            docker stats --no-stream "$CONTAINER_NAME"
            read -rp "Enter para continuar..." ;;
        2)
            mkdir -p backups
            FILE="backups/world_$(date +%F_%H-%M-%S).tar.gz"
            docker exec "$CONTAINER_NAME" rcon-cli "save-all"
            docker exec "$CONTAINER_NAME" bash -c "tar -czf /tmp/world.tar.gz /data"
            docker cp "$CONTAINER_NAME":/tmp/world.tar.gz "$FILE"
            echo "✅ Backup creado: $FILE"
            read -rp "Enter para continuar..." ;;
        3)
            docker restart "$CONTAINER_NAME"
            echo "🔄 Reiniciado"
            read -rp "Enter para continuar..." ;;
        4)
            docker logs -f "$CONTAINER_NAME"
            ;;
        5)
            read -rp "Jugador OP: " user
            docker exec "$CONTAINER_NAME" rcon-cli "op $user"
            echo "✅ OP dado"
            read -rp "Enter para continuar..." ;;
        6)
            read -rp "Jugador DEOP: " user
            docker exec "$CONTAINER_NAME" rcon-cli "deop $user"
            echo "❌ OP removido"
            read -rp "Enter para continuar..." ;;
        7)
            read -rp "Jugador whitelist ADD: " user
            docker exec "$CONTAINER_NAME" rcon-cli "whitelist add $user"
            echo "✅ Agregado"
            read -rp "Enter para continuar..." ;;
        8)
            read -rp "Jugador whitelist REMOVE: " user
            docker exec "$CONTAINER_NAME" rcon-cli "whitelist remove $user"
            echo "❌ Eliminado"
            read -rp "Enter para continuar..." ;;
        9)
            read -rp "Mensaje: " msg
            docker exec "$CONTAINER_NAME" rcon-cli "say $msg"
            echo "📢 Enviado"
            read -rp "Enter para continuar..." ;;
        10)
            read -rp "Comando: " cmd
            docker exec "$CONTAINER_NAME" rcon-cli "$cmd"
            echo "⚡ Ejecutado"
            read -rp "Enter para continuar..." ;;
        0)
            echo "Saliendo..."
            break
            ;;
        *)
            echo "❌ Opción inválida"
            read -rp "Enter para continuar..." ;;
        esac
    done
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

echo -e "${YELLOW} 1)${GREEN} Instalar servidor"
echo -e "${YELLOW} 2)${YELLOW} Desinstalar servidor"
echo -e "${YELLOW} 3)${RESET} Estado del Servidor (Puerto/IP)"
echo -e "${YELLOW} 4)${RESET} Reiniciar"
echo -e "${YELLOW} 5)${RESET} Iniciar"
echo -e "${YELLOW} 6)${RESET} Detener"
echo -e "${YELLOW} 7)${RESET} Ver logs"
echo -e "${YELLOW} 8)${RESET} Menu Minecraft"
echo -e "${YELLOW} 9)${RESET} Consola Minecraft"
echo -e "${YELLOW}10)${RESET} Verificar Minecraft"
echo -e "${YELLOW}11)${RESET} Vercion de Minecraft"
echo -e "${YELLOW}12)${RESET} Verificar Docker"
echo -e "${YELLOW}11)${CYAN} Salir"
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
			8) panel_minecraft ;;
			9) consola_minecraft ;;
		   10) verificar ;;
		   11) ver_minecraft ;;
		   12) verificar_docker ;;
            0) exit 0 ;;
            *) echo "Opción inválida" ;;
        esac

        echo
        read -p "ENTER para continuar..."
    done
}

menu
