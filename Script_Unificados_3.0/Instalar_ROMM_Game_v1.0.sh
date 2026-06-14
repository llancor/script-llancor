#!/bin/bash
# ===== COLORES =====

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
ROMM_DIR="/opt/romm"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Ejecute como root"
        exit 1
    fi
}

check_dependencies() {

    echo "Verificando dependencias..."

    if ! command -v docker >/dev/null 2>&1; then

        echo "Instalando Docker..."

        apt update
        apt install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        mkdir -p /etc/apt/keyrings

        curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

        echo \
        "deb [arch=$(dpkg --print-architecture) \
        signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/debian \
        $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
        > /etc/apt/sources.list.d/docker.list

        apt update

        apt install -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin

        systemctl enable docker
        systemctl start docker

    fi

    echo "Dependencias OK"
}
install_romm() {
check_dependencies
    ROMM_DIR="/opt/romm"

    clear

    echo
    echo "════════════════════════════════════════════"
    echo "           INSTALADOR ROMM"
    echo "════════════════════════════════════════════"
    echo

    # Detectar instalación existente
    if docker ps -a --format '{{.Names}}' | grep -q '^romm$'; then
        echo "⚠️ RomM ya está instalado (contenedor existente)."
        read -rp "¿Reinstalar de todas formas? [s/N]: " CONF
        [[ "$CONF" != "s" && "$CONF" != "S" ]] && return

        echo "Eliminando contenedores antiguos..."
        docker compose -f "$ROMM_DIR/docker-compose.yml" down 2>/dev/null
        docker rm -f romm romm-db 2>/dev/null
    fi

    read -rp "Puerto RomM [8087]: " ROMM_PORT
    ROMM_PORT=${ROMM_PORT:-8087}

    read -rp "Ruta backups [/opt/backups/romm]: " BACKUP_DIR
    BACKUP_DIR=${BACKUP_DIR:-/opt/backups/romm}

    mkdir -p "$ROMM_DIR"
    mkdir -p "$BACKUP_DIR"

    mkdir -p "$ROMM_DIR/library/roms"
    mkdir -p "$ROMM_DIR/assets"
    mkdir -p "$ROMM_DIR/config"
    mkdir -p "$ROMM_DIR/mariadb"

    # Usuarios/permisos (evita errores de escritura)
    chown -R 1000:1000 "$ROMM_DIR" 2>/dev/null

    DB_PASS=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)
    SECRET=$(openssl rand -hex 32)

    cat > "$ROMM_DIR/.env" <<EOF
TZ=America/Santiago

ROMM_AUTH_SECRET_KEY=$SECRET

DB_HOST=romm-db
DB_PORT=3306
DB_TYPE=mariadb
DB_NAME=romm
DB_USER=romm
DB_PASSWD=$DB_PASS
EOF

    cat > "$ROMM_DIR/docker-compose.yml" <<EOF
services:

  mariadb:
    image: mariadb:11
    container_name: romm-db
    restart: unless-stopped

    environment:
      MARIADB_ROOT_PASSWORD: rootpassword
      MARIADB_DATABASE: romm
      MARIADB_USER: romm
      MARIADB_PASSWORD: $DB_PASS

    volumes:
      - ./mariadb:/var/lib/mysql

    healthcheck:
      test: ["CMD", "mariadb-admin", "ping", "-h", "localhost"]
      interval: 5s
      timeout: 3s
      retries: 20

  romm:
    image: rommapp/romm:latest
    container_name: romm
    restart: unless-stopped

    depends_on:
      mariadb:
        condition: service_healthy

    env_file:
      - .env

    ports:
      - "$ROMM_PORT:8080"

    volumes:
      - ./library/roms:/romm/library
      - ./assets:/romm/assets
      - ./config:/romm/config
EOF

    cd "$ROMM_DIR" || return

    echo
    echo "📥 Descargando imágenes..."
    docker compose pull

    echo
    echo "🚀 Iniciando contenedores..."
    docker compose up -d

    echo
    echo "⏳ Esperando MariaDB (healthcheck)..."

    # Espera real (no sleep fijo)
    until docker ps --format '{{.Names}} {{.Status}}' | grep romm-db | grep -q "healthy"; do
        sleep 3
    done

    echo "✅ MariaDB lista"

    echo
    echo "⏳ Esperando RomM..."
    sleep 10

    IP_LOCAL=$(hostname -I | awk '{print $1}')

    echo
    echo "════════════════════════════════════════════"
    echo "          ROMM INSTALADO"
    echo "════════════════════════════════════════════"
    echo
    echo "Ruta        : $ROMM_DIR"
    echo "ROMs        : $ROMM_DIR/library/roms"
    echo "Backups     : $BACKUP_DIR"
    echo
    echo "IP Local    : $IP_LOCAL"
    echo "Puerto      : $ROMM_PORT"
    echo
    echo "Acceso:"
    echo "http://$IP_LOCAL:$ROMM_PORT"
    echo
    echo "📌 Logs si falla:"
    echo "docker logs romm --tail 100"
    echo "docker logs romm-db --tail 100"
    echo

    docker ps --filter name=romm
}
remove_romm() {

    clear

    echo "═══════════════════════════════════════"
    echo "          DESINSTALAR ROMM"
    echo "═══════════════════════════════════════"
    echo

    if [ ! -d "$ROMM_DIR" ]; then
        echo "RomM no está instalado en $ROMM_DIR"
        return
    fi

    cd "$ROMM_DIR" || return

    echo "Se eliminarán los siguientes componentes:"
    echo
    echo "📦 Contenedores:"
    docker ps -a --format '{{.Names}}' | grep -E '^romm$|^romm-db$' || echo "   (no encontrados)"

    echo
    echo "🧱 Imágenes usadas por este stack:"
    docker inspect romm romm-db \
        --format '{{.Config.Image}}' 2>/dev/null | sort -u

    echo
    echo "📁 Directorio del proyecto:"
    echo "   $ROMM_DIR"

    echo
    echo "💾 Volúmenes Docker (si existen):"
    docker volume ls --format '{{.Name}}' | grep romm || echo "   (ninguno)"

    echo
    read -rp "¿Continuar con la desinstalación? [s/N]: " CONF

    if [[ ! "$CONF" =~ ^[Ss]$ ]]; then
        echo "Cancelado."
        return
    fi

    echo
    echo "Deteniendo contenedores..."
    docker compose down --remove-orphans 2>/dev/null

    echo "Eliminando contenedores..."
    docker rm -f romm romm-db 2>/dev/null

    echo
    read -rp "¿Eliminar imágenes de RomM? [s/N]: " IMG

    if [[ "$IMG" =~ ^[Ss]$ ]]; then

        docker inspect romm romm-db \
            --format '{{.Config.Image}}' 2>/dev/null | sort -u |
        while read -r IMAGE; do
            echo "Eliminando imagen: $IMAGE"
            docker image rm -f "$IMAGE" 2>/dev/null
        done

    fi

    echo
    read -rp "¿Eliminar TODOS los datos en $ROMM_DIR? [s/N]: " DATA

    if [[ "$DATA" =~ ^[Ss]$ ]]; then
        rm -rf "$ROMM_DIR"
        echo "Datos eliminados."
    else
        echo "Datos conservados en $ROMM_DIR"
    fi

    echo
    echo "Limpiando recursos huérfanos..."
    docker network prune -f >/dev/null 2>&1
    docker volume prune -f >/dev/null 2>&1

    echo
    echo "═══════════════════════════════════════"
    echo "        ROMM DESINSTALADO"
    echo "═══════════════════════════════════════"
    echo
}

status_romm() {

    docker ps -a --filter name=romm
}

restart_romm() {

    cd "$ROMM_DIR" || exit

    docker compose restart
}

start_romm() {

    cd "$ROMM_DIR" || exit

    docker compose up -d
}

stop_romm() {

    cd "$ROMM_DIR" || exit

    docker compose stop
}

update_romm() {

    cd "$ROMM_DIR" || exit

    docker compose pull
    docker compose up -d

    echo "Actualización completada"
}
show_info() {

    clear

    if ! docker ps -a --format '{{.Names}}' | grep -q '^romm$'; then
        echo "RomM no está instalado."
        return
    fi

    IP_LOCAL=$(hostname -I | awk '{print $1}')

    PUERTO=$(docker inspect romm \
        --format='{{(index (index .NetworkSettings.Ports "8080/tcp") 0).HostPort}}' \
        2>/dev/null)

    echo
    echo "═══════════════════════════════════════"
    echo "           INFORMACIÓN ROMM"
    echo "═══════════════════════════════════════"
    echo
    echo "Contenedor : romm"
    echo "IP Servidor: $IP_LOCAL"
    echo "Puerto     : $PUERTO"
    echo
    echo "Acceso LAN:"
    echo "http://$IP_LOCAL:$PUERTO"
    echo

    if command -v curl >/dev/null 2>&1; then

        PUBLIC_IP=$(curl -s ifconfig.me)

        if [ -n "$PUBLIC_IP" ]; then
            echo "IP Pública : $PUBLIC_IP"
            echo "Acceso WAN : http://$PUBLIC_IP:$PUERTO"
        fi

    fi

    echo
}
menu() {

while true
do

clear

echo -e "${CYAN}"
echo "╔══════════════════════════════════════╗"
echo "║           ROMM MANAGER              ║"
echo "║         Debian 11 / 12              ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}[1]${NC} Instalar RomM"
echo -e "${YELLOW}[2]${NC} Desinstalar RomM"
echo -e "${YELLOW}[3]${NC} Estado"
echo -e "${YELLOW}[4]${NC} Iniciar"
echo -e "${YELLOW}[5]${NC} Detener"
echo -e "${YELLOW}[6]${NC} Reiniciar"
echo -e "${YELLOW}[7]${NC} Actualizar"
echo -e "${YELLOW}[8]${NC} Información"
echo
echo -e "${CYAN}[0]${NC} Salir"
echo

read -p "Opción: " OP

case $OP in

1) install_romm ;;
2) remove_romm ;;
3) status_romm ;;
4) start_romm ;;
5) stop_romm ;;
6) restart_romm ;;
7) update_romm ;;
8) show_info ;;
0) exit ;;

*) echo "Opción inválida" ;;

esac

echo
read -p "Enter para continuar..."
done
}

check_root
menu
