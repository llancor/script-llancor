#!/bin/bash

# ============================================================

# GESTIÓN DE RED - ZORIN OS

# NetworkManager / nmcli

# Diseñado para administración por SSH

# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

CONEXION="LAN-0"
INTERFAZ="enp2s0"
LOG="/tmp/reinicio_red.log"

# ------------------------------------------------------------

# FUNCIONES

# ------------------------------------------------------------

require_root() {
if [ "$EUID" -ne 0 ]; then
echo -e "${RED}[ERROR]${NC} Este script debe ejecutarse como root."
echo "Ejecute:"
echo " sudo bash $0"
exit 1
fi
}

pause() {
echo
read -rp "Presione ENTER para continuar..."
}

ok() {
echo -e "${GREEN}[OK]${NC} $1"
}

error() {
echo -e "${RED}[ERROR]${NC} $1"
}

info() {
echo -e "${CYAN}[INFO]${NC} $1"
}

warning() {
echo -e "${YELLOW}[ADVERTENCIA]${NC} $1"
}

validar_ip() {
local ip="$1"

if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    IFS='.' read -r a b c d <<< "$ip"

    for octeto in "$a" "$b" "$c" "$d"; do
        if (( octeto < 0 || octeto > 255 )); then
            return 1
        fi
    done

    return 0
fi

return 1


}

comprobar_networkmanager() {
if ! systemctl is-active --quiet NetworkManager; then
error "NetworkManager no está ejecutándose."
echo
systemctl status NetworkManager --no-pager
exit 1
fi
}

mostrar_configuracion() {

clear

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}       CONFIGURACIÓN ACTUAL DE RED${NC}"
echo -e "${CYAN}========================================${NC}"
echo

echo -e "${WHITE}Conexión:${NC}  $CONEXION"
echo -e "${WHITE}Interfaz:${NC}  $INTERFAZ"
echo

echo -e "${YELLOW}--- IP ACTUAL ---${NC}"
ip -br addr show "$INTERFAZ"
echo

echo -e "${YELLOW}--- RUTAS ---${NC}"
ip route
echo

echo -e "${YELLOW}--- CONFIGURACIÓN NETWORKMANAGER ---${NC}"

nmcli connection show "$CONEXION" | \
    grep -E 'ipv4.method|ipv4.addresses|ipv4.gateway|ipv4.dns' \
    | sed 's/^/  /'

echo


}

configurar_ip() {

clear

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}          CONFIGURAR IP FIJA${NC}"
echo -e "${CYAN}========================================${NC}"
echo

ip_actual=$(nmcli -g ipv4.addresses connection show "$CONEXION")

echo -e "IP actual: ${YELLOW}${ip_actual}${NC}"
echo

read -rp "Nueva IP: " nueva_ip

if ! validar_ip "$nueva_ip"; then
    error "La dirección IP no es válida."
    pause
    return
fi

read -rp "Prefijo de red [24]: " prefijo
prefijo="${prefijo:-24}"

if ! [[ "$prefijo" =~ ^[0-9]+$ ]] || (( prefijo < 1 || prefijo > 32 )); then
    error "Prefijo inválido."
    pause
    return
fi

echo
echo -e "${YELLOW}Nueva configuración:${NC}"
echo "IP:      $nueva_ip/$prefijo"
echo

read -rp "¿Guardar esta configuración? [s/N]: " confirmar

if [[ ! "$confirmar" =~ ^[Ss]$ ]]; then
    warning "Operación cancelada."
    pause
    return
fi

nmcli connection modify "$CONEXION" \
    ipv4.method manual \
    ipv4.addresses "$nueva_ip/$prefijo"

if [ $? -eq 0 ]; then
    ok "Nueva IP guardada correctamente."
else
    error "No fue posible modificar la IP."
fi

pause


}

configurar_gateway() {

clear

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}           CONFIGURAR GATEWAY${NC}"
echo -e "${CYAN}========================================${NC}"
echo

gateway_actual=$(nmcli -g ipv4.gateway connection show "$CONEXION")

echo -e "Gateway actual: ${YELLOW}${gateway_actual:-No configurado}${NC}"
echo

read -rp "Nuevo gateway: " nuevo_gateway

if ! validar_ip "$nuevo_gateway"; then
    error "El gateway no es válido."
    pause
    return
fi

nmcli connection modify "$CONEXION" ipv4.gateway "$nuevo_gateway"

if [ $? -eq 0 ]; then
    ok "Gateway guardado: $nuevo_gateway"
else
    error "No fue posible modificar el gateway."
fi

pause


}

configurar_dns() {

clear

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}             CONFIGURAR DNS${NC}"
echo -e "${CYAN}========================================${NC}"
echo

dns_actual=$(nmcli -g ipv4.dns connection show "$CONEXION")

echo -e "DNS actual: ${YELLOW}${dns_actual:-No configurado}${NC}"
echo

read -rp "DNS primario: " dns1

if ! validar_ip "$dns1"; then
    error "El DNS primario no es válido."
    pause
    return
fi

read -rp "DNS secundario [opcional]: " dns2

if [ -n "$dns2" ]; then
    if ! validar_ip "$dns2"; then
        error "El DNS secundario no es válido."
        pause
        return
    fi

    dns="$dns1 $dns2"
else
    dns="$dns1"
fi

nmcli connection modify "$CONEXION" ipv4.dns "$dns"

if [ $? -eq 0 ]; then
    ok "DNS guardado correctamente."
    echo "DNS: $dns"
else
    error "No fue posible modificar el DNS."
fi

pause


}

cambiar_dhcp() {

clear

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}              CONFIGURAR DHCP${NC}"
echo -e "${CYAN}========================================${NC}"
echo

warning "La conexión pasará a obtener IP automáticamente."
echo

read -rp "¿Continuar? [s/N]: " confirmar

if [[ ! "$confirmar" =~ ^[Ss]$ ]]; then
    warning "Operación cancelada."
    pause
    return
fi

nmcli connection modify "$CONEXION" \
    ipv4.method auto \
    ipv4.addresses "" \
    ipv4.gateway "" \
    ipv4.dns ""

if [ $? -eq 0 ]; then
    ok "DHCP configurado correctamente."
else
    error "No fue posible configurar DHCP."
fi

pause


}

reiniciar_red() {

clear

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}        REINICIAR CONEXIÓN DE RED${NC}"
echo -e "${CYAN}========================================${NC}"
echo

warning "La conexión SSH se perderá."
echo
echo "Se ejecutará:"
echo "  nmcli connection down \"$CONEXION\""
echo "  nmcli connection up \"$CONEXION\""
echo
echo "El proceso continuará en segundo plano aunque SSH se desconecte."
echo
echo "Registro:"
echo "  $LOG"
echo

read -rp "¿Reiniciar la conexión de red? [s/N]: " confirmar

if [[ ! "$confirmar" =~ ^[Ss]$ ]]; then
    warning "Operación cancelada."
    pause
    return
fi

# Limpiar registro
: > "$LOG"

# Lanzar proceso independiente de la sesión SSH
nohup bash -c "
    echo '========================================' >> '$LOG'
    echo 'REINICIO DE RED - \$(date)' >> '$LOG'
    echo '========================================' >> '$LOG'

    sleep 3

    echo '[1] Bajando conexión $CONEXION...' >> '$LOG'
    nmcli connection down '$CONEXION' >> '$LOG' 2>&1

    sleep 3

    echo '[2] Subiendo conexión $CONEXION...' >> '$LOG'
    nmcli connection up '$CONEXION' >> '$LOG' 2>&1

    sleep 3

    echo '[3] Estado final:' >> '$LOG'
    nmcli connection show --active >> '$LOG' 2>&1

    echo '[4] Dirección IP:' >> '$LOG'
    ip -br addr show '$INTERFAZ' >> '$LOG' 2>&1

    echo '========================================' >> '$LOG'
    echo 'PROCESO FINALIZADO - \$(date)' >> '$LOG'
    echo '========================================' >> '$LOG'
" >/dev/null 2>&1 &

echo
ok "Reinicio de red programado."
echo
echo -e "${YELLOW}La conexión SSH se desconectará en unos segundos.${NC}"
echo
echo "Después vuelva a conectarse utilizando la nueva IP."
echo
echo "Registro disponible en:"
echo "  $LOG"
echo

# Salir inmediatamente para no matar el proceso
exit 0


}

reiniciar_networkmanager() {

clear

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}       REINICIAR NETWORKMANAGER${NC}"
echo -e "${CYAN}========================================${NC}"
echo

warning "Esto puede cortar la conexión SSH."
echo

read -rp "¿Continuar? [s/N]: " confirmar

if [[ ! "$confirmar" =~ ^[Ss]$ ]]; then
    return
fi

nohup bash -c "
    sleep 3
    systemctl restart NetworkManager
" >/tmp/restart_networkmanager.log 2>&1 &

ok "Reinicio de NetworkManager programado."
echo "SSH puede desconectarse."
echo "Registro: /tmp/restart_networkmanager.log"

exit 0


}

probar_conectividad() {

clear

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}          PRUEBA DE CONECTIVIDAD${NC}"
echo -e "${CYAN}========================================${NC}"
echo

echo -e "${YELLOW}[1] Gateway${NC}"

gateway=$(ip route | awk '/default/ {print $3; exit}')

if [ -n "$gateway" ]; then
    echo "Gateway: $gateway"

    if ping -c 3 -W 2 "$gateway" >/dev/null 2>&1; then
        ok "Gateway responde."
    else
        error "El gateway no responde."
    fi
else
    error "No se encontró gateway."
fi

echo
echo -e "${YELLOW}[2] Internet - 8.8.8.8${NC}"

if ping -c 3 -W 2 8.8.8.8 >/dev/null 2>&1; then
    ok "Conectividad IP a Internet OK."
else
    error "No hay conectividad IP a Internet."
fi

echo
echo -e "${YELLOW}[3] Resolución DNS${NC}"

if getent hosts google.com >/dev/null 2>&1; then
    ok "Resolución DNS funcionando."
else
    error "No funciona la resolución DNS."
fi

echo
pause


}

mostrar_dns_google() {

clear

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}             DNS DE GOOGLE${NC}"
echo -e "${CYAN}========================================${NC}"
echo

echo "Se configurará:"
echo "  DNS primario:   8.8.8.8"
echo "  DNS secundario: 8.8.4.4"
echo

read -rp "¿Continuar? [s/N]: " confirmar

if [[ ! "$confirmar" =~ ^[Ss]$ ]]; then
    return
fi

nmcli connection modify "$CONEXION" \
    ipv4.dns "8.8.8.8 8.8.4.4"

if [ $? -eq 0 ]; then
    ok "DNS de Google guardados."
else
    error "No fue posible configurar los DNS."
fi

pause


}

verificar_conexion() {

if ! nmcli connection show "$CONEXION" >/dev/null 2>&1; then
    error "No existe la conexión '$CONEXION'."
    echo
    echo "Conexiones disponibles:"
    nmcli connection show
    exit 1
fi


}

# ------------------------------------------------------------

# INICIO

# ------------------------------------------------------------

require_root
comprobar_networkmanager
verificar_conexion

while true; do

clear

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}       GESTIÓN DE RED - ZORIN OS${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo -e "Conexión : ${GREEN}$CONEXION${NC}"
echo -e "Interfaz : ${GREEN}$INTERFAZ${NC}"
echo

echo -e "${YELLOW}1)${NC} Ver configuración actual"
echo -e "${YELLOW}2)${NC} Configurar IP fija"
echo -e "${YELLOW}3)${NC} Configurar Gateway"
echo -e "${YELLOW}4)${NC} Configurar DNS"
echo -e "${YELLOW}5)${NC} Cambiar a DHCP"
echo -e "${YELLOW}6)${NC} Reiniciar conexión de red"
echo -e "${YELLOW}7)${NC} Reiniciar NetworkManager"
echo -e "${YELLOW}8)${NC} Probar conectividad"
echo -e "${YELLOW}9)${NC} Restaurar DNS Google"
echo -e "${YELLOW}0)${NC} Salir"
echo
echo -e "${BLUE}========================================${NC}"

read -rp "Seleccione una opción: " opcion

case "$opcion" in

    1)
        mostrar_configuracion
        pause
        ;;

    2)
        configurar_ip
        ;;

    3)
        configurar_gateway
        ;;

    4)
        configurar_dns
        ;;

    5)
        cambiar_dhcp
        ;;

    6)
        reiniciar_red
        ;;

    7)
        reiniciar_networkmanager
        ;;

    8)
        probar_conectividad
        ;;

    9)
        mostrar_dns_google
        ;;

    0)
        echo
        ok "Saliendo..."
        exit 0
        ;;

    *)
        error "Opción inválida."
        sleep 2
        ;;

esac


done
