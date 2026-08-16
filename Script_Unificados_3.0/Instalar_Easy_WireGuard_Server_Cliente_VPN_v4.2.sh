#!/bin/bash

# ============================================================
# WG-Easy Manager v1.0
# Debian 12
# Docker + WG-Easy v15
# ============================================================

set -e

VERSION="4.2"
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

    echo -e "${CYAN}================ MENÚ PRINCIPAL ================${RESET}"
    echo
    echo -e "${YELLOW}1)${RESET} ${WHITE}Dependencias y verificación del sistema${RESET}"
    echo -e "${YELLOW}2)${RESET} ${WHITE}Docker${RESET}"
    echo -e "${YELLOW}3)${RESET} ${WHITE}WG-Easy - Servidor WireGuard${RESET}"
    echo -e "${YELLOW}4)${RESET} ${WHITE}Ajustes WG-Easy${RESET}"
    echo -e "${YELLOW}5)${RESET} ${WHITE}Servicios WG-Easy${RESET}"
    echo -e "${YELLOW}6)${RESET} ${WHITE}Cliente WireGuard${RESET}"
    echo -e "${YELLOW}7)${RESET} ${WHITE}Backup / Restauración${RESET}"
    echo -e "${YELLOW}8)${RESET} ${WHITE}Información de red${RESET}"
    echo
    echo -e "${YELLOW}0)${RESET} ${WHITE}Salir${RESET}"
    echo

    read -rp "Seleccione una opción: " OPCION

    case "$OPCION" in
        1) menu_dependencias ;;
        2) menu_docker ;;
        3) menu_wg_easy_servidor ;;
        4) menu_ajustes_wg_easy ;;
        5) menu_servicios_wg_easy ;;
        6) menu_wireguard_cliente ;;
        7) menu_backup_wg_easy ;;
        8) mostrar_ip ;;
        0) exit 0 ;;
        *) warning "Opción incorrecta"; pause ;;
    esac

done

}

menu_dependencias(){
    while true; do
        banner
        echo -e "${CYAN}=========== DEPENDENCIAS / SISTEMA ===========${RESET}"
        echo
        echo " 1) Verificar sistema y dependencias"
        echo " 2) Instalar dependencias base"
        echo " 3) Verificar WireGuard / IP Forward / puertos"
        echo " 0) Volver"
        echo
        read -rp "Seleccione una opción: " op
        case "$op" in
            1) verificar_sistema ;;
            2) banner; verificar_dependencias; pause ;;
            3) banner; verificar_wireguard; verificar_ipforward; verificar_puertos; pause ;;
            0) return ;;
            *) warning "Opción incorrecta"; pause ;;
        esac
    done
}

menu_docker(){
    while true; do
        banner
        echo -e "${CYAN}================ DOCKER ================${RESET}"
        echo
        echo " 1) Instalar Docker"
        echo " 2) Iniciar Docker"
        echo " 3) Detener Docker"
        echo " 4) Reiniciar Docker"
        echo " 5) Estado Docker"
        echo " 6) Desinstalar Docker"
        echo " 0) Volver"
        echo
        read -rp "Seleccione una opción: " op
        case "$op" in
            1) instalar_docker ;;
            2) iniciar_docker ;;
            3) detener_docker ;;
            4) reiniciar_docker ;;
            5) estado_docker ;;
            6) desinstalar_docker ;;
            0) return ;;
            *) warning "Opción incorrecta"; pause ;;
        esac
    done
}

menu_wg_easy_servidor(){
    while true; do
        banner
        echo -e "${CYAN}============= WG-EASY SERVIDOR =============${RESET}"
        echo
        echo " 1) Instalar WG-Easy"
        echo " 2) Actualizar WG-Easy"
        echo " 3) Desinstalar WG-Easy"
        echo " 4) Ver logs WG-Easy"
        echo " 0) Volver"
        echo
        read -rp "Seleccione una opción: " op
        case "$op" in
            1) instalar_wg_easy ;;
            2) actualizar_wg_easy ;;
            3) desinstalar_wg_easy ;;
            4) ver_logs ;;
            0) return ;;
            *) warning "Opción incorrecta"; pause ;;
        esac
    done
}

menu_ajustes_wg_easy(){
    while true; do
        banner
        echo -e "${CYAN}=============== AJUSTES WG-EASY ===============${RESET}"
        echo
        echo " 1) Cambiar puerto UDP WireGuard"
        echo " 2) Cambiar puerto TCP panel web"
        echo " 3) Configurar HTTP / HTTPS"
        echo " 4) Mostrar configuración docker-compose.yml"
        echo " 0) Volver"
        echo
        read -rp "Seleccione una opción: " op
        case "$op" in
            1) cambiar_puerto_udp ;;
            2) cambiar_puerto_tcp ;;
            3) configurar_https_wg_easy ;;
            4) ver_compose_wg_easy ;;
            0) return ;;
            *) warning "Opción incorrecta"; pause ;;
        esac
    done
}

menu_servicios_wg_easy(){
    while true; do
        banner
        echo -e "${CYAN}============= SERVICIOS WG-EASY =============${RESET}"
        echo
        echo " 1) Iniciar WG-Easy"
        echo " 2) Detener WG-Easy"
        echo " 3) Reiniciar WG-Easy"
        echo " 4) Estado WG-Easy"
        echo " 5) Ver logs"
        echo " 0) Volver"
        echo
        read -rp "Seleccione una opción: " op
        case "$op" in
            1) iniciar_servicio ;;
            2) detener_servicio ;;
            3) reiniciar_servicio ;;
            4) estado_servicio ;;
            5) ver_logs ;;
            0) return ;;
            *) warning "Opción incorrecta"; pause ;;
        esac
    done
}

menu_backup_wg_easy(){
    while true; do
        banner
        echo -e "${CYAN}============= BACKUP WG-EASY =============${RESET}"
        echo
        echo " 1) Crear backup"
        echo " 2) Restaurar backup"
        echo " 0) Volver"
        echo
        read -rp "Seleccione una opción: " op
        case "$op" in
            1) backup ;;
            2) restaurar_backup ;;
            0) return ;;
            *) warning "Opción incorrecta"; pause ;;
        esac
    done
}

ver_compose_wg_easy(){
    banner
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "WG-Easy no está instalado o no existe $COMPOSE_FILE"
        pause
        return
    fi
    echo -e "${CYAN}=========== DOCKER COMPOSE WG-EASY ===========${RESET}"
    echo
    cat "$COMPOSE_FILE"
    echo
    pause
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
verificar_dependencias() {

    local paquetes=(
        ca-certificates
        curl
        gnupg
        lsb-release
        apt-transport-https
    )

    info "Verificando dependencias..."

    apt-get update -qq

    for paquete in "${paquetes[@]}"; do
        if dpkg -s "$paquete" >/dev/null 2>&1; then
            success "$paquete ya está instalado."
        else
            warning "$paquete no encontrado. Instalando..."
            apt-get install -y "$paquete"

            if dpkg -s "$paquete" >/dev/null 2>&1; then
                success "$paquete instalado correctamente."
            else
                error "No se pudo instalar $paquete."
                pause
                return 1
            fi
        fi
    done

    return 0
}
############################################################
# Función Principal Verificación
############################################################

verificar_sistema(){

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
instalar_docker
}
############################################################
# Instalar Docker CE
############################################################

instalar_docker() {

    banner

    echo "============== INSTALAR DOCKER =============="
    echo

    if command -v docker >/dev/null 2>&1; then
        success "Docker ya está instalado."
        docker --version
        pause
        return
    fi

    verificar_dependencias || return

    info "Actualizando repositorios..."
    apt-get update

    info "Eliminando versiones antiguas..."
    apt-get remove -y \
        docker \
        docker-engine \
        docker.io \
        containerd \
        runc >/dev/null 2>&1 || true

    mkdir -p /etc/apt/keyrings

    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        info "Descargando clave GPG de Docker..."

        curl -fsSL https://download.docker.com/linux/debian/gpg \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

        chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update

    info "Instalando Docker..."

    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable docker
    systemctl restart docker

    sleep 3

    if systemctl is-active --quiet docker; then
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
# Menu WireGuard + configuracion
############################################################
menu_wireguard_cliente() {

    while true; do

        banner

        echo "=========== WIREGUARD CLIENTE ==========="
        echo
        echo " 1) Instalar WireGuard"
        echo " 2) Importar / Reemplazar configuración"
        echo " 3) Iniciar VPN"
        echo " 4) Detener VPN"
        echo " 5) Reiniciar VPN"
		echo " 6) Ver configuración VPN"
        echo " 7) Estado de la VPN"
        echo " 8) Eliminar configuración"
        echo " 0) Volver"
        echo

        read -rp "Seleccione una opción: " op

        case "$op" in
            1) instalar_wireguard_cliente ;;
            2) importar_config_wireguard ;;
            3) iniciar_wireguard ;;
            4) detener_wireguard ;;
            5) reiniciar_wireguard ;;
			6) ver_config_wireguard ;;
            7) estado_wireguard ;;
            8) eliminar_wireguard ;;
            0) break ;;
            *) warning "Opción inválida."; sleep 2 ;;
        esac

    done

}
seleccionar_config_wireguard(){
    mapfile -t CFG < <(find /etc/wireguard -maxdepth 1 -type f -name "*.conf" 2>/dev/null | sort)

    if [ ${#CFG[@]} -eq 0 ]; then
        warning "No existen configuraciones WireGuard."
        return 1
    fi

    echo "Configuraciones disponibles:"
    echo
    for i in "${!CFG[@]}"; do
        local interfaz
        interfaz=$(basename "${CFG[$i]}" .conf)
        local estado="DETENIDA"
        systemctl is-active --quiet "wg-quick@$interfaz" && estado="ACTIVA"
        echo " $((i+1))) $interfaz [$estado]"
    done
    echo

    read -rp "Seleccione una configuración: " opc
    if [[ ! "$opc" =~ ^[0-9]+$ ]] || (( opc < 1 || opc > ${#CFG[@]} )); then
        warning "Opción inválida."
        return 1
    fi

    WG_CONFIG_SELECCIONADA="${CFG[$((opc-1))]}"
    WG_INTERFAZ_SELECCIONADA=$(basename "$WG_CONFIG_SELECCIONADA" .conf)
    return 0
}

instalar_wireguard_cliente() {

    banner

    echo "=========== INSTALAR WIREGUARD ==========="
    echo

    if command -v wg >/dev/null 2>&1; then
        success "WireGuard ya está instalado."
        pause
        return
    fi

    info "Actualizando repositorios..."
    apt-get update

    info "Instalando WireGuard..."

    apt-get install -y wireguard wireguard-tools

    if command -v wg >/dev/null 2>&1; then
        success "WireGuard instalado correctamente."
    else
        error "No fue posible instalar WireGuard."
    fi

    pause

}
normalizar_nombre_wireguard() {
    local nombre="$1"

    # Quitar extensión .conf si viene incluida.
    nombre="${nombre%.conf}"

    # Convertir caracteres no válidos a guion bajo.
    nombre=$(printf '%s' "$nombre" \
        | sed -E 's/[^A-Za-z0-9_=+.-]+/_/g; s/^_+//; s/_+$//; s/_+/_/g')

    # El nombre real de una interfaz Linux/WireGuard no puede superar 15 caracteres.
    nombre="${nombre:0:15}"

    printf '%s' "$nombre"
}

importar_config_wireguard() {

    banner

    echo "======= IMPORTAR CONFIGURACIÓN ======="
    echo

    if ! command -v wg >/dev/null 2>&1; then
        error "WireGuard no está instalado."
        pause
        return
    fi

    mkdir -p /etc/wireguard

    mapfile -t ARCHIVOS < <(find /root -maxdepth 1 -type f -name "*.conf" | sort)

    if [ ${#ARCHIVOS[@]} -eq 0 ]; then
        warning "No se encontraron archivos .conf en /root."
        pause
        return
    fi

    echo "Archivos encontrados:"
    echo

    for i in "${!ARCHIVOS[@]}"; do
        echo " $((i+1))) $(basename "${ARCHIVOS[$i]}")"
    done

    echo
    read -rp "Seleccione un archivo: " opc

    if [[ ! "$opc" =~ ^[0-9]+$ ]] || (( opc < 1 || opc > ${#ARCHIVOS[@]} )); then
        warning "Opción inválida."
        pause
        return
    fi

    ARCHIVO="${ARCHIVOS[$((opc-1))]}"
    NOMBRE_ORIGINAL=$(basename "$ARCHIVO")
    INTERFAZ=$(normalizar_nombre_wireguard "$NOMBRE_ORIGINAL")

    if [ -z "$INTERFAZ" ]; then
        error "No se pudo generar un nombre de interfaz válido."
        pause
        return
    fi

    NOMBRE="${INTERFAZ}.conf"
    DESTINO="/etc/wireguard/$NOMBRE"

    if [ "$NOMBRE_ORIGINAL" != "$NOMBRE" ]; then
        warning "El nombre '$NOMBRE_ORIGINAL' no puede usarse directamente como interfaz WireGuard."
        info "Se instalará como: $NOMBRE"
        echo
    fi

    if [ -f "$DESTINO" ]; then
        read -rp "La configuración '$NOMBRE' ya existe. ¿Desea reemplazarla? (s/n): " r
        [[ ! "$r" =~ ^[sSyY]$ ]] && return

        systemctl stop "wg-quick@$INTERFAZ" >/dev/null 2>&1 || true
        wg-quick down "/etc/wireguard/$NOMBRE" >/dev/null 2>&1 || true
    fi

    cp "$ARCHIVO" "$DESTINO"
    chmod 600 "$DESTINO"
    systemctl daemon-reload

    info "Iniciando VPN '$INTERFAZ'..."

    if systemctl start "wg-quick@$INTERFAZ"; then
        systemctl enable "wg-quick@$INTERFAZ" >/dev/null 2>&1 || true
        success "Configuración importada correctamente."
        success "Interfaz activa: $INTERFAZ"
    else
        error "No fue posible iniciar la VPN '$INTERFAZ'."
        echo
        journalctl -u "wg-quick@$INTERFAZ" --no-pager -n 20
    fi

    pause
}

iniciar_wireguard() {

    banner
    echo "=========== INICIAR WIREGUARD ==========="
    echo

    seleccionar_config_wireguard || { pause; return; }

    if [ ${#WG_INTERFAZ_SELECCIONADA} -gt 15 ]; then
        error "La configuración '$WG_INTERFAZ_SELECCIONADA.conf' tiene un nombre demasiado largo."
        info "WireGuard admite como máximo 15 caracteres para el nombre de interfaz."
        info "Vuelva a importarla con la opción 'Importar / Reemplazar configuración'."
        pause
        return
    fi

    if systemctl is-active --quiet "wg-quick@$WG_INTERFAZ_SELECCIONADA"; then
        warning "La VPN '$WG_INTERFAZ_SELECCIONADA' ya está iniciada."
        pause
        return
    fi

    info "Iniciando VPN..."

    if systemctl start "wg-quick@$WG_INTERFAZ_SELECCIONADA"; then
        systemctl enable "wg-quick@$WG_INTERFAZ_SELECCIONADA" >/dev/null 2>&1 || true
        success "VPN '$WG_INTERFAZ_SELECCIONADA' iniciada correctamente."
    else
        error "No fue posible iniciar la VPN."
        journalctl -u "wg-quick@$WG_INTERFAZ_SELECCIONADA" --no-pager -n 20
    fi

    pause
}

detener_wireguard() {
    banner
    echo "=========== DETENER WIREGUARD ==========="
    echo
    seleccionar_config_wireguard || { pause; return; }

    if ! systemctl is-active --quiet "wg-quick@$WG_INTERFAZ_SELECCIONADA"; then
        warning "La VPN '$WG_INTERFAZ_SELECCIONADA' ya está detenida."
        pause
        return
    fi

    if systemctl stop "wg-quick@$WG_INTERFAZ_SELECCIONADA"; then
        success "VPN '$WG_INTERFAZ_SELECCIONADA' detenida correctamente."
    else
        error "No fue posible detener la VPN."
    fi
    pause
}

reiniciar_wireguard() {
    banner
    echo "=========== REINICIAR WIREGUARD ==========="
    echo
    seleccionar_config_wireguard || { pause; return; }

    if systemctl restart "wg-quick@$WG_INTERFAZ_SELECCIONADA"; then
        systemctl enable "wg-quick@$WG_INTERFAZ_SELECCIONADA" >/dev/null 2>&1 || true
        success "VPN '$WG_INTERFAZ_SELECCIONADA' reiniciada correctamente."
    else
        error "No fue posible reiniciar la VPN."
        journalctl -u "wg-quick@$WG_INTERFAZ_SELECCIONADA" --no-pager -n 15
    fi
    pause
}

ver_config_wireguard() {

    banner

    echo "=========== CONFIGURACIÓN WIREGUARD ==========="
    echo

    mapfile -t CFG < <(find /etc/wireguard -maxdepth 1 -name "*.conf" | sort)

    if [ ${#CFG[@]} -eq 0 ]; then

        warning "No existen configuraciones WireGuard."
        pause
        return

    fi


    echo "Configuraciones disponibles:"
    echo

    for i in "${!CFG[@]}"; do
        echo -e " ${YELLOW}$((i+1)))${RESET} $(basename "${CFG[$i]}")"
    done

    echo

    read -rp "Seleccione una configuración: " opc


    if [[ ! "$opc" =~ ^[0-9]+$ ]] || (( opc<1 || opc>${#CFG[@]} )); then

        warning "Opción inválida."
        pause
        return

    fi


    ARCHIVO="${CFG[$((opc-1))]}"

    clear

    echo "=========== ARCHIVO =========="
    echo "$(basename "$ARCHIVO")"
    echo


    echo "=========== CONTENIDO =========="
    echo


    sed -E \
    -e 's/(PrivateKey[[:space:]]*=[[:space:]]*).*/\1********/' \
    "$ARCHIVO"


    echo
    echo "================================"

    echo
    echo "Estado actual:"
    echo

    INTERFAZ=$(basename "$ARCHIVO" .conf)

    if systemctl is-active --quiet "wg-quick@$INTERFAZ"; then

        echo "VPN: ACTIVA"

    else

        echo "VPN: DETENIDA"

    fi


    echo

    if command -v wg >/dev/null 2>&1; then

        wg show "$INTERFAZ" 2>/dev/null || true

    fi


    pause

}
estado_wireguard() {

    banner

    echo "=========== ESTADO DE WIREGUARD ==========="
    echo

    if ! command -v wg >/dev/null 2>&1; then
        error "WireGuard no está instalado."
        pause
        return
    fi

    if ls /etc/wireguard/*.conf >/dev/null 2>&1; then

        for archivo in /etc/wireguard/*.conf; do

            INTERFAZ=$(basename "$archivo" .conf)

            if systemctl is-active --quiet "wg-quick@$INTERFAZ"; then

                echo "● $INTERFAZ : ACTIVA"

            else

                echo "○ $INTERFAZ : DETENIDA"

            fi

        done

    else

        warning "No existen configuraciones."

    fi

    echo
    echo "-------------"

    wg show 2>/dev/null || echo "No hay interfaces activas."

    echo
    pause

}
eliminar_wireguard() {
    banner
    echo "=========== ELIMINAR CONFIGURACIÓN ==========="
    echo
    seleccionar_config_wireguard || { pause; return; }

    read -rp "¿Eliminar '$WG_INTERFAZ_SELECCIONADA'? (s/n): " resp
    if [[ ! "$resp" =~ ^[sS]$ ]]; then
        warning "Operación cancelada."
        pause
        return
    fi

    systemctl stop "wg-quick@$WG_INTERFAZ_SELECCIONADA" >/dev/null 2>&1 || true
    systemctl disable "wg-quick@$WG_INTERFAZ_SELECCIONADA" >/dev/null 2>&1 || true
    rm -f "$WG_CONFIG_SELECCIONADA"
    success "Configuración '$WG_INTERFAZ_SELECCIONADA' eliminada."
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