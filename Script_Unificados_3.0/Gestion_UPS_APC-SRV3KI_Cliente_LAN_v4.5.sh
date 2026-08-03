#!/bin/bash
############################################################
# GESTION UPS APC SRV3KI - CLIENTE / SERVIDOR NUT LAN
############################################################
VERSION="4.5"

UPS_NAME="apc"

NUT_SERVICE="nut-server"

NUT_MONITOR="nut-monitor"

BACKUP_DIR="/root/backup-nut"

LOGFILE="/var/log/ups-manager.log"

CONFIG_DIR="/etc/nut"
############################################################
# RUTAS 
############################################################

SCRIPT="/root/Gestion_UPS_APC-SRV3KI_Cliente_LAN_v4.5.sh"

SCRIPT_MONITOR="/usr/local/sbin/ups-apc-monitor-lan"

# AL CAMBIAR EL NOMBRE DE LOS SERVICIO SIEMPRE PREMANECE EL .service AL FINAL #
# Y DEBEN LLAMARCE IGUAL EN SERVICIO_MONITOR Y NOMBRE_SERVICIO ups-apc-monitor-lan.service #

SERVICIO_MONITOR="/etc/systemd/system/ups-apc-monitor-lan.service"

NOMBRE_SERVICIO="ups-apc-monitor-lan.service"

############################################################
# COLORES (deben definirse ANTES de usarse en iconos/mensajes)
############################################################

RESET="\e[0m"
ROJO="\e[1;31m"
VERDE="\e[1;32m"
AMARILLO="\e[1;33m"
AZUL="\e[1;34m"
MAGENTA="\e[1;35m"
CYAN="\e[1;36m"
BLANCO="\e[1;37m"
NEGRITA="\e[1m"

############################################################
# ICONOS
############################################################

OK="${VERDE}✔${RESET}"
ERROR="${ROJO}✘${RESET}"
INFO="${CYAN}ℹ${RESET}"
WARNING="${AMARILLO}⚠${RESET}"

############################################################
# COMPROBAR ROOT
############################################################

if [[ $EUID -ne 0 ]]; then
    clear
    echo
    echo -e "${ROJO}Este script debe ejecutarse como root.${RESET}"
    echo
    exit 1
fi

############################################################
# CREAR DIRECTORIOS
############################################################

mkdir -p "$BACKUP_DIR"

touch "$LOGFILE"

############################################################
# REGISTRAR LOG (usada en todo el script, antes no existía)
############################################################

registrar_log() {

    local MSG="$1"

    echo "[$(date '+%d/%m/%Y %H:%M:%S')] $MSG" >> "$LOGFILE"

}

############################################################
# FUNCIONES DE PANTALLA
############################################################

header_lan(){

    clear

    echo -e "${CYAN}══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${NEGRITA}       APC UPS SRV3KI - CLIENTE NUT LAN v${VERSION}${RESET}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${RESET}"
    echo

}

# Alias: el resto del script llama a "header" en decenas de sitios,
# pero solo existía "header_lan". Sin este alias, TODAS esas
# funciones fallaban con "header: command not found".
header(){

    header_lan

}


titulo(){

    echo -e "${AZUL}──────────────────────────────────────────────────────────────${RESET}"
    echo -e "${CYAN}${NEGRITA}$1${RESET}"
    echo -e "${AZUL}──────────────────────────────────────────────────────────────${RESET}"

}


linea(){

    echo -e "${AZUL}──────────────────────────────────────────────────────────────${RESET}"

}


pausa(){

    echo
    read -rp "Presione ENTER para continuar..."

}


mensaje_ok(){

    echo
    echo -e "${VERDE}✔${RESET} ${VERDE}$1${RESET}"
    echo

}


mensaje_error(){

    echo
    echo -e "${ROJO}✘${RESET} ${ROJO}$1${RESET}"
    echo

}


mensaje_info(){

    echo
    echo -e "${AZUL}ℹ${RESET} ${AZUL}$1${RESET}"
    echo

}
############################################################
# CONFIGURAR SERVIDOR NUT
############################################################

configurar_servidor_nut() {

    header

    titulo "CONFIGURAR SERVIDOR NUT"

    echo

    if ! command -v upsc >/dev/null 2>&1
    then
        mensaje_error "NUT no está instalado."
        pausa
        return
    fi

    ########################################################
    # Verificar que exista la UPS y pedir el resto de datos
    # (antes se pedía el nombre de la UPS DOS VECES seguidas)
    ########################################################

    read -rp "Nombre de la UPS [apc]: " UPSNAME
    UPSNAME=${UPSNAME:-apc}

    if ! upsc "$UPSNAME" >/dev/null 2>&1
    then

        mensaje_error "No se pudo comunicar con la UPS."

        echo
        echo "Configure primero la UPS local."

        pausa
        return

    fi

    read -rp "Puerto TCP [3493]: " PUERTO
    PUERTO=${PUERTO:-3493}

    read -rp "Usuario cliente [monitor]: " USUARIO
    USUARIO=${USUARIO:-monitor}

    read -rsp "Contraseña: " PASSWORD
    echo

    [[ -z "$PASSWORD" ]] && PASSWORD="123456"

    ########################################################
    # nut.conf
    ########################################################

    cat >/etc/nut/nut.conf <<EOF
MODE=netserver
EOF

    ########################################################
    # upsd.conf
    ########################################################

    cat >/etc/nut/upsd.conf <<EOF
# Servidor NUT accesible por red LAN
LISTEN 0.0.0.0 $PUERTO
EOF

    ########################################################
    # upsd.users (contraseña entre comillas: evita problemas
    # si contiene espacios o caracteres especiales)
    ########################################################

    cat >/etc/nut/upsd.users <<EOF
[$USUARIO]
password = "$PASSWORD"
upsmon primary
actions = SET
instcmds = ALL
EOF

    chmod 640 /etc/nut/upsd.users
    chown root:nut /etc/nut/upsd.users 2>/dev/null

    ########################################################
    # Reiniciar
    ########################################################

    systemctl enable nut-driver@${UPSNAME} >/dev/null 2>&1
    systemctl enable nut-server >/dev/null 2>&1

    systemctl restart nut-driver@${UPSNAME}
    sleep 2

    systemctl restart nut-server
    sleep 2

    ########################################################
    # Verificar puerto NUT
    ########################################################

    echo
    echo "Verificando servidor NUT..."

    if ss -tln | grep -q ":$PUERTO"
    then

        mensaje_ok "NUT escuchando en puerto $PUERTO"

    else

        mensaje_error "NUT no está escuchando en puerto $PUERTO"

    fi

    ########################################################
    # Estado
    ########################################################

    header

    titulo "RESULTADO"

    echo

    if systemctl is-active --quiet nut-server
    then

        mensaje_ok "Servidor NUT iniciado."

    else

        mensaje_error "No fue posible iniciar nut-server."

        pausa
        return

    fi

    echo

    MODELO=$(upsc "$UPSNAME" device.model 2>/dev/null)

    IP=$(hostname -I | awk '{print $1}')

    printf "%-20s %s\n" "Servidor:" "$IP"
    printf "%-20s %s\n" "Puerto:" "$PUERTO"
    printf "%-20s %s\n" "UPS:" "$UPSNAME"
    printf "%-20s %s\n" "Modelo:" "$MODELO"
    printf "%-20s %s\n" "Usuario:" "$USUARIO"

    echo

    linea

    echo

    echo "Los clientes deberán conectarse usando:"

    echo

    echo "upsc ${UPSNAME}@${IP}"

    echo

    echo "o"

    echo

    echo "MONITOR ${UPSNAME}@${IP} 1 ${USUARIO} ******** secondary"

    registrar_log "Servidor NUT configurado (UPS=$UPSNAME, puerto=$PUERTO)"

    pausa

}
############################################################
# CONFIGURAR CLIENTE NUT
############################################################

configurar_cliente_nut() {

    header

    titulo "CONFIGURAR CLIENTE NUT"

    echo

    if ! command -v upsc >/dev/null 2>&1
    then
        mensaje_error "NUT no está instalado."

        pausa
        return
    fi

    ########################################################
    # Datos
    ########################################################

    read -rp "IP Servidor NUT: " SERVER_IP

    [[ -z "$SERVER_IP" ]] && return

    read -rp "Nombre UPS [apc]: " UPSNAME
    UPSNAME=${UPSNAME:-apc}

    read -rp "Puerto [3493]: " PUERTO
    PUERTO=${PUERTO:-3493}

    read -rp "Usuario [monitor]: " USUARIO
    USUARIO=${USUARIO:-monitor}

    read -rsp "Contraseña: " PASSWORD
    echo

    ########################################################
    # nut.conf
    ########################################################

    cat >/etc/nut/nut.conf <<EOF
MODE=netclient
EOF

    ########################################################
    # upsmon.conf
    ########################################################

    cp /etc/nut/upsmon.conf /etc/nut/upsmon.conf.bak

    sed -i '/^MONITOR /d' /etc/nut/upsmon.conf
    sed -i '/^SHUTDOWNCMD /d' /etc/nut/upsmon.conf

    # NOTA: NUT no soporta contraseñas con espacios en la línea
    # MONITOR aunque se pongan comillas; evite espacios en la clave.
    cat >> /etc/nut/upsmon.conf <<EOF

MONITOR ${UPSNAME}@${SERVER_IP}:${PUERTO} 1 ${USUARIO} ${PASSWORD} secondary

SHUTDOWNCMD "/sbin/shutdown -h now"
EOF

    ########################################################
    # Reiniciar
    ########################################################

    systemctl enable nut-monitor >/dev/null 2>&1

    systemctl restart nut-monitor

    sleep 2

    ########################################################
    # Resultado
    ########################################################

    header

    titulo "CLIENTE CONFIGURADO"

    echo

    if systemctl is-active --quiet nut-monitor
    then

        mensaje_ok "Cliente NUT iniciado."

    else

        mensaje_error "nut-monitor no pudo iniciarse."

    fi

    echo

    printf "%-18s %s\n" "Servidor:" "$SERVER_IP"
    printf "%-18s %s\n" "Puerto:" "$PUERTO"
    printf "%-18s %s\n" "UPS:" "$UPSNAME"
    printf "%-18s %s\n" "Usuario:" "$USUARIO"

    registrar_log "Cliente NUT configurado contra $SERVER_IP:$PUERTO (UPS=$UPSNAME)"

    pausa

}
############################################################
# PROBAR CLIENTE NUT (USANDO CONFIGURACION EXISTENTE)
############################################################

probar_cliente_nut() {

    header

    titulo "PROBANDO CONEXION NUT CONFIGURADA"

    echo

    if [ ! -f /etc/nut/upsmon.conf ]
    then
        mensaje_error "No existe /etc/nut/upsmon.conf"
        pausa
        return
    fi

    MONITOR_LINE=$(grep "^MONITOR " /etc/nut/upsmon.conf | head -1)

    if [ -z "$MONITOR_LINE" ]
    then
        mensaje_error "No existe configuración MONITOR en upsmon.conf"
        pausa
        return
    fi

    UPS_REMOTA=$(echo "$MONITOR_LINE" | awk '{print $2}')

    if [ -z "$UPS_REMOTA" ]
    then
        mensaje_error "No se pudo obtener UPS remota"
        pausa
        return
    fi

    echo
    echo "Configuración encontrada:"
    echo

    printf "%-20s %s\n" "UPS:" "$UPS_REMOTA"

    echo
    linea
    echo

    echo "Consultando UPS..."

    echo

    if upsc "$UPS_REMOTA" >/tmp/nut_test 2>/dev/null
    then

        mensaje_ok "Conexión correcta."

        echo

        echo "Modelo:"
        grep "device.model" /tmp/nut_test

        echo

        echo "Estado:"
        grep "ups.status" /tmp/nut_test

        echo

        echo "Batería:"
        grep "battery.charge" /tmp/nut_test

        echo

        echo "Autonomía:"
        grep "battery.runtime" /tmp/nut_test

    else

        mensaje_error "No fue posible conectar con la UPS."

        echo
        echo "Revisar:"
        echo "- Servidor NUT activo"
        echo "- Puerto 3493 abierto"
        echo "- Nombre UPS correcto"
        echo "- Red LAN"

    fi

    rm -f /tmp/nut_test

    echo
    linea

    pausa

}
############################################################
# ESTADO CLIENTE
############################################################

estado_cliente_nut() {

    header

    titulo "ESTADO CLIENTE"

    echo

    systemctl status nut-monitor --no-pager

    echo

    echo "Configuración:"

    echo

    grep "^MONITOR" /etc/nut/upsmon.conf 2>/dev/null

    pausa

}
############################################################
# MENU TELEGRAM
############################################################
menu_telegram() {

    while true
    do

        header

        titulo "GESTION TELEGRAM"

        echo
        echo -e "${AMARILLO}1)${RESET} Configurar Bot"
        echo -e "${AMARILLO}2)${RESET} Agregar Chat ID"
        echo -e "${AMARILLO}3)${RESET} Ver Chat ID"
        echo -e "${AMARILLO}4)${RESET} Eliminar Chat ID"
        echo -e "${AMARILLO}5)${RESET} Activar / Desactivar alertas"
        echo -e "${AMARILLO}6)${RESET} Ver configuración"
        echo -e "${AMARILLO}7)${RESET} Probar Telegram"
        echo
        echo -e "${AMARILLO}0)${RESET} Volver"
        echo

        read -rp "Seleccione una opción: " OPCION

        case "$OPCION" in

            1) configurar_telegram ;;

            2) agregar_chatid ;;

            3) ver_chatid ;;

            4) eliminar_chatid ;;

            5) toggle_alertas_telegram ;;

            6) ver_configuracion_telegram ;;

            7) probar_telegram ;;

            0) break ;;

            *) mensaje_error "Opción inválida."; pausa ;;

        esac

    done

}
############################################################
# TELEGRAM
############################################################

TELEGRAM_CONFIG="/root/telegram_ups.conf"

TELEGRAM_LISTA="/root/telegram-chatid.conf"

cargar_telegram() {

    if [[ -f "$TELEGRAM_CONFIG" ]]
    then

        source "$TELEGRAM_CONFIG"

    else

        return 1

    fi

}

configurar_telegram() {

    header

    titulo "CONFIGURAR BOT TELEGRAM"

    echo
    echo "Este asistente configurará las notificaciones por Telegram."
    echo
    echo "Antes de continuar necesita:"
    echo
    echo "  1) Crear un bot con @BotFather."
    echo "  2) Copiar el BOT TOKEN entregado por BotFather."
    echo "  3) Iniciar un chat con su bot y enviar cualquier mensaje."
    echo "  4) Obtener el CHAT ID."
    echo
    echo "Cómo obtener el CHAT ID:"
    echo
    echo "  https://api.telegram.org/bot<BOT_TOKEN>/getUpdates"
    echo
    echo "Busque el valor:"
    echo
    echo '  "chat":{"id":123456789,...}'
    echo
    echo "Si utilizará un grupo:"
    echo
    echo "  • Agregue el bot al grupo."
    echo "  • Envíe un mensaje al grupo."
    echo "  • Ejecute nuevamente getUpdates."
    echo "  • El CHAT ID será un número negativo."
    echo
    echo "Ejemplo:"
    echo "  -1001234567890"
    echo

    read -rp "BOT TOKEN: " TOKEN
    read -rp "CHAT ID : " CHATID

    cat > "$TELEGRAM_CONFIG" <<EOF
BOT_TOKEN="$TOKEN"
CHAT_ID="$CHATID"
ALERTAS_TELEGRAM="OFF"
EOF

    chmod 600 "$TELEGRAM_CONFIG"

    touch "$TELEGRAM_LISTA"
    chmod 600 "$TELEGRAM_LISTA"

    mensaje_ok "Telegram configurado correctamente."

    pausa

}

agregar_chatid() {

    cargar_telegram || return

    header

    titulo "AGREGAR CHAT ID"

    echo

    touch "$TELEGRAM_LISTA"

    read -r -p "Ingrese Chat ID: " CHAT

    CHAT=$(echo "$CHAT" | xargs)

    [[ -z "$CHAT" ]] && return

    if grep -Fxq -- "$CHAT" "$TELEGRAM_LISTA"
    then

        mensaje_error "El Chat ID ya existe."

    else

        echo "$CHAT" >> "$TELEGRAM_LISTA"

        mensaje_ok "Chat ID agregado."

    fi

    pausa

}

ver_chatid() {

    header

    titulo "CHAT ID CONFIGURADOS"

    echo

    if [[ ! -s "$TELEGRAM_LISTA" ]]
    then

        echo "No existen Chat ID."

    else

        nl -w2 -s") " "$TELEGRAM_LISTA"

    fi

    echo

    pausa

}

eliminar_chatid() {

    header

    titulo "ELIMINAR CHAT ID"

    echo

    if [[ ! -s "$TELEGRAM_LISTA" ]]
    then
        mensaje_error "No existen Chat ID."
        pausa
        return
    fi

    nl -w2 -s") " "$TELEGRAM_LISTA"

    echo

    read -r -p "Número a eliminar: " NUM

    [[ ! "$NUM" =~ ^[0-9]+$ ]] && {
        mensaje_error "Número inválido."
        pausa
        return
    }

    CHAT=$(sed -n "${NUM}p" "$TELEGRAM_LISTA")

    if [[ -z "$CHAT" ]]
    then
        mensaje_error "No existe ese Chat ID."
        pausa
        return
    fi

    grep -Fxv -- "$CHAT" "$TELEGRAM_LISTA" > /tmp/chat.tmp
    mv /tmp/chat.tmp "$TELEGRAM_LISTA"

    mensaje_ok "Chat ID eliminado."

    pausa

}

toggle_alertas_telegram() {

    header

    titulo "ALERTAS TELEGRAM"

    cargar_telegram

    if [[ -z "$BOT_TOKEN" ]] || [[ -z "$CHAT_ID" ]]
    then

        mensaje_error "Telegram no está configurado."

        pausa

        return

    fi

    if [[ "$ALERTAS_TELEGRAM" == "ON" ]]
    then

        echo
        echo "Estado actual: ACTIVADAS"
        echo

        read -rp "¿Desactivar alertas Telegram? [s/N]: " RESP

        if [[ "$RESP" =~ ^[sS]$ ]]
        then

            sed -i 's/ALERTAS_TELEGRAM="ON"/ALERTAS_TELEGRAM="OFF"/' "$TELEGRAM_CONFIG"

            mensaje_ok "Alertas Telegram desactivadas."

        fi

    else

        echo
        echo "Estado actual: DESACTIVADAS"
        echo

        read -rp "¿Activar alertas Telegram? [s/N]: " RESP

        if [[ "$RESP" =~ ^[sS]$ ]]
        then

            if grep -q "ALERTAS_TELEGRAM" "$TELEGRAM_CONFIG"
            then

                sed -i 's/ALERTAS_TELEGRAM="OFF"/ALERTAS_TELEGRAM="ON"/' "$TELEGRAM_CONFIG"

            else

                cat >> "$TELEGRAM_CONFIG" <<EOF
ALERTAS_TELEGRAM="ON"
EOF

            fi

            mensaje_ok "Alertas Telegram activadas."

        fi

    fi

    pausa

}

ver_configuracion_telegram() {

    cargar_telegram || return

    header

    titulo "CONFIGURACION TELEGRAM"

    echo

    printf "%-20s %s\n" "Alertas:" "$ALERTAS_TELEGRAM"
    printf "%-20s %s\n" "BOT TOKEN:" "$BOT_TOKEN"

    echo

    echo "Chat ID configurados:"

    if [[ -s "$TELEGRAM_LISTA" ]]
    then

        nl -w2 -s") " "$TELEGRAM_LISTA"

    else

        echo "Ninguno"

    fi

    echo

    pausa

}

enviar_telegram() {

    local MENSAJE="$1"

    cargar_telegram || return 1

    [[ "$ALERTAS_TELEGRAM" != "ON" ]] && return 0

    [[ ! -s "$TELEGRAM_LISTA" ]] && return 1

    if ! command -v curl >/dev/null 2>&1
    then

        registrar_log "curl no está instalado."

        return 1

    fi

    while IFS= read -r CHAT
    do

        [[ -z "$CHAT" ]] && continue
        [[ "$CHAT" =~ ^# ]] && continue

        RESPUESTA=$(curl -s \
        --connect-timeout 10 \
        --max-time 30 \
        -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="$CHAT" \
        --data-urlencode "text=$MENSAJE" \
        -d parse_mode="HTML")

        if echo "$RESPUESTA" | grep -q '"ok":true'
        then

            registrar_log "Telegram enviado a $CHAT"

        else

            registrar_log "ERROR enviando Telegram a $CHAT"

        fi

    done < "$TELEGRAM_LISTA"

}

probar_telegram() {

    header

    titulo "PRUEBA TELEGRAM"

    enviar_telegram "<b>✅ APC UPS MANAGER</b>

La configuración de Telegram es correcta.

Servidor: $(hostname)

Fecha: $(date "+%d/%m/%Y %H:%M:%S %Z")

Estado: ONLINE"

    mensaje_ok "Mensaje enviado."

    pausa

}
############################################################
# PANEL GENERAL DEL SISTEMA
############################################################

estado_alertas() {

    echo
    echo "ALERTAS"
    echo "────────────────────────────────"

    if [[ -f "$TELEGRAM_CONFIG" ]]
    then

        cargar_telegram

        CHAT_TOTAL=0

        [[ -f "$TELEGRAM_LISTA" ]] && CHAT_TOTAL=$(grep -vc '^\s*$\|^#' "$TELEGRAM_LISTA")

        if [[ "$ALERTAS_TELEGRAM" == "ON" ]]
        then
            echo -e "Telegram       : ${VERDE}ACTIVO${RESET} (${CHAT_TOTAL} Chat ID)"
        else
            echo -e "Telegram       : ${AMARILLO}DESACTIVADO${RESET} (${CHAT_TOTAL} Chat ID)"
        fi

    else

        echo -e "Telegram       : ${ROJO}NO CONFIGURADO${RESET}"

    fi

    if [[ -f "$EMAIL_CONFIG" ]]
    then

        cargar_email

        EMAIL_TOTAL=0

        [[ -f "$EMAIL_LISTA" ]] && EMAIL_TOTAL=$(grep -vc '^\s*$\|^#' "$EMAIL_LISTA")

        if [[ "$ALERTAS_CORREO" == "ON" ]]
        then
            echo -e "Correo         : ${VERDE}ACTIVO${RESET} (${EMAIL_TOTAL} destinatarios)"
        else
            echo -e "Correo         : ${AMARILLO}DESACTIVADO${RESET} (${EMAIL_TOTAL} destinatarios)"
        fi

    else

        echo -e "Correo         : ${ROJO}NO CONFIGURADO${RESET}"

    fi

}
############################################################
# CONFIGURACION CORREO
############################################################

EMAIL_CONFIG="/root/ups-email.conf"

EMAIL_LISTA="/root/ups-email-lista.conf"

menu_correo() {

    while true
    do

        header

        titulo "$(echo -e "${CYAN}GESTION DE CORREO SMTP${RESET}")"

        echo

        echo -e "${AMARILLO}1)${RESET} Configurar servidor SMTP"
        echo -e "${AMARILLO}2)${RESET} Activar alertas por correo"
        echo -e "${AMARILLO}3)${RESET} Desactivar alertas por correo"
        echo -e "${AMARILLO}4)${RESET} Agregar destinatario"
        echo -e "${AMARILLO}5)${RESET} Eliminar destinatario"
        echo -e "${AMARILLO}6)${RESET} Ver destinatarios"
        echo -e "${AMARILLO}7)${RESET} Enviar correo de prueba"
        echo -e "${AMARILLO}8)${RESET} Ver configuración SMTP"
        echo -e "${AMARILLO}9)${RESET} ${AMARILLO}Menu Modificar configuración SMTP${RESET}"

        echo
        echo -e "${ROJO}0)${RESET} Volver"
        echo

        read -rp "Seleccione una opción: " OP

        case "$OP" in

            1) configurar_correo ;;

            2) activar_alertas_correo ;;

            3) desactivar_alertas_correo ;;

            4) agregar_destinatario ;;

            5) eliminar_destinatario ;;

            6) ver_destinatarios ;;

            7) probar_correo ;;

            8) ver_configuracion_correo ;;

            9) modificar_configuracion_correo ;;

            0) break ;;

            *) mensaje_error "Opción inválida."; sleep 1 ;;

        esac

    done

}

cargar_email() {

    if [[ -f "$EMAIL_CONFIG" ]]
    then

        source "$EMAIL_CONFIG"

    else

        return 1

    fi

}
############################################################
# ENVIAR CORREO A TODOS LOS DESTINATARIOS
############################################################
enviar_correo() {
    local ASUNTO="$1"
    local MENSAJE="$2"
    cargar_email || return 1
    [[ "$ALERTAS_CORREO" != "ON" ]] && return 0
    if ! command -v mail >/dev/null 2>&1
    then
        registrar_log "ERROR: mailutils no está instalado."
        return 1
    fi
    if [[ ! -s "$EMAIL_LISTA" ]]
    then
        registrar_log "No existen destinatarios configurados."
        return 1
    fi
    local ENVIADOS=0
    local ERRORES=0
    while IFS= read -r DESTINO
    do
        # Ignorar líneas vacías y comentarios
        [[ -z "$DESTINO" ]] && continue
        [[ "$DESTINO" =~ ^# ]] && continue
        if echo "$MENSAJE" | mail -s "$ASUNTO" "$DESTINO"
        then
            registrar_log "Correo enviado correctamente a $DESTINO"
            ((ENVIADOS++))
        else
            registrar_log "ERROR enviando correo a $DESTINO"
            ((ERRORES++))
        fi
    done < "$EMAIL_LISTA"
    registrar_log "Resumen correo -> Enviados: $ENVIADOS | Errores: $ERRORES"
    return 0
}

verificar_dependencias_correo() {

    echo
    echo "Verificando dependencias..."
    echo

    local PAQUETES=(
        msmtp
        msmtp-mta
        mailutils
        ca-certificates
    )

    local FALTAN=()

    for PKG in "${PAQUETES[@]}"
    do

        if ! dpkg -s "$PKG" >/dev/null 2>&1
        then
            FALTAN+=("$PKG")
        fi

    done

    if [[ ${#FALTAN[@]} -gt 0 ]]
    then

        echo
        echo "Instalando dependencias..."
        echo

        apt update

        if ! apt install -y "${FALTAN[@]}"
        then

            mensaje_error "No fue posible instalar las dependencias."

            return 1

        fi

        mensaje_ok "Dependencias instaladas."

    else

        mensaje_ok "Todas las dependencias ya están instaladas."

    fi

    local COMANDOS=(
        msmtp
        mail
    )

    for CMD in "${COMANDOS[@]}"
    do

        if ! command -v "$CMD" >/dev/null 2>&1
        then

            mensaje_error "No se encontró el comando: $CMD"

            return 1

        fi

    done

    if [[ ! -f /etc/ssl/certs/ca-certificates.crt ]]
    then

        mensaje_error "No existen certificados CA."

        return 1

    fi

    mensaje_ok "Sistema listo para configurar correo."

    return 0

}

configurar_correo() {

    header
    titulo "CONFIGURAR CORREO SMTP"

    verificar_dependencias_correo || {
        pausa
        return
    }

    echo
    echo "Seleccione el proveedor SMTP"
    echo
    echo "1) Gmail"
    echo "2) Outlook / Hotmail"
    echo "3) Microsoft 365"
    echo "4) Zoho Mail"
    echo "5) Personalizado"
    echo

    read -rp "Opción [1]: " OPCION

    case "$OPCION" in

        ""|1)

            SMTP_HOST="smtp.gmail.com"
            SMTP_PORT="587"
            SMTP_TLS="on"

        ;;

        2)

            SMTP_HOST="smtp.office365.com"
            SMTP_PORT="587"
            SMTP_TLS="on"

        ;;

        3)

            SMTP_HOST="smtp.office365.com"
            SMTP_PORT="587"
            SMTP_TLS="on"

        ;;

        4)

            SMTP_HOST="smtp.zoho.com"
            SMTP_PORT="587"
            SMTP_TLS="on"

        ;;

        5)

            read -rp "Servidor SMTP: " SMTP_HOST
            read -rp "Puerto SMTP: " SMTP_PORT

            read -rp "Usar TLS (S/n): " RESP

            [[ -z "$RESP" || "$RESP" =~ ^[sS]$ ]] && SMTP_TLS="on" || SMTP_TLS="off"

        ;;

        *)

            mensaje_error "Opción inválida."

            pausa

            return

        ;;

    esac

    echo

    while [[ -z "$SMTP_FROM" ]]
    do
        read -rp "Correo remitente: " SMTP_FROM
    done

    while [[ -z "$SMTP_USER" ]]
    do
        read -rp "Usuario SMTP: " SMTP_USER
    done

    while [[ -z "$SMTP_PASS" ]]
    do
        read -rsp "Contraseña / Clave de aplicación: " SMTP_PASS
        echo
    done

    while [[ -z "$EMAIL_DESTINO" ]]
    do
        read -rp "Correo destino alertas: " EMAIL_DESTINO
    done

    cat > "$EMAIL_CONFIG" <<EOF
SMTP_HOST="$SMTP_HOST"
SMTP_PORT="$SMTP_PORT"
SMTP_TLS="$SMTP_TLS"

SMTP_FROM="$SMTP_FROM"
SMTP_USER="$SMTP_USER"
SMTP_PASS="$SMTP_PASS"

EMAIL_DESTINO="$EMAIL_DESTINO"

ALERTAS_CORREO="OFF"
EOF

    chmod 600 "$EMAIL_CONFIG"

    cat > /etc/msmtprc <<EOF
defaults

auth on

tls $SMTP_TLS

tls_trust_file /etc/ssl/certs/ca-certificates.crt

account default

host $SMTP_HOST
port $SMTP_PORT

from $SMTP_FROM

user $SMTP_USER

password $SMTP_PASS

logfile /var/log/msmtp.log
EOF

    chmod 600 /etc/msmtprc

    touch /var/log/msmtp.log

    chmod 644 /var/log/msmtp.log

    echo
    echo "Enviando correo de prueba..."
    echo

    MENSAJE="

APC UPS MANAGER

Configuracion SMTP realizada correctamente.

Servidor: $(hostname)

Fecha: $(date "+%d/%m/%Y %H:%M:%S %Z")

Si recibio este correo, el envio funciona correctamente.

"

    echo "$MENSAJE" | mail -s "Prueba APC UPS Manager" "$EMAIL_DESTINO"

    if [[ $? -eq 0 ]]
    then

        mensaje_ok "Correo enviado correctamente."

        registrar_log "Configuración SMTP finalizada."

    else

        mensaje_error "No fue posible enviar el correo."

        echo
        echo "Revise:"
        echo "  - Usuario SMTP"
        echo "  - Contraseña"
        echo "  - Servidor SMTP"
        echo "  - Puerto"
        echo "  - Firewall"
        echo

    fi

    pausa

}

activar_alertas_correo() {

    header

    titulo "ACTIVAR ALERTAS POR CORREO"

    cargar_email || {

        mensaje_error "Primero debe configurar el correo SMTP."

        pausa

        return

    }

    if [[ "$ALERTAS_CORREO" == "ON" ]]
    then

        mensaje_ok "Las alertas ya están activadas."

        pausa

        return

    fi

    sed -i 's/ALERTAS_CORREO="OFF"/ALERTAS_CORREO="ON"/' "$EMAIL_CONFIG"

    mensaje_ok "Alertas por correo activadas."

    pausa

}

desactivar_alertas_correo() {

    header

    titulo "DESACTIVAR ALERTAS POR CORREO"

    cargar_email || {

        mensaje_error "No existe configuración de correo."

        pausa

        return

    }

    if [[ "$ALERTAS_CORREO" == "OFF" ]]
    then

        mensaje_ok "Las alertas ya están desactivadas."

        pausa

        return

    fi

    sed -i 's/ALERTAS_CORREO="ON"/ALERTAS_CORREO="OFF"/' "$EMAIL_CONFIG"

    mensaje_ok "Alertas por correo desactivadas."

    pausa

}

agregar_destinatario() {

    header
    titulo "AGREGAR DESTINATARIO"

    touch "$EMAIL_LISTA"
    chmod 600 "$EMAIL_LISTA"

    echo

    read -rp "Correo electrónico: " CORREO

    if [[ -z "$CORREO" ]]
    then
        mensaje_error "Debe ingresar un correo."
        pausa
        return
    fi

    if grep -Fxq "$CORREO" "$EMAIL_LISTA"
    then
        mensaje_error "Ese correo ya existe."
    else
        echo "$CORREO" >> "$EMAIL_LISTA"
        mensaje_ok "Correo agregado correctamente."
    fi

    pausa

}

eliminar_destinatario() {

    header

    titulo "ELIMINAR DESTINATARIO"

    echo

    if [[ ! -f "$EMAIL_LISTA" ]] || [[ ! -s "$EMAIL_LISTA" ]]
    then

        mensaje_error "No existen destinatarios configurados."

        pausa

        return

    fi

    echo "Destinatarios actuales:"
    echo

    nl -w2 -s". " "$EMAIL_LISTA"

    echo

    read -rp "Número del correo a eliminar: " NUM

    if ! [[ "$NUM" =~ ^[0-9]+$ ]]
    then

        mensaje_error "Número inválido."

        pausa

        return

    fi

    TOTAL=$(wc -l < "$EMAIL_LISTA")

    if (( NUM < 1 || NUM > TOTAL ))
    then

        mensaje_error "El número no existe."

        pausa

        return

    fi

    CORREO=$(sed -n "${NUM}p" "$EMAIL_LISTA")

    echo

    echo "Se eliminará:"
    echo "$CORREO"

    echo

    read -rp "¿Confirmar eliminación? [s/N]: " RESP

    if [[ "$RESP" =~ ^[sS]$ ]]
    then

        sed -i "${NUM}d" "$EMAIL_LISTA"

        mensaje_ok "Destinatario eliminado."

        registrar_log "Destinatario eliminado: $CORREO"

    else

        echo "Operación cancelada."

    fi

    pausa

}

ver_destinatarios() {

    header

    titulo "DESTINATARIOS DE ALERTAS"

    echo

    if [[ ! -f "$EMAIL_LISTA" ]] || [[ ! -s "$EMAIL_LISTA" ]]
    then

        mensaje_error "No existen destinatarios configurados."

        pausa

        return

    fi

    echo "Correos que recibirán alertas:"
    echo

    nl -w2 -s". " "$EMAIL_LISTA"

    echo

    TOTAL=$(wc -l < "$EMAIL_LISTA")

    echo "Total destinatarios: $TOTAL"

    pausa

}

ver_configuracion_correo() {

    header

    titulo "CONFIGURACION CORREO SMTP"

    echo

    if [[ ! -f "$EMAIL_CONFIG" ]]
    then

        mensaje_error "No existe configuración SMTP."

        pausa

        return

    fi

    source "$EMAIL_CONFIG"

    echo "Servidor SMTP : $SMTP_HOST"

    echo "Puerto SMTP   : $SMTP_PORT"

    echo "TLS           : $SMTP_TLS"

    echo

    echo "Remitente     : $SMTP_FROM"

    echo "Usuario SMTP  : $SMTP_USER"

    echo "Contraseña    : ********"

    echo

    if [[ "$ALERTAS_CORREO" == "ON" ]]
    then

        echo -e "Estado alertas: ${VERDE}ACTIVADAS${RESET}"

    else

        echo -e "Estado alertas: ${ROJO}DESACTIVADAS${RESET}"

    fi

    echo

    if [[ -f "$EMAIL_LISTA" ]] && [[ -s "$EMAIL_LISTA" ]]
    then

        TOTAL=$(wc -l < "$EMAIL_LISTA")

        echo "Destinatarios configurados: $TOTAL"

    else

        echo "Destinatarios configurados: 0"

    fi

    echo

    pausa

}

# NOTA: en el original esta función estaba duplicada dos veces
# de forma idéntica (copy/paste). Se dejó una sola copia.
probar_correo() {

    header

    titulo "PRUEBA DE CORREO"

    cargar_email || {

        mensaje_error "No existe configuración SMTP."

        pausa

        return

    }

    if [[ ! -f "$EMAIL_LISTA" ]] || [[ ! -s "$EMAIL_LISTA" ]]
    then

        mensaje_error "No existen destinatarios configurados."

        pausa

        return

    fi

    MENSAJE="

APC UPS MANAGER

Correo de prueba enviado correctamente.

Servidor : $(hostname)

Fecha    : $(date "+%d/%m/%Y %H:%M:%S %Z")


Si recibió este mensaje, la configuración SMTP es correcta.

"

    TOTAL=0

    while IFS= read -r DESTINO
    do

        [[ -z "$DESTINO" ]] && continue

        echo "$MENSAJE" | mail -s "Prueba APC UPS Manager" "$DESTINO"

        if [[ $? -eq 0 ]]
        then

            echo "Enviado a: $DESTINO"

            ((TOTAL++))

        else

            echo "Error enviando a: $DESTINO"

        fi

    done < "$EMAIL_LISTA"

    echo

    if [[ $TOTAL -gt 0 ]]
    then

        mensaje_ok "Correo enviado a $TOTAL destinatario(s)."

        registrar_log "Prueba correo enviada a $TOTAL destinatarios."

    else

        mensaje_error "No se pudo enviar ningún correo."

    fi

    pausa

}

modificar_configuracion_correo() {

    if [[ ! -f "$EMAIL_CONFIG" ]]; then
        header
        titulo "MODIFICAR CONFIGURACION SMTP"
        mensaje_error "No existe una configuración SMTP."
        pausa
        return
    fi

    source "$EMAIL_CONFIG"

    while true; do

        header
        titulo "MODIFICAR CONFIGURACION SMTP"
        echo

        echo "Configuración actual:"
        echo "------------------------------------------------"
        echo "1) Servidor SMTP : $SMTP_HOST"
        echo "2) Puerto SMTP   : $SMTP_PORT"
        echo "3) TLS           : $SMTP_TLS"
        echo "4) Remitente     : $SMTP_FROM"
        echo "5) Usuario SMTP  : $SMTP_USER"
        echo "6) Contraseña    : ********"
        echo "------------------------------------------------"
        echo
        echo "7) Guardar cambios"
        echo "0) Volver"
        echo

        read -rp "Seleccione una opción: " op

        case $op in

            1)
                read -rp "Nuevo servidor SMTP: " SMTP_HOST
                ;;

            2)
                read -rp "Nuevo puerto SMTP: " SMTP_PORT
                ;;

            3)
                echo
                echo "1) SI"
                echo "2) NO"
                read -rp "Seleccione: " tls

                case $tls in
                    1) SMTP_TLS="on" ;;
                    2) SMTP_TLS="off" ;;
                    *) mensaje_error "Opción inválida"; sleep 1 ;;
                esac
                ;;

            4)
                read -rp "Nuevo remitente: " SMTP_FROM
                ;;

            5)
                read -rp "Nuevo usuario SMTP: " SMTP_USER
                ;;

            6)
                read -rsp "Nueva contraseña: " SMTP_PASS
                echo
                ;;

            7)

                cat > "$EMAIL_CONFIG" <<EOF
SMTP_HOST="$SMTP_HOST"
SMTP_PORT="$SMTP_PORT"
SMTP_TLS="$SMTP_TLS"
SMTP_FROM="$SMTP_FROM"
SMTP_USER="$SMTP_USER"
SMTP_PASS="$SMTP_PASS"
ALERTAS_CORREO="${ALERTAS_CORREO:-OFF}"
EOF

                # También se actualiza /etc/msmtprc, que antes
                # quedaba desincronizado tras modificar aquí.
                cat > /etc/msmtprc <<EOF
defaults

auth on

tls $SMTP_TLS

tls_trust_file /etc/ssl/certs/ca-certificates.crt

account default

host $SMTP_HOST
port $SMTP_PORT

from $SMTP_FROM

user $SMTP_USER

password $SMTP_PASS

logfile /var/log/msmtp.log
EOF
                chmod 600 /etc/msmtprc

                mensaje_ok "Configuración SMTP actualizada correctamente."
                pausa
                return
                ;;

            0)
                return
                ;;

            *)
                mensaje_error "Opción inválida."
                sleep 1
                ;;

        esac

    done

}

configurar_log_msmtp() {

    touch /var/log/msmtp.log

    chown root:root /var/log/msmtp.log

    chmod 600 /var/log/msmtp.log

}
############################################################
# CONFIGURACION MONITOR
############################################################

CONFIG_FILE="/root/ups-apc.conf"

BATTERY_LIMIT=20
RUNTIME_LIMIT=600
WAIT_POWER_FAIL=60
MONITOR_INTERVAL=10
MONITOR_APAGADO="OFF"

cargar_configuracion() {

    if [[ ! -f "$CONFIG_FILE" ]]
    then

        cat > "$CONFIG_FILE" <<EOF
MONITOR_APAGADO="OFF"
WAIT_POWER_FAIL="60"
BATTERY_LIMIT="20"
RUNTIME_LIMIT="600"
MONITOR_INTERVAL="10"
EOF

    fi

    source "$CONFIG_FILE"

}

editar_configuracion_monitor() {

    cargar_configuracion

    header

    titulo "EDITAR CONFIGURACION DEL MONITOR"

    echo
    echo "Se abrirá el editor nano."
    echo
    echo "Modifique los valores necesarios, luego:"
    echo
    echo "  CTRL + O  Guardar"
    echo "  ENTER     Confirmar"
    echo "  CTRL + X  Salir"
    echo

    read -rp "Presione ENTER para continuar..."

    nano "$CONFIG_FILE"

    cargar_configuracion

    mensaje_ok "Configuración actualizada."

    pausa

}

mostrar_config_shutdown() {

    cargar_configuracion

    header

    titulo "CONFIGURACION APAGADO AUTOMATICO"

    echo

    printf "%-30s %s\n" "Monitor automático:" "$MONITOR_APAGADO"
    printf "%-30s %s segundos\n" "Espera por corte:" "$WAIT_POWER_FAIL"
    printf "%-30s %s %%\n" "Batería mínima:" "$BATTERY_LIMIT"
    printf "%-30s %s segundos\n" "Autonomía mínima:" "$RUNTIME_LIMIT"
    printf "%-30s %s segundos\n" "Intervalo monitoreo:" "$MONITOR_INTERVAL"

    echo

    pausa

}

configurar_shutdown() {

    cargar_configuracion

    header

    titulo "CONFIGURAR APAGADO AUTOMATICO"

    echo

    read -rp "Espera por corte [$WAIT_POWER_FAIL]: " TMP
    [[ -n "$TMP" ]] && WAIT_POWER_FAIL="$TMP"

    read -rp "Batería mínima (%) [$BATTERY_LIMIT]: " TMP
    [[ -n "$TMP" ]] && BATTERY_LIMIT="$TMP"

    read -rp "Autonomía mínima (segundos) [$RUNTIME_LIMIT]: " TMP
    [[ -n "$TMP" ]] && RUNTIME_LIMIT="$TMP"

    read -rp "Intervalo de monitoreo (segundos) [$MONITOR_INTERVAL]: " TMP
    [[ -n "$TMP" ]] && MONITOR_INTERVAL="$TMP"

    echo
    echo "¿Activar el apagado automático al llegar a los límites?"
    read -rp "MONITOR_APAGADO [$MONITOR_APAGADO] (ON/OFF): " TMP
    [[ -n "$TMP" ]] && MONITOR_APAGADO="${TMP^^}"

    cat > "$CONFIG_FILE" <<EOF
MONITOR_APAGADO="$MONITOR_APAGADO"
WAIT_POWER_FAIL="$WAIT_POWER_FAIL"
BATTERY_LIMIT="$BATTERY_LIMIT"
RUNTIME_LIMIT="$RUNTIME_LIMIT"
MONITOR_INTERVAL="$MONITOR_INTERVAL"
EOF

    mensaje_ok "Configuración actualizada correctamente."

    pausa

}
############################################################
# REINICIAR SERVICIOS NUT
############################################################

reiniciar_servicios_nut() {

    header

    titulo "REINICIAR SERVICIOS NUT"

    echo

    mensaje_info "Reiniciando servicios..."

    echo

    UPS_DRIVER=$(grep -oP '^\[\K[^\]]+' /etc/nut/ups.conf 2>/dev/null | head -1)

    SERVICIOS=(
    "nut-server"
    "nut-monitor"
    )

    [[ -n "$UPS_DRIVER" ]] && SERVICIOS+=("nut-driver@$UPS_DRIVER")

    for SERVICIO in "${SERVICIOS[@]}"
    do

        if systemctl list-unit-files | grep -q "^${SERVICIO}\.service"
        then

            printf "%-30s" "$SERVICIO"

            if systemctl restart "$SERVICIO" >/dev/null 2>&1
            then

                echo -e "${VERDE}OK${RESET}"

            else

                echo -e "${ROJO}ERROR${RESET}"

            fi

        fi

    done

    echo
    linea
    echo

    echo "Estado de los servicios"

    echo

    for SERVICIO in "${SERVICIOS[@]}"
    do

        if systemctl list-unit-files | grep -q "^${SERVICIO}\.service"
        then

            if systemctl is-active --quiet "$SERVICIO"
            then

                echo -e "${VERDE}✔${RESET} $SERVICIO"

            else

                echo -e "${ROJO}✘${RESET} $SERVICIO"

            fi

        fi

    done

    registrar_log "Servicios NUT reiniciados"

    pausa

}
############################################################
# PANEL UPS REMOTA EN TIEMPO REAL
############################################################

panel_ups_remota() {

    header

    titulo "UPS REMOTA EN TIEMPO REAL"

    echo

    if [ ! -f /etc/nut/upsmon.conf ]
    then

        mensaje_error "No existe /etc/nut/upsmon.conf"

        pausa
        return

    fi

    MONITOR_LINE=$(grep "^MONITOR " /etc/nut/upsmon.conf | head -1)

    if [ -z "$MONITOR_LINE" ]
    then

        mensaje_error "No existe configuración MONITOR en upsmon.conf"

        pausa
        return

    fi

    UPS_REMOTA=$(echo "$MONITOR_LINE" | awk '{print $2}')

    if [ -z "$UPS_REMOTA" ]
    then

        mensaje_error "No se pudo obtener UPS remota"

        pausa
        return

    fi

    SERVER_IP=$(echo "$UPS_REMOTA" | cut -d@ -f2)

    UPSNAME=$(echo "$UPS_REMOTA" | cut -d@ -f1)

    clear

    # trap para volver limpiamente con CTRL+C en vez de matar el script
    trap 'echo; return 0' INT

    while true
    do

        ESTADO=$(upsc "$UPS_REMOTA" ups.status 2>/dev/null)
        BATERIA=$(upsc "$UPS_REMOTA" battery.charge 2>/dev/null)
        AUTONOMIA=$(upsc "$UPS_REMOTA" battery.runtime 2>/dev/null)
        VOLTAJE_ENTRADA=$(upsc "$UPS_REMOTA" input.voltage 2>/dev/null)
        VOLTAJE_SALIDA=$(upsc "$UPS_REMOTA" output.voltage 2>/dev/null)
        FRECUENCIA=$(upsc "$UPS_REMOTA" input.frequency 2>/dev/null)
        CARGA=$(upsc "$UPS_REMOTA" ups.load 2>/dev/null)
        MODELO=$(upsc "$UPS_REMOTA" device.model 2>/dev/null)
        FABRICANTE=$(upsc "$UPS_REMOTA" device.mfr 2>/dev/null)
        TEMPERATURA=$(upsc "$UPS_REMOTA" ups.temperature 2>/dev/null)

        clear

        echo "════════════════════════════════════════════"
        echo "          UPS REMOTA NUT MONITOR"
        echo "════════════════════════════════════════════"

        echo

        printf "%-25s %s\n" "Servidor:" "$SERVER_IP"
        printf "%-25s %s\n" "UPS:" "$UPSNAME"
        printf "%-25s %s\n" "Fabricante:" "$FABRICANTE"
        printf "%-25s %s\n" "Modelo:" "$MODELO"

        echo

        echo "────────────────────────────────────────────"

        printf "%-25s %s\n" "Estado:" "$ESTADO"
        printf "%-25s %s %%\n" "Batería:" "$BATERIA"
        printf "%-25s %s seg\n" "Autonomía:" "$AUTONOMIA"
        printf "%-25s %s %%\n" "Carga:" "$CARGA"

        echo

        echo "────────────────────────────────────────────"

        printf "%-25s %s V\n" "Entrada:" "$VOLTAJE_ENTRADA"
        printf "%-25s %s V\n" "Salida:" "$VOLTAJE_SALIDA"
        printf "%-25s %s Hz\n" "Frecuencia:" "$FRECUENCIA"
        printf "%-25s %s °C\n" "Temperatura:" "$TEMPERATURA"

        echo

        echo "Configuración:"
        echo "$(echo "$MONITOR_LINE" | awk '{$4="********"; print}')"

        echo

        echo "Actualización: $(date '+%d/%m/%Y %H:%M:%S')"

        echo

        echo "CTRL+C para salir"

        sleep 2

    done

    trap - INT

}
############################################################
# MENU SERVICIO UPS APC MONITOR
############################################################

menu_servicio_ups() {

    while true
    do

        header

        titulo "GESTION SERVICIO UPS APC MONITOR"

        echo

        echo -e "${AMARILLO}1)${RESET} Crear servicio UPS APC Monitor"
        echo -e "${AMARILLO}2)${RESET} Activar e iniciar monitor"
        echo -e "${AMARILLO}3)${RESET} Detener y desactivar monitor"
        echo -e "${AMARILLO}4)${RESET} Ver estado del servicio"
		echo -e "${AMARILLO}5)${RESET} Eliminar servicio UPS APC Monitor"

        echo
        linea

        echo -e "${ROJO}0)${RESET} Volver"

        echo

        read -rp "Seleccione una opción: " OPCION


        case "$OPCION" in


            1)

                crear_servicio_ups

            ;;


            2)

                activar_monitor_ups

            ;;


            3)

                desactivar_monitor_ups

            ;;


            4)

                estado_monitor_ups

            ;;

			5)

				eliminar_servicio_ups

			;;
			
            0)

                return

            ;;


            *)

                mensaje_error "Opción no válida."

                pausa

            ;;

        esac


    done

}
############################################################
# CREAR SERVICIO UPS APC MONITOR
############################################################

crear_servicio_ups() {

    header

    titulo "CREAR SERVICIO UPS APC MONITOR"

    ############################################################
    # VERIFICAR SCRIPT ORIGINAL
    ############################################################

    if [[ ! -f "$SCRIPT" ]]
    then

        mensaje_error "No se encontró el script original."

        echo
        echo "Archivo esperado:"
        echo "$SCRIPT"
        echo

        pausa
        return

    fi


    ############################################################
    # DETENER SERVICIO SI YA EXISTE
    ############################################################

    if systemctl list-unit-files | grep -q "^${NOMBRE_SERVICIO}"
    then

        echo
        echo "Deteniendo servicio existente..."

        systemctl stop "$NOMBRE_SERVICIO" 2>/dev/null

    fi


    ############################################################
    # INSTALAR SCRIPT DEL MONITOR
    ############################################################

    echo
    echo "Instalando monitor UPS..."

    mkdir -p "$(dirname "$SCRIPT_MONITOR")"

    cp "$SCRIPT" "$SCRIPT_MONITOR"

    if [[ $? -ne 0 ]]
    then

        mensaje_error "No se pudo copiar el script."

        pausa
        return

    fi


    ############################################################
    # PERMISOS
    ############################################################

    chmod 755 "$SCRIPT_MONITOR"

    if [[ $? -ne 0 ]]
    then

        mensaje_error "No se pudieron establecer los permisos."

        pausa
        return

    fi


    ############################################################
    # CREAR SERVICIO SYSTEMD
    ############################################################

    echo
    echo "Creando servicio systemd..."

cat > "$SERVICIO_MONITOR" <<EOF
[Unit]
Description=APC UPS SRV3KI Monitor
After=network.target nut-server.service nut-monitor.service

Wants=nut-server.service

[Service]
Type=simple
ExecStart=/bin/bash $SCRIPT_MONITOR --service
WorkingDirectory=$(dirname "$SCRIPT_MONITOR")
User=root

Restart=always
RestartSec=10

KillMode=process

[Install]
WantedBy=multi-user.target
EOF


    ############################################################
    # VERIFICAR ARCHIVO SERVICE
    ############################################################

    if [[ ! -f "$SERVICIO_MONITOR" ]]
    then

        mensaje_error "No se pudo crear el servicio systemd."

        pausa
        return

    fi


    ############################################################
    # RECARGAR SYSTEMD
    ############################################################

    echo
    echo "Recargando systemd..."

    systemctl daemon-reload

    if [[ $? -ne 0 ]]
    then

        mensaje_error "Error recargando systemd."

        pausa
        return

    fi


    ############################################################
    # HABILITAR SERVICIO AL ARRANQUE
    ############################################################

    echo
    echo "Activando inicio automático..."

    systemctl enable "$NOMBRE_SERVICIO"

    if [[ $? -ne 0 ]]
    then

        mensaje_error "No se pudo activar el inicio automático."

        pausa
        return

    fi


    ############################################################
    # INICIAR SERVICIO
    ############################################################

    echo
    echo "Iniciando monitor UPS..."

    systemctl start "$NOMBRE_SERVICIO"

    if [[ $? -ne 0 ]]
    then

        mensaje_error "El servicio no pudo iniciarse."

        echo
        echo "Estado del servicio:"
        systemctl status "$NOMBRE_SERVICIO" --no-pager

        pausa
        return

    fi


    ############################################################
    # VERIFICAR ESTADO
    ############################################################

    sleep 2

    if systemctl is-active --quiet "$NOMBRE_SERVICIO"
    then

        mensaje_ok "Monitor UPS instalado y funcionando."

        echo
        echo "=============================================="
        echo "          APC UPS MONITOR INSTALADO"
        echo "=============================================="
        echo
        echo "Script original:"
        echo "$SCRIPT"
        echo
        echo "Script instalado:"
        echo "$SCRIPT_MONITOR"
        echo
        echo "Servicio:"
        echo "$SERVICIO_MONITOR"
        echo
        echo "Ejecutando:"
        echo "/bin/bash $SCRIPT_MONITOR --service"
        echo
        echo "Inicio automático: ACTIVADO"
        echo
        echo "Estado:"
        systemctl is-active "$NOMBRE_SERVICIO"
        echo

    else

        mensaje_error "El servicio fue creado pero no está activo."

        echo
        systemctl status "$NOMBRE_SERVICIO" --no-pager

    fi

    pausa

}
############################################################
# ACTIVAR SERVICIO UPS APC MONITOR
############################################################

activar_monitor_ups() {

    header

    titulo "ACTIVAR UPS APC MONITOR"

    systemctl enable "$NOMBRE_SERVICIO"

    systemctl start "$NOMBRE_SERVICIO"

    if systemctl is-active --quiet "$NOMBRE_SERVICIO"
    then

        mensaje_ok "UPS APC Monitor activo y configurado al inicio."

    else

        mensaje_error "No fue posible iniciar el monitor."

    fi

    pausa

}
############################################################
# DESACTIVAR SERVICIO UPS APC MONITOR
############################################################

desactivar_monitor_ups() {

    header

    titulo "DESACTIVAR UPS APC MONITOR"

    systemctl stop "$NOMBRE_SERVICIO"

    systemctl disable "$NOMBRE_SERVICIO"

    mensaje_ok "UPS APC Monitor detenido y eliminado del inicio automático."

    pausa

}
############################################################
# ESTADO UPS APC MONITOR
############################################################

estado_monitor_ups() {

    header

    titulo "ESTADO UPS APC MONITOR"

    echo

    if systemctl is-active --quiet "$NOMBRE_SERVICIO"
    then

        echo -e "Servicio: ${VERDE}ACTIVO${RESET}"

    else

        echo -e "Servicio: ${ROJO}DETENIDO${RESET}"

    fi

    echo

    systemctl status "$NOMBRE_SERVICIO" --no-pager -l

    pausa

}
############################################################
# ELIMINAR SERVICIO UPS APC MONITOR
############################################################

eliminar_servicio_ups() {

    header

    titulo "ELIMINAR SERVICIO UPS APC MONITOR"

    echo
    echo -e "${AMARILLO}Se eliminará el servicio UPS APC Monitor.${RESET}"
    echo

    read -rp "¿Desea continuar? [s/N]: " RESPUESTA

    if [[ ! "$RESPUESTA" =~ ^[Ss]$ ]]
    then

        mensaje_error "Operación cancelada."

        pausa
        return

    fi


    ############################################################
    # DETENER Y DESHABILITAR SERVICIO
    ############################################################

    systemctl stop "$NOMBRE_SERVICIO" 2>/dev/null

    systemctl disable "$NOMBRE_SERVICIO" 2>/dev/null


    ############################################################
    # ELIMINAR ARCHIVO DEL SERVICIO
    ############################################################

    if [[ -f "$SERVICIO_MONITOR" ]]
    then
        rm -f "$SERVICIO_MONITOR"
    fi


    ############################################################
    # ELIMINAR SCRIPT INSTALADO
    ############################################################

    if [[ -f "$SCRIPT_MONITOR" ]]
    then
        rm -f "$SCRIPT_MONITOR"
    fi


    ############################################################
    # RECARGAR SYSTEMD
    ############################################################

    systemctl daemon-reload


    ############################################################
    # RESULTADO
    ############################################################

    mensaje_ok "Servicio UPS APC Monitor eliminado correctamente."

    pausa

}
############################################################
# MENU PROXMOX
############################################################

menu_proxmox() {

    while true
    do

        clear

        echo
		echo
		echo -e "${CYAN}===== PROXMOX MANAGER =====${RESET}"
		echo
		echo -e "${AMARILLO}1)${RESET} Apagar máquinas virtuales"
		echo -e "${AMARILLO}2)${RESET} Apagar contenedores LXC"
		echo -e "${AMARILLO}3)${RESET} Apagar host Proxmox/Servidor debian"
		echo -e "${AMARILLO}4)${RESET} Apagar Todo en orden 1,2,3"
		echo -e "${AMARILLO}0)${RESET} Volver"
		echo

        read -rp "Seleccione una opción: " OPCION

        case "$OPCION" in

            1)
                clear
                apagar_vm_proxmox
                echo
                read -rp "Presione ENTER para continuar..."
                ;;

            2)
                clear
                apagar_lxc_proxmox
                echo
                read -rp "Presione ENTER para continuar..."
                ;;

            3)
                clear

                echo
                echo -e "${ROJO}==============================================${RESET}"
                echo -e "${ROJO}          APAGADO HOST PROXMOX               ${RESET}"
                echo -e "${ROJO}==============================================${RESET}"
                echo
                echo -e "${AMARILLO}ADVERTENCIA: Esta acción apagará el servidor.${RESET}"
                echo

                read -rp "¿Desea continuar? [s/N]: " CONFIRMAR

                if [[ "$CONFIRMAR" =~ ^[Ss]$ ]]
                then
                    apagar_host_proxmox
                else
                    echo
                    echo -e "${AMARILLO}Operación cancelada.${RESET}"
                    sleep 2
                fi
                ;;
				
				4)
                
                apagar_host

                ;;

            0)
                clear
                return
                ;;

            *)
                echo
                echo -e "${ROJO}Opción inválida.${RESET}"
                sleep 2
                ;;

        esac

    done
}
############################################################
# APAGAR MAQUINAS VIRTUALES (solo aplica en nodos Proxmox)
############################################################

apagar_vm_proxmox() {

    echo
    echo "Apagando máquinas virtuales..."
    echo

    if command -v qm >/dev/null 2>&1
    then

        VMS=$(qm list | awk 'NR>1 {print $1}')

        for VM in $VMS
        do

            echo "Apagando VM $VM"
            registrar_log "Apagando VM $VM"

            qm shutdown "$VM" --timeout 60

        done

    else

        echo "No es un nodo Proxmox."

    fi

}
############################################################
# APAGAR CONTENEDORES LXC (solo aplica en nodos Proxmox)
############################################################

apagar_lxc_proxmox() {

    echo
    echo "Apagando contenedores LXC..."
    echo

    if command -v pct >/dev/null 2>&1
    then

        CT=$(pct list | awk 'NR>1 {print $1}')

        for ID in $CT
        do

            echo "Apagando CT $ID"
            registrar_log "Apagando CT $ID"

            pct shutdown "$ID"

        done

    fi

}
############################################################
# APAGADO COMPLETO DEL HOST
############################################################

apagar_host_proxmox() {

    echo
    echo "Apagando Sistema..."
    echo

    registrar_log "Inicio apagado automático por corte de energía"

    sleep 10

    shutdown -h now

}
############################################################
# APAGADO LOS 3 EN ORDEN DESCOMETAR SI ES PROXMOX 
############################################################

apagar_host() {
                  apagar_vm_proxmox
                  apagar_lxc_proxmox
                  apagar_host_proxmox

}



############################################################
# DETERMINAR SOBRE QUE UPS SE TRABAJA (local o remota/cliente)
# Antes esto no existía: el panel y el demonio dependían de
# una variable UPS_REMOTA que nadie inicializaba.
############################################################

determinar_ups_objetivo() {

    UPS_REMOTA=""

    if [[ -f /etc/nut/upsmon.conf ]]
    then

        MONITOR_LINE=$(grep "^MONITOR " /etc/nut/upsmon.conf | head -1)

        [[ -n "$MONITOR_LINE" ]] && UPS_REMOTA=$(echo "$MONITOR_LINE" | awk '{print $2}')

    fi

    # Si no hay cliente configurado, se asume UPS local (servidor)
    [[ -z "$UPS_REMOTA" ]] && UPS_REMOTA="$UPS_NAME"

}
############################################################
# obtener_valor
############################################################
obtener_valor() {

    local CAMPO="$1"

    upsc "$UPS_REMOTA" "$CAMPO" 2>/dev/null

}
############################################################
# VERIFICAR NUT / UPS DISPONIBLE
############################################################

verificar_nut() {

    if ! command -v upsc >/dev/null 2>&1
    then

        mensaje_error "NUT no está instalado (falta el comando upsc)."

        return 1

    fi

    return 0

}

verificar_ups() {

    determinar_ups_objetivo

    if ! upsc "$UPS_REMOTA" >/dev/null 2>&1
    then

        mensaje_error "No se pudo comunicar con la UPS ($UPS_REMOTA)."

        return 1

    fi

    return 0

}
############################################################
# CONVERTIR SEGUNDOS A FORMATO LEGIBLE
############################################################

convertir_tiempo() {

    local SEGUNDOS="$1"

    if [[ -z "$SEGUNDOS" ]] || ! [[ "$SEGUNDOS" =~ ^[0-9]+$ ]]
    then
        echo "N/D"
        return
    fi

    local H=$(( SEGUNDOS / 3600 ))
    local M=$(( (SEGUNDOS % 3600) / 60 ))
    local S=$(( SEGUNDOS % 60 ))

    printf "%02d:%02d:%02d" "$H" "$M" "$S"

}
############################################################
# BARRA DE PROGRESO (%)
############################################################

barra_progreso() {

    local VALOR="$1"

    [[ -z "$VALOR" ]] && VALOR=0
    # el valor puede venir como "87.0" desde upsc
    VALOR=${VALOR%.*}
    [[ "$VALOR" =~ ^[0-9]+$ ]] || VALOR=0

    local ANCHO=40
    local LLENO=$(( VALOR * ANCHO / 100 ))
    (( LLENO < 0 )) && LLENO=0
    (( LLENO > ANCHO )) && LLENO=$ANCHO
    local VACIO=$(( ANCHO - LLENO ))

    local COLOR="$VERDE"
    (( VALOR < 50 )) && COLOR="$AMARILLO"
    (( VALOR < 20 )) && COLOR="$ROJO"

    printf "["
    printf "%b" "$COLOR"
    printf "%${LLENO}s" "" | tr ' ' '#'
    printf "%b" "$RESET"
    printf "%${VACIO}s" "" | tr ' ' '-'
    printf "] %3s%%\n" "$VALOR"

}
############################################################
# DIBUJAR PANEL (estructura estática)
############################################################

dibujar_panel() {

    clear

    echo "══════════════════════════════════════════════════════════════"
    echo -e "          ${CYAN}APC UPS MANAGER - MONITOR EN TIEMPO REAL${RESET}"
    echo "══════════════════════════════════════════════════════════════"

    echo

    echo "Modelo:"
    echo "Estado:"
    echo "Potencia:"

    linea

    echo
    echo "Batería"
    echo

    echo
    echo "Carga UPS"
    echo

    linea

    printf "%-25s\n" "Autonomía:"
    printf "%-25s\n" "Entrada:"
    printf "%-25s\n" "Salida:"
    printf "%-25s\n" "Frecuencia:"
    printf "%-25s\n" "Temperatura:"

    linea

    echo
    echo "Información batería"

    printf "%-25s\n" "Voltaje batería:"

    linea

    echo
    echo "Sistema"

    printf "%-25s\n" "Firmware:"
    printf "%-25s\n" "Alarma:"

    linea

    echo
    echo "Última actualización:"
    echo
    echo -e "${AMARILLO}CTRL+C${RESET} Volver al menú"

}
############################################################
# ACTUALIZAR PANEL (valores dinámicos)
############################################################

actualizar_panel() {

    verificar_nut || return
    verificar_ups || return

    MODELO=$(obtener_valor device.model)
    ESTADO=$(obtener_valor ups.status)
    BATERIA=$(obtener_valor battery.charge)
    CARGA=$(obtener_valor ups.load)
    AUTONOMIA=$(obtener_valor battery.runtime)
    ENTRADA=$(obtener_valor input.voltage)
    SALIDA=$(obtener_valor output.voltage)
    FRECUENCIA=$(obtener_valor output.frequency)
    TEMPERATURA=$(obtener_valor ups.temperature)
    VOLTAJE_BATERIA=$(obtener_valor battery.voltage)
    FIRMWARE=$(obtener_valor ups.firmware)
    ALARMA=$(obtener_valor ups.beeper.status)
    POTENCIA=$(obtener_valor ups.power.nominal)

    case "$ESTADO" in
        OL) ESTADO_TXT="${VERDE}ONLINE${RESET}" ;;
        OB) ESTADO_TXT="${AMARILLO}EN BATERÍA${RESET}" ;;
        LB) ESTADO_TXT="${ROJO}BATERÍA BAJA${RESET}" ;;
        *)  ESTADO_TXT="${MAGENTA}${ESTADO}${RESET}" ;;
    esac

    cargar_configuracion
    cargar_email
    cargar_telegram

    if systemctl is-active --quiet ups-apc-monitor.service
    then
        ESTADO_MONITOR="${VERDE}ACTIVADO${RESET}"
    else
        ESTADO_MONITOR="${ROJO}DESACTIVADO${RESET}"
    fi

    if [[ "$ALERTAS_CORREO" == "ON" ]]
    then
        ESTADO_CORREO="${VERDE}ACTIVADO${RESET}"
    else
        ESTADO_CORREO="${ROJO}DESACTIVADO${RESET}"
    fi

    if [[ "$ALERTAS_TELEGRAM" == "ON" ]]
    then
        ESTADO_TELEGRAM="${VERDE}ACTIVADO${RESET}"
    else
        ESTADO_TELEGRAM="${ROJO}DESACTIVADO${RESET}"
    fi

    if [[ -f "$LOGFILE" ]]
    then

        mapfile -t EVENTOS < <(tail -n 3 "$LOGFILE")

        LOG1="${EVENTOS[0]:-Sin registros.}"
        LOG2="${EVENTOS[1]}"
        LOG3="${EVENTOS[2]}"

    else

        LOG1="Archivo de log inexistente."
        LOG2=""
        LOG3=""

    fi

    tput cup 4 10
    tput el
    printf "%-45s" "$MODELO"

    tput cup 5 10
    tput el
    printf "%-45b" "$ESTADO_TXT"

    tput cup 6 10
    tput el
    printf "%-20s" "$POTENCIA VA"

    tput cup 10 0
    tput el
    barra_progreso "$BATERIA"

    tput cup 13 0
    tput el
    barra_progreso "$CARGA"

    tput cup 16 25
    tput el
    printf "%-20s" "$(convertir_tiempo "$AUTONOMIA")"

    tput cup 17 25
    tput el
    printf "%-20s" "$ENTRADA V"

    tput cup 18 25
    tput el
    printf "%-20s" "$SALIDA V"

    tput cup 19 25
    tput el
    printf "%-20s" "$FRECUENCIA Hz"

    tput cup 20 25
    tput el
    printf "%-20s" "$TEMPERATURA °C"

    tput cup 24 25
    tput el
    printf "%-20s" "$VOLTAJE_BATERIA V"

    tput cup 28 25
    tput el
    printf "%-20s" "$FIRMWARE"

    tput cup 29 25
    tput el
    printf "%-20s" "$ALARMA"

    tput cup 35 0
    tput el
    printf "${CYAN}Monitor automático al reiniciar :${RESET} %b" "$ESTADO_MONITOR"

    tput cup 36 0
    tput el
    printf "${CYAN}Alertas correo.... :${RESET} %b" "$ESTADO_CORREO"

    tput cup 37 0
    tput el
    printf "${CYAN}Alertas Telegram.. :${RESET} %b" "$ESTADO_TELEGRAM"

    tput cup 39 0
    tput el
    echo -e "${CYAN}Últimos eventos${RESET}"

    tput cup 40 0
    tput el
    printf "%s" "$LOG1"

    tput cup 41 0
    tput el
    printf "%s" "$LOG2"
	
	tput cup 42 0
    tput el
    printf "%s" "$LOG3"

    tput cup 43 0
    tput el
    printf "%s" "$LOG3"

    tput cup 44 0
    tput el
    printf "Última actualización: %s" "$(date '+%d/%m/%Y %H:%M:%S')"

}
############################################################
# LANZAR PANEL EN TIEMPO REAL (antes dibujar_panel/actualizar_panel
# existían pero ningún menú las invocaba)
############################################################

panel_tiempo_real() {

    verificar_nut || { pausa; return; }

    dibujar_panel

    trap 'tput cnorm; trap - INT; return 0' INT

    tput civis

    while true
    do
        actualizar_panel
        sleep 2
    done

    tput cnorm

}
############################################################
# DETECTAR MODO NUT LOCAL (netserver / netclient)
#
# Necesario para adaptar el servicio por LAN: en el equipo
# servidor (UPS por USB) el servicio local a vigilar es
# nut-server; en el equipo cliente (UPS remota por LAN) es
# nut-monitor. Antes el script asumía siempre nut-server
# y "upsc apc" en local, lo cual solo funciona en el servidor.
############################################################

detectar_modo_nut() {

    local MODE=""

    if [[ -f /etc/nut/nut.conf ]]
    then
        MODE=$(grep -oP '^MODE=\K.*' /etc/nut/nut.conf 2>/dev/null)
    fi

    case "$MODE" in

        netserver) echo "netserver" ;;

        netclient) echo "netclient" ;;

        *)
            # Sin nut.conf claro: si existe MONITOR en upsmon.conf
            # apuntando a un host distinto de localhost, se asume cliente.
            if grep -q "^MONITOR " /etc/nut/upsmon.conf 2>/dev/null
            then
                echo "netclient"
            else
                echo "netserver"
            fi
        ;;

    esac

}
############################################################
# SERVICIO DE MONITOREO / APAGADO AUTOMATICO (--service)
#
# Esta es la versión real confirmada por el usuario (funciona
# al 100% cuando la UPS está por USB en local). Se adapta aquí
# para LAN en dos puntos exactamente:
#
#   1) El servicio local que se comprueba como "disponible":
#      - Servidor (UPS por USB) -> nut-server
#      - Cliente  (UPS remota)  -> nut-monitor
#
#   2) El nombre de UPS que se consulta con upsc:
#      - Servidor -> "$UPS_NAME" (local, ej. "apc")
#      - Cliente  -> "$UPS_REMOTA" (ej. "apc@192.168.1.10"),
#        obtenido de la línea MONITOR de /etc/nut/upsmon.conf
#
# El resto de la lógica (temporización, límites, avisos por
# correo/Telegram, apagado de VMs/LXC/host) queda intacto tal
# como lo entregó el usuario.
############################################################

############################################################
# SERVICIO DE MONITOREO / APAGADO AUTOMATICO (--service)
############################################################

servicio_apagado_ups() {

    ########################################################
    # VARIABLES
    ########################################################

    UPS_EN_BATERIA=0
    SALIR_SERVICIO=0

    ########################################################
    # CAPTURAR CIERRE DEL SERVICIO (SYSTEMD)
    ########################################################

    trap '
        SALIR_SERVICIO=1

        registrar_log "Servicio detenido por systemd."

        if [[ -t 1 ]]; then
            tput cnorm
            clear
        fi

        exit 0
    ' SIGTERM SIGINT

    ########################################################
    # DETERMINAR MODO NUT
    ########################################################

    MODO_NUT=$(detectar_modo_nut)

    if [[ "$MODO_NUT" == "netclient" ]]
    then

        SERVICIO_NUT_LOCAL="nut-monitor"

        determinar_ups_objetivo
        UPS_OBJETIVO="$UPS_REMOTA"

    else

        SERVICIO_NUT_LOCAL="nut-server"

        UPS_OBJETIVO="$UPS_NAME"

    fi

    UPS_REMOTA="$UPS_OBJETIVO"

    registrar_log "Servicio de monitoreo iniciado. Modo: $MODO_NUT. UPS objetivo: $UPS_OBJETIVO"

    ########################################################
    # OCULTAR CURSOR
    ########################################################

    if [[ -t 1 ]]
    then
        tput civis
        clear
    fi

    ########################################################
    # CARGAR CONFIGURACIONES
    ########################################################

    cargar_configuracion
    cargar_email
    cargar_telegram

    ########################################################
    # BUCLE PRINCIPAL
    ########################################################

    while [[ $SALIR_SERVICIO -eq 0 ]]
    do

        ####################################################
        # VERIFICAR NUT
        ####################################################

        if ! systemctl is-active --quiet "${SERVICIO_NUT_LOCAL}.service"
        then

            registrar_log "$SERVICIO_NUT_LOCAL no está disponible. Esperando..."

            if [[ -t 1 ]]
            then
                clear
                echo
                echo -e "${AMARILLO}==============================================${RESET}"
                echo -e "${AMARILLO}       APC UPS - ESPERANDO NUT               ${RESET}"
                echo -e "${AMARILLO}==============================================${RESET}"
                echo
                echo "El servicio $SERVICIO_NUT_LOCAL no está disponible."
                echo
                echo "Reintentando automáticamente..."
                echo
                echo "Fecha: $(date '+%d/%m/%Y %H:%M:%S')"
            fi

            sleep 10
            continue

        fi

        ####################################################
        # VERIFICAR COMUNICACIÓN UPS
        ####################################################

        if ! upsc "$UPS_OBJETIVO" >/dev/null 2>&1
        then

            registrar_log "UPS ($UPS_OBJETIVO) no disponible. Esperando conexión..."

            if [[ -t 1 ]]
            then
                clear
                echo
                echo -e "${AMARILLO}==============================================${RESET}"
                echo -e "${AMARILLO}       APC UPS - ESPERANDO UPS               ${RESET}"
                echo -e "${AMARILLO}==============================================${RESET}"
                echo
                echo -e "${ROJO}No se puede comunicar con la UPS ($UPS_OBJETIVO).${RESET}"
                echo
                echo "Reintentando automáticamente..."
                echo
                echo "Fecha: $(date '+%d/%m/%Y %H:%M:%S')"
            fi

            sleep 10
            continue

        fi

        ####################################################
        # PANEL
        ####################################################

        if [[ -t 1 ]]
        then
            dibujar_panel
        fi

        ####################################################
        # LEER DATOS
        ####################################################

        ESTADO=$(obtener_valor ups.status)
        BATERIA=$(obtener_valor battery.charge)
        AUTONOMIA=$(obtener_valor battery.runtime)

        if [[ -z "$ESTADO" ]]
        then
            registrar_log "No se pudo obtener estado de la UPS."
            sleep 10
            continue
        fi

        ####################################################
        # ACTUALIZAR PANEL
        ####################################################

		if [[ -t 1 ]]
		then
		actualizar_panel
		fi

        ####################################################
        # UPS EN BATERÍA
        ####################################################

        if [[ "$ESTADO" == *"OB"* ]]
        then

            if [[ $UPS_EN_BATERIA -eq 0 ]]
            then

                UPS_EN_BATERIA=1

                registrar_log "Corte eléctrico detectado."

                enviar_correo \
                "UPS APC - Corte eléctrico" \
"Se detectó un corte eléctrico.

Servidor : $(hostname)

Fecha : $(date "+%d/%m/%Y %H:%M:%S %Z")

UPS : $UPS_OBJETIVO

Estado UPS : EN BATERÍA

Carga batería : ${BATERIA} %

Autonomía : ${AUTONOMIA} segundos"

                enviar_telegram \
"⚠️ UPS APC

Corte eléctrico detectado.

Servidor: $(hostname)

UPS: $UPS_OBJETIVO

Batería: ${BATERIA}%

Autonomía: ${AUTONOMIA}s"

            fi

            ################################################
            # ESPERA CONFIGURABLE
            ################################################

            if [[ -n "$WAIT_POWER_FAIL" ]] &&
               (( WAIT_POWER_FAIL > 0 ))
            then

                registrar_log "Esperando ${WAIT_POWER_FAIL} segundos para confirmar corte."

                for ((i=1;i<=WAIT_POWER_FAIL;i++))
                do

                    [[ $SALIR_SERVICIO -eq 1 ]] && break

                    sleep 1

                    if ! upsc "$UPS_OBJETIVO" >/dev/null 2>&1
                    then
                        registrar_log "Comunicación UPS perdida durante espera."
                        continue
                    fi

                    ESTADO=$(obtener_valor ups.status)

                    if [[ "$ESTADO" == *"OL"* ]]
                    then

                        UPS_EN_BATERIA=0

                        registrar_log "Energía restablecida."

                        enviar_correo \
                        "UPS APC - Energía restablecida" \
"La alimentación eléctrica ha sido restablecida.

Servidor : $(hostname)

Fecha : $(date "+%d/%m/%Y %H:%M:%S %Z")

UPS : $UPS_OBJETIVO

El apagado automático fue cancelado."

                        enviar_telegram \
"✅ UPS APC

La energía volvió.

Servidor: $(hostname)

UPS: $UPS_OBJETIVO

El apagado automático fue cancelado."

                        break

                    fi

                done

            fi

            ESTADO=$(obtener_valor ups.status)

            if [[ "$ESTADO" == *"OB"* ]]
            then

                BATERIA=$(obtener_valor battery.charge)
                AUTONOMIA=$(obtener_valor battery.runtime)

                if (( BATERIA <= BATTERY_LIMIT )) ||
                   (( AUTONOMIA <= RUNTIME_LIMIT ))
                then

                    registrar_log "Comienza apagado automático."

                    enviar_correo \
                    "UPS APC - Inicio de apagado" \
"La UPS alcanzó el límite configurado.

Servidor : $(hostname)

UPS : $UPS_OBJETIVO

Batería : ${BATERIA} %

Autonomía : ${AUTONOMIA} segundos

Comienza el apagado automático."

                    enviar_telegram \
"🛑 UPS APC

Comienza el apagado automático.

Servidor: $(hostname)

UPS: $UPS_OBJETIVO

Batería: ${BATERIA}%

Autonomía: ${AUTONOMIA}s"


                    apagar_host

                fi

            fi

        elif [[ "$ESTADO" == *"OL"* ]]
        then

            UPS_EN_BATERIA=0

        fi

        ####################################################
        # ESPERA ENTRE CONSULTAS
        ####################################################

        sleep 2

    done

    ########################################################
    # RESTAURAR TERMINAL
    ########################################################

    if [[ -t 1 ]]
    then
        tput cnorm
        clear
    fi

    registrar_log "Servicio finalizado."

}
############################################################
# MENU NUT NETWORK
############################################################

menu_nut_network() {

while true
do

    header_lan

    titulo "NUT NETWORK"

    echo

    echo -e "${AMARILLO}1)${RESET} Configurar NUT en Servidor Conectado a UPS"
    echo -e "${AMARILLO}2)${RESET} Estado del servidor NUT Conectado a UPS"
    echo
    echo -e "${AMARILLO}3)${RESET} Configurar Cliente NUT por LAN"
    echo -e "${AMARILLO}4)${RESET} Estado cliente NUT"
    echo -e "${AMARILLO}5)${RESET} Probar conexión a Cliente/Servidor por LAN"
    echo
    echo -e "${AMARILLO}6)${RESET} Menu Configurar Telegram ${VERDE}Mensajes / Alertas${RESET}"
    echo
    echo -e "${AMARILLO}7)${RESET} Menu Configurar Correo ${VERDE}SMTP / Alertas${RESET}"
    echo
    echo -e "${AMARILLO}8)${RESET} Menu Servicio systemd UPS APC ${VERDE}* Arranque al Inicio Monitor + Mensajes${RESET}"
    echo
    echo -e "${AMARILLO}9)${RESET} Reiniciar servicios NUT"
    echo -e "${AMARILLO}10)${RESET} Ver UPS remota en tiempo real ${VERDE}*(Monitor Texto)"
    echo -e "${AMARILLO}11)${RESET} Panel UPS en tiempo real ${VERDE}*(Monitor Gráfico)"
    echo -e "${AMARILLO}12)${RESET} Configurar apagado automático"
    echo -e "${AMARILLO}13)${RESET} Editar configuración del monitor (nano)"
	echo
    echo -e "${AMARILLO}14)${RESET} Ver estado de alertas"
	echo -e "${AMARILLO}15)${RESET} Ver logs UPS-APC del administrador"
    echo
	echo -e "${AMARILLO}16)${AMARILLO} Menu Apagado Server Proxmox - ${VERDE} Apagar VM / PC"
	
    linea

    echo -e "${ROJO}0)${RESET} Volver"

    echo

    read -rp "Seleccione: " OP

    case "$OP" in

        1) configurar_servidor_nut ;;

        2)
            header
            titulo "ESTADO SERVIDOR NUT"
            echo
            systemctl status nut-server --no-pager -l
            pausa
        ;;

        3) configurar_cliente_nut ;;

        4) estado_cliente_nut ;;

        5) probar_cliente_nut ;;

        6) menu_telegram ;;

        7) menu_correo ;;

        8) menu_servicio_ups ;;

        9) reiniciar_servicios_nut ;;

        10) panel_ups_remota ;;

        11) panel_tiempo_real ;;

        12) configurar_shutdown ;;

        13) editar_configuracion_monitor ;;

        14)
            header
            titulo "ESTADO DE ALERTAS"
            estado_alertas
            pausa
        ;;
		
		15)

                echo
                tail -50 "$LOGFILE"

                pausa

        ;;
		
		16)	menu_proxmox ;;		

        0) return ;;

        *) mensaje_error "Opción inválida."; pausa ;;

    esac

done

}
############################################################
# INICIO DEL PROGRAMA
############################################################

if [[ "$1" == "--service" ]]
then

    registrar_log "Inicio servicio monitor UPS"

    servicio_apagado_ups

else

    registrar_log "Inicio APC UPS Manager"

    menu_nut_network

fi
