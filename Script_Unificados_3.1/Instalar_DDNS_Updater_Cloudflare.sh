#!/bin/bash

# ==========================================
# DDNS UPDATER MANAGER
# ==========================================

APP_NAME="ddns-updater"
APP_DIR="/opt/ddns-updater"
COMPOSE_FILE="$APP_DIR/docker-compose.yml"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

banner() {

    clear

    echo -e "${CYAN}"
    echo "=================================================="
    echo "            DDNS UPDATER MANAGER"
    echo "=================================================="
    echo -e "${NC}"

    echo -e "${BLUE}Servidor:${NC} $(hostname)"
    echo -e "${BLUE}IP Local:${NC} $(hostname -I | awk '{print $1}')"
    echo -e "${BLUE}CPU:${NC} $(nproc) núcleos"
    echo -e "${BLUE}RAM:${NC} $(free -h | awk '/Mem:/ {print $3 "/" $2}')"
    echo
}

ok() {
    echo -e "${GREEN}✔ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

error() {
    echo -e "${RED}✖ $1${NC}"
}

info() {
    echo -e "${BLUE}➜ $1${NC}"
}

pause() {
    echo
    read -rp "Presione ENTER para continuar..."
}

detect_compose() {

    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
        return 0
    fi

    if command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
        return 0
    fi

    return 1
}

check_dependencies() {

    info "Verificando dependencias..."

    if ! command -v docker >/dev/null 2>&1; then
        error "Docker no está instalado"
        return 1
    fi

    if ! detect_compose; then
        error "Docker Compose no encontrado"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        warn "jq no encontrado, instalando..."

        apt update -qq
        apt install -y jq

        if ! command -v jq >/dev/null 2>&1; then
            error "No fue posible instalar jq"
            return 1
        fi
    fi

    ok "Dependencias OK"
    return 0
}

install_dependencies() {

    if check_dependencies; then
        return
    fi

    info "Instalando dependencias..."

    apt update

    if ! command -v docker >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com | sh
    fi

    if ! detect_compose; then
        apt install -y docker-compose
		
    fi

    ok "Dependencias instaladas"
}

is_installed() {
    docker inspect "$APP_NAME" >/dev/null 2>&1
}

port_in_use() {
    ss -tuln | grep -q ":$1 "
}

get_free_port() {

    for port in 8000 8001 8002 8003 8004 8080 8081 8082 8085 8090; do

        if ! port_in_use "$port"; then
            echo "$port"
            return
        fi

    done

    echo "9000"
}

install_app() {

    check_dependencies || install_dependencies

    if is_installed; then

        STATUS=$(docker inspect -f '{{.State.Status}}' "$APP_NAME")

        if [ "$STATUS" = "running" ]; then
            warn "DDNS Updater ya está instalado"
            return
        fi

        warn "Instalación dañada detectada ($STATUS)"

        docker rm -f "$APP_NAME" >/dev/null 2>&1

    fi

    DEFAULT_PORT=$(get_free_port)

    while true; do

        read -rp "Puerto Web [$DEFAULT_PORT]: " PORT
        PORT=${PORT:-$DEFAULT_PORT}

        if port_in_use "$PORT"; then
            error "El puerto $PORT está ocupado"
            continue
        fi

        break

    done

    mkdir -p "$APP_DIR/data"

    chmod -R 777 "$APP_DIR/data"

    if [ ! -f "$APP_DIR/data/config.json" ]; then
        echo "{}" > "$APP_DIR/data/config.json"
    fi

    chmod 666 "$APP_DIR/data/config.json"

    cat > "$COMPOSE_FILE" <<EOF
services:
  ddns-updater:
    image: qmcgaw/ddns-updater:latest
    container_name: ddns-updater
    restart: unless-stopped
    ports:
      - "$PORT:8000"
    volumes:
      - ./data:/updater/data
EOF

    detect_compose

    cd "$APP_DIR" || return

    $COMPOSE_CMD up -d

    sleep 10

    if docker ps --filter "name=$APP_NAME" --filter "status=running" | grep -q "$APP_NAME"; then

        ok "DDNS Updater iniciado correctamente"

        echo
        echo "URL: http://$(hostname -I | awk '{print $1}'):$PORT"
        echo

    else

        error "DDNS Updater no inició correctamente"

        echo
        docker logs --tail=30 "$APP_NAME"
        echo

    fi
}

update_app() {

    if [ ! -d "$APP_DIR" ]; then
        error "DDNS Updater no está instalado"
        return
    fi

    detect_compose

    cd "$APP_DIR" || return

    info "Actualizando..."

    $COMPOSE_CMD pull
    $COMPOSE_CMD up -d

    ok "Actualizado"
}

restart_app() {

    if is_installed; then

        docker restart "$APP_NAME"

        ok "Contenedor reiniciado"

    else

        error "DDNS Updater no está instalado"

    fi
}

logs_app() {

    if is_installed; then

        docker logs -f "$APP_NAME"

    else

        error "DDNS Updater no está instalado"

    fi
}

status_app() {

    echo

    docker ps -a --filter "name=$APP_NAME"

    echo
}

show_public_ip() {

    info "Consultando IP pública..."

    echo
    curl -s https://api.ipify.org
    echo
}

backup_app() {

    mkdir -p /root/backups

    FILE="/root/backups/ddns-updater-$(date +%F-%H%M).tar.gz"

    tar -czf "$FILE" "$APP_DIR" 2>/dev/null

    ok "Backup creado:"
    echo "$FILE"
}

uninstall_app() {

    warn "Se eliminará DDNS Updater"

    read -rp "¿Continuar? (s/N): " CONFIRM

    [[ "$CONFIRM" =~ ^[sS]$ ]] || return

    docker rm -f "$APP_NAME" >/dev/null 2>&1

    rm -rf "$APP_DIR"

    docker image prune -f >/dev/null 2>&1

    docker network prune -f >/dev/null 2>&1

    ok "DDNS Updater eliminado completamente"
}
# ==============================
# DDNS UPDATER CONFIG MANAGER PRO
# ==============================

CONFIG_FILE="/opt/ddns-updater/data/config.json"
CONTAINER="ddns-updater"
BACKUP_DIR="/opt/ddns-updater/backups"

ensure_dirs() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    mkdir -p "$BACKUP_DIR"
}

backup_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$BACKUP_DIR/config_$(date +%F_%H-%M-%S).json"
    fi
}

restart_container() {
    docker restart "$CONTAINER" >/dev/null 2>&1
}

validar_json() {
    python3 -m json.tool "$CONFIG_FILE" >/dev/null 2>&1
}

crear_config() {

    ensure_dirs
    backup_config

    echo '{ "settings": [' > "$CONFIG_FILE"

    FIRST=1

    while true; do

        echo
        read -rp "Dominio completo (ej: 6002i.llancor.com) o 'fin' para terminar: " DOMAIN

        [[ "$DOMAIN" =~ ^(fin|exit|done)$ ]] && break

        echo
        echo "⚠️ NO escriba llancor.com ni 6002i.llancor.com"
        echo "⚠️ Debe ingresar el Zone ID de Cloudflare"
        echo "⚠️ Ejemplo: 8f7a1234567890abcdef1234567890ab"
        echo

        read -rp "Zone ID Cloudflare: " ZONE_ID
        read -rp "API Token Cloudflare: " TOKEN

        [[ -z "$DOMAIN" || -z "$ZONE_ID" || -z "$TOKEN" ]] && {
            echo "❌ Todos los campos son obligatorios"
            continue
        }

        [[ $FIRST -eq 0 ]] && echo "," >> "$CONFIG_FILE"

        cat >> "$CONFIG_FILE" <<EOF
{
  "provider": "cloudflare",
  "domain": "$DOMAIN",
  "zone_identifier": "$ZONE_ID",
  "ttl": 1,
  "token": "$TOKEN",
  "ip_version": "ipv4"
}
EOF

        FIRST=0

        echo
        echo "✅ Dominio agregado: $DOMAIN"

    done

    echo '] }' >> "$CONFIG_FILE"

    echo
    echo "🔍 Validando configuración..."

    if validar_json; then

        echo "✅ JSON válido"

        echo
        echo "📄 Configuración generada:"
        python3 -m json.tool "$CONFIG_FILE"

        echo
        echo "🔄 Reiniciando DDNS Updater..."

        restart_container

        sleep 5

        echo
        echo "📋 Últimos logs:"
        docker logs --tail 20 "$CONTAINER"

    else

        echo "❌ JSON inválido"

    fi
}

ver_config() {
    echo
    [[ -f "$CONFIG_FILE" ]] && cat "$CONFIG_FILE" || echo "⚠️ No existe configuración"
    echo
}

borrar_config() {

    read -rp "¿Eliminar configuración? (s/N): " RESP

    [[ ! "$RESP" =~ ^[sS]$ ]] && return

    backup_config
    echo "{}" > "$CONFIG_FILE"

    restart_container
    echo "✅ Configuración eliminada"
}

borrar_dominio() {

    mapfile -t DOMINIOS < <(
        jq -r '.settings[].domain' "$CONFIG_FILE" 2>/dev/null
    )

    if [[ ${#DOMINIOS[@]} -eq 0 ]]; then
        echo
        echo "❌ No hay dominios configurados"
        return
    fi

    echo
    echo "==================================="
    echo "      DOMINIOS CONFIGURADOS"
    echo "==================================="
    echo

    for i in "${!DOMINIOS[@]}"; do
        echo "$((i+1))) ${DOMINIOS[$i]}"
    done

    echo
    read -rp "Seleccione dominio a borrar (ENTER cancela): " OP

    if [[ -z "$OP" ]]; then
        echo
        echo "❌ Operación cancelada"
        return
    fi

    if [[ ! "$OP" =~ ^[0-9]+$ ]]; then
        echo
        echo "❌ Debe ingresar un número válido"
        return
    fi

    INDEX=$((OP-1))

    if [[ -z "${DOMINIOS[$INDEX]}" ]]; then
        echo
        echo "❌ Opción inválida"
        return
    fi

    echo
    echo "Dominio seleccionado:"
    echo "👉 ${DOMINIOS[$INDEX]}"
    echo

    read -rp "¿Eliminar este dominio? (s/N): " RESP

    if [[ ! "$RESP" =~ ^[sS]$ ]]; then
        echo
        echo "❌ Operación cancelada"
        return
    fi

    backup_config

    if ! jq "del(.settings[$INDEX])" "$CONFIG_FILE" > /tmp/ddns-config.json; then
        echo
        echo "❌ Error al modificar configuración"
        return
    fi

    mv /tmp/ddns-config.json "$CONFIG_FILE"

    echo
    echo "🔍 Validando configuración..."

    if validar_json; then

        echo "✅ Dominio eliminado"

        SETTINGS_COUNT=$(jq '.settings | length' "$CONFIG_FILE" 2>/dev/null)

        if [[ "$SETTINGS_COUNT" -eq 0 ]]; then
            echo
            echo "ℹ️ No quedan dominios configurados"
        fi

        restart_container

    else

        echo "❌ Error: configuración inválida"
        restore_last_backup
        return

    fi

    echo
    echo "📋 Configuración actual:"
    python3 -m json.tool "$CONFIG_FILE"

}

restaurar_backup() {

    echo
    echo "📦 Backups disponibles:"
    echo "--------------------------------"

    select FILE in "$BACKUP_DIR"/*.json; do
        [[ -z "$FILE" ]] && echo "Cancelado" && return

        cp "$FILE" "$CONFIG_FILE"
        echo "♻️ Restaurado: $FILE"

        restart_container
        break
    done
}

ddns_menu() {

    while true; do
        clear

echo -e "${CYAN}===================================${NC}"
echo -e "${GREEN}   DDNS UPDATER PRO MANAGER${NC}"
echo -e "${CYAN}===================================${NC}"
echo
echo -e "${YELLOW}1)${NC} Crear configuración Cloudflare"
echo -e "${YELLOW}2)${NC} Ver configuración"
echo -e "${YELLOW}3)${NC} Borrar una API Token DDNS"
echo -e "${YELLOW}4)${NC} Borrar Todas las API Token DDNS"
echo -e "${YELLOW}5)${NC} Restaurar backup"
echo -e "${RED}0)${NC} Salir"
echo

        read -rp "Opción: " OP

        case "$OP" in
            1) crear_config ;;
            2) ver_config ;;
			3) borrar_dominio ;;
            4) borrar_config ;;
            5) restaurar_backup ;;
            0) break ;;
            *) echo "Opción inválida" ;;
        esac

        echo
        read -rp "ENTER para continuar..."
    done
}

menu() {

    while true; do

        banner

        echo -e "${WHITE}Seleccione una opción:${NC}"
        echo
        echo -e "${GREEN}1)${NC} Instalar"
        echo -e "${GREEN}2)${NC} Actualizar"
        echo -e "${GREEN}3)${NC} Estado"
        echo -e "${GREEN}4)${NC} Reiniciar"
        echo -e "${GREEN}5)${NC} Ver Logs"
        echo -e "${GREEN}6)${NC} Verificar Dependencias"
        echo -e "${GREEN}7)${NC} Backup"
        echo -e "${GREEN}8)${NC} Ver IP Pública"
        echo -e "${GREEN}9)${NC} Desinstalar"
		echo -e "${GREEN}10)${YELLOW} Configurar DDNS Updater / Cloudflare ${GREEN}(usar source no ./)"
        echo -e "${RED}0)${NC} Salir"
        echo

        read -rp "Opción: " OP

        case $OP in
            1) install_app ;;
            2) update_app ;;
            3) status_app ;;
            4) restart_app ;;
            5) logs_app ;;
            6) check_dependencies ;;
            7) backup_app ;;
            8) show_public_ip ;;
            9) uninstall_app ;;
			10) ddns_menu ;;
            0) clear; exit ;;
            *) error "Opción inválida" ;;
        esac

        pause

    done
}

menu
