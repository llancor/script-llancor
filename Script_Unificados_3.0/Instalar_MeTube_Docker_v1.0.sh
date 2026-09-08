#!/usr/bin/env bash

# ==========================================================
# METUBE MANAGER v1.0
# Debian 12 / 13
# Adaptado para instalaciones creadas desde Portainer
# ==========================================================

METUBE_DIR="/opt/metube"
COMPOSE_FILE="$METUBE_DIR/docker-compose.yml"
CONTAINER_NAME="MeTube"
IMAGE="alexta69/metube:latest"
DOWNLOADS_DIR="/portainer/Downloads"
HOST_PORT="8081"
PUID="1000"
PGID="1000"
UMASK_VALUE="022"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

header() {
    clear
    echo -e "${CYAN}"
    echo "========================================="
    echo "            METUBE MANAGER"
    echo "========================================="
    echo -e "${NC}"
}

pause() {
    read -rp "Presione ENTER para continuar..."
}

require_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo -e "${RED}Este script debe ejecutarse como root.${NC}"
        exit 1
    fi
}

container_exists() {
    docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1
}

container_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" = "true" ]
}

server_ip() {
    hostname -I 2>/dev/null | awk '{print $1}'
}

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}Docker no está instalado. Use primero la opción 1.${NC}"
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}Docker no está iniciado o no responde.${NC}"
        return 1
    fi
}

write_compose() {
    mkdir -p "$METUBE_DIR" "$DOWNLOADS_DIR"

    if [ -e "$COMPOSE_FILE" ]; then
        cp -a "$COMPOSE_FILE" "${COMPOSE_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
    fi

    cat > "$COMPOSE_FILE" <<EOF
services:
  metube:
    image: ${IMAGE}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    ports:
      - "${HOST_PORT}:8081"
    environment:
      PUID: "${PUID}"
      PGID: "${PGID}"
      UMASK: "${UMASK_VALUE}"
      DOWNLOAD_DIR: /downloads
      STATE_DIR: /downloads/.metube
      TEMP_DIR: /downloads
    volumes:
      - ${DOWNLOADS_DIR}:/downloads
EOF
}

install_dependencies() {
    header
    echo "Verificando dependencias..."
    echo

    local docker_ok=0 compose_ok=0
    command -v docker >/dev/null 2>&1 && docker_ok=1
    docker compose version >/dev/null 2>&1 && compose_ok=1

    if [ "$docker_ok" -eq 1 ]; then
        echo -e "${GREEN}✓ Docker ya está instalado${NC}"
    else
        echo -e "${YELLOW}✗ Docker no está instalado${NC}"
    fi

    if [ "$compose_ok" -eq 1 ]; then
        echo -e "${GREEN}✓ Docker Compose ya está instalado${NC}"
    else
        echo -e "${YELLOW}✗ Docker Compose no está instalado${NC}"
    fi

    if [ "$docker_ok" -eq 1 ] && [ "$compose_ok" -eq 1 ]; then
        echo
        echo -e "${GREEN}Todas las dependencias ya están instaladas.${NC}"
        pause
        return 0
    fi

    echo
    echo -e "${YELLOW}Instalando las dependencias faltantes...${NC}"
    apt-get update || { echo -e "${RED}Falló apt update.${NC}"; pause; return 1; }
    apt-get install -y ca-certificates curl gnupg || { pause; return 1; }
    install -m 0755 -d /etc/apt/keyrings

    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || { pause; return 1; }
        chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
        . /etc/os-release
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
            > /etc/apt/sources.list.d/docker.list
    fi

    apt-get update && apt-get install -y \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable --now docker
    echo
    docker --version
    docker compose version
    echo
    echo -e "${GREEN}Dependencias instaladas correctamente.${NC}"
    pause
}

install_metube() {
    header
    check_docker || { pause; return; }

    if container_exists; then
        echo -e "${YELLOW}MeTube ya está instalado como contenedor '$CONTAINER_NAME'.${NC}"
        echo "No se realizó ningún cambio. Puede administrarlo desde este menú."
        pause
        return
    fi

    read -rp "Puerto para acceder a MeTube [$HOST_PORT]: " value
    HOST_PORT="${value:-$HOST_PORT}"
    read -rp "Carpeta de descargas [$DOWNLOADS_DIR]: " value
    DOWNLOADS_DIR="${value:-$DOWNLOADS_DIR}"
    read -rp "PUID [$PUID]: " value
    PUID="${value:-$PUID}"
    read -rp "PGID [$PGID]: " value
    PGID="${value:-$PGID}"

    if ! [[ "$HOST_PORT" =~ ^[0-9]+$ ]] || [ "$HOST_PORT" -lt 1 ] || [ "$HOST_PORT" -gt 65535 ]; then
        echo -e "${RED}Puerto no válido.${NC}"
        pause
        return
    fi

    write_compose
    docker compose -f "$COMPOSE_FILE" pull && \
        docker compose -f "$COMPOSE_FILE" up -d

    if container_running; then
        echo
        echo -e "${GREEN}MeTube fue instalado correctamente.${NC}"
        echo "URL: http://$(server_ip):$HOST_PORT"
        echo "Descargas: $DOWNLOADS_DIR"
    else
        echo -e "${RED}MeTube no logró iniciar. Revise los logs desde la opción 8.${NC}"
    fi
    pause
}

show_status() {
    header
    check_docker || { pause; return; }
    if ! container_exists; then
        echo -e "${YELLOW}MeTube no está instalado.${NC}"
        pause
        return
    fi

    echo "Estado del contenedor:"
    docker ps -a --filter "name=^/${CONTAINER_NAME}$"
    echo
    echo "Uso de recursos:"
    docker stats "$CONTAINER_NAME" --no-stream 2>/dev/null || true
    echo
    echo "Imagen instalada:"
    docker inspect -f '{{.Config.Image}} ({{.Image}})' "$CONTAINER_NAME"
    echo
    echo "Carpetas persistentes:"
    docker inspect -f '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}' "$CONTAINER_NAME"
    pause
}

restart_metube() {
    header
    check_docker && container_exists || { echo -e "${RED}MeTube no está instalado.${NC}"; pause; return; }
    docker restart "$CONTAINER_NAME" && echo -e "${GREEN}Servicio reiniciado.${NC}"
    pause
}

start_metube() {
    header
    check_docker && container_exists || { echo -e "${RED}MeTube no está instalado.${NC}"; pause; return; }
    docker start "$CONTAINER_NAME" && echo -e "${GREEN}Servicio iniciado.${NC}"
    pause
}

stop_metube() {
    header
    check_docker && container_exists || { echo -e "${RED}MeTube no está instalado.${NC}"; pause; return; }
    docker stop "$CONTAINER_NAME" && echo -e "${GREEN}Servicio detenido.${NC}"
    pause
}

update_metube() {
    header
    check_docker || { pause; return; }
    container_exists || { echo -e "${RED}MeTube no está instalado.${NC}"; pause; return; }

    local old_image new_image backup_name
    old_image="$(docker inspect -f '{{.Image}}' "$CONTAINER_NAME")"
    echo "Descargando la imagen más reciente: $IMAGE"
    docker pull "$IMAGE" || { echo -e "${RED}No se pudo descargar la imagen.${NC}"; pause; return; }
    new_image="$(docker image inspect -f '{{.Id}}' "$IMAGE")"

    if [ "$old_image" = "$new_image" ]; then
        echo
        echo -e "${GREEN}MeTube ya utiliza la imagen más reciente.${NC}"
        pause
        return
    fi

    echo
    echo "La carpeta $DOWNLOADS_DIR se conservará."
    read -rp "¿Recrear el contenedor para aplicar la actualización? (s/n): " answer
    [[ "$answer" =~ ^[Ss]$ ]] || { echo "Actualización cancelada."; pause; return; }

    # Conserva el contenedor anterior detenido hasta verificar el nuevo.
    backup_name="MeTube-anterior-$(date +%Y%m%d-%H%M%S)"
    docker stop "$CONTAINER_NAME" >/dev/null || { pause; return; }
    docker rename "$CONTAINER_NAME" "$backup_name" || { pause; return; }

    write_compose
    if docker compose -f "$COMPOSE_FILE" up -d && container_running; then
        docker rm "$backup_name" >/dev/null
        echo
        echo -e "${GREEN}MeTube fue actualizado correctamente.${NC}"
        echo "Imagen anterior: $old_image"
        echo "Imagen nueva:    $new_image"
        echo "Descargas conservadas en: $DOWNLOADS_DIR"
    else
        echo -e "${RED}La versión nueva no inició. Restaurando el contenedor anterior...${NC}"
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rename "$backup_name" "$CONTAINER_NAME"
        docker start "$CONTAINER_NAME"
        echo -e "${YELLOW}Se restauró la versión anterior.${NC}"
    fi
    pause
}

show_logs() {
    header
    check_docker && container_exists || { echo -e "${RED}MeTube no está instalado.${NC}"; pause; return; }
    echo "Mostrando las últimas 100 líneas. Presione Ctrl+C para salir."
    echo
    docker logs --tail 100 -f "$CONTAINER_NAME"
    pause
}

show_configuration() {
    header
    check_docker && container_exists || { echo -e "${RED}MeTube no está instalado.${NC}"; pause; return; }
    echo "Nombre: $CONTAINER_NAME"
    echo "URL: http://$(server_ip):$(docker port "$CONTAINER_NAME" 8081/tcp 2>/dev/null | head -n1 | awk -F: '{print $NF}')"
    echo "Imagen: $(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME")"
    echo "Reinicio: $(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$CONTAINER_NAME")"
    echo
    echo "Volúmenes:"
    docker inspect -f '{{range .Mounts}}{{.Source}} -> {{.Destination}} (RW={{.RW}}){{println}}{{end}}' "$CONTAINER_NAME"
    echo
    echo "Variables configurables:"
    docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME" \
        | grep -E '^(PUID|PGID|UMASK|DOWNLOAD_DIR|STATE_DIR|TEMP_DIR|PORT)=' || true
    pause
}

uninstall_metube() {
    header
    check_docker || { pause; return; }
    if ! container_exists; then
        echo -e "${YELLOW}MeTube no está instalado.${NC}"
        pause
        return
    fi

    echo -e "${YELLOW}Se eliminará solamente el contenedor MeTube.${NC}"
    echo "Las descargas de $DOWNLOADS_DIR se conservarán."
    read -rp "¿Continuar? Escriba ELIMINAR para confirmar: " answer
    [ "$answer" = "ELIMINAR" ] || { echo "Desinstalación cancelada."; pause; return; }

    docker rm -f "$CONTAINER_NAME"
    if [ -f "$COMPOSE_FILE" ]; then
        rm -f "$COMPOSE_FILE"
        rmdir "$METUBE_DIR" 2>/dev/null || true
    fi
    echo
    echo -e "${GREEN}MeTube fue desinstalado.${NC}"
    echo "Las descargas permanecen en $DOWNLOADS_DIR"
    pause
}

require_root

while true; do
    header
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}          GESTOR DE METUBE v1.0         ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo
    echo -e "${YELLOW}[1]${NC} ${CYAN}Instalar dependencias${NC}"
    echo -e "${YELLOW}[2]${NC} ${CYAN}Instalar MeTube${NC}"
    echo -e "${YELLOW}[3]${NC} ${CYAN}Ver estado${NC}"
    echo -e "${YELLOW}[4]${NC} ${CYAN}Reiniciar servicio${NC}"
    echo -e "${YELLOW}[5]${NC} ${CYAN}Iniciar servicio${NC}"
    echo -e "${YELLOW}[6]${NC} ${CYAN}Detener servicio${NC}"
    echo -e "${YELLOW}[7]${NC} ${CYAN}Actualizar MeTube${NC}"
    echo -e "${YELLOW}[8]${NC} ${CYAN}Ver logs en tiempo real${NC}"
    echo -e "${YELLOW}[9]${NC} ${CYAN}Mostrar configuración${NC}"
    echo -e "${YELLOW}[10]${NC} ${CYAN}Desinstalar MeTube${NC}"
    echo
    echo -e "${YELLOW}[0]${NC} ${RED}Salir${NC}"
    echo

    read -rp "Seleccione una opción: " option
    case "$option" in
        1) install_dependencies ;;
        2) install_metube ;;
        3) show_status ;;
        4) restart_metube ;;
        5) start_metube ;;
        6) stop_metube ;;
        7) update_metube ;;
        8) show_logs ;;
        9) show_configuration ;;
        10) uninstall_metube ;;
        0) exit 0 ;;
        *) echo "Opción inválida"; sleep 2 ;;
    esac
done
