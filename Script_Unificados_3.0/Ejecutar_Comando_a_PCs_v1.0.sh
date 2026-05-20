#!/bin/bash

# =========================================================
# CLUSTER PRO SSH
# =========================================================

# ========= CONFIG =========

MAX_JOBS=10
LOG_DIR="./logs_cluster"

mkdir -p "$LOG_DIR"

# ========= COLORES =========

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

# ========= LIMPIAR HISTORIAL =========

trap 'history -c; : > ~/.bash_history' EXIT
unset HISTFILE

# =========================================================
# PARSEAR RANGO
# =========================================================

parse_rango() {

    local RANGO=$1

    if [[ "$RANGO" == *"-"* ]]; then

        IP_BASE=$(echo "$RANGO" | cut -d'.' -f1-3)
        INICIO=$(echo "$RANGO" | cut -d'.' -f4 | cut -d'-' -f1)
        FIN=$(echo "$RANGO" | cut -d'.' -f4 | cut -d'-' -f2)

        for i in $(seq "$INICIO" "$FIN"); do
            echo "$IP_BASE.$i"
        done

    else

        echo "$RANGO"

    fi
}

# =========================================================
# VERIFICAR HOST
# =========================================================

check_host() {

    ping -c 1 -W 1 "$1" > /dev/null 2>&1

}

# =========================================================
# EJECUTAR COMANDO
# =========================================================

run_command_cluster() {

    read -p "Usuario SSH: " USER
    read -s -p "Password SSH: " PASS
    echo

    read -p "Comando: " CMD
    read -p "Ejecutar como root? (s/n): " ROOT

    echo
    echo -e "${GREEN}✔ Ejemplo rango: 192.168.0.100-120${RESET}"
    read -p "IP o rango: " RANGO

    HOSTS=($(parse_rango "$RANGO"))

    TOTAL=${#HOSTS[@]}
    COMPLETADOS=0

    echo
    echo -e "${YELLOW}🚀 Ejecutando comando en $TOTAL hosts...${RESET}"
    echo

    for HOST in "${HOSTS[@]}"; do

        (
            LOG="$LOG_DIR/$HOST-command.log"

            if check_host "$HOST"; then

                echo "[+] $HOST conectado" > "$LOG"

                if [[ "$ROOT" == "s" ]]; then
                    REMOTE_CMD="echo '$PASS' | sudo -S $CMD"
                else
                    REMOTE_CMD="$CMD"
                fi

                sshpass -p "$PASS" ssh \
                    -o StrictHostKeyChecking=no \
                    -o ConnectTimeout=5 \
                    -o LogLevel=ERROR \
                    "$USER@$HOST" "$REMOTE_CMD" >> "$LOG" 2>&1

                echo "[OK] $HOST" >> "$LOG"

            else

                echo "[X] $HOST no responde" > "$LOG"

            fi

            ((COMPLETADOS++))

            PCT=$((COMPLETADOS * 100 / TOTAL))

            echo -ne "\r${CYAN}Progreso:${RESET} $COMPLETADOS/$TOTAL (${GREEN}$PCT%${RESET})"

        ) &

        while [ "$(jobs -r | wc -l)" -ge "$MAX_JOBS" ]; do
            sleep 0.2
        done

    done

    wait

    echo
    echo
    echo -e "${GREEN}✔ Ejecución terminada${RESET}"
    echo -e "${YELLOW}📂 Logs:${RESET} $LOG_DIR"
}

# =========================================================
# COPIAR ARCHIVO
# =========================================================

copy_file_cluster() {

    read -p "Usuario SSH: " USER
    read -s -p "Password SSH: " PASS
    echo

    read -p "Archivo local: " FILE
    read -p "Ruta destino remota: " DEST

    echo
    echo -e "${GREEN}✔ Ejemplo rango: 192.168.0.100-120${RESET}"
    read -p "IP o rango: " RANGO

    echo
    echo "Permisos para archivo remoto:"
    echo

    echo "1) chmod +x"
    echo "2) chmod u+rw"

    while true; do

        read -p "Opción (1/2): " PERM_OP

        if [[ "$PERM_OP" == "1" || "$PERM_OP" == "2" ]]; then
            break
        fi

        echo -e "${RED}Opción inválida${RESET}"

    done

    HOSTS=($(parse_rango "$RANGO"))

    TOTAL=${#HOSTS[@]}
    COMPLETADOS=0

    echo
    echo -e "${YELLOW}🚀 Copiando archivo a $TOTAL hosts...${RESET}"
    echo

    for HOST in "${HOSTS[@]}"; do

        (
            LOG="$LOG_DIR/$HOST-copy.log"

            if check_host "$HOST"; then

                sshpass -p "$PASS" scp \
                    -o StrictHostKeyChecking=no \
                    "$FILE" "$USER@$HOST:$DEST" >> "$LOG" 2>&1

                if [[ "$PERM_OP" == "1" ]]; then
                    CHMOD_CMD="chmod +x $DEST/$(basename "$FILE")"
                else
                    CHMOD_CMD="chmod u+rw $DEST/$(basename "$FILE")"
                fi

                sshpass -p "$PASS" ssh \
                    -o StrictHostKeyChecking=no \
                    "$USER@$HOST" "$CHMOD_CMD" >> "$LOG" 2>&1

                echo "[OK] Archivo copiado en $HOST" >> "$LOG"

            else

                echo "[X] $HOST no responde" > "$LOG"

            fi

            ((COMPLETADOS++))

            PCT=$((COMPLETADOS * 100 / TOTAL))

            echo -ne "\r${CYAN}Progreso:${RESET} $COMPLETADOS/$TOTAL (${GREEN}$PCT%${RESET})"

        ) &

        while [ "$(jobs -r | wc -l)" -ge "$MAX_JOBS" ]; do
            sleep 0.2
        done

    done

    wait

    echo
    echo
    echo -e "${GREEN}✔ Copia terminada${RESET}"
}

# =========================================================
# EJECUTAR SCRIPT REMOTO
# =========================================================

run_script_cluster() {

    read -p "Usuario SSH: " USER
    read -s -p "Password SSH: " PASS
    echo

    read -p "Script local (.sh): " SCRIPT

    echo
    echo -e "${GREEN}✔ Ejemplo rango: 192.168.0.100-120${RESET}"
    read -p "IP o rango: " RANGO

    echo
    echo "Permisos para script remoto:"
    echo

    echo "1) chmod +x"
    echo "2) chmod u+rw"

    while true; do

        read -p "Opción (1/2): " PERM_OP

        if [[ "$PERM_OP" == "1" || "$PERM_OP" == "2" ]]; then
            break
        fi

        echo -e "${RED}Opción inválida${RESET}"

    done

    HOSTS=($(parse_rango "$RANGO"))

    TOTAL=${#HOSTS[@]}
    COMPLETADOS=0

    echo
    echo -e "${YELLOW}🚀 Ejecutando scripts en $TOTAL hosts...${RESET}"
    echo

    for HOST in "${HOSTS[@]}"; do

        (
            LOG="$LOG_DIR/$HOST-script.log"

            if check_host "$HOST"; then

                sshpass -p "$PASS" scp \
                    -o StrictHostKeyChecking=no \
                    "$SCRIPT" "$USER@$HOST:/tmp/script.sh" > /dev/null 2>&1

                if [[ "$PERM_OP" == "1" ]]; then
                    CHMOD_CMD="chmod +x /tmp/script.sh"
                else
                    CHMOD_CMD="chmod u+rw /tmp/script.sh"
                fi

                sshpass -p "$PASS" ssh \
                    -o StrictHostKeyChecking=no \
                    "$USER@$HOST" \
                    "$CHMOD_CMD && bash /tmp/script.sh" >> "$LOG" 2>&1

                echo "[OK] Script ejecutado en $HOST" >> "$LOG"

            else

                echo "[X] $HOST no responde" > "$LOG"

            fi

            ((COMPLETADOS++))

            PCT=$((COMPLETADOS * 100 / TOTAL))

            echo -ne "\r${CYAN}Progreso:${RESET} $COMPLETADOS/$TOTAL (${GREEN}$PCT%${RESET})"

        ) &

        while [ "$(jobs -r | wc -l)" -ge "$MAX_JOBS" ]; do
            sleep 0.2
        done

    done

    wait

    echo
    echo
    echo -e "${GREEN}✔ Scripts ejecutados${RESET}"
}

# =========================================================
# MENU
# =========================================================

while true; do

    clear

    echo -e "${CYAN}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}${YELLOW}         CLUSTER PRO SSH (PROGRESO)        ${RESET}${CYAN}║${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${RESET}"

    echo
    echo -e " ${GREEN}1)${RESET} Ejecutar comando en múltiples hosts"
    echo -e " ${GREEN}2)${RESET} Copiar archivo a múltiples hosts"
    echo -e " ${GREEN}3)${RESET} Ejecutar script .sh en múltiples hosts"
    echo -e " ${RED}4)${RESET} Salir"

    echo
    echo -e "${BLUE}════════════════════════════════════════════════${RESET}"
    echo

    read -p "Seleccione una opción: " OPCION

    case $OPCION in

        1)
            clear
            echo -e "${YELLOW}=== EJECUTAR COMANDO REMOTO ===${RESET}"
            echo
            run_command_cluster
            echo
            read -p "Presione ENTER para continuar..."
            ;;

        2)
            clear
            echo -e "${YELLOW}=== COPIAR ARCHIVO ===${RESET}"
            echo
            copy_file_cluster
            echo
            read -p "Presione ENTER para continuar..."
            ;;

        3)
            clear
            echo -e "${YELLOW}=== EJECUTAR SCRIPT REMOTO ===${RESET}"
            echo
            run_script_cluster
            echo
            read -p "Presione ENTER para continuar..."
            ;;

        4)
            clear
            echo -e "${RED}Saliendo...${RESET}"
            exit 0
            ;;

        *)
            echo
            echo -e "${RED}❌ Opción inválida${RESET}"
            sleep 1
            ;;

    esac

done