#!/bin/bash

# =========================================================
# CLUSTER PRO SSH v2.3
# Administración de múltiples PCs Linux por SSH
# =========================================================

MAX_JOBS=10
LOG_DIR="${LOG_DIR:-./logs_cluster}"
SSH_TIMEOUT=5

mkdir -p "$LOG_DIR"

# ========= COLORES =========
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

# ========= UTILIDADES =========
pause() { echo; read -rp "Presione ENTER para continuar..."; }
ok()    { echo -e "${GREEN}[OK]${RESET} $*"; }
info()  { echo -e "${CYAN}[INFO]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[AVISO]${RESET} $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*"; }

cleanup_secret() {
    PASS=""
    unset PASS
}
trap cleanup_secret EXIT INT TERM

have_cmd() { command -v "$1" >/dev/null 2>&1; }

check_dependencies() {
    local missing=()
    local cmd
    for cmd in ssh scp sshpass ping; do
        have_cmd "$cmd" || missing+=("$cmd")
    done

    if ((${#missing[@]} == 0)); then
        ok "Todas las dependencias están instaladas."
        return 0
    fi

    error "Faltan dependencias: ${missing[*]}"
    if have_cmd apt-get; then
        echo
        read -rp "¿Instalarlas ahora con apt? [s/N]: " r
        if [[ "$r" =~ ^[Ss]$ ]]; then
            if [[ $EUID -eq 0 ]]; then
                apt-get update && apt-get install -y openssh-client sshpass iputils-ping
            elif have_cmd sudo; then
                sudo apt-get update && sudo apt-get install -y openssh-client sshpass iputils-ping
            else
                error "Necesita ejecutar como root para instalar paquetes."
                return 1
            fi
        fi
    fi
}

validate_ipv4() {
    local ip=$1 a b c d
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r a b c d <<< "$ip"
    ((a<=255 && b<=255 && c<=255 && d<=255))
}

# Acepta:
#   192.168.0.100
#   192.168.0.100-120
#   192.168.0.100-120,192.168.0.130,192.168.0.150-160
parse_targets() {
    local input=$1 item base start end i
    local -A uniq=()

    IFS=',' read -ra ITEMS <<< "$input"
    for item in "${ITEMS[@]}"; do
        item="${item//[[:space:]]/}"
        [[ -z $item ]] && continue

        if [[ $item =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.([0-9]{1,3})-([0-9]{1,3})$ ]]; then
            base=${BASH_REMATCH[1]}
            start=${BASH_REMATCH[2]}
            end=${BASH_REMATCH[3]}
            validate_ipv4 "$base.$start" || continue
            validate_ipv4 "$base.$end" || continue
            ((start <= end)) || { local tmp=$start; start=$end; end=$tmp; }
            for ((i=start; i<=end; i++)); do uniq["$base.$i"]=1; done
        elif validate_ipv4 "$item"; then
            uniq["$item"]=1
        else
            warn "Objetivo inválido ignorado: $item" >&2
        fi
    done

    printf '%s\n' "${!uniq[@]}" | sort -V
}

ask_targets() {
    echo
    echo -e "${GREEN}Ejemplos:${RESET}"
    echo "  192.168.0.100"
    echo "  192.168.0.100-120"
    echo "  192.168.0.100-120,192.168.0.150"
    read -rp "IP, rango o lista: " RANGO
    mapfile -t HOSTS < <(parse_targets "$RANGO")
    TOTAL=${#HOSTS[@]}
    if ((TOTAL == 0)); then
        error "No se encontró ningún host válido."
        return 1
    fi
    info "Hosts seleccionados: $TOTAL"
}

ask_credentials() {
    read -rp "Usuario SSH: " USER
    [[ -n $USER ]] || { error "El usuario no puede quedar vacío."; return 1; }
    read -srp "Password SSH: " PASS
    echo
}

check_host() {
    ping -c 1 -W 1 "$1" >/dev/null 2>&1
}

ssh_base() {
    sshpass -p "$PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout="$SSH_TIMEOUT" \
        -o ServerAliveInterval=5 \
        -o ServerAliveCountMax=1 \
        -o LogLevel=ERROR \
        "$USER@$1" "${@:2}"
}


classify_ssh_error() {
    local log="$1" rc="$2"

    if grep -qiE 'Permission denied|Authentication failed' "$log" 2>/dev/null; then
        echo "Autenticación SSH rechazada (usuario/contraseña)"
    elif grep -qi 'Connection refused' "$log" 2>/dev/null; then
        echo "Puerto SSH rechazado (sshd detenido o puerto cerrado)"
    elif grep -qiE 'Connection timed out|Operation timed out' "$log" 2>/dev/null; then
        echo "Timeout SSH (firewall, puerto 22 filtrado o equipo inaccesible)"
    elif grep -qiE 'No route to host|Network is unreachable' "$log" 2>/dev/null; then
        echo "Sin ruta de red hacia el equipo"
    elif grep -qiE 'Could not resolve hostname|Name or service not known' "$log" 2>/dev/null; then
        echo "No se pudo resolver el host"
    elif grep -qiE 'Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED' "$log" 2>/dev/null; then
        echo "Problema con la clave SSH del host"
    elif (( rc == 5 )); then
        echo "Contraseña SSH incorrecta"
    else
        echo "Error SSH (código $rc) - revise el log"
    fi
}

probe_host() {
    local host="$1"
    if check_host "$host"; then
        echo "PING_OK"
    else
        echo "PING_FAIL"
    fi
}
scp_file() {
    sshpass -p "$PASS" scp \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout="$SSH_TIMEOUT" \
        -o LogLevel=ERROR \
        "$1" "$USER@$2:$3"
}

# ========= MOTOR DE PROGRESO =========
# La función recibida debe crear: $STATUS_DIR/<host>.done
run_parallel() {
    local worker=$1
    shift
    local status_dir host running completed=0 ok_count=0 fail_count=0
    local -A shown=()

    status_dir=$(mktemp -d)
    STATUS_DIR=$status_dir
    export STATUS_DIR

    echo
    echo -e "${CYAN}────────────────────────────────────────────────────${RESET}"
    echo -e "${WHITE}Avance en tiempo real${RESET}  |  Total: ${YELLOW}$TOTAL${RESET}  |  Paralelos: ${YELLOW}$MAX_JOBS${RESET}"
    echo -e "${CYAN}────────────────────────────────────────────────────${RESET}"

    for host in "${HOSTS[@]}"; do
        while :; do
            running=$(jobs -rp | wc -l)
            ((running < MAX_JOBS)) && break
            collect_progress "$status_dir" shown completed ok_count fail_count
            sleep 0.15
        done
        "$worker" "$host" "$@" &
    done

    while ((completed < TOTAL)); do
        collect_progress "$status_dir" shown completed ok_count fail_count
        sleep 0.15
    done
    wait

    # Lectura final, por seguridad
    collect_progress "$status_dir" shown completed ok_count fail_count

    echo -e "${CYAN}────────────────────────────────────────────────────${RESET}"
    echo -e "Finalizados: ${WHITE}$completed/$TOTAL${RESET} | ${GREEN}OK: $ok_count${RESET} | ${RED}Error/Offline: $fail_count${RESET}"
    echo -e "Logs: ${YELLOW}$LOG_DIR${RESET}"
    echo -e "${CYAN}────────────────────────────────────────────────────${RESET}"

    rm -rf "$status_dir"
}

collect_progress() {
    local dir=$1 shown_name=$2 completed_name=$3 ok_name=$4 fail_name=$5
    local -n _shown=$shown_name
    local -n _completed=$completed_name
    local -n _ok=$ok_name
    local -n _fail=$fail_name
    local f host status msg pct

    shopt -s nullglob
    for f in "$dir"/*.done; do
        host=$(basename "$f" .done)
        [[ ${_shown[$host]+x} ]] && continue
        IFS='|' read -r status msg < "$f"
        _shown[$host]=1
        ((_completed++))
        pct=$((_completed * 100 / TOTAL))
        if [[ $status == OK ]]; then
            ((_ok++))
            printf "[%3d%%] %-15s ${GREEN}✔${RESET} %s\n" "$pct" "$host" "$msg"
        else
            ((_fail++))
            printf "[%3d%%] %-15s ${RED}✘${RESET} %s\n" "$pct" "$host" "$msg"
        fi
    done
    shopt -u nullglob
}

write_status() {
    local host=$1 status=$2 msg=$3
    printf '%s|%s\n' "$status" "$msg" > "$STATUS_DIR/$host.done.tmp"
    mv "$STATUS_DIR/$host.done.tmp" "$STATUS_DIR/$host.done"
}

# =========================================================
# 1) EJECUTAR COMANDO
# =========================================================
worker_command() {
    local host=$1 cmd=$2 root=$3
    local log="$LOG_DIR/$host-command.log" rc qcmd
    : > "$log"

    local ping_state
    ping_state=$(probe_host "$host")
    echo "=== $host | $(date '+%F %T') ===" >> "$log"
    [[ $ping_state == PING_OK ]] && echo "[PING] Responde" >> "$log" || echo "[PING] Sin respuesta; se intentará SSH igualmente" >> "$log"
    if [[ $root == s ]]; then
        printf -v qcmd '%q' "$cmd"
        printf '%s\n' "$PASS" | sshpass -p "$PASS" ssh \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout="$SSH_TIMEOUT" -o LogLevel=ERROR \
            "$USER@$host" "sudo -S -p '' bash -lc $qcmd" >> "$log" 2>&1
        rc=$?
    else
        ssh_base "$host" "$cmd" >> "$log" 2>&1
        rc=$?
    fi

    if ((rc == 0)); then
        if [[ $ping_state == PING_OK ]]; then
            write_status "$host" OK "Comando ejecutado"
        else
            write_status "$host" OK "Comando ejecutado por SSH (ping bloqueado/sin respuesta)"
        fi
    else
        reason=$(classify_ssh_error "$log" "$rc")
        if [[ $ping_state == PING_FAIL ]]; then
            write_status "$host" FAIL "Sin ping + $reason"
        else
            write_status "$host" FAIL "$reason"
        fi
    fi
}

run_command_cluster() {
    ask_credentials || return
    read -rp "Comando: " CMD
    [[ -n $CMD ]] || { error "El comando no puede estar vacío."; return; }
    read -rp "¿Ejecutar con sudo? [s/N]: " ROOT
    ROOT=${ROOT,,}
    [[ $ROOT == s ]] || ROOT=n
    ask_targets || return
    run_parallel worker_command "$CMD" "$ROOT"
    cleanup_secret
}

# =========================================================
# 2) COPIAR ARCHIVO
# =========================================================
worker_copy() {
    local host=$1 file=$2 dest=$3 perm=$4
    local log="$LOG_DIR/$host-copy.log" rc remote_file base qdest qremote chmod_cmd
    : > "$log"

    local ping_state reason
    ping_state=$(probe_host "$host")
    [[ $ping_state == PING_OK ]] && echo "[PING] Responde" >> "$log" || echo "[PING] Sin respuesta; se intentará SCP/SSH igualmente" >> "$log"

    echo "[SCP] Origen : $file" >> "$log"
    echo "[SCP] Destino: $dest" >> "$log"

    scp_file "$file" "$host" "$dest" >> "$log" 2>&1
    rc=$?
    if ((rc != 0)); then
        reason=$(classify_ssh_error "$log" "$rc")
        write_status "$host" FAIL "Falló SCP: $reason"
        return
    fi

    # Resolver la ruta REAL del archivo remoto.
    # Si DEST es un directorio: DEST/nombre_archivo.
    # Si DEST es una ruta de archivo: se usa DEST directamente.
    base=$(basename "$file")
    printf -v qdest '%q' "$dest"
    remote_file=$(ssh_base "$host" "if [ -d $qdest ]; then printf '%s/%s' \"${dest%/}\" '$base'; else printf '%s' '$dest'; fi" 2>> "$log")
    rc=$?
    if ((rc != 0)) || [[ -z $remote_file ]]; then
        echo "[WARN] No fue posible resolver destino remoto; usando cálculo local." >> "$log"
        if [[ $dest == */ ]]; then
            remote_file="${dest%/}/$base"
        else
            remote_file="$dest"
        fi
    fi

    echo "[OK] Archivo copiado en: $remote_file" >> "$log"

    if [[ $perm == none ]]; then
        write_status "$host" OK "Archivo copiado (permisos sin cambios)"
        return
    fi

    case $perm in
        x)  chmod_cmd="chmod +x" ;;
        rw) chmod_cmd="chmod u+rw" ;;
        *)  chmod_cmd="" ;;
    esac

    printf -v qremote '%q' "$remote_file"

    # 1) Intento normal con el usuario SSH.
    echo "[CHMOD] Intento normal: $chmod_cmd $remote_file" >> "$log"
    ssh_base "$host" "$chmod_cmd $qremote" >> "$log" 2>&1
    rc=$?

    if ((rc == 0)); then
        write_status "$host" OK "Archivo copiado y permisos aplicados"
        return
    fi

    # 2) Si falla por permisos, intentar automáticamente mediante sudo.
    echo "[CHMOD] Falló intento normal (rc=$rc). Intentando con sudo..." >> "$log"
    printf '%s\n' "$PASS" | sshpass -p "$PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout="$SSH_TIMEOUT" \
        -o LogLevel=ERROR \
        "$USER@$host" "sudo -S -p '' $chmod_cmd $qremote" >> "$log" 2>&1
    rc=$?

    if ((rc == 0)); then
        write_status "$host" OK "Archivo copiado; permisos aplicados con sudo"
    else
        echo "[ERROR] No se pudieron aplicar permisos ni normal ni con sudo." >> "$log"
        ssh_base "$host" "ls -l $qremote 2>/dev/null || true" >> "$log" 2>&1
        write_status "$host" FAIL "Copiado, pero chmod falló incluso con sudo"
    fi
}

copy_file_cluster() {
    ask_credentials || return
    read -erp "Archivo local: " FILE
    [[ -f $FILE ]] || { error "No existe el archivo: $FILE"; return; }
    read -rp "Ruta destino remota (ej. /tmp): " DEST
    [[ -n $DEST ]] || DEST=/tmp

    echo
    echo -e "${CYAN}Tipo de archivo que desea copiar:${RESET}"
    echo -e " ${GREEN}1)${RESET} Ejecutable / script  (chmod +x)"
    echo -e " ${GREEN}2)${RESET} Archivo de usuario    (lectura/escritura para el usuario)"
    echo -e " ${GREEN}3)${RESET} Mantener permisos actuales"
    echo
    while true; do
        read -rp "Seleccione tipo [2]: " p
        p=${p:-2}
        case $p in
            1) PERM=x;  TIPO_ARCHIVO="Ejecutable"; break ;;
            2) PERM=rw; TIPO_ARCHIVO="Usuario"; break ;;
            3) PERM=none; TIPO_ARCHIVO="Sin cambios"; break ;;
            *) error "Opción inválida. Seleccione 1, 2 o 3." ;;
        esac
    done
    info "Tipo seleccionado: $TIPO_ARCHIVO"

    ask_targets || return
    run_parallel worker_copy "$FILE" "$DEST" "$PERM"
    cleanup_secret
}

# =========================================================
# 3) EJECUTAR SCRIPT .SH
# =========================================================
worker_script() {
    local host=$1 script=$2 sudo_mode=$3
    local log="$LOG_DIR/$host-script.log" remote="/tmp/cluster_pro_${$}.sh" rc
    : > "$log"

    local ping_state reason
    ping_state=$(probe_host "$host")
    [[ $ping_state == PING_OK ]] && echo "[PING] Responde" >> "$log" || echo "[PING] Sin respuesta; se intentará SSH igualmente" >> "$log"

    scp_file "$script" "$host" "$remote" >> "$log" 2>&1 || {
        write_status "$host" FAIL "Falló la copia del script"; return;
    }

    if [[ $sudo_mode == s ]]; then
        printf '%s\n' "$PASS" | sshpass -p "$PASS" ssh \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout="$SSH_TIMEOUT" -o LogLevel=ERROR \
            "$USER@$host" "chmod +x '$remote' && sudo -S -p '' bash '$remote'; rc=\$?; rm -f '$remote'; exit \$rc" >> "$log" 2>&1
        rc=$?
    else
        ssh_base "$host" "chmod +x '$remote' && bash '$remote'; rc=\$?; rm -f '$remote'; exit \$rc" >> "$log" 2>&1
        rc=$?
    fi

    if ((rc == 0)); then
        [[ $ping_state == PING_OK ]] && write_status "$host" OK "Script ejecutado" || write_status "$host" OK "Script ejecutado por SSH (sin respuesta al ping)"
    else
        reason=$(classify_ssh_error "$log" "$rc")
        write_status "$host" FAIL "$reason"
    fi
}

run_script_cluster() {
    ask_credentials || return
    read -erp "Script local (.sh): " SCRIPT
    [[ -f $SCRIPT ]] || { error "No existe: $SCRIPT"; return; }
    read -rp "¿Ejecutar script con sudo? [s/N]: " SUDO_MODE
    SUDO_MODE=${SUDO_MODE,,}; [[ $SUDO_MODE == s ]] || SUDO_MODE=n
    ask_targets || return
    run_parallel worker_script "$SCRIPT" "$SUDO_MODE"
    cleanup_secret
}

# =========================================================
# 4) COMPROBAR HOSTS / SSH
# =========================================================
worker_check() {
    local host=$1 mode=$2 log="$LOG_DIR/$host-check.log"
    : > "$log"
    if ! check_host "$host"; then
        write_status "$host" FAIL "Offline / ping sin respuesta"
        return
    fi
    if [[ $mode == ssh ]]; then
        if ssh_base "$host" "echo SSH_OK" >/dev/null 2>>"$log"; then
            write_status "$host" OK "Ping + SSH OK"
        else
            write_status "$host" FAIL "Ping OK, SSH falló"
        fi
    else
        write_status "$host" OK "Responde al ping"
    fi
}

check_hosts_menu() {
    echo "1) Solo comprobar ping"
    echo "2) Comprobar ping + acceso SSH"
    read -rp "Opción [1]: " op
    if [[ $op == 2 ]]; then
        ask_credentials || return
        mode=ssh
    else
        mode=ping
    fi
    ask_targets || return
    run_parallel worker_check "$mode"
    cleanup_secret
}

# =========================================================
# 5) INFORMACIÓN DEL SISTEMA
# =========================================================
worker_info() {
    local host=$1 log="$LOG_DIR/$host-info.log" cmd rc
    : > "$log"
    if ! check_host "$host"; then
        write_status "$host" FAIL "No responde al ping"
        return
    fi
    cmd='echo "HOST=$(hostname)"; echo "IP=$(hostname -I 2>/dev/null | awk "{print \\$1}")"; echo "SO=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d \"\\\"\")"; echo "KERNEL=$(uname -r)"; echo "UPTIME=$(uptime -p 2>/dev/null)"; echo "RAM=$(free -h 2>/dev/null | awk "/Mem:/ {print \\$3 \"/\" \\$2}")"; echo "DISCO=$(df -h / 2>/dev/null | awk "NR==2 {print \\$3 \"/\" \\$2 \" (\" \\$5 \")\"}")"'
    ssh_base "$host" "$cmd" > "$log" 2>&1
    rc=$?
    ((rc == 0)) && write_status "$host" OK "Información guardada" || write_status "$host" FAIL "No se pudo consultar"
}

system_info_cluster() {
    ask_credentials || return
    ask_targets || return
    run_parallel worker_info
    echo
    info "Resumen:"
    local h
    for h in "${HOSTS[@]}"; do
        [[ -s "$LOG_DIR/$h-info.log" ]] || continue
        echo -e "${YELLOW}--- $h ---${RESET}"
        cat "$LOG_DIR/$h-info.log"
        echo
    done
    cleanup_secret
}

# =========================================================
# 6) REINICIAR EQUIPOS
# =========================================================
worker_reboot() {
    local host=$1 log="$LOG_DIR/$host-reboot.log" rc
    : > "$log"
    if ! check_host "$host"; then
        write_status "$host" FAIL "No responde al ping"
        return
    fi
    printf '%s\n' "$PASS" | sshpass -p "$PASS" ssh \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout="$SSH_TIMEOUT" -o LogLevel=ERROR \
        "$USER@$host" "sudo -S -p '' nohup sh -c 'sleep 2; reboot' >/dev/null 2>&1 &" >> "$log" 2>&1
    rc=$?
    ((rc == 0)) && write_status "$host" OK "Reinicio enviado" || write_status "$host" FAIL "No se pudo reiniciar"
}

reboot_cluster() {
    ask_credentials || return
    ask_targets || return
    echo
    warn "Se reiniciarán $TOTAL equipos. La conexión SSH de esos equipos se perderá."
    read -rp "Escriba REINICIAR para confirmar: " confirm
    [[ $confirm == REINICIAR ]] || { warn "Operación cancelada."; return; }
    run_parallel worker_reboot
    cleanup_secret
}

# =========================================================
# 7) LOGS
# =========================================================
view_logs() {
    echo
    if ! compgen -G "$LOG_DIR/*.log" >/dev/null; then
        warn "No hay logs todavía."
        return
    fi
    echo -e "${CYAN}Logs disponibles:${RESET}"
    ls -1t "$LOG_DIR"/*.log | nl -w2 -s') '
    echo
    read -rp "Nombre/IP para filtrar (ENTER = volver): " filter
    [[ -z $filter ]] && return
    local matches=("$LOG_DIR"/*"$filter"*.log)
    if [[ ! -e ${matches[0]} ]]; then
        error "No se encontraron logs para '$filter'."
        return
    fi
    for f in "${matches[@]}"; do
        echo -e "${YELLOW}===== $f =====${RESET}"
        tail -n 100 "$f"
        echo
    done
}

clear_logs() {
    local count
    count=$(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' | wc -l)
    warn "Se eliminarán $count archivos de log de $LOG_DIR."
    read -rp "¿Continuar? [s/N]: " r
    if [[ $r =~ ^[Ss]$ ]]; then
        rm -f "$LOG_DIR"/*.log
        ok "Logs eliminados."
    fi
}

# =========================================================
# 8) CONFIGURACIÓN
# =========================================================
configure_jobs() {
    echo "Trabajos simultáneos actuales: $MAX_JOBS"
    read -rp "Nuevo valor [1-50]: " n
    if [[ $n =~ ^[0-9]+$ ]] && ((n >= 1 && n <= 50)); then
        MAX_JOBS=$n
        ok "MAX_JOBS cambiado a $MAX_JOBS para esta ejecución."
    else
        error "Valor inválido."
    fi
}

# =========================================================
# MENÚ
# =========================================================
main_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║${RESET}${YELLOW}           CLUSTER PRO SSH v2.3                  ${RESET}${CYAN}║${RESET}"
        echo -e "${CYAN}╠════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET} Paralelos: ${GREEN}$MAX_JOBS${RESET}   Logs: ${GREEN}$LOG_DIR${RESET}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════╝${RESET}"
        echo
        echo -e " ${YELLOW}1)${RESET} Ejecutar comando en múltiples hosts"
        echo -e " ${YELLOW}2)${RESET} Copiar archivo a múltiples hosts"
        echo -e " ${YELLOW}3)${RESET} Ejecutar script .sh en múltiples hosts"
        echo -e " ${YELLOW}4)${RESET} Comprobar equipos (Ping / SSH)"
        echo -e " ${YELLOW}5)${RESET} Obtener información de los equipos"
        echo -e " ${YELLOW}6)${RESET} Reiniciar equipos remotos"
        echo -e " ${YELLOW}7)${RESET} Ver logs"
        echo -e " ${YELLOW}8)${RESET} Limpiar logs"
        echo -e " ${YELLOW}9)${RESET} Cambiar trabajos simultáneos"
        echo -e "${YELLOW}10)${RESET} Comprobar / instalar dependencias"
        echo -e " ${RED}0)${RESET} Salir"
        echo
        echo -e "${BLUE}══════════════════════════════════════════════════════${RESET}"
        read -rp "Seleccione una opción: " OPCION

        case $OPCION in
            1) clear; echo -e "${YELLOW}=== EJECUTAR COMANDO REMOTO ===${RESET}"; run_command_cluster; pause ;;
            2) clear; echo -e "${YELLOW}=== COPIAR ARCHIVO ===${RESET}"; copy_file_cluster; pause ;;
            3) clear; echo -e "${YELLOW}=== EJECUTAR SCRIPT REMOTO ===${RESET}"; run_script_cluster; pause ;;
            4) clear; echo -e "${YELLOW}=== COMPROBAR EQUIPOS ===${RESET}"; check_hosts_menu; pause ;;
            5) clear; echo -e "${YELLOW}=== INFORMACIÓN DE EQUIPOS ===${RESET}"; system_info_cluster; pause ;;
            6) clear; echo -e "${RED}=== REINICIAR EQUIPOS ===${RESET}"; reboot_cluster; pause ;;
            7) clear; view_logs; pause ;;
            8) clear; clear_logs; pause ;;
            9) clear; configure_jobs; pause ;;
            10) clear; check_dependencies; pause ;;
            0) clear; echo -e "${GREEN}Saliendo...${RESET}"; exit 0 ;;
            *) error "Opción inválida."; sleep 1 ;;
        esac
    done
}

main_menu
