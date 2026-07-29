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

echo -e "${CYAN}"
echo "══════════════════════════════════════════════════════════════"
echo "                 APC UPS APC SRV3KI MANAGER v${VERSION}"
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

    titulo "CONFIGURAR APC EASY UPS"

    echo
    echo -e "${AMARILLO}1)${RESET} Detectar automáticamente (USB + RS232)"
    echo -e "${AMARILLO}2)${RESET} Buscar solamente USB"
    echo -e "${AMARILLO}3)${RESET} Buscar solamente RS232"
    echo
    echo -e "${ROJO}0)${RESET} Cancelar"
    echo

    read -rp "Seleccione una opción: " TIPO

    case $TIPO in

        1)
            PATRON="/dev/ttyUSB* /dev/ttyS*"
        ;;

        2)
            PATRON="/dev/ttyUSB*"
        ;;

        3)
            PATRON="/dev/ttyS*"
        ;;

        0)
            return
        ;;

        *)
            mensaje_error "Opción inválida."
            pausa
            return
        ;;

    esac


    header
    titulo "BUSCANDO UPS"

    echo

    UPS_ENCONTRADA=0

    for PUERTO in $PATRON
    do

        [[ ! -e "$PUERTO" ]] && continue

        echo -ne "Probando $PUERTO ... "

cat > /etc/nut/ups.conf <<EOF
[apc]
driver = nutdrv_qx
port = $PUERTO
desc = APC Easy UPS SRV3KI
EOF

        upsdrvctl stop >/dev/null 2>&1
        sleep 1

        upsdrvctl start >/dev/null 2>&1

        sleep 3

        if upsc apc >/tmp/ups_test 2>/dev/null
        then

            MODELO=$(grep "device.model" /tmp/ups_test | cut -d: -f2- | xargs)

            echo -e "${VERDE}OK${RESET}"

            UPS_ENCONTRADA=1

            break

        else

            echo -e "${ROJO}NO${RESET}"

        fi

    done


    if [[ $UPS_ENCONTRADA -eq 0 ]]
    then

        echo
        mensaje_error "No se encontró ninguna UPS."

        pausa

        return

    fi


cat > /etc/nut/nut.conf <<EOF
MODE=standalone
EOF


    usermod -aG dialout nut

    systemctl enable nut-server >/dev/null 2>&1
    systemctl enable nut-monitor >/dev/null 2>&1

    systemctl restart nut-server
    systemctl restart nut-monitor

    echo
    linea

    echo -e "${VERDE}UPS detectada correctamente${RESET}"

    echo

    printf "%-20s %s\n" "Modelo:" "$MODELO"
    printf "%-20s %s\n" "Puerto:" "$PUERTO"
    printf "%-20s %s\n" "Driver:" "nutdrv_qx"

    linea

    mensaje_ok "Configuración aplicada."

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
# CONFIGURACION CORREO
############################################################

EMAIL_CONFIG="/root/ups-email.conf"

EMAIL_LISTA="/root/ups-email-lista.conf"

############################################################
# MENU GESTION CORREO
############################################################

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

            1)

                configurar_correo

            ;;

            2)

                activar_alertas_correo

            ;;

            3)

                desactivar_alertas_correo

            ;;

            4)

                agregar_destinatario

            ;;

            5)

                eliminar_destinatario

            ;;

            6)

                ver_destinatarios

            ;;

            7)

                probar_correo

            ;;

            8)

                ver_configuracion_correo

            ;;
			
            9)
                modificar_configuracion_correo
            ;;
			
            0)

                break

            ;;

            *)

                mensaje_error "Opción inválida."

                sleep 1

            ;;

        esac

    done

}
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
# ENVIAR CORREO A TODOS LOS DESTINATARIOS
############################################################

enviar_correo() {

    local ASUNTO="$1"
    local MENSAJE="$2"

    cargar_email || return 1

    [[ "$ALERTAS_CORREO" != "ON" ]] && return 0

    [[ ! -f "$EMAIL_LISTA" ]] && return 1

    while IFS= read -r DESTINO
    do

        [[ -z "$DESTINO" ]] && continue

        echo "$MENSAJE" | mail -s "$ASUNTO" "$DESTINO"

    done < "$EMAIL_LISTA"

    registrar_log "Correo enviado: $ASUNTO"

}

############################################################
# VERIFICAR DEPENDENCIAS CORREO
############################################################

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


    ####################################################
    # VERIFICAR COMANDOS
    ####################################################

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


    ####################################################
    # VERIFICAR CERTIFICADOS
    ####################################################

    if [[ ! -f /etc/ssl/certs/ca-certificates.crt ]]
    then

        mensaje_error "No existen certificados CA."

        return 1

    fi


    mensaje_ok "Sistema listo para configurar correo."

    return 0

}
############################################################
# CONFIGURAR CORREO SMTP
############################################################

configurar_correo() {

    header
    titulo "CONFIGURAR CORREO SMTP"

    verificar_dependencias_correo || {
        pausa
        return
    }

    ########################################################
    # SELECCIONAR PROVEEDOR
    ########################################################

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


    ########################################################
    # DATOS SMTP
    ########################################################

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


    ########################################################
    # GUARDAR CONFIGURACION
    ########################################################

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


    ########################################################
    # CONFIGURAR MSMTP
    ########################################################

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


    ########################################################
    # PRUEBA DE ENVIO
    ########################################################

    echo
    echo "Enviando correo de prueba..."
    echo

    MENSAJE="

APC UPS MANAGER

Configuracion SMTP realizada correctamente.

Servidor: $(hostname)

Fecha: $(date)

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
############################################################
# ACTIVAR ALERTAS POR CORREO
############################################################

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
############################################################
# DESACTIVAR ALERTAS POR CORREO
############################################################

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
############################################################
# AGREGAR DESTINATARIO
############################################################

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
############################################################
# ELIMINAR DESTINATARIO
############################################################

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
############################################################
# VER DESTINATARIOS
############################################################

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
############################################################
# VER CONFIGURACION CORREO SMTP
############################################################

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
############################################################
# ENVIAR CORREO DE PRUEBA A TODOS
############################################################

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

Fecha    : $(date)


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
############################################################
# MODIFICAR CONFIGURACION CORREO SMTP
############################################################

modificar_configuracion_correo() {

    if [[ ! -f "$EMAIL_CONFIG" ]]; then
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
                    1) SMTP_TLS="SI" ;;
                    2) SMTP_TLS="NO" ;;
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
		echo -e "${VERDE}16)${AMARILLO} Menu Configurar Correo ${VERDE}SMTP / Alertas"
		echo
		echo -e "${VERDE}17)${RESET} Estado general del sistema"
		echo
		echo -e "${CYAN}# Instala Servicio para Alertas (Correo - Telegram) Bateria Baja / Corte de Luz"
		echo
		echo -e "${VERDE}18)${RESET} Instalar Servicio systemd UPS APC"
		echo -e "${VERDE}19)${RESET} Activar UPS APC Monitor"
        echo -e "${VERDE}20)${RESET} Desactivar UPS APC Monitor"
        echo -e "${VERDE}21)${RESET} Estado UPS APC Monitor"
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

                menu_correo

            ;;

			
			17)

                panel_sistema

            ;;
			
			18)

                instalar_servicio_systemd

            ;;
			
			19)

                activar_monitor_ups

            ;;


            20)

               desactivar_monitor_ups

            ;;


            21)

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