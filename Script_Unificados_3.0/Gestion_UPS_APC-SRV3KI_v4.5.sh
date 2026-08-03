#!/bin/bash

############################################################
# APC UPS MANAGER
# Versión: 4.5
# Compatible:
# Debian 12
# Debian 13
# Ubuntu
# Proxmox VE
############################################################

VERSION="4.5"

UPS_NAME="apc"

NUT_SERVICE="nut-server"

NUT_MONITOR="nut-monitor"

BACKUP_DIR="/root/backup-nut"

LOGFILE="/var/log/ups-manager.log"

CONFIG_DIR="/etc/nut"

############################################################
# VARIABLES
############################################################
SCRIPT="/root/Gestion_UPS_APC-SRV3KI_v4.5.sh"

SCRIPT_MONITOR="/usr/local/sbin/ups-apc-monitor"

# AL CAMBIAR EL NOMBRE DE LOS SERVICIO SIEMPRE PREMANECE EL .service AL FINAL #
# Y DEBEN LLAMARCE IGUAL EN SERVICIO_MONITOR Y NOMBRE_SERVICIO ups-apc-monitor.service #

SERVICIO_MONITOR="/etc/systemd/system/ups-apc-monitor.service"

NOMBRE_SERVICIO="ups-apc-monitor.service"

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

    local VALOR="${1:-0}"
    local ANCHO=30
    local COLOR=""
    local LLENOS
    local VACIOS
    local i

    # Eliminar decimales
    VALOR=${VALOR%.*}

    # Validar número
    [[ ! "$VALOR" =~ ^[0-9]+$ ]] && VALOR=0

    (( VALOR < 0 )) && VALOR=0
    (( VALOR > 100 )) && VALOR=100

    LLENOS=$((VALOR * ANCHO / 100))
    VACIOS=$((ANCHO - LLENOS))

    if (( VALOR >= 70 )); then
        COLOR="$VERDE"
    elif (( VALOR >= 30 )); then
        COLOR="$AMARILLO"
    else
        COLOR="$ROJO"
    fi

    printf "%b" "$COLOR"

    for ((i=0; i<LLENOS; i++)); do
        printf "█"
    done

    printf "%b" "$RESET"

    for ((i=0; i<VACIOS; i++)); do
        printf "░"
    done

    printf " %3d%%" "$VALOR"

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
# DIBUJAR PANEL
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
# ACTUALIZAR PANEL
############################################################

actualizar_panel() {

    verificar_nut || return
    verificar_ups || return

    ########################################################
    # DATOS UPS
    ########################################################

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

    ########################################################
    # ESTADO UPS
    ########################################################

    case "$ESTADO" in
        OL) ESTADO_TXT="${VERDE}ONLINE${RESET}" ;;
        OB) ESTADO_TXT="${AMARILLO}EN BATERÍA${RESET}" ;;
        LB) ESTADO_TXT="${ROJO}BATERÍA BAJA${RESET}" ;;
        *)  ESTADO_TXT="${MAGENTA}${ESTADO}${RESET}" ;;
    esac

    ########################################################
    # CARGAR CONFIGURACIÓN
    ########################################################

    cargar_configuracion
    cargar_email
    cargar_telegram

	####################################################
	# ESTADO DEL SERVICIO MONITOR
	####################################################

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

    ########################################################
    # ÚLTIMOS EVENTOS
    ########################################################

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

    ########################################################
    # INFORMACIÓN UPS
    ########################################################

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

    ########################################################
    # ESTADO DEL MONITOR
    ########################################################

    tput cup 35 0
    tput el
    printf "${CYAN}Monitor automático al reiniciar :${RESET} %b" "$ESTADO_MONITOR"

    tput cup 36 0
    tput el
    printf "${CYAN}Alertas correo.... :${RESET} %b" "$ESTADO_CORREO"

    tput cup 37 0
    tput el
    printf "${CYAN}Alertas Telegram.. :${RESET} %b" "$ESTADO_TELEGRAM"

    ########################################################
    # ÚLTIMOS EVENTOS
    ########################################################

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

    ########################################################
    # FECHA
    ########################################################

    tput cup 44 0
    tput el
    printf "Última actualización: %s" "$(date '+%d/%m/%Y %H:%M:%S')"

}
############################################################
# PANEL AVANZADO DE ESTADO UPS
############################################################

mostrar_estado() {

    verificar_nut || return
    verificar_ups || return

echo "══════════════════════════════════════════════════════════════"
echo -e "    ${CYAN}APC UPS MANAGER - MONITOR EN TIEMPO REAL${RESET}"
echo "══════════════════════════════════════════════════════════════"
echo
    

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
# MONITOR EN TIEMPO REAL
############################################################

estado_tiempo_real() {

    trap 'tput cnorm; clear; return' INT

    tput civis

    dibujar_panel

    while true
    do

        ####################################################
        # ÚLTIMOS 3 LOGS
        ####################################################

        if [[ -f "$LOGFILE" ]]
        then

            mapfile -t ULTIMOS < <(tail -n 3 "$LOGFILE")

            LOG1="${ULTIMOS[0]:-}"
            LOG2="${ULTIMOS[1]:-}"
            LOG3="${ULTIMOS[2]:-}"

        else

            LOG1="No existen registros."
            LOG2=""
            LOG3=""

        fi

        ####################################################
        # ACTUALIZAR PANEL
        ####################################################

        actualizar_panel

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


	MODELO=$(upsc apc device.model 2>/dev/null)

	if [[ -n "$MODELO" ]]
	then
    echo -e "${VERDE}✔${RESET} UPS detectada: $MODELO"
	else
    echo -e "${ROJO}✘${RESET} No se detecta la UPS"
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

    if [[ $? -ne 0 ]]
    then
        mensaje_error "Error instalando NUT."
        pausa
        return 1
    fi

    ########################################################
    # AGREGAR USUARIO NUT AL GRUPO DIALOUT
    ########################################################

    if id nut >/dev/null 2>&1
    then

        if id -nG nut | grep -qw dialout
        then

            echo -e "${VERDE}✔${RESET} El usuario 'nut' ya pertenece al grupo dialout."

        else

            usermod -aG dialout nut

            if [[ $? -eq 0 ]]
            then
                echo -e "${VERDE}✔${RESET} Usuario 'nut' agregado al grupo dialout."
            else
                echo -e "${ROJO}✘${RESET} No fue posible agregar el usuario 'nut' al grupo dialout."
            fi

        fi

    else

        echo -e "${AMARILLO}⚠${RESET} El usuario 'nut' no existe."

    fi

    ########################################################
    # REINICIAR SERVICIOS
    ########################################################

    systemctl restart nut-server 2>/dev/null
    systemctl restart nut-monitor 2>/dev/null

    mensaje_ok "NUT instalado y configurado correctamente."

    pausa

}
############################################################
# CONFIGURAR NUT PARA APC SRV3KI
# Detección USB + RS232
# USB utiliza /dev/serial/by-id/ para evitar cambios ttyUSB
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

    case "$TIPO" in

        1)
            BUSCAR_USB=1
            BUSCAR_RS232=1
        ;;

        2)
            BUSCAR_USB=1
            BUSCAR_RS232=0
        ;;

        3)
            BUSCAR_USB=0
            BUSCAR_RS232=1
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


    ########################################################
    # COMPROBAR DEPENDENCIAS
    ########################################################

    if ! command -v upsc >/dev/null 2>&1
    then
        mensaje_error "NUT no está instalado."
        pausa
        return
    fi

    if ! command -v upsdrvctl >/dev/null 2>&1
    then
        mensaje_error "upsdrvctl no está disponible."
        pausa
        return
    fi


    ########################################################
    # PREPARAR
    ########################################################

    header
    titulo "BUSCANDO UPS"

    echo

    UPS_ENCONTRADA=0
    PUERTO_FINAL=""
    TIPO_PUERTO=""


    ########################################################
    # DETENER DRIVER ANTERIOR
    ########################################################

    echo "Deteniendo drivers NUT anteriores..."

    systemctl stop 'nut-driver@*.service' >/dev/null 2>&1
    upsdrvctl stop >/dev/null 2>&1

    sleep 2


    ########################################################
    # BUSCAR USB
    ########################################################

    if [[ $BUSCAR_USB -eq 1 ]]
    then

        echo
        echo -e "${CYAN}Buscando adaptadores USB...${RESET}"
        echo

        for PUERTO in /dev/ttyUSB*
        do

            [[ ! -e "$PUERTO" ]] && continue

            echo -ne "Probando $PUERTO ... "

            ################################################
            # BUSCAR RUTA PERMANENTE
            ################################################

            PUERTO_ESTABLE=""

            for LINK in /dev/serial/by-id/*
            do

                [[ ! -e "$LINK" ]] && continue

                TARGET=$(readlink -f "$LINK" 2>/dev/null)

                if [[ "$TARGET" == "$PUERTO" ]]
                then

                    PUERTO_ESTABLE="$LINK"
                    break

                fi

            done


            ################################################
            # SI NO EXISTE BY-ID USAR TEMPORALMENTE USB
            ################################################

            if [[ -n "$PUERTO_ESTABLE" ]]
            then

                PUERTO_PRUEBA="$PUERTO_ESTABLE"

                echo -ne "USB estable encontrado "

            else

                PUERTO_PRUEBA="$PUERTO"

                echo -ne "sin ruta by-id "

            fi


            ################################################
            # CONFIGURAR TEMPORALMENTE NUT
            ################################################

            cat > /etc/nut/ups.conf <<EOF
[apc]
driver = nutdrv_qx
port = $PUERTO_PRUEBA
desc = APC Easy UPS SRV3KI
EOF


            ################################################
            # PROBAR DRIVER
            ################################################

            upsdrvctl stop >/dev/null 2>&1
            sleep 1

            upsdrvctl start >/dev/null 2>&1

            sleep 3


            ################################################
            # COMPROBAR UPS
            ################################################

            if upsc apc >/tmp/ups_test 2>/dev/null
            then

                MODELO=$(grep "^device.model:" /tmp/ups_test \
                    | cut -d: -f2- | xargs)

                [[ -z "$MODELO" ]] && MODELO="APC Easy UPS SRV3KI"


                echo -e "${VERDE}OK${RESET}"

                UPS_ENCONTRADA=1

                if [[ -n "$PUERTO_ESTABLE" ]]
                then
                    PUERTO_FINAL="$PUERTO_ESTABLE"
                    TIPO_PUERTO="USB permanente"
                else
                    PUERTO_FINAL="$PUERTO"
                    TIPO_PUERTO="USB temporal"
                fi

                break

            else

                echo -e "${ROJO}NO${RESET}"

            fi

        done

    fi


    ########################################################
    # BUSCAR RS232
    ########################################################

    if [[ $UPS_ENCONTRADA -eq 0 && $BUSCAR_RS232 -eq 1 ]]
    then

        echo
        echo -e "${CYAN}Buscando puertos RS232...${RESET}"
        echo

        for PUERTO in /dev/ttyS*
        do

            [[ ! -e "$PUERTO" ]] && continue

            echo -ne "Probando $PUERTO ... "


            ################################################
            # CONFIGURAR NUT
            ################################################

            cat > /etc/nut/ups.conf <<EOF
[apc]
driver = nutdrv_qx
port = $PUERTO
desc = APC Easy UPS SRV3KI
EOF


            ################################################
            # PROBAR DRIVER
            ################################################

            upsdrvctl stop >/dev/null 2>&1
            sleep 1

            upsdrvctl start >/dev/null 2>&1

            sleep 3


            ################################################
            # COMPROBAR UPS
            ################################################

            if upsc apc >/tmp/ups_test 2>/dev/null
            then

                MODELO=$(grep "^device.model:" /tmp/ups_test \
                    | cut -d: -f2- | xargs)

                [[ -z "$MODELO" ]] && MODELO="APC Easy UPS SRV3KI"


                echo -e "${VERDE}OK${RESET}"

                UPS_ENCONTRADA=1

                PUERTO_FINAL="$PUERTO"
                TIPO_PUERTO="RS232"

                break

            else

                echo -e "${ROJO}NO${RESET}"

            fi

        done

    fi


    ########################################################
    # NO ENCONTRADA
    ########################################################

    if [[ $UPS_ENCONTRADA -eq 0 ]]
    then

        echo
        mensaje_error "No se encontró ninguna UPS."

        upsdrvctl stop >/dev/null 2>&1

        rm -f /tmp/ups_test

        pausa

        return

    fi


    ########################################################
    # CONFIGURACIÓN NUT
    ########################################################

    cat > /etc/nut/nut.conf <<EOF
MODE=standalone
EOF


    ########################################################
    # PERMISOS
    ########################################################

    usermod -aG dialout nut


    ########################################################
    # GUARDAR CONFIGURACIÓN DEFINITIVA
    ########################################################

    cat > /etc/nut/ups.conf <<EOF
[apc]
driver = nutdrv_qx
port = $PUERTO_FINAL
desc = APC Easy UPS SRV3KI
EOF


    ########################################################
    # DETENER DRIVER MANUAL
    ########################################################

    upsdrvctl stop >/dev/null 2>&1

    sleep 2


    ########################################################
    # RECARGAR SYSTEMD
    ########################################################

    systemctl daemon-reload


    ########################################################
    # ACTIVAR NUT
    ########################################################

    systemctl enable nut-driver-enumerator.path >/dev/null 2>&1
    systemctl enable nut-server.service >/dev/null 2>&1
    systemctl enable nut-monitor.service >/dev/null 2>&1


    ########################################################
    # INICIAR NUT SERVER
    ########################################################

    systemctl restart nut-server.service

    sleep 2


    ########################################################
    # INICIAR DRIVER
    ########################################################

    if systemctl list-unit-files \
        | grep -q "^nut-driver@.service"
    then

        systemctl restart nut-driver@apc.service >/dev/null 2>&1

    else

        upsdrvctl start >/dev/null 2>&1

    fi


    sleep 4


    ########################################################
    # INICIAR MONITOR
    ########################################################

    systemctl restart nut-monitor.service >/dev/null 2>&1


    ########################################################
    # COMPROBAR COMUNICACIÓN
    ########################################################

    echo
    echo "Comprobando comunicación con la UPS..."
    echo

    if upsc apc >/tmp/ups_test 2>/dev/null
    then

        ESTADO=$(grep "^ups.status:" /tmp/ups_test \
            | cut -d: -f2- | xargs)

        BATERIA=$(grep "^battery.charge:" /tmp/ups_test \
            | cut -d: -f2- | xargs)

        AUTONOMIA=$(grep "^battery.runtime:" /tmp/ups_test \
            | cut -d: -f2- | xargs)


        ####################################################
        # RESULTADO
        ####################################################

        echo
        linea

        echo -e "${VERDE}UPS DETECTADA CORRECTAMENTE${RESET}"

        echo

        printf "%-22s %s\n" "Modelo:" "$MODELO"
        printf "%-22s %s\n" "Puerto:" "$PUERTO_FINAL"
        printf "%-22s %s\n" "Tipo:" "$TIPO_PUERTO"
        printf "%-22s %s\n" "Driver:" "nutdrv_qx"
        printf "%-22s %s\n" "Estado:" "$ESTADO"
        printf "%-22s %s %%\n" "Batería:" "$BATERIA"
        printf "%-22s %s segundos\n" "Autonomía:" "$AUTONOMIA"

        linea

        ####################################################
        # INFORMACIÓN IMPORTANTE
        ####################################################

        if [[ "$TIPO_PUERTO" == "USB permanente" ]]
        then

            echo
            echo -e "${VERDE}✓ Puerto USB permanente configurado.${RESET}"
            echo
            echo "NUT utilizará:"
            echo "$PUERTO_FINAL"
            echo
            echo "El puerto ttyUSB puede cambiar después de"
            echo "un reinicio, pero NUT seguirá utilizando"
            echo "el dispositivo correcto mediante /dev/serial/by-id/."

        else

            echo
            echo -e "${AMARILLO}⚠ Puerto sin identificador permanente.${RESET}"
            echo
            echo "Configurado:"
            echo "$PUERTO_FINAL"

        fi

        echo

        mensaje_ok "Configuración NUT aplicada correctamente."

    else

        echo
        mensaje_error "La UPS fue detectada, pero no responde mediante NUT."
        echo

        echo "Revise:"
        echo "  - /etc/nut/ups.conf"
        echo "  - permisos del puerto"
        echo "  - servicio nut-driver@apc.service"
        echo

    fi


    rm -f /tmp/ups_test

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
# CONFIGURACION MONITOR
############################################################

CONFIG_FILE="/root/ups-apc.conf"

BATTERY_LIMIT=20
RUNTIME_LIMIT=600
WAIT_POWER_FAIL=60
MONITOR_INTERVAL=10
MONITOR_APAGADO="OFF"

############################################################
# CARGAR CONFIGURACION
############################################################

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
############################################################
# EDITAR CONFIGURACION DEL MONITOR
############################################################

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
############################################################
# VER CONFIGURACION APAGADO
############################################################

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
############################################################
# CONFIGURAR APAGADO AUTOMATICO
############################################################

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
# APAGADO LOS 3 EN ORDEN DESCOMETAR SI ES PROXMOX 
############################################################

apagar_host() {
                  apagar_vm_proxmox
                  apagar_lxc_proxmox
                  apagar_host_proxmox

}

############################################################
# MONITOR AUTOMATICO UPS + PANEL EN TIEMPO REAL
############################################################

monitor_apagado_ups() {

    ########################################################
    # Si se ejecuta desde una terminal mostrar panel
    ########################################################

    if [[ -t 1 ]]
    then

        trap 'tput cnorm; clear; return' INT

        tput civis

        dibujar_panel

    fi


    while true
    do

        ESTADO=$(obtener_valor ups.status)
        BATERIA=$(obtener_valor battery.charge)
        AUTONOMIA=$(obtener_valor battery.runtime)
####################################################
# ESTADO DEL MONITOR
####################################################

cargar_configuracion
cargar_email
cargar_telegram

if [[ "$MONITOR_APAGADO" == "ON" ]]
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

####################################################
# ÚLTIMOS EVENTOS
####################################################

if [[ -f "$LOGFILE" ]]
then

    mapfile -t ULTIMOS < <(tail -n 3 "$LOGFILE")

    LOG1="${ULTIMOS[0]:-}"
    LOG2="${ULTIMOS[1]:-}"
    LOG3="${ULTIMOS[2]:-}"

else

    LOG1="No existen registros."
    LOG2=""
    LOG3=""

fi

        ####################################################
        # ACTUALIZAR PANEL
        ####################################################

		if [[ -t 1 ]]
		then
		actualizar_panel
		fi

        ####################################################
        # CORTE ELECTRICO
        ####################################################

        if [[ "$ESTADO" == *"OB"* ]]
        then

            ################################################
            # Enviar aviso una sola vez
            ################################################

            if [[ $UPS_EN_BATERIA -eq 0 ]]
            then

                UPS_EN_BATERIA=1

                registrar_log "Corte eléctrico detectado."

                enviar_correo \
                "UPS APC - Corte eléctrico" \
"Se detectó un corte eléctrico.

Servidor : $(hostname)

Fecha : $(date "+%d/%m/%Y %H:%M:%S %Z")

Estado UPS : EN BATERÍA

Carga batería : ${BATERIA} %

Autonomía : ${AUTONOMIA} segundos"

                enviar_telegram \
"⚠️ UPS APC

Corte eléctrico detectado.

Servidor: $(hostname)

Batería: ${BATERIA}%

Autonomía: ${AUTONOMIA}s"

            fi

            ################################################
            # ESPERA CONFIGURABLE
            ################################################

            for ((i=1;i<=WAIT_POWER_FAIL;i++))
            do

                sleep 1

                ESTADO=$(obtener_valor ups.status)

                ################################################
                # VOLVIÓ LA ENERGÍA
                ################################################

                if [[ "$ESTADO" == *"OL"* ]]
                then

                    UPS_EN_BATERIA=0

                    registrar_log "Energía restablecida."

                    enviar_correo \
                    "UPS APC - Energía restablecida" \
"La alimentación eléctrica ha sido restablecida.

Servidor : $(hostname)

Fecha : $(date "+%d/%m/%Y %H:%M:%S %Z")

El apagado automático fue cancelado."

                    enviar_telegram \
"✅ UPS APC

La energía volvió.

Servidor: $(hostname)

El apagado automático fue cancelado."

                    break

                fi

            done

            ################################################
            # SIGUE EN BATERÍA
            ################################################

            ESTADO=$(obtener_valor ups.status)

            if [[ "$ESTADO" == *"OB"* ]]
            then

                BATERIA=$(obtener_valor battery.charge)
                AUTONOMIA=$(obtener_valor battery.runtime)

                if (( BATERIA <= BATTERY_LIMIT )) || (( AUTONOMIA <= RUNTIME_LIMIT ))
                then

                    registrar_log "Comienza apagado automático."

                    enviar_correo \
                    "UPS APC - Inicio de apagado" \
"La UPS alcanzó el límite configurado.

Servidor : $(hostname)

Batería : ${BATERIA} %

Autonomía : ${AUTONOMIA} segundos

Comienza el apagado automático."

                    enviar_telegram \
"🛑 UPS APC

Comienza el apagado automático.

Servidor: $(hostname)"

			apagar_host

                fi

            fi

        ####################################################
        # UPS ONLINE
        ####################################################

        elif [[ "$ESTADO" == *"OL"* ]]
        then

            UPS_EN_BATERIA=0

        fi

        sleep 2

    done

}

############################################################
# SERVICIO MONITOR AUTOMATICO UPS
############################################################

servicio_apagado_ups() {

    ########################################################
    # VARIABLES
    ########################################################

    UPS_EN_BATERIA=0

    ########################################################
    # OCULTAR CURSOR
    ########################################################

    if [[ -t 1 ]]
    then
        trap 'tput cnorm; clear; exit 0' INT TERM
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
    # BUCLE PRINCIPAL DEL SERVICIO
    ########################################################

    while true
    do

        ####################################################
        # VERIFICAR NUT
        ####################################################

        if ! systemctl is-active --quiet nut-server.service
        then

            registrar_log "NUT no está disponible. Esperando..."

            if [[ -t 1 ]]
            then
                clear
                echo
                echo -e "${AMARILLO}==============================================${RESET}"
                echo -e "${AMARILLO}       APC UPS - ESPERANDO NUT               ${RESET}"
                echo -e "${AMARILLO}==============================================${RESET}"
                echo
                echo "El servicio NUT no está disponible."
                echo
                echo "Reintentando automáticamente..."
                echo
                echo "Fecha: $(date '+%d/%m/%Y %H:%M:%S')"
            fi

            sleep 10
            continue

        fi


        ####################################################
        # VERIFICAR COMUNICACIÓN CON LA UPS
        ####################################################

        if ! upsc apc >/dev/null 2>&1
        then

            registrar_log "UPS no disponible. Esperando conexión..."

            if [[ -t 1 ]]
            then
                clear
                echo
                echo -e "${AMARILLO}==============================================${RESET}"
                echo -e "${AMARILLO}       APC UPS - ESPERANDO UPS               ${RESET}"
                echo -e "${AMARILLO}==============================================${RESET}"
                echo
                echo -e "${ROJO}No se puede comunicar con la UPS.${RESET}"
                echo
                echo "Posibles causas:"
                echo "  - Cable USB/RS232 desconectado"
                echo "  - Driver NUT detenido"
                echo "  - UPS apagada"
                echo "  - Puerto /dev/ttyUSB0 no disponible"
                echo
                echo "Reintentando automáticamente..."
                echo
                echo "Fecha: $(date '+%d/%m/%Y %H:%M:%S')"
            fi

            sleep 10
            continue

        fi


        ####################################################
        # UPS DISPONIBLE
        ####################################################

        if [[ -t 1 ]]
        then

            dibujar_panel

        fi


        ####################################################
        # LEER ESTADO UPS
        ####################################################

        ESTADO=$(obtener_valor ups.status)
        BATERIA=$(obtener_valor battery.charge)
        AUTONOMIA=$(obtener_valor battery.runtime)


        ####################################################
        # VALIDAR ESTADO
        ####################################################

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
        # CORTE ELECTRICO
        ####################################################

        if [[ "$ESTADO" == *"OB"* ]]
        then

            ################################################
            # ENTRADA A BATERIA
            ################################################

            if [[ $UPS_EN_BATERIA -eq 0 ]]
            then

                UPS_EN_BATERIA=1

                registrar_log "Corte eléctrico detectado."


                ################################################
                # CORREO
                ################################################

                enviar_correo \
                "UPS APC - Corte eléctrico" \
"Se detectó un corte eléctrico.

Servidor : $(hostname)

Fecha : $(date "+%d/%m/%Y %H:%M:%S %Z")

Estado UPS : EN BATERÍA

Carga batería : ${BATERIA} %

Autonomía : ${AUTONOMIA} segundos"


                ################################################
                # TELEGRAM
                ################################################

                enviar_telegram \
"⚠️ UPS APC

Corte eléctrico detectado.

Servidor: $(hostname)

Batería: ${BATERIA}%

Autonomía: ${AUTONOMIA}s"

            fi


            ################################################
            # ESPERA CONFIGURABLE
            ################################################

            if [[ -n "$WAIT_POWER_FAIL" ]] &&
               (( WAIT_POWER_FAIL > 0 ))
            then

                registrar_log \
                "Esperando ${WAIT_POWER_FAIL} segundos para confirmar corte."

                for ((i=1;i<=WAIT_POWER_FAIL;i++))
                do

                    sleep 1

                    ################################################
                    # VERIFICAR UPS DURANTE ESPERA
                    ################################################

                    if ! upsc apc >/dev/null 2>&1
                    then

                        registrar_log \
                        "Comunicación UPS perdida durante espera."

                        continue

                    fi


                    ESTADO=$(obtener_valor ups.status)


                    ################################################
                    # VOLVIO LA ENERGIA
                    ################################################

                    if [[ "$ESTADO" == *"OL"* ]]
                    then

                        UPS_EN_BATERIA=0

                        registrar_log \
                        "Energía restablecida."


                        ################################################
                        # CORREO
                        ################################################

                        enviar_correo \
                        "UPS APC - Energía restablecida" \
"La alimentación eléctrica ha sido restablecida.

Servidor : $(hostname)

Fecha : $(date "+%d/%m/%Y %H:%M:%S %Z")

El apagado automático fue cancelado."


                        ################################################
                        # TELEGRAM
                        ################################################

                        enviar_telegram \
"✅ UPS APC

La energía volvió.

Servidor: $(hostname)

El apagado automático fue cancelado."


                        if [[ -t 1 ]]
                        then

                            echo
                            echo -e "${VERDE}La energía volvió.${RESET}"
                            echo -e "${VERDE}Apagado automático cancelado.${RESET}"
                            echo

                        fi

                        break

                    fi

                done

            fi


            ################################################
            # VERIFICAR SI SIGUE EN BATERIA
            ################################################

            ESTADO=$(obtener_valor ups.status)


            if [[ "$ESTADO" == *"OB"* ]]
            then

                BATERIA=$(obtener_valor battery.charge)
                AUTONOMIA=$(obtener_valor battery.runtime)


                ################################################
                # LIMITES DE APAGADO
                ################################################

                if (( BATERIA <= BATTERY_LIMIT )) ||
                   (( AUTONOMIA <= RUNTIME_LIMIT ))
                then

                    registrar_log \
                    "Comienza apagado automático."


                    ################################################
                    # CORREO
                    ################################################

                    enviar_correo \
                    "UPS APC - Inicio de apagado" \
"La UPS alcanzó el límite configurado.

Servidor : $(hostname)

Batería : ${BATERIA} %

Autonomía : ${AUTONOMIA} segundos

Comienza el apagado automático."


                    ################################################
                    # TELEGRAM
                    ################################################

                    enviar_telegram \
"🛑 UPS APC

Comienza el apagado automático.

Servidor: $(hostname)

Batería: ${BATERIA}%

Autonomía: ${AUTONOMIA}s"


			apagar_host

                fi

            fi


        ########################################################
        # UPS ONLINE
        ########################################################

        elif [[ "$ESTADO" == *"OL"* ]]
        then

            UPS_EN_BATERIA=0

        fi


        ########################################################
        # ACTUALIZAR CADA 2 SEGUNDOS
        ########################################################

        sleep 2

    done

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

############################################################
# CARGAR CONFIGURACION TELEGRAM
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
# CONFIGURAR TELEGRAM
############################################################

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
############################################################
# AGREGAR CHAT ID
############################################################

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
############################################################
# VER CHAT ID
############################################################

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
############################################################
# ELIMINAR CHAT ID
############################################################

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

    # Validar que sea un número
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
############################################################
# ACTIVAR ALERTAS TELEGRAM
############################################################

activar_alertas_telegram() {

    cargar_telegram || return

    sed -i 's/ALERTAS_TELEGRAM="OFF"/ALERTAS_TELEGRAM="ON"/' "$TELEGRAM_CONFIG"

    mensaje_ok "Alertas Telegram activadas."

    pausa

}
############################################################
# DESACTIVAR ALERTAS TELEGRAM
############################################################

desactivar_alertas_telegram() {

    cargar_telegram || return

    sed -i 's/ALERTAS_TELEGRAM="ON"/ALERTAS_TELEGRAM="OFF"/' "$TELEGRAM_CONFIG"

    mensaje_ok "Alertas Telegram desactivadas."

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
# VER CONFIGURACION TELEGRAM
############################################################

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
############################################################
# ENVIAR MENSAJE TELEGRAM
############################################################

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
############################################################
# PRUEBA TELEGRAM
############################################################

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

    ########################################################
    # TELEGRAM
    ########################################################

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

    ########################################################
    # CORREO
    ########################################################

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
# CONFIGURAR LOG DE MSMTP
############################################################

configurar_log_msmtp() {

    touch /var/log/msmtp.log

    chown root:root /var/log/msmtp.log

    chmod 600 /var/log/msmtp.log

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
After=network-online.target nut-server.service nut-monitor.service
Wants=network-online.target nut-server.service nut-monitor.service

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
        echo "$SCRIPT_MONITOR --service"
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
        echo -e "${VERDE}6)${RESET} Ver logs UPS del administrador"
		echo
		echo -e "${CYAN}# Instalacion y Ajustes UPS"
        echo
		echo -e "${VERDE}7)${RESET} Verificar dependencias y Estado de NUT - ${CYAN}(1°)${RESET}"
        echo -e "${VERDE}8)${RESET} Instalar NUT - ${CYAN}(2°)${RESET}"
        echo -e "${VERDE}9)${RESET} Configurar APC SRV3KI USB/RS232 - ${CYAN}(3°)${RESET}"
        echo -e "${VERDE}10)${RESET} Probar comunicación UPS - ${CYAN}(4°)${RESET}"
        echo
		echo -e "${CYAN}# Apagado Automatico de PC-SERVIDOR${VERDE} * Activa Mensajes Automaticos"
        echo
		echo -e "${VERDE}11)${RESET} Configurar parametros de UPS para el apagado"
		echo -e "${VERDE}12)${RESET} Ver configuración apagado"
		echo -e "${VERDE}13)${RESET} Editar configuración apagado"
		echo
        echo -e "${VERDE}14)${AMARILLO} Activar monitor apagado automático ${VERDE}* Activa Mensajes Automaticos"
		echo
		echo -e "${CYAN}# Alertas Por (Correo - Telegram) Bateria Baja / Corte de Luz"
		echo
		echo -e "${VERDE}15)${AMARILLO} Menu Configurar Telegram ${VERDE}Mensajes / Alertas"
		echo
		echo -e "${VERDE}16)${AMARILLO} Menu Configurar Correo ${VERDE}SMTP / Alertas"
		echo
		echo -e "${VERDE}17)${AMARILLO} Menu Servicio systemd UPS APC ${VERDE}* Arranque al Inicio Monitor + Mensajes"
		echo
		echo -e "${VERDE}18)${VERDE} Estado general del sistema"
		echo
		echo -e "${VERDE}19)${AMARILLO} Menu Apagado Server Proxmox - ${VERDE} Apagar VM / PC"
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

                configurar_shutdown

            ;;


            12)

                mostrar_config_shutdown

            ;;
			
			13)

                editar_configuracion_monitor

            ;;
			
			14)

                monitor_apagado_ups

            ;;
			
            15)

                menu_telegram

            ;;

			
            16)

                menu_correo

            ;;

			
			17)

                menu_servicio_ups

            ;;
			
			18)

                panel_sistema

            ;;
			
			19)
			
				menu_proxmox
				
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

if [[ "$1" == "--service" ]]
then

    registrar_log "Inicio servicio monitor UPS"

    servicio_apagado_ups

else

    registrar_log "Inicio APC UPS Manager"

    menu

fi

