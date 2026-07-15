#!/bin/bash

# ============================================================
# WG-Easy Manager v1.0
# Debian 12
# Docker + WG-Easy v15
# ============================================================

set -e

VERSION="1.0"
APP_NAME="WG-Easy Manager"

INSTALL_DIR="/opt/wg-easy"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
CONTAINER_NAME="wg-easy"

DEFAULT_UDP_PORT=51820
DEFAULT_TCP_PORT=51821

############################
# Colores
############################

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
WHITE="\e[97m"
RESET="\e[0m"

############################
# Mensajes
############################

success() {
    echo -e "${GREEN}[ OK ]${RESET} $1"
}

error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${RESET} $1"
}

info() {
    echo -e "${CYAN}[INFO]${RESET} $1"
}

pause() {
    echo
    read -rp "Presione ENTER para continuar..."
}

############################
# Banner
############################

banner() {

clear

echo -e "${GREEN}"
cat << "EOF"

 __      __  _____          ______
 \ \    / / / ____|        |  ____|
  \ \  / / | |  __  ______ | |__
   \ \/ /  | | |_ | |______||  __|
    \  /   | |__| |        | |____
     \/     \_____|        |______|

EOF

echo -e "${CYAN}"

echo "======================================================"
echo "              WG-Easy Manager v$VERSION"
echo "======================================================"
echo
}

############################
# Detectar IP Local
############################

get_local_ip() {

hostname -I | awk '{print $1}'

}

############################
# Detectar IP Pública
############################

get_public_ip() {

curl -s https://api.ipify.org

}

############################
# Verificar Root
############################

check_root(){

if [ "$EUID" != "0" ]; then

    error "Debe ejecutar este script como root."

    exit 1

fi

}
desinstalar_wg_easy(){

banner

warning "Esto eliminará WG-Easy"

read -rp "¿Continuar? (s/n): " RESP

if [[ "$RESP" =~ ^[sS]$ ]]; then

    cd "$INSTALL_DIR"

    docker compose down

    rm -rf "$INSTALL_DIR"

    success "WG-Easy eliminado"

else

    warning "Operación cancelada"

fi

pause

}
iniciar_servicio(){

cd "$INSTALL_DIR"

docker compose start

success "WG-Easy iniciado"

pause

}
detener_servicio(){

cd "$INSTALL_DIR"

docker compose stop

success "WG-Easy detenido"

pause

}
reiniciar_servicio(){

cd "$INSTALL_DIR"

docker compose restart

success "WG-Easy reiniciado"

pause

}
estado_servicio(){

banner

docker ps --filter name=wg-easy

echo

pause

}
ver_logs(){

banner

docker logs --tail 100 wg-easy

pause

}
cambiar_puerto_udp(){

banner

if [ ! -f "$COMPOSE_FILE" ]; then

error "WG-Easy no instalado"

pause

return

fi


read -rp "Nuevo puerto UDP: " NUEVO

sed -i \
"s/[0-9]*:51820\/udp/$NUEVO:51820\/udp/" \
"$COMPOSE_FILE"


cd "$INSTALL_DIR"

docker compose up -d

success "Puerto UDP cambiado a $NUEVO"

pause

}
cambiar_puerto_tcp(){

banner

read -rp "Nuevo puerto Panel Web: " NUEVO


sed -i \
"s/[0-9]*:51821\/tcp/$NUEVO:51821\/tcp/" \
"$COMPOSE_FILE"


cd "$INSTALL_DIR"

docker compose up -d


success "Puerto Web cambiado a $NUEVO"

pause

}
actualizar_wg_easy(){

banner

cd "$INSTALL_DIR"

docker compose pull

docker compose up -d


success "WG-Easy actualizado"

pause

}
backup(){

banner

FECHA=$(date +%Y-%m-%d_%H-%M)

mkdir -p /root/wg-backups


tar -czf \
/root/wg-backups/wg-easy-$FECHA.tar.gz \
"$INSTALL_DIR"


success "Backup creado:"
echo
echo "/root/wg-backups/wg-easy-$FECHA.tar.gz"

pause

}
restaurar_backup(){

banner

ls -lh /root/wg-backups

echo

read -rp "Archivo backup: " ARCHIVO


if [ -f "/root/wg-backups/$ARCHIVO" ]; then

tar -xzf \
"/root/wg-backups/$ARCHIVO" \
-C /


cd "$INSTALL_DIR"

docker compose up -d


success "Restauración completada"

else

error "Archivo no encontrado"

fi

pause

}
mostrar_ip(){

banner

LOCAL=$(hostname -I | awk '{print $1}')

PUBLICA=$(curl -s https://api.ipify.org)


echo
echo -e "${CYAN}IP Local:${RESET} $LOCAL"

echo -e "${CYAN}IP Pública:${RESET} $PUBLICA"

echo

pause

}
############################################################
# Activar / Desactivar HTTPS WG-Easy
############################################################
############################################################
# Configurar HTTPS / HTTP WG-Easy
############################################################

configurar_https_wg_easy(){

banner

echo "============== CONFIGURAR HTTPS WG-EASY =============="

echo

echo -e "${YELLOW}1)${RESET} ${WHITE}Activar HTTPS (INSECURE=false)${RESET}"
echo -e "${YELLOW}2)${RESET} ${WHITE}Desactivar HTTPS (INSECURE=true)${RESET}"
echo -e "${YELLOW}0)${RESET} ${WHITE}Volver${RESET}"

echo

read -rp "Seleccione una opción: " HTTPS_OP

case "$HTTPS_OP" in

1)

    if [ ! -f "$COMPOSE_FILE" ]; then
        error "WG-Easy no está instalado."
        pause
        return
    fi

    if grep -q "INSECURE=false" "$COMPOSE_FILE"; then
        warning "HTTPS ya está activado."
        pause
        return
    fi

    info "Activando HTTPS..."

    sed -i 's/INSECURE=true/INSECURE=false/g' "$COMPOSE_FILE"

    cd "$INSTALL_DIR"

    docker compose up -d --force-recreate

    sleep 5

    if docker inspect "$CONTAINER_NAME" | grep -q '"INSECURE=false"'; then
        success "HTTPS activado correctamente."
        echo
        info "Recuerde que deberá acceder mediante HTTPS."
    else
        error "No fue posible activar HTTPS."
    fi

    ;;

2)

    if [ ! -f "$COMPOSE_FILE" ]; then
        error "WG-Easy no está instalado."
        pause
        return
    fi

    if grep -q "INSECURE=true" "$COMPOSE_FILE"; then
        warning "HTTP ya está activado."
        pause
        return
    fi

    info "Desactivando HTTPS..."

    sed -i 's/INSECURE=false/INSECURE=true/g' "$COMPOSE_FILE"

    cd "$INSTALL_DIR"

    docker compose up -d --force-recreate

    sleep 5

    if docker inspect "$CONTAINER_NAME" | grep -q '"INSECURE=true"'; then
        success "HTTP activado correctamente."
        echo
        warning "Ahora podrá acceder mediante HTTP."
    else
        error "No fue posible desactivar HTTPS."
    fi

    ;;

0)

    return

    ;;

*)

    warning "Opción incorrecta."

    ;;

esac

pause

}
############################
# Menú Principal
############################

main_menu(){

while true
do

banner

echo -e "${YELLOW}1)${RESET} ${WHITE}Verificar dependencias${RESET}"

echo -e "${YELLOW}2)${RESET} ${WHITE}Instalar Docker${RESET}"

echo -e "${YELLOW}3)${RESET} ${WHITE}Iniciar Docker${RESET}"

echo -e "${YELLOW}4)${RESET} ${WHITE}Detener Docker${RESET}"

echo -e "${YELLOW}5)${RESET} ${WHITE}Reiniciar Docker${RESET}"

echo -e "${YELLOW}6)${RESET} ${WHITE}Estado Docker${RESET}"

echo -e "${YELLOW}7)${RESET} ${WHITE}Desinstalar Docker${RESET}"

echo -e "${YELLOW}8)${RESET} ${WHITE}Instalar WG-Easy${RESET}"

echo -e "${YELLOW}9)${RESET} ${WHITE}Desinstalar WG-Easy${RESET}"

echo -e "${YELLOW}10)${RESET} ${WHITE}Iniciar WG-Easy${RESET}"

echo -e "${YELLOW}11)${RESET} ${WHITE}Detener WG-Easy${RESET}"

echo -e "${YELLOW}12)${RESET} ${WHITE}Reiniciar WG-Easy${RESET}"

echo -e "${YELLOW}13)${RESET} ${WHITE}Estado WG-Easy${RESET}"

echo -e "${YELLOW}14)${RESET} ${WHITE}Ver Logs${RESET}"

echo -e "${YELLOW}15)${RESET} ${WHITE}Cambiar Puerto UDP${RESET}"

echo -e "${YELLOW}16)${RESET} ${WHITE}Cambiar Puerto TCP${RESET}"

echo -e "${YELLOW}17)${RESET} ${WHITE}Actualizar WG-Easy${RESET}"

echo -e "${YELLOW}18)${RESET} ${WHITE}Backup${RESET}"

echo -e "${YELLOW}19)${RESET} ${WHITE}Restaurar Backup${RESET}"

echo -e "${YELLOW}20)${RESET} ${WHITE}Mostrar IP${RESET}"

echo -e "${YELLOW}21)${RESET} ${WHITE}Configurar HTTPS WG-Easy${RESET}"

echo

echo -e "${YELLOW}0)${RESET} ${WHITE}Salir${RESET}"

echo

read -rp "Seleccione una opción: " OPCION

case $OPCION in

1) verificar_dependencias ;;
2) instalar_docker ;;
3) iniciar_docker ;;
4) detener_docker ;;
5) reiniciar_docker ;;
6) estado_docker ;;
7) desinstalar_docker ;;
8) instalar_wg_easy ;;
9) desinstalar_wg_easy ;;
10) iniciar_servicio ;;
11) detener_servicio ;;
12) reiniciar_servicio ;;
13) estado_servicio ;;
14) ver_logs ;;
15) cambiar_puerto_udp ;;
16) cambiar_puerto_tcp ;;
17) actualizar_wg_easy ;;
18) backup ;;
19) restaurar_backup ;;
20) mostrar_ip ;;
21) configurar_https_wg_easy ;;
0) exit ;;
*) warning "Opción incorrecta"; pause ;;

esac

done

}

############################
# Inicio
############################

############################################################
# Verificar Debian
############################################################

verificar_debian(){

if [ ! -f /etc/os-release ]; then
    error "No se pudo detectar el sistema operativo."
    return
fi

source /etc/os-release

if [ "$ID" != "debian" ]; then
    error "Este script requiere Debian."
    return
fi

success "Sistema Operativo: Debian $VERSION_ID"

}


############################################################
# Verificar Internet
############################################################

verificar_internet(){

if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then

    success "Conexión Internet: OK"

else

    error "Sin conexión a Internet"

fi


if ping -c1 -W2 google.com >/dev/null 2>&1; then

    success "Resolución DNS: OK"

else

    warning "Problema de DNS"

fi

}


############################################################
# Verificar Arquitectura
############################################################

verificar_arquitectura(){

ARCH=$(uname -m)

success "Arquitectura: $ARCH"

}


############################################################
# Verificar Docker
############################################################

verificar_docker(){

if command -v docker >/dev/null 2>&1; then

    success "$(docker --version)"

else

    warning "Docker NO instalado"

fi

}


############################################################
# Verificar Docker Compose
############################################################

verificar_compose(){

if command -v docker >/dev/null 2>&1; then

    if docker compose version >/dev/null 2>&1; then

        success "$(docker compose version)"

    else

        warning "Docker Compose Plugin NO instalado"

    fi

else

    warning "Docker no disponible"

fi

}


############################################################
# Verificar WireGuard
############################################################

verificar_wireguard(){

if command -v wg >/dev/null 2>&1; then

    success "WireGuard Tools instalado"

elif modprobe wireguard >/dev/null 2>&1; then

    success "Módulo WireGuard disponible"

else

    warning "WireGuard no encontrado"

fi

}


############################################################
# Verificar Curl
############################################################

verificar_curl(){

if command -v curl >/dev/null; then

    success "curl instalado"

else

    warning "curl NO instalado"

fi

}


############################################################
# Verificar wget
############################################################

verificar_wget(){

if command -v wget >/dev/null; then

    success "wget instalado"

else

    warning "wget NO instalado"

fi

}


############################################################
# Verificar Git
############################################################

verificar_git(){

if command -v git >/dev/null; then

    success "git instalado"

else

    warning "git NO instalado"

fi

}


############################################################
# Verificar iptables
############################################################

verificar_iptables(){

if command -v iptables >/dev/null; then

    success "iptables instalado"

else

    warning "iptables NO instalado"

fi

}


############################################################
# Verificar sysctl ip_forward
############################################################

verificar_ipforward(){

VALOR=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)

if [ "$VALOR" = "1" ]; then

    success "IP Forward activado"

else

    warning "IP Forward desactivado"

fi

}


############################################################
# Verificar Puertos
############################################################

verificar_puertos(){

echo

info "Puertos WireGuard"

echo


if ss -lun | grep -q ":51820"; then

    warning "UDP 51820 ocupado"

else

    success "UDP 51820 libre"

fi


if ss -lnt | grep -q ":51821"; then

    warning "TCP 51821 ocupado"

else

    success "TCP 51821 libre"

fi

}


############################################################
# Verificar Espacio Disco
############################################################

verificar_disco(){

DISCO=$(df -h / | awk 'NR==2 {print $4}')

success "Espacio libre: $DISCO"

}


############################################################
# Verificar Memoria
############################################################

verificar_memoria(){

MEM=$(free -m | awk '/Mem:/ {print $2}')

success "RAM Total: ${MEM} MB"

}


############################################################
# Verificar Usuario Root
############################################################

verificar_root(){

if [ "$EUID" = "0" ]; then

    success "Ejecutando como root"

else

    error "Debe ejecutar como root"

    exit 1

fi

}

############################################################
# Función Principal Verificación
############################################################

verificar_dependencias(){

banner

echo "============== VERIFICANDO SISTEMA =============="

echo

verificar_root

verificar_debian

verificar_arquitectura

verificar_internet

verificar_memoria

verificar_disco

verificar_curl

verificar_wget

verificar_git

verificar_iptables

verificar_docker

verificar_compose

verificar_wireguard

verificar_ipforward

verificar_puertos

echo

success "Verificación finalizada"

pause

}
############################################################
# Instalar Docker CE
############################################################

instalar_docker(){

banner

echo "============== INSTALAR DOCKER =============="

echo

if command -v docker >/dev/null 2>&1; then

    success "Docker ya está instalado."

    docker --version

    pause

    return

fi

info "Actualizando repositorios..."

apt update

info "Eliminando versiones antiguas..."

apt remove -y \
docker \
docker-engine \
docker.io \
containerd \
runc >/dev/null 2>&1 || true

info "Instalando dependencias..."

apt install -y \
ca-certificates \
curl \
gnupg \
lsb-release \
apt-transport-https

mkdir -p /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/docker.asc ]; then

curl -fsSL https://download.docker.com/linux/debian/gpg \
| gpg --dearmor \
-o /etc/apt/keyrings/docker.gpg

chmod a+r /etc/apt/keyrings/docker.gpg

fi

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
> /etc/apt/sources.list.d/docker.list

apt update

info "Instalando Docker..."

apt install -y \
docker-ce \
docker-ce-cli \
containerd.io \
docker-buildx-plugin \
docker-compose-plugin

systemctl enable docker

systemctl restart docker

sleep 3

if systemctl is-active docker >/dev/null; then

success "Docker iniciado correctamente."

else

error "Docker no pudo iniciarse."

pause

return

fi

echo

docker --version

docker compose version

echo

success "Docker instalado correctamente."

pause

}

############################################################
# Iniciar Docker
############################################################

iniciar_docker(){

systemctl start docker

success "Docker iniciado."

pause

}

############################################################
# Reiniciar Docker
############################################################

reiniciar_docker(){

systemctl restart docker

success "Docker reiniciado."

pause

}

############################################################
# Detener Docker
############################################################

detener_docker(){

systemctl stop docker

success "Docker detenido."

pause

}

############################################################
# Estado Docker
############################################################

estado_docker(){

banner

systemctl status docker --no-pager

pause

}

############################################################
# Desinstalar Docker
############################################################

desinstalar_docker(){

banner

warning "Esta acción eliminará Docker."

echo

read -rp "¿Desea continuar? (s/n): " RESP

case "$RESP" in

s|S)

systemctl stop docker

apt remove -y \
docker-ce \
docker-ce-cli \
containerd.io \
docker-buildx-plugin \
docker-compose-plugin

rm -rf /var/lib/docker

rm -rf /var/lib/containerd

rm -rf /etc/docker

rm -f /etc/apt/sources.list.d/docker.list

success "Docker eliminado."

;;

*)

warning "Operación cancelada."

;;

esac

pause

}
############################################################
# Instalar WG-Easy
############################################################

instalar_wg_easy(){

banner

echo "============== INSTALAR WG-EASY =============="

echo

############################################################
# Verificar Docker
############################################################

if ! command -v docker >/dev/null 2>&1; then

    error "Docker no está instalado."

    pause

    return

fi

############################################################
# Crear carpeta
############################################################

mkdir -p "$INSTALL_DIR"

############################################################
# Puerto VPN
############################################################

echo

read -rp "Puerto VPN UDP [51820]: " UDP_PORT

UDP_PORT=${UDP_PORT:-51820}

############################################################
# Puerto Panel
############################################################

read -rp "Puerto Panel Web [51821]: " TCP_PORT

TCP_PORT=${TCP_PORT:-51821}

############################################################
# Verificar puertos
############################################################

if ss -lntup | grep -q ":$UDP_PORT "; then

    error "El puerto UDP $UDP_PORT está ocupado."

    pause

    return

fi

if ss -lntup | grep -q ":$TCP_PORT "; then

    error "El puerto TCP $TCP_PORT está ocupado."

    pause

    return

fi

############################################################
# Crear docker-compose
############################################################

cat > "$COMPOSE_FILE" <<EOF
services:

  wg-easy:

    image: ghcr.io/wg-easy/wg-easy:15

    container_name: wg-easy

    restart: unless-stopped

    environment:

      - INSECURE=true

      - LANG=es_ES.UTF-8

    ports:

      - "$UDP_PORT:51820/udp"

      - "$TCP_PORT:51821/tcp"

    volumes:

      - ./wireguard:/etc/wireguard

      - /lib/modules:/lib/modules:ro

    cap_add:

      - NET_ADMIN

      - SYS_MODULE

    sysctls:

      - net.ipv4.ip_forward=1

      - net.ipv4.conf.all.src_valid_mark=1

EOF

############################################################
# Descargar imagen
############################################################

info "Descargando imagen..."

cd "$INSTALL_DIR"

docker compose pull

############################################################
# Crear contenedor
############################################################

info "Iniciando WG-Easy..."

docker compose up -d

sleep 5

############################################################
# Verificar estado
############################################################

if docker ps | grep -q wg-easy; then

    success "WG-Easy instalado correctamente."

else

    error "No fue posible iniciar WG-Easy."

    pause

    return

fi

############################################################
# Mostrar información
############################################################

LOCAL_IP=$(hostname -I | awk '{print $1}')

echo

echo "=============================================="

success "Instalación Finalizada"

echo

echo "Panel Web"

echo

echo "http://$LOCAL_IP:$TCP_PORT"

echo

echo "Puerto WireGuard"

echo

echo "$UDP_PORT/UDP"

echo

warning "Recuerde abrir el puerto UDP $UDP_PORT en el router."

echo

pause

}
check_root
main_menu