#!/bin/bash

# ==========================================================
# AGENTE DVR v1.0
# Debian 12 / 13
# ==========================================================
############################################################
# CONFIGURACIÓN AGENT DVR
############################################################

APP_NAME="Agent DVR"
APP_VERSION="1.0"

BASE_DIR="/opt/agentdvr"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"

CONTAINER_NAME="agentdvr"
IMAGE_NAME="doitandbedone/ispyagentdvr:latest"

HTTP_PORT="8090"
STUN_PORT="3478"
WEBRTC_PORT_START="50000"
WEBRTC_PORT_END="50010"

TZ="America/Santiago"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
CYAN="\e[1;36m"

############################################################
# HEADER
############################################################

header() {

    clear

    echo -e "${CYAN}"
    echo "========================================="
    echo "        AGENT DVR - DOCKER"
    echo "             Versión ${APP_VERSION}"
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
############################################################
# INSTALAR AGENT DVR
############################################################

instalar_agent_dvr() {

    header

    titulo "INSTALAR AGENT DVR"

    DIRECTORIO="/opt/agentdvr"

    echo
    echo "Creando directorio..."
    mkdir -p "$DIRECTORIO"

    cat > "$DIRECTORIO/docker-compose.yml" <<'EOF'
services:
  agentdvr:
    image: doitandbedone/ispyagentdvr:latest
    container_name: agentdvr
    restart: unless-stopped

    ports:
      - "8090:8090"
      - "3478:3478/udp"
      - "50000-50010:50000-50010/udp"

    volumes:
      - ./AgentDVR/Media:/AgentDVR/Media
      - ./AgentDVR/Config:/AgentDVR/Config

    environment:
      - TZ=America/Santiago
EOF

    echo
    echo "Iniciando contenedor..."

    cd "$DIRECTORIO" || return
    docker compose up -d

    echo
    echo "Esperando inicio..."
    sleep 10

    if docker ps --format '{{.Names}}' | grep -q "^agentdvr$"; then
        echo
        echo "=========================================="
        echo " Agent DVR instalado correctamente"
        echo "=========================================="
        echo
        echo "Acceso:"
        echo "http://$(hostname -I | awk '{print $1}'):8090"
    else
        echo
        echo "Error al iniciar Agent DVR."
    fi

    read -rp "Presione ENTER para continuar..."
}
############################################################
# ESTADO AGENT DVR
############################################################

estado_agent_dvr() {

    header

    titulo "ESTADO AGENT DVR"

    echo

    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${RED}Agent DVR no está instalado.${NC}"
        echo
        pause
        return
    fi

    ESTADO=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)
    IMAGE=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null)
    UPTIME=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER_NAME" 2>/dev/null)

    PUERTOS=$(docker port "$CONTAINER_NAME" 2>/dev/null)

    IP_SERVIDOR=$(hostname -I | awk '{print $1}')

    CPU=$(docker stats --no-stream --format "{{.CPUPerc}}" "$CONTAINER_NAME" 2>/dev/null)
    MEM=$(docker stats --no-stream --format "{{.MemUsage}}" "$CONTAINER_NAME" 2>/dev/null)

    echo -e "Estado             : ${GREEN}${ESTADO^^}${NC}"
    echo "Contenedor         : $CONTAINER_NAME"
    echo "Imagen             : $IMAGE"
    echo "Directorio         : $BASE_DIR"
    echo
    echo "Puertos publicados :"
    echo "$PUERTOS"
    echo
    echo "Uso CPU            : $CPU"
    echo "Uso Memoria        : $MEM"
    echo
    echo "Iniciado           : $UPTIME"
    echo
    echo "Acceso Web         : http://$IP_SERVIDOR:$HTTP_PORT"
    echo

    pause

}

############################################################
# ADMINISTRAR SERVICIOS
############################################################

administrar_servicios() {

    while true; do

        header

        titulo "ADMINISTRAR SERVICIOS"

        echo
        echo -e " ${YELLOW}1)${NC} Iniciar Agent DVR"
        echo -e " ${YELLOW}2)${NC} Detener Agent DVR"
        echo -e " ${YELLOW}3)${NC} Reiniciar Agent DVR"
        echo -e " ${YELLOW}4)${NC} Ver estado del contenedor"
        echo -e " ${YELLOW}5)${NC} Ver logs en tiempo real"
        echo
        echo -e " ${YELLOW}0)${NC} Volver"
        echo

        read -rp "Seleccione una opción: " opcion

        case "$opcion" in

            1)
                iniciar_agentdvr
                ;;

            2)
                detener_agentdvr
                ;;

            3)
                reiniciar_agentdvr
                ;;

            4)
                estado_contenedor_agentdvr
                ;;

            5)
                logs_agentdvr
                ;;

            0)
                return
                ;;

            *)
                echo
                echo -e "${RED}Opción inválida.${NC}"
                sleep 2
                ;;

        esac

    done

}
############################################################
# INICIAR AGENT DVR
############################################################

iniciar_agentdvr() {

    header

    titulo "INICIAR AGENT DVR"

    cd "$BASE_DIR" || return

    docker compose up -d

    echo
    echo -e "${GREEN}Agent DVR iniciado correctamente.${NC}"

    pause

}
############################################################
# DETENER AGENT DVR
############################################################

detener_agentdvr() {

    header

    titulo "DETENER AGENT DVR"

    cd "$BASE_DIR" || return

    docker compose stop

    echo
    echo -e "${GREEN}Agent DVR detenido correctamente.${NC}"

    pause

}
############################################################
# REINICIAR AGENT DVR
############################################################

reiniciar_agentdvr() {

    header

    titulo "REINICIAR AGENT DVR"

    cd "$BASE_DIR" || return

    docker compose restart

    echo
    echo -e "${GREEN}Agent DVR reiniciado correctamente.${NC}"

    pause

}
############################################################
# ESTADO DEL CONTENEDOR
############################################################

estado_contenedor_agentdvr() {

    header

    titulo "ESTADO DEL CONTENEDOR"

    docker ps -a --filter "name=$CONTAINER_NAME"

    echo

    pause

}
############################################################
# LOGS AGENT DVR
############################################################

logs_agentdvr() {

    header

    titulo "LOGS AGENT DVR"

    echo
    echo "Presione CTRL+C para volver."
    echo

    docker logs -f "$CONTAINER_NAME"

}
############################################################
# AJUSTES
############################################################

menu_ajustes() {

    while true; do

        header

        titulo "AJUSTES AGENT DVR"

        echo
        echo -e " ${YELLOW}1)${NC} Cambiar puerto Web"
        echo -e " ${YELLOW}2)${NC} Cambiar zona horaria"
        echo -e " ${YELLOW}3)${NC} Actualizar Agent DVR"
        echo -e " ${YELLOW}4)${NC} Recrear contenedor"
        echo
        echo -e " ${YELLOW}0)${NC} Volver"
        echo

        read -rp "Seleccione una opción: " opcion

        case "$opcion" in

            1)
                cambiar_puerto_web
                ;;

            2)
                cambiar_zona_horaria
                ;;

            3)
                actualizar_agentdvr
                ;;

            4)
                recrear_contenedor
                ;;

            0)
                return
                ;;

            *)
                echo
                echo -e "${RED}Opción inválida.${NC}"
                sleep 2
                ;;

        esac

    done

}
############################################################
# CAMBIAR PUERTO WEB
############################################################

cambiar_puerto_web() {

    header

    titulo "CAMBIAR PUERTO WEB"

    echo
    echo "Puerto actual: $HTTP_PORT"
    echo

    read -rp "Nuevo puerto: " NUEVO_PUERTO

    [[ -z "$NUEVO_PUERTO" ]] && return

    if ss -tuln | grep -q ":${NUEVO_PUERTO} "; then
        echo
        echo -e "${RED}El puerto ${NUEVO_PUERTO} ya está en uso.${NC}"
        pause
        return
    fi

    sed -i "s/${HTTP_PORT}:8090/${NUEVO_PUERTO}:8090/g" "$COMPOSE_FILE"

    HTTP_PORT="$NUEVO_PUERTO"

    cd "$BASE_DIR" || return

    docker compose up -d

    echo
    echo -e "${GREEN}Puerto cambiado correctamente.${NC}"
    echo
    echo "Nuevo acceso:"
    echo "http://$(hostname -I | awk '{print $1}'):$HTTP_PORT"

    pause

}
############################################################
# CAMBIAR ZONA HORARIA
############################################################

cambiar_zona_horaria() {

    header

    titulo "CAMBIAR ZONA HORARIA"

    echo
    echo "Zona actual: $TZ"
    echo

    read -rp "Nueva zona horaria: " NUEVA_TZ

    [[ -z "$NUEVA_TZ" ]] && return

    sed -i "s|TZ: .*|TZ: ${NUEVA_TZ}|g" "$COMPOSE_FILE"

    TZ="$NUEVA_TZ"

    cd "$BASE_DIR" || return

    docker compose up -d

    echo
    echo -e "${GREEN}Zona horaria actualizada.${NC}"

    pause

}
############################################################
# ACTUALIZAR AGENT DVR
############################################################

actualizar_agentdvr() {

    header

    titulo "ACTUALIZAR AGENT DVR"

    cd "$BASE_DIR" || return

    echo
    echo "Descargando última versión..."
    echo

    docker compose pull

    echo
    echo "Actualizando contenedor..."
    echo

    docker compose up -d

    docker image prune -f

    echo
    echo -e "${GREEN}Agent DVR actualizado correctamente.${NC}"

    pause

}
############################################################
# RECREAR CONTENEDOR
############################################################

recrear_contenedor() {

    header

    titulo "RECREAR CONTENEDOR"

    cd "$BASE_DIR" || return

    echo
    echo "Recreando contenedor..."
    echo

    docker compose down

    docker compose up -d

    echo
    echo -e "${GREEN}Contenedor recreado correctamente.${NC}"

    pause

}
############################################################
# INFORMACIÓN
############################################################

menu_informacion() {

    while true; do

        header

        titulo "INFORMACIÓN AGENT DVR"

        echo
        echo -e " ${YELLOW}1)${NC} Información de la instalación"
        echo -e " ${YELLOW}2)${NC} Uso de recursos"
        echo -e " ${YELLOW}3)${NC} Volúmenes Docker"
        echo -e " ${YELLOW}4)${NC} Red Docker"
        echo
        echo -e " ${YELLOW}0)${NC} Volver"
        echo

        read -rp "Seleccione una opción: " opcion

        case "$opcion" in

            1) informacion_instalacion ;;
            2) uso_recursos ;;
            3) volumenes_docker ;;
            4) red_docker ;;
            0) return ;;
            *) echo -e "${RED}Opción inválida.${NC}"; sleep 2 ;;
        esac

    done

}
############################################################
# INFORMACIÓN INSTALACIÓN
############################################################

informacion_instalacion() {

    header

    titulo "INFORMACIÓN DE LA INSTALACIÓN"

    echo
    echo "Aplicación........: $APP_NAME"
    echo "Contenedor........: $CONTAINER_NAME"
    echo "Imagen............: $IMAGE_NAME"
    echo "Directorio........: $BASE_DIR"
    echo "Compose...........: $COMPOSE_FILE"
    echo "Puerto Web........: $HTTP_PORT"
    echo "Zona Horaria......: $TZ"
    echo
    echo "URL:"
    echo "http://$(hostname -I | awk '{print $1}'):$HTTP_PORT"
    echo

    pause

}
############################################################
# USO DE RECURSOS
############################################################

uso_recursos() {

    header

    titulo "USO DE RECURSOS"

    docker stats --no-stream "$CONTAINER_NAME"

    echo

    pause

}
############################################################
# VOLÚMENES DOCKER
############################################################

volumenes_docker() {

    header

    titulo "VOLÚMENES DOCKER"

    docker volume ls

    echo

    pause

}
############################################################
# RED DOCKER
############################################################

red_docker() {

    header

    titulo "RED DOCKER"

    docker network ls

    echo

    pause

}
############################################################
# DESINSTALAR AGENT DVR
############################################################

desinstalar_agentdvr() {

    while true; do

        header

        titulo "DESINSTALAR AGENT DVR"

        echo
        echo -e " ${YELLOW}1)${NC} Eliminar solo el contenedor"
        echo -e " ${YELLOW}2)${NC} Eliminar contenedor e imagen Docker"
        echo -e " ${YELLOW}3)${NC} Eliminación completa"
        echo
        echo -e " ${YELLOW}0)${NC} Volver"
        echo

        read -rp "Seleccione una opción: " opcion

        case "$opcion" in

            ##################################################
            # SOLO CONTENEDOR
            ##################################################
            1)

                echo
                read -rp "¿Eliminar el contenedor? (s/n): " RESP

                [[ "$RESP" != "s" && "$RESP" != "S" ]] && continue

                cd "$BASE_DIR" 2>/dev/null

                docker compose down 2>/dev/null
                docker rm -f "$CONTAINER_NAME" 2>/dev/null

                echo
                echo -e "${GREEN}✓ Contenedor eliminado correctamente.${NC}"

                pause
                ;;

            ##################################################
            # CONTENEDOR + IMAGEN
            ##################################################
            2)

                echo
                read -rp "¿Eliminar contenedor e imagen? (s/n): " RESP

                [[ "$RESP" != "s" && "$RESP" != "S" ]] && continue

                cd "$BASE_DIR" 2>/dev/null

                docker compose down 2>/dev/null
                docker rm -f "$CONTAINER_NAME" 2>/dev/null
                docker image rm "$IMAGE_NAME" 2>/dev/null

                echo
                echo -e "${GREEN}✓ Contenedor e imagen eliminados.${NC}"

                pause
                ;;

            ##################################################
            # ELIMINACIÓN COMPLETA
            ##################################################
            3)

                echo
                echo -e "${RED}¡¡ATENCIÓN!!${NC}"
                echo
                echo "Se eliminará:"
                echo
                echo " • Contenedor"
                echo " • Imagen Docker"
                echo " • Configuración"
                echo " • Grabaciones"
                echo " • Directorio: $BASE_DIR"
                echo
                echo -e "${GREEN}Docker y Docker Compose NO serán eliminados.${NC}"
                echo

                read -rp "¿Desea continuar? (s/n): " RESP

                [[ "$RESP" != "s" && "$RESP" != "S" ]] && continue

                cd "$BASE_DIR" 2>/dev/null

                docker compose down 2>/dev/null
                docker rm -f "$CONTAINER_NAME" 2>/dev/null
                docker image rm "$IMAGE_NAME" 2>/dev/null

                rm -rf "$BASE_DIR"

                docker image prune -f >/dev/null 2>&1

                echo
                echo -e "${GREEN}✓ Agent DVR desinstalado completamente.${NC}"

                pause
                ;;

            ##################################################
            # VOLVER
            ##################################################
            0)
                return
                ;;

            *)
                echo
                echo -e "${RED}Opción inválida.${NC}"
                sleep 2
                ;;

        esac

    done

}
############################################################
# MENÚ PRINCIPAL
############################################################

menu_principal() {

    while true; do

        header

        echo
        echo -e " ${YELLOW}1)${NC} Instalar dependencias Docker"
        echo -e " ${YELLOW}2)${NC} Instalar Agent DVR"
        echo -e " ${YELLOW}3)${NC} Estado de Agent DVR"
        echo -e " ${YELLOW}4)${NC} Administrar servicios"
        echo -e " ${YELLOW}5)${NC} Ajustes"
        echo -e " ${YELLOW}6)${NC} Información"
        echo -e " ${YELLOW}7)${NC} Desinstalar Agent DVR"
        echo
        echo -e " ${YELLOW}0)${NC} Salir"
        echo

        read -rp "Seleccione una opción: " opcion

        case "$opcion" in

            1)
                instalar_dependencias
                ;;

            2)
                instalar_agent_dvr
                ;;

            3)
                estado_agent_dvr
                ;;

            4)
                administrar_servicios
                ;;

            5)
                menu_ajustes
                ;;

            6)
                menu_informacion
                ;;

            7)
                desinstalar_agentdvr
                ;;

            0)
                clear
                exit 0
                ;;

            *)
                echo
                echo -e "${RED}Opción inválida.${NC}"
                sleep 2
                ;;

        esac

    done

}

############################################################
# INICIO
############################################################

menu_principal