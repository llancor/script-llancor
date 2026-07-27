#!/bin/bash

############################################################
# APC UPS MANAGER
# Versión: 1.0
# Compatible:
# Debian 12
# Debian 13
# Ubuntu
# Proxmox VE
############################################################

VERSION="1.0"

UPS_NAME="apc"

NUT_SERVICE="nut-server"

NUT_MONITOR="nut-monitor"

BACKUP_DIR="/root/backup-nut"

LOGFILE="/var/log/ups-manager.log"

CONFIG_DIR="/etc/nut"

############################################################
# COLORES
############################################################

ROJO="\e[1;31m"
VERDE="\e[1;32m"
AMARILLO="\e[1;33m"
AZUL="\e[1;34m"
MAGENTA="\e[1;35m"
CYAN="\e[1;36m"
BLANCO="\e[1;37m"

RESET="\e[0m"

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
# CABECERA
############################################################

header() {

clear

echo -e "${AZUL}"
echo "══════════════════════════════════════════════════════════════"
echo "                 APC UPS MANAGER v${VERSION}"
echo "══════════════════════════════════════════════════════════════"
echo -e "${RESET}"

}

############################################################
# FUNCIONES GENERALES
############################################################

pausa() {

    echo
    read -rp "Presione ENTER para continuar..."

}

############################################################

registrar_log() {

    FECHA=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$FECHA] $1" >> "$LOGFILE"

}

############################################################

mensaje_ok() {

    echo
    echo -e "${OK} ${VERDE}$1${RESET}"
    registrar_log "$1"

}

############################################################

mensaje_error() {

    echo
    echo -e "${ERROR} ${ROJO}$1${RESET}"
    registrar_log "ERROR: $1"

}

############################################################

mensaje_info() {

    echo
    echo -e "${INFO} ${CYAN}$1${RESET}"

}

############################################################

mensaje_warning() {

    echo
    echo -e "${WARNING} ${AMARILLO}$1${RESET}"

}

############################################################

linea() {

    echo "────────────────────────────────────────────────────────────"

}

############################################################

titulo() {

    linea
    echo -e "${AZUL}$1${RESET}"
    linea

}

############################################################

verificar_comando() {

    command -v "$1" >/dev/null 2>&1

}

############################################################

verificar_nut() {

    if ! verificar_comando upsc; then

        mensaje_error "NUT no está instalado."

        pausa

        return 1

    fi

    return 0

}

############################################################

verificar_ups() {

    upsc "$UPS_NAME" >/dev/null 2>&1

    if [[ $? -ne 0 ]]; then

        mensaje_error "No se pudo comunicar con la UPS."

        pausa

        return 1

    fi

    return 0

}

############################################################

servicio_activo() {

    systemctl is-active --quiet "$1"

}

############################################################

iniciar_servicio() {

    systemctl start "$1"

}

############################################################

detener_servicio() {

    systemctl stop "$1"

}

############################################################

reiniciar_servicio() {

    systemctl restart "$1"

}

############################################################

habilitar_servicio() {

    systemctl enable "$1"

}

############################################################

deshabilitar_servicio() {

    systemctl disable "$1"

}

############################################################

obtener_valor() {

    upsc "$UPS_NAME" 2>/dev/null | grep "^$1" | cut -d':' -f2- | sed 's/^ *//'

}

############################################################

confirmar() {

    read -rp "$1 [s/N]: " RESPUESTA

    case "$RESPUESTA" in

        s|S|si|SI|Si|sí|Sí)

            return 0
            ;;

        *)

            return 1
            ;;

    esac

}

############################################################

spinner() {

    local pid=$1
    local delay=0.1
    local spin='|/-\'

    while ps -p "$pid" >/dev/null 2>&1
    do
        for i in $(seq 0 3)
        do
            printf "\r${CYAN}Procesando... %s${RESET}" "${spin:$i:1}"
            sleep $delay
        done
    done

    printf "\r"

}

############################################################

ejecutar() {

    "$@" >/dev/null 2>&1 &

    spinner $!

    wait $!

}

############################################################

limpiar_logs() {

    > "$LOGFILE"

    mensaje_ok "Registro limpiado."

}

############################################################

fecha_actual() {

    date '+%d/%m/%Y %H:%M:%S'

}

############################################################

cabecera_estado() {

    header

    titulo "ESTADO GENERAL"

}

############################################################

mostrar_error_nut() {

    echo
    echo -e "${ROJO}No fue posible obtener información de la UPS.${RESET}"
    echo
    echo "Revise:"
    echo
    echo " • Servicio nut-server"
    echo " • Servicio nut-monitor"
    echo " • Archivo ups.conf"
    echo " • Puerto /dev/ttyUSB0"
    echo

}
############################################################
# BARRA DE PROGRESO
############################################################

barra_progreso() {

    local VALOR=$1
    local ANCHO=30

    [[ -z "$VALOR" ]] && VALOR=0

    VALOR=${VALOR%.*}

    (( VALOR < 0 )) && VALOR=0
    (( VALOR > 100 )) && VALOR=100

    local LLENOS=$((VALOR * ANCHO / 100))
    local VACIOS=$((ANCHO - LLENOS))

    if (( VALOR >= 70 )); then
        COLOR=$VERDE
    elif (( VALOR >= 30 )); then
        COLOR=$AMARILLO
    else
        COLOR=$ROJO
    fi

    printf "${COLOR}"

    for ((i=0;i<LLENOS;i++)); do
        printf "█"
    done

    printf "${RESET}"

    for ((i=0;i<VACIOS;i++)); do
        printf "░"
    done

    printf " %d%%" "$VALOR"

}

############################################################
# CONVERTIR SEGUNDOS A HH:MM
############################################################

convertir_tiempo() {

    local SEG=$1

    [[ -z "$SEG" ]] && SEG=0

    local HORAS=$((SEG/3600))
    local MINUTOS=$(((SEG%3600)/60))

    printf "%02d:%02d" "$HORAS" "$MINUTOS"

}

############################################################
# PANEL AVANZADO DE ESTADO UPS
############################################################

mostrar_estado() {

    verificar_nut || return
    verificar_ups || return


    header

    MODELO=$(obtener_valor device.model)
    ESTADO=$(obtener_valor ups.status)

    BATERIA=$(obtener_valor battery.charge)
    AUTONOMIA=$(obtener_valor battery.runtime)

    CARGA=$(obtener_valor ups.load)

    ENTRADA=$(obtener_valor input.voltage)
    SALIDA=$(obtener_valor output.voltage)

    FRECUENCIA=$(obtener_valor output.frequency)

    TEMPERATURA=$(obtener_valor ups.temperature)

    VOLTAJE_BATERIA=$(obtener_valor battery.voltage)

    FIRMWARE=$(obtener_valor ups.firmware)

    ALARMA=$(obtener_valor ups.beeper.status)

    POTENCIA=$(obtener_valor ups.power.nominal)


    case "$ESTADO" in

        OL)
            ESTADO_TXT="${VERDE}ONLINE${RESET}"
            ;;

        OB)
            ESTADO_TXT="${AMARILLO}EN BATERÍA${RESET}"
            ;;

        LB)
            ESTADO_TXT="${ROJO}BATERÍA BAJA${RESET}"
            ;;

        *)
            ESTADO_TXT="${MAGENTA}$ESTADO${RESET}"
            ;;

    esac


    echo -e "${CYAN}Modelo:${RESET}          $MODELO"
    echo -e "${CYAN}Estado:${RESET}          $ESTADO_TXT"
    echo -e "${CYAN}Potencia:${RESET}        $POTENCIA VA"

    linea


    echo -e "${CYAN}Batería${RESET}"
    barra_progreso "$BATERIA"

    echo


    echo -e "${CYAN}Carga UPS${RESET}"
    barra_progreso "$CARGA"


    echo
    linea


    printf "%-25s %s\n" "Autonomía:" "$(convertir_tiempo $AUTONOMIA)"
    printf "%-25s %s V\n" "Entrada:" "$ENTRADA"
    printf "%-25s %s V\n" "Salida:" "$SALIDA"
    printf "%-25s %s Hz\n" "Frecuencia:" "$FRECUENCIA"
    printf "%-25s %s °C\n" "Temperatura:" "$TEMPERATURA"

    echo

    linea

    echo -e "${CYAN}Información batería${RESET}"

    printf "%-25s %s V\n" "Voltaje batería:" "$VOLTAJE_BATERIA"

    echo

    linea

    echo -e "${CYAN}Sistema${RESET}"

    printf "%-25s %s\n" "Firmware:" "$FIRMWARE"
    printf "%-25s %s\n" "Alarma:" "$ALARMA"

    linea


    registrar_log "Consulta estado UPS"

}

############################################################
# PANEL EN TIEMPO REAL
############################################################

estado_tiempo_real() {

    while true
    do

        mostrar_estado

        echo
        echo -e "${AMARILLO}Actualizando cada 2 segundos...${RESET}"
        echo
        echo "Presione CTRL+C para volver al menú."

        sleep 2

    done

}
############################################################
# INSTALACION Y CONFIGURACION NUT
############################################################


verificar_dependencias_nut() {

    header

    titulo "VERIFICANDO DEPENDENCIAS"


    echo


    if command -v upsc >/dev/null 2>&1
    then
        echo -e "${VERDE}✔${RESET} NUT instalado"
    else
        echo -e "${AMARILLO}⚠${RESET} NUT no instalado"
    fi


    if [[ -e /dev/ttyUSB0 ]]
    then
        echo -e "${VERDE}✔${RESET} UPS detectada en /dev/ttyUSB0"
    else
        echo -e "${ROJO}✘${RESET} No se detecta /dev/ttyUSB0"
    fi


    if id nut | grep -q dialout
    then
        echo -e "${VERDE}✔${RESET} Usuario nut pertenece a dialout"
    else
        echo -e "${AMARILLO}⚠${RESET} Usuario nut no pertenece a dialout"
    fi


    if systemctl is-active --quiet nut-server
    then
        echo -e "${VERDE}✔${RESET} nut-server activo"
    else
        echo -e "${AMARILLO}⚠${RESET} nut-server detenido"
    fi


    pausa

}



############################################################
# INSTALAR NUT
############################################################


instalar_nut() {


    header

    titulo "INSTALANDO NUT"


    echo


    apt update


    apt install -y \
    nut \
    nut-client \
    nut-server


    if [[ $? -eq 0 ]]
    then

        mensaje_ok "NUT instalado correctamente."

    else

        mensaje_error "Error instalando NUT."

    fi


    pausa

}



############################################################
# CONFIGURAR NUT PARA APC SRV3KI
############################################################


configurar_nut_apc() {


    header

    titulo "CONFIGURANDO APC SRV3KI"


    echo


    echo "Creando configuración NUT..."


cat > /etc/nut/nut.conf <<EOF
MODE=standalone
EOF



cat > /etc/nut/ups.conf <<EOF
[apc]

driver = nutdrv_qx

port = /dev/ttyUSB0

desc = APC Easy UPS SRV3KI

EOF



    echo
    echo "Ajustando permisos USB..."


    usermod -aG dialout nut



    systemctl enable nut-server
    systemctl enable nut-monitor



    systemctl restart nut-server
    systemctl restart nut-monitor



    mensaje_ok "Configuración APC SRV3KI aplicada."


    pausa

}



############################################################
# PRUEBA AUTOMATICA UPS
############################################################


prueba_ups() {


    header

    titulo "PRUEBA COMUNICACION UPS"


    echo


    sleep 2


    if upsc apc >/dev/null 2>&1
    then

        mensaje_ok "Comunicación con UPS correcta."

        echo

        echo "Modelo:"
        obtener_valor device.model

        echo

        echo "Estado:"
        obtener_valor ups.status

        echo

        echo "Batería:"
        obtener_valor battery.charge

        echo

        echo "Carga:"
        obtener_valor ups.load


    else

        mensaje_error "No hay comunicación con la UPS."

    fi


    pausa

}
############################################################
# APAGADO SEGURO PROXMOX
############################################################


# Valores por defecto

BATTERY_LIMIT=20

RUNTIME_LIMIT=600

WAIT_POWER_FAIL=60



############################################################
# MOSTRAR CONFIGURACION APAGADO
############################################################

mostrar_config_shutdown() {


    header

    titulo "CONFIGURACION APAGADO AUTOMATICO"


    echo
    echo "Porcentaje mínimo batería: ${BATTERY_LIMIT}%"
    echo "Autonomía mínima:         ${RUNTIME_LIMIT} segundos"
    echo "Espera corte eléctrico:   ${WAIT_POWER_FAIL} segundos"


    pausa

}



############################################################
# APAGAR MAQUINAS VIRTUALES
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

            qm shutdown "$VM" --timeout 60


        done


    else

        echo "No es un nodo Proxmox."

    fi

}



############################################################
# APAGAR CONTENEDORES LXC
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

            pct shutdown "$ID"


        done


    fi

}



############################################################
# APAGADO COMPLETO DEL HOST
############################################################

apagar_host_proxmox() {


    echo
    echo "Apagando nodo Proxmox..."
    echo


    registrar_log "Inicio apagado automático Proxmox"


    sleep 10


    shutdown -h now


}



############################################################
# MONITOR AUTOMATICO UPS
############################################################

monitor_apagado_ups() {


    header

    titulo "MONITOR APAGADO AUTOMATICO"


    echo
    echo "Esperando eventos de UPS..."
    echo "CTRL+C para cancelar."
    echo


    while true
    do


        ESTADO=$(obtener_valor ups.status)

        BATERIA=$(obtener_valor battery.charge)

        AUTONOMIA=$(obtener_valor battery.runtime)



        echo "$(date) Estado:$ESTADO Bateria:$BATERIA% Tiempo:${AUTONOMIA}s"



        if [[ "$ESTADO" == *"OB"* ]]
        then


            echo
            echo "⚠ CORTE ELECTRICO DETECTADO"
            echo


            sleep "$WAIT_POWER_FAIL"



            BATERIA=$(obtener_valor battery.charge)

            AUTONOMIA=$(obtener_valor battery.runtime)



            if (( BATERIA <= BATTERY_LIMIT )) || (( AUTONOMIA <= RUNTIME_LIMIT ))
            then


                echo
                echo "Condiciones de apagado cumplidas."
                echo


                apagar_vm_proxmox

                apagar_lxc_proxmox

                apagar_host_proxmox


            fi


        fi



        sleep 10


    done

}
############################################################
# TELEGRAM
############################################################


TELEGRAM_CONFIG="/root/telegram_ups.conf"


############################################################
# CARGAR CONFIG TELEGRAM
############################################################

cargar_telegram() {


    if [[ -f "$TELEGRAM_CONFIG" ]]
    then

        source "$TELEGRAM_CONFIG"

    else

        return 1

    fi

}



############################################################
# ENVIAR MENSAJE TELEGRAM
############################################################

enviar_telegram() {


    MENSAJE="$1"


    cargar_telegram


    if [[ -z "$BOT_TOKEN" ]] || [[ -z "$CHAT_ID" ]]
    then

        echo "Telegram no configurado"

        return 1

    fi



    curl -s \
    -X POST \
    "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$MENSAJE" \
    -d parse_mode="HTML" \
    >/dev/null



}



############################################################
# CONFIGURAR TELEGRAM
############################################################

configurar_telegram() {


    header

    titulo "CONFIGURACION TELEGRAM"


    echo


    read -rp "Ingrese BOT TOKEN: " TOKEN


    read -rp "Ingrese CHAT ID: " ID



cat > "$TELEGRAM_CONFIG" <<EOF
BOT_TOKEN="$TOKEN"
CHAT_ID="$ID"
ALERTAS_TELEGRAM="OFF"
EOF



    chmod 600 "$TELEGRAM_CONFIG"



    mensaje_ok "Telegram configurado."


    pausa

}



############################################################
# PRUEBA TELEGRAM
############################################################

probar_telegram() {


    header

    titulo "PRUEBA TELEGRAM"


    enviar_telegram "
<b>✅ APC UPS MANAGER</b>

Prueba de notificación correcta.

Servidor: $(hostname)
Fecha: $(date)
"


    mensaje_ok "Mensaje enviado."

    pausa

}
############################################################
# ACTIVAR / DESACTIVAR ALERTAS TELEGRAM
############################################################

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
############################################################
# ALERTAS POR CORREO
############################################################


EMAIL_CONFIG="/root/ups-email.conf"


############################################################
# CARGAR CONFIGURACION EMAIL
############################################################

cargar_email() {

    if [[ -f "$EMAIL_CONFIG" ]]
    then

        source "$EMAIL_CONFIG"

    else

        return 1

    fi

}



############################################################
# ENVIAR CORREO
############################################################

enviar_correo() {


    ASUNTO="$1"
    MENSAJE="$2"


    cargar_email


    if [[ "$ALERTAS_CORREO" != "ON" ]]
    then

        return 0

    fi



    if [[ -z "$EMAIL_DESTINO" ]]
    then

        return 1

    fi



    echo "$MENSAJE" | mail -s "$ASUNTO" "$EMAIL_DESTINO"


    registrar_log "Correo enviado: $ASUNTO"


}



############################################################
# CONFIGURAR CORREO
############################################################

configurar_correo() {


    header

    titulo "CONFIGURACION CORREO"


    echo


    read -rp "Correo destino: " DESTINO



cat > "$EMAIL_CONFIG" <<EOF
EMAIL_DESTINO="$DESTINO"
ALERTAS_CORREO="OFF"
EOF


    chmod 600 "$EMAIL_CONFIG"


    mensaje_ok "Correo configurado."

    echo
    echo "Estado inicial: DESACTIVADO"

    pausa

}



############################################################
# PRUEBA CORREO
############################################################

probar_correo() {


    header

    titulo "PRUEBA DE CORREO"


    cargar_email


    if [[ -z "$EMAIL_DESTINO" ]]
    then

        mensaje_error "Correo no configurado."

        pausa

        return

    fi



    echo "
APC UPS MANAGER

Prueba de correo correcta.

Servidor:
$(hostname)

Fecha:
$(date)
" | mail -s "Prueba UPS APC" "$EMAIL_DESTINO"



    mensaje_ok "Correo enviado."

    pausa

}



############################################################
# ACTIVAR / DESACTIVAR ALERTAS
############################################################

toggle_alertas_correo() {


    header

    titulo "ALERTAS CORREO"


    cargar_email



    if [[ "$ALERTAS_CORREO" == "ON" ]]
    then


        echo
        echo "Estado actual: ACTIVADAS"
        echo


        read -rp "¿Desactivar alertas? [s/N]: " RESP


        if [[ "$RESP" =~ ^[sS]$ ]]
        then

            sed -i 's/ALERTAS_CORREO="ON"/ALERTAS_CORREO="OFF"/' "$EMAIL_CONFIG"

            mensaje_ok "Alertas por correo desactivadas."

        fi



    else


        echo
        echo "Estado actual: DESACTIVADAS"
        echo


        read -rp "¿Activar alertas? [s/N]: " RESP


        if [[ "$RESP" =~ ^[sS]$ ]]
        then

            sed -i 's/ALERTAS_CORREO="OFF"/ALERTAS_CORREO="ON"/' "$EMAIL_CONFIG"

            mensaje_ok "Alertas por correo activadas."

        fi


    fi


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


        if [[ "$ALERTAS_TELEGRAM" == "ON" ]]
        then
            echo -e "Telegram       : ${VERDE}ACTIVO${RESET}"
        else
            echo -e "Telegram       : ${AMARILLO}DESACTIVADO${RESET}"
        fi

    else

        echo -e "Telegram       : ${ROJO}NO CONFIGURADO${RESET}"

    fi



    if [[ -f "$EMAIL_CONFIG" ]]
    then

        cargar_email


        if [[ "$ALERTAS_CORREO" == "ON" ]]
        then
            echo -e "Correo         : ${VERDE}ACTIVO${RESET}"
        else
            echo -e "Correo         : ${AMARILLO}DESACTIVADO${RESET}"
        fi


    else

        echo -e "Correo         : ${ROJO}NO CONFIGURADO${RESET}"

    fi


}



############################################################
# ESTADO COMPLETO
############################################################


panel_sistema() {


    header

    titulo "ESTADO GENERAL APC UPS MANAGER"


    echo


    echo "UPS"
    echo "────────────────────────────────"


    obtener_valor ups.status
    obtener_valor device.model
    obtener_valor battery.charge
    obtener_valor ups.load
    obtener_valor battery.runtime
    obtener_valor ups.temperature


    echo


    echo "SERVICIOS"
    echo "────────────────────────────────"


    if systemctl is-active --quiet nut-server
    then

        echo -e "NUT Server     : ${VERDE}ACTIVO${RESET}"

    else

        echo -e "NUT Server     : ${ROJO}DETENIDO${RESET}"

    fi



    if systemctl is-active --quiet nut-monitor
    then

        echo -e "NUT Monitor    : ${VERDE}ACTIVO${RESET}"

    else

        echo -e "NUT Monitor    : ${ROJO}DETENIDO${RESET}"

    fi



    echo


    estado_alertas


    echo


    if systemctl is-enabled ups-apc-monitor >/dev/null 2>&1
    then

        echo -e "Monitor UPS    : ${VERDE}INSTALADO${RESET}"

    else

        echo -e "Monitor UPS    : ${AMARILLO}NO INSTALADO${RESET}"

    fi


    linea


    pausa

}
############################################################
# CONTROL SERVICIO UPS APC MONITOR
############################################################


activar_monitor_ups() {


    header

    titulo "ACTIVAR UPS APC MONITOR"


    echo

    systemctl enable ups-apc-monitor

    systemctl start ups-apc-monitor


    if systemctl is-active --quiet ups-apc-monitor
    then

        mensaje_ok "UPS APC Monitor activado."

    else

        mensaje_error "No fue posible iniciar el monitor."

    fi


    pausa

}



############################################################


desactivar_monitor_ups() {


    header

    titulo "DESACTIVAR UPS APC MONITOR"


    echo


    systemctl stop ups-apc-monitor


    systemctl disable ups-apc-monitor



    if systemctl is-active --quiet ups-apc-monitor
    then

        mensaje_error "El monitor sigue activo."

    else

        mensaje_ok "UPS APC Monitor desactivado."

    fi


    pausa

}



############################################################


estado_monitor_ups() {


    header

    titulo "ESTADO UPS APC MONITOR"


    echo


    if systemctl is-active --quiet ups-apc-monitor
    then

        echo -e "Servicio: ${VERDE}ACTIVO${RESET}"

    else

        echo -e "Servicio: ${ROJO}DETENIDO${RESET}"

    fi



    echo


    systemctl status ups-apc-monitor --no-pager -l



    pausa

}
############################################################
# MENU PRINCIPAL
############################################################

menu() {

    while true
    do

        header

        echo -e "${CYAN}"
        echo "              APC UPS MANAGER"
        echo -e "${RESET}"

        linea

        echo -e "${VERDE}1)${RESET} Ver estado de la UPS"
        echo -e "${VERDE}2)${RESET} Monitor en tiempo real"
        echo -e "${VERDE}3)${RESET} Probar comunicación NUT"
        echo -e "${VERDE}4)${RESET} Reiniciar servicios NUT"
        echo -e "${VERDE}5)${RESET} Ver configuración UPS"
        echo -e "${VERDE}6)${RESET} Ver logs del administrador"
		echo
		echo -e "${CYAN}# Instalacion y Ajustes UPS"
        echo
		echo -e "${VERDE}7)${RESET} Verificar dependencias NUT - ${CYAN}(1°)${RESET}"
        echo -e "${VERDE}8)${RESET} Instalar NUT - ${CYAN}(2°)${RESET}"
        echo -e "${VERDE}9)${RESET} Configurar APC SRV3KI - ${CYAN}(3°)${RESET}"
        echo -e "${VERDE}10)${RESET} Probar comunicación UPS - ${CYAN}(4°)${RESET}"
        echo
		echo -e "${CYAN}# Apagado Automatico de PC-SERVIDOR"
        echo
		echo -e "${VERDE}11)${RESET} Ver configuración apagado"
        echo -e "${VERDE}12)${RESET} Activar monitor apagado automático"
		echo
		echo -e "${CYAN}# Alertas Por (Correo - Telegram) Bateria Baja / Corte de Luz"
		echo
		echo -e "${VERDE}13)${RESET} Configurar Telegram"
        echo -e "${VERDE}14)${RESET} Probar Telegram"
		echo -e "${VERDE}15)${RESET} Activar/desactivar alertas Telegram"
		echo
		echo -e "${VERDE}16)${RESET} Configurar correo"
        echo -e "${VERDE}17)${RESET} Probar correo"
        echo -e "${VERDE}18)${RESET} Activar/desactivar alertas correo"
		echo
		echo -e "${VERDE}19)${RESET} Estado general del sistema"
		echo
		echo -e "${CYAN}# Instala Servicio para Alertas (Correo - Telegram) Bateria Baja / Corte de Luz"
		echo
		echo -e "${VERDE}20)${RESET} Instalar Servicio systemd UPS APC"
		echo -e "${VERDE}21)${RESET} Activar UPS APC Monitor"
        echo -e "${VERDE}22)${RESET} Desactivar UPS APC Monitor"
        echo -e "${VERDE}23)${RESET} Estado UPS APC Monitor"
		echo
        echo -e "${ROJO}0)${RESET} Salir"

        linea

        read -rp "Seleccione una opción: " OPCION


        case $OPCION in

            1)

                mostrar_estado
                pausa

            ;;


            2)

                estado_tiempo_real

            ;;


            3)

                if verificar_ups; then

                    mensaje_ok "Comunicación con UPS correcta."

                else

                    mensaje_error "No hay comunicación con la UPS."

                fi

                pausa

            ;;


            4)

                reiniciar_servicio nut-server
                reiniciar_servicio nut-monitor

                mensaje_ok "Servicios NUT reiniciados."

                pausa

            ;;


            5)

                echo
                cat /etc/nut/ups.conf

                pausa

            ;;


            6)

                echo
                tail -50 "$LOGFILE"

                pausa

            ;;

            7)

                verificar_dependencias_nut

            ;;


            8)

                instalar_nut

            ;;


            9)

                configurar_nut_apc

            ;;


            10)

                prueba_ups

            ;;
			
            11)

                mostrar_config_shutdown

            ;;


            12)

                monitor_apagado_ups

            ;;
			
            13)

                configurar_telegram

            ;;


            14)

                probar_telegram

            ;;
			
			15)

               toggle_alertas_telegram

            ;;
			
            16)

                configurar_correo

            ;;


            17)

                probar_correo

            ;;


            18)

                toggle_alertas_correo

            ;;
			
			19)

                panel_sistema

            ;;
			
			20)

                instalar_servicio_systemd

            ;;
			
			21)

                activar_monitor_ups

            ;;


            22)

               desactivar_monitor_ups

            ;;


            23)

               estado_monitor_ups

            ;;
			
            0)

                clear
                echo "Saliendo APC UPS Manager..."
                exit 0

            ;;


            *)

                mensaje_error "Opción incorrecta."
                pausa

            ;;

        esac

    done

}


############################################################
# INICIO DEL PROGRAMA
############################################################

registrar_log "Inicio APC UPS Manager"

menu