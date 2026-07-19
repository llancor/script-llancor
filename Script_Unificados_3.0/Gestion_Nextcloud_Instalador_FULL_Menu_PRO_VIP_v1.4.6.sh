#!/bin/bash

# =========================================================
# NEXTCLOUD PRO v5.1 FIXED
# Debian / Ubuntu / TurnKey Linux
# =========================================================

set -uo pipefail

trap 'echo -e "\n\033[1;31m[ERROR] Línea $LINENO\033[0m"' ERR

clear

# =========================================================
# CONFIG
# =========================================================

NC_DIR="/var/www/nextcloud"
DATA_DIR="/var/www/nextcloud-data"
WEB_USER="www-data"
DB_FILE="/root/nextcloud_db.conf"

# ========= Variables =========
SUDO="sudo -u $WEB_USER"
USER_WEB="www-data"
APACHE_SITES="/etc/apache2/sites-available"
ROOT_PASS=""
BACKUP_DIR_DEFAULT="$HOME/backups-mysql"
EDITOR_BIN="nano"
NEXTCLOUD_DIR="/var/www/nextcloud"
NEXTCLOUD_DATA="/var/www/nextcloud-data"
# =========================================================
# COLORES
# =========================================================

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
NC='\033[0m'
BOLD="\e[1m"

# ========= Utilidades =========
log(){ echo "$(date '+%F %T') | $1" >> "$LOG_FILE"; }
pausa(){ read -rp "Presiona ENTER para continuar..."; }
ok(){ echo -e "${GREEN}✅ $1${NC}"; }
warn(){ echo -e "${YELLOW}⚠️  $1${NC}"; }
err(){ echo -e "${RED}❌ $1${NC}"; }
require_cmd(){ command -v "$1" >/dev/null 2>&1 || { err "Falta el comando '$1'."; return 1; }; }

pedir_root_pass(){
  if [ -z "$ROOT_PASS" ]; then
    echo -e "${CYAN}🔐 Introduce la contraseña de root de MySQL:${NC}"
    read -rs -p "Contraseña: " ROOT_PASS; echo
  fi
}

confirmar(){ read -rp "⚠️  $1 (s/N): " _c; [[ "$_c" =~ ^[sS]$ ]]; }
# =========================================================
# ROOT
# =========================================================

[ "$EUID" -ne 0 ] && echo "Ejecuta como root" && exit 1

pause(){
read -p "ENTER para continuar..."
}

# =========================================================
# PHP
# =========================================================

detect_php(){

PHPV=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)

if [ -z "${PHPV:-}" ]; then
    PHPV="8.2"
fi

PHPINI="/etc/php/$PHPV/apache2/php.ini"

}

# =========================================================
# INTERNET
# =========================================================

check_internet(){

ping -c 1 8.8.8.8 &>/dev/null || {

    echo -e "${RED}Sin internet${RESET}"
    pause
    return 1
}

}
#!/bin/bash
# ==============================================================================
#  ADMIN NEXTCLOUD & MYSQL - MENU UNIFICADO (TODO EN UNO)
#  Version: 3.7 (colores ajustados, menus corregidos)
# ==============================================================================

# ========= Colores =========
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ========= Variables =========
NEXTCLOUD_DIR="/var/www/nextcloud"
NEXTCLOUD_DATA="/var/www/nextcloud-data"
APACHE_SITES="/etc/apache2/sites-available"
USER_WEB="www-data"
ROOT_PASS=""
BACKUP_DIR_DEFAULT="$HOME/backups-mysql"
EDITOR_BIN="nano"
LOG_FILE="$HOME/gestion_nc_mysql.log"
SCRIPT_NAME="menu"
SCRIPT_PATH="/usr/local/bin/$SCRIPT_NAME"

# SERVICIOS=(apache2 mysql redis-server cron jellyfin)

# Variables adicionales para NC-TOOLS (copiar/borrar/montar HDD/USB)
NC_PATH="$NEXTCLOUD_DIR"
DATA_PATH="$NEXTCLOUD_DATA"
WEB_USER="$USER_WEB"
PHP_BIN="$(command -v php)"

# ========= Utilidades =========
log(){ echo "$(date '+%F %T') | $1" >> "$LOG_FILE"; }
pausa(){ read -rp "Presiona ENTER para continuar..."; }
ok(){ echo -e "${GREEN}✅ $1${NC}"; }
warn(){ echo -e "${YELLOW}⚠️  $1${NC}"; }
err(){ echo -e "${RED}❌ $1${NC}"; }

require_cmd(){ command -v "$1" >/dev/null 2>&1 || { err "Falta el comando '$1'."; return 1; }; }

pedir_root_pass(){
  if [ -z "$ROOT_PASS" ]; then
    echo -e "${CYAN}🔐 Introduce la contraseña de root de MySQL:${NC}"
    read -rs -p "Contraseña: " ROOT_PASS; echo
  fi
}

confirmar(){ read -rp "⚠️  $1 (s/N): " _c; [[ "$_c" =~ ^[sS]$ ]]; }

# =========================================================
# CONFIG
# =========================================================

NC_DIR="/var/www/nextcloud"
WEB_USER="www-data"

# =========================================================
# STATUS SERVICIOS NEXTCLOUD PRO
# =========================================================

status_services(){

clear

echo -e "${CYAN}========================================${RESET}"
echo -e "${WHITE}        ESTADO NEXTCLOUD PRO${RESET}"
echo -e "${CYAN}========================================${RESET}"

echo

# =========================================================
# SERVICIOS
# =========================================================

check_service(){

SERVICE_NAME="$1"
DISPLAY_NAME="$2"

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${GREEN}✔${RESET} $DISPLAY_NAME: active"
else
    echo -e "${RED}✘${RESET} $DISPLAY_NAME: inactive"
fi

}

check_service apache2 "Apache"
check_service mariadb "MariaDB"
check_service redis-server "Redis"

echo

# =========================================================
# PHP
# =========================================================

PHP_VERSION=$(php -v 2>/dev/null | head -n 1)

echo -e "${CYAN}PHP:${RESET} ${PHP_VERSION:-No instalado}"

echo

# =========================================================
# RAM / DISCO
# =========================================================

echo -e "${CYAN}RAM:${RESET}"
free -h | awk 'NR==2 {print "Usada: "$3" / Total: "$2}'

echo

echo -e "${CYAN}DISCO:${RESET}"
df -h / | awk 'NR==2 {print "Usado: "$3" / Total: "$2" ("$5")"}'

echo

# =========================================================
# NEXTCLOUD
# =========================================================

if [ -f "$NC_DIR/occ" ]; then

    STATUS=$(
        sudo -u "$WEB_USER" php \
        -d memory_limit=1G \
        "$NC_DIR/occ" status 2>/dev/null || true
    )

    VERSION=$(echo "$STATUS" \
    | grep "version:" \
    | head -n1 \
    | cut -d':' -f2 \
    | xargs)

    INSTALLED=$(echo "$STATUS" \
    | grep "installed:" \
    | head -n1 \
    | cut -d':' -f2 \
    | xargs)

    MAINT=$(echo "$STATUS" \
    | grep "maintenance:" \
    | head -n1 \
    | cut -d':' -f2 \
    | xargs)

    EDITION=$(echo "$STATUS" \
    | grep "edition:" \
    | head -n1 \
    | cut -d':' -f2 \
    | xargs)

    echo -e "${GREEN}✔ Nextcloud instalado${RESET}"

    echo
    echo -e "${CYAN}Versión:${RESET} ${VERSION:-Desconocida}"
    echo -e "${CYAN}Instalado:${RESET} ${INSTALLED:-Unknown}"
    echo -e "${CYAN}Maintenance:${RESET} ${MAINT:-Unknown}"

    [ -n "$EDITION" ] && \
    echo -e "${CYAN}Edition:${RESET} $EDITION"

    echo


# =========================================================
# URL DESDE VHOST NEXTCLOUD
# =========================================================

VHOST_FILE=$(find /etc/apache2/sites-enabled \
-name "*nextcloud*.conf" 2>/dev/null | head -n1)

if [ -z "$VHOST_FILE" ]; then
    VHOST_FILE=$(find /etc/apache2/sites-available \
    -name "*nextcloud*.conf" 2>/dev/null | head -n1)
fi

if [ -n "$VHOST_FILE" ]; then

    DOMAIN=$(grep -i "^ServerName" "$VHOST_FILE" \
    | awk '{print $2}' \
    | head -n1)

    SSL_ENABLED="false"

    if grep -qi "SSLEngine on" "$VHOST_FILE"; then
        SSL_ENABLED="true"
    fi

    if [ -n "$DOMAIN" ]; then

        if [ "$SSL_ENABLED" = "true" ]; then
            echo -e "${CYAN}URL:${RESET} https://$DOMAIN"
        else
            echo -e "${CYAN}URL:${RESET} http://$DOMAIN"
        fi

    else

        echo -e "${YELLOW}ServerName no detectado${RESET}"

    fi

else

    echo -e "${YELLOW}VHost Nextcloud no encontrado${RESET}"

fi

echo

    # =========================================================
    # DATA DIRECTORY
    # =========================================================

    DATA_DIR=$(grep "'datadirectory'" "$NC_DIR/config/config.php" \
    | cut -d"'" -f4)

    echo -e "${CYAN}Data:${RESET} ${DATA_DIR:-No detectado}"

    echo

    # =========================================================
    # APPS IMPORTANTES
    # =========================================================

    echo -e "${CYAN}Apps:${RESET}"

    APPS=(
        "files"
        "activity"
        "calendar"
        "contacts"
        "music"
        "onlyoffice"
        "richdocuments"
        "spreed"
    )

    ENABLED_APPS=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list 2>/dev/null)

    for APP in "${APPS[@]}"; do

        if echo "$ENABLED_APPS" \
        | grep -A999 "Enabled:" \
        | grep -q " - $APP"; then

            echo -e "${GREEN}✔${RESET} $APP"

        else

            echo -e "${RED}✘${RESET} $APP"

        fi

    done

    echo

    # =========================================================
    # CRON
    # =========================================================

    echo -e "${CYAN}Cron:${RESET}"

    if crontab -u "$WEB_USER" -l 2>/dev/null | grep -q "cron.php"; then
        echo -e "${GREEN}✔ Cron configurado${RESET}"
    else
        echo -e "${RED}✘ Cron NO configurado${RESET}"
    fi

else

    echo -e "${RED}❌ Nextcloud NO instalado${RESET}"

fi

echo
echo -e "${CYAN}========================================${RESET}"

pause
}

# =========================================================
# PAUSE
# =========================================================

pause(){
    echo
    read -rp "Presiona ENTER para continuar..."
}

# ===========================================================
# MENU DOCUMENTSERVER COMMUNITY + COLLABORA ONLINE
# ===========================================================

menu_office_app(){

while true; do
clear

echo -e "${CYAN}===== DOCUMENTSERVER COMMUNITY + OnlyOffice =====${RESET}"
echo
echo -e "${YELLOW}1)${RESET} Instalar DocumentServer + OnlyOffice"
echo -e "${YELLOW}2)${RESET} Desinstalar DocumentServer + OnlyOffice"
echo -e "${YELLOW}3)${RESET} Actualizar DocumentServer + OnlyOffice"
echo -e "${YELLOW}4)${RESET} Estado DocumentServer + OnlyOffice"
echo -e "${YELLOW}5)${RESET} Reconstruir fuentes DocumentServer"
echo
echo -e "${YELLOW}=====================================${RESET}"
echo
echo -e "${GREEN}===== COLLABORA ONLINE + NEXTCLOUD OFFICE =====${RESET}"
echo
echo -e "${YELLOW}6)${RESET} Instalar Collabora Online + Nextcloud Office"
echo -e "${YELLOW}7)${RESET} Desinstalar Collabora Online + Nextcloud Office"
echo -e "${YELLOW}8)${RESET} Actualizar Collabora Online + Nextcloud Office"
echo -e "${YELLOW}9)${RESET} Estado Collabora Online + Nextcloud Office"
echo -e "${YELLOW}10)${RESET} Reparar Fuentes Collabora Online"
echo -e "${YELLOW}0)${RESET} Volver"


read -p "Opción: " op

case $op in

1)
    echo
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW} Instalando documentserver_community${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo

    spin='-\|/'

    echo -e "${CYAN}Descargando aplicación...${RESET}"
	echo
    echo -e "${CYAN}Esto puede tardar unos minutos...${RESET}"
	
    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:install documentserver_community &
    PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        for i in 0 1 2 3; do
            printf "\rInstalando documentserver... %s" "${spin:$i:1}"
            sleep 0.2
        done
    done

    wait "$PID"

    echo -e "\n${CYAN}Habilitando aplicación...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:enable documentserver_community

    echo
    echo -e "${GREEN}✔ documentserver_community instalado${RESET}"

    echo
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW} Instalando onlyoffice${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo

    echo -e "${CYAN}Descargando aplicación...${RESET}"

    sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" app:install onlyoffice &
    PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        for i in 0 1 2 3; do
            printf "\rInstalando onlyoffice... %s" "${spin:$i:1}"
            sleep 0.2
        done
    done

    wait "$PID"

    echo -e "\n${CYAN}Habilitando aplicación...${RESET}"

    sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" app:enable onlyoffice

    echo
    echo -e "${GREEN}✔ onlyoffice instalado${RESET}"
    echo

IP=$(hostname -I | awk '{print $1}')

echo -e "${CYAN}Servidor Nextcloud:${RESET}"
echo "http://$IP"

echo
echo -e "${CYAN}IMPORTANTE:${RESET}"
echo "Debes configurar un servidor ONLYOFFICE Document Server."
echo
echo "Ejemplos:"
echo "http://ip-srvidor//index.php/apps/documentserver_community/"
echo "https://office.midominio.com/index.php/apps/documentserver_community/"
echo

pause
;;

2)
echo
echo -e "${YELLOW}========================================${RESET}"
echo -e "${YELLOW} Desinstalando documentserver_community${RESET}"
echo -e "${YELLOW}========================================${RESET}"
echo

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q "documentserver_community:"; then

    echo -e "${CYAN}Deshabilitando aplicación...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:disable documentserver_community

    echo
    echo -e "${CYAN}Intentando eliminar aplicación...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:remove documentserver_community 2>/dev/null

    echo
    echo -e "${CYAN}Eliminando archivos residuales...${RESET}"

    rm -rf "$NC_DIR/apps/documentserver_community"

    echo
    echo -e "${GREEN}✔ documentserver_community eliminado completamente${RESET}"

else

    echo -e "${YELLOW}documentserver_community no está instalado${RESET}"

fi

echo
echo -e "${YELLOW}========================================${RESET}"
echo -e "${YELLOW} Desinstalando onlyoffice${RESET}"
echo -e "${YELLOW}========================================${RESET}"
echo

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q "onlyoffice:"; then

    echo -e "${CYAN}Deshabilitando aplicación...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:disable onlyoffice

    echo
    echo -e "${CYAN}Intentando eliminar aplicación...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:remove onlyoffice 2>/dev/null

    echo
    echo -e "${CYAN}Eliminando archivos residuales...${RESET}"

    rm -rf "$NC_DIR/apps/onlyoffice"

    echo
    echo -e "${GREEN}✔ onlyoffice eliminado completamente${RESET}"

else

    echo -e "${YELLOW}onlyoffice no está instalado${RESET}"

fi

echo
echo -e "${CYAN}Ejecutando reparación de Nextcloud...${RESET}"

sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:repair

echo
echo -e "${GREEN}✔ Limpieza finalizada${RESET}"

pause
;;

3)
echo
echo -e "${YELLOW}========================================${RESET}"
echo -e "${YELLOW} Actualizando documentserver_community${RESET}"
echo -e "${YELLOW}========================================${RESET}"
echo

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q documentserver_community; then

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:update documentserver_community

    echo
    echo -e "${GREEN}✔ documentserver_community actualizado${RESET}"

else

    echo -e "${YELLOW}documentserver_community no está instalado${RESET}"

fi

echo
echo -e "${YELLOW}========================================${RESET}"
echo -e "${YELLOW} Actualizando onlyoffice${RESET}"
echo -e "${YELLOW}========================================${RESET}"
echo

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q onlyoffice; then

    sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" app:update onlyoffice

    echo
    echo -e "${GREEN}✔ onlyoffice actualizado${RESET}"

else

    echo -e "${YELLOW}onlyoffice no está instalado${RESET}"

fi

echo
echo -e "${CYAN}Ejecutando reparación de Nextcloud...${RESET}"

sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:repair

echo
echo -e "${GREEN}✔ Reparación completada${RESET}"

pause
;;

4)
echo
echo -e "${YELLOW}========================================${RESET}"
echo -e "${YELLOW} Estado aplicaciones Office${RESET}"
echo -e "${YELLOW}========================================${RESET}"
echo

# ========================================
# documentserver_community
# ========================================

echo -e "${CYAN}documentserver_community:${RESET}"

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q "documentserver_community:"; then

    echo -e "${GREEN}✔ Instalado${RESET}"

    if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -A999 enabled | grep -q "documentserver_community"; then
        echo -e "${GREEN}✔ Estado: Habilitado${RESET}"
    else
        echo -e "${YELLOW}⚠ Estado: Deshabilitado${RESET}"
    fi

else

    echo -e "${RED}✘ No instalado${RESET}"

fi

echo

# ========================================
# onlyoffice
# ========================================

echo -e "${CYAN}onlyoffice:${RESET}"

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q "onlyoffice:"; then

    echo -e "${GREEN}✔ Instalado${RESET}"

    if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -A999 enabled | grep -q "onlyoffice"; then
        echo -e "${GREEN}✔ Estado: Habilitado${RESET}"
    else
        echo -e "${YELLOW}⚠ Estado: Deshabilitado${RESET}"
    fi

else

    echo -e "${RED}✘ No instalado${RESET}"

fi

echo
    pause
;;

5)
    echo -e "${YELLOW}Reconstruyendo fuentes DocumentServer...${RESET}"

    if sudo -u $WEB_USER php $NC_DIR/occ list | grep -q documentserver:fonts; then

        sudo -u $WEB_USER php $NC_DIR/occ documentserver:fonts --rebuild

        echo
        echo -e "${GREEN}✔ Fuentes reconstruidas correctamente${RESET}"

    else

        echo -e "${RED}DocumentServer Community no instalado${RESET}"

    fi

    pause
;;


6)

    echo
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW} Instalando Nextcloud Office${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo

    spin='-\|/'

    # =========================================================
    # RICHDOCUMENTS
    # =========================================================

    echo -e "${CYAN}Instalando richdocuments...${RESET}"
	echo
    echo -e "${CYAN}Esto puede tardar unos minutos...${RESET}"
	
    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:install richdocuments &
    PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        for i in 0 1 2 3; do
            printf "\rInstalando richdocuments... %s" "${spin:$i:1}"
            sleep 0.2
        done
    done

    wait "$PID"

    echo -e "\n${CYAN}Habilitando richdocuments...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:enable richdocuments

    # =========================================================
    # RICHDOCUMENTSCODE (COLLABORA CODE SERVER)
    # =========================================================

    echo
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW} Instalando CODE Server (Collabora)${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo

    echo -e "${CYAN}Instalando richdocumentscode...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:install richdocumentscode &
    PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        for i in 0 1 2 3; do
            printf "\rInstalando richdocumentscode... %s" "${spin:$i:1}"
            sleep 0.2
        done
    done

    wait "$PID"

    echo -e "\n${CYAN}Habilitando richdocumentscode...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:enable richdocumentscode

    # =========================================================
    # FINAL
    # =========================================================

    echo
    echo -e "${GREEN}✔ Collabora Online instalado${RESET}"
    echo -e "${GREEN}✔ Nextcloud Office habilitado${RESET}"
    echo

echo
echo -e "${YELLOW}IMPORTANTE:${RESET}"
echo "Si usas proxy reverso o HTTPS,"
echo "verifica la configuración en:"
echo "Ajustes → Administración → Nextcloud Office"

pause
;;

7)
    echo
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW} Desinstalando Collabora${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo

    echo
    echo -e "${CYAN}Eliminando richdocumentscode...${RESET}"

    sudo -u $WEB_USER php $NC_DIR/occ app:remove richdocumentscode


    echo
    echo -e "${CYAN}Eliminando richdocuments...${RESET}"

    sudo -u $WEB_USER php $NC_DIR/occ app:remove richdocuments

    echo
    echo -e "${GREEN}✔ Collabora eliminado${RESET}"

    pause
;;

8)
echo
echo -e "${YELLOW}========================================${RESET}"
echo -e "${YELLOW} Actualizando Collabora${RESET}"
echo -e "${YELLOW}========================================${RESET}"
echo

# ========================================
# richdocuments
# ========================================

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q richdocuments; then

    echo -e "${CYAN}Actualizando richdocuments...${RESET}"

    sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" app:update richdocuments

    echo
    echo -e "${GREEN}✔ richdocuments actualizado${RESET}"

else

    echo -e "${YELLOW}richdocuments no está instalado${RESET}"

fi

echo

# ========================================
# richdocumentscode
# ========================================

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q richdocumentscode; then

    echo -e "${CYAN}Actualizando richdocumentscode...${RESET}"
    echo -e "${YELLOW}Esto puede tardar varios minutos...${RESET}"
    echo

    (
    sudo -u "$WEB_USER" php -d memory_limit=2G "$NC_DIR/occ" app:update richdocumentscode
    ) &

    PID=$!

    spin='-\|/'

    while kill -0 $PID 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r${CYAN}Actualizando CODE Server... ${spin:$i:1}${RESET}"
            sleep 0.2
        done
    done

    wait $PID
    STATUS=$?

    echo

    if [ $STATUS -eq 0 ]; then
        echo -e "${GREEN}✔ richdocumentscode actualizado${RESET}"
    else
        echo -e "${RED}✘ Error actualizando richdocumentscode${RESET}"
    fi

else

    echo -e "${YELLOW}richdocumentscode no está instalado${RESET}"

fi

echo
echo -e "${CYAN}Ejecutando reparación de Nextcloud...${RESET}"

sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:repair

echo
echo -e "${CYAN}Ejecutando limpieza de caché...${RESET}"
sudo -u "$WEB_USER" php "$NC_DIR/occ" files:scan-app-data

echo
echo -e "${GREEN}✔ Collabora actualizado${RESET}"

pause
;;


9)
echo
echo -e "${YELLOW}========================================${RESET}"
echo -e "${YELLOW} Estado Nextcloud Office${RESET}"
echo -e "${YELLOW}========================================${RESET}"
echo

# ========================================
# richdocuments
# ========================================

echo -e "${CYAN}Nextcloud Office (richdocuments):${RESET}"

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q "richdocuments:"; then

    echo -e "${GREEN}✔ Instalado${RESET}"

    if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list --enabled | grep -q "richdocuments"; then
        echo -e "${GREEN}✔ Estado: Habilitado${RESET}"
    else
        echo -e "${YELLOW}⚠ Estado: Deshabilitado${RESET}"
    fi

else

    echo -e "${RED}✘ No instalado${RESET}"

fi

echo

# ========================================
# richdocumentscode
# ========================================

echo -e "${CYAN}Collabora Online CODE (richdocumentscode):${RESET}"

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q "richdocumentscode:"; then

    echo -e "${GREEN}✔ Instalado${RESET}"

    if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list --enabled | grep -q "richdocumentscode"; then
        echo -e "${GREEN}✔ Estado: Habilitado${RESET}"
    else
        echo -e "${YELLOW}⚠ Estado: Deshabilitado${RESET}"
    fi

else

    echo -e "${RED}✘ No instalado${RESET}"

fi

echo

# ========================================
# Configuración WOPI
# ========================================

echo -e "${CYAN}Configuración WOPI:${RESET}"

WOPI_URL=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" config:app:get richdocuments wopi_url 2>/dev/null)

if [ -n "$WOPI_URL" ]; then

    echo -e "${GREEN}✔ Configurado${RESET}"
    echo "$WOPI_URL"

else

    echo -e "${YELLOW}⚠ No configurado${RESET}"

fi

echo

# ========================================
# Verificación final
# ========================================

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list --enabled | grep -q "richdocuments" \
&& sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list --enabled | grep -q "richdocumentscode"; then

    echo -e "${GREEN}✔ Collabora Online instalado${RESET}"
    echo -e "${GREEN}✔ Nextcloud Office habilitado${RESET}"

else

    echo -e "${RED}✘ Configuración incompleta${RESET}"

fi

pause
;;

10)
   echo -e "${YELLOW}Reparando Collabora / Nextcloud Office...${RESET}"
    echo

    if sudo -u $WEB_USER php $NC_DIR/occ app:list | grep -q richdocuments; then

        echo -e "${CYAN}Activando configuración...${RESET}"

        sudo -u $WEB_USER php $NC_DIR/occ richdocuments:activate-config

        echo
        echo -e "${CYAN}Instalando fuentes...${RESET}"

        sudo -u $WEB_USER php $NC_DIR/occ richdocuments:install-fonts

        echo
        echo -e "${CYAN}Actualizando templates...${RESET}"

        sudo -u $WEB_USER php $NC_DIR/occ richdocuments:update-empty-templates

        echo
        echo -e "${GREEN}✔ Collabora reparado correctamente${RESET}"

    else

        echo -e "${RED}Collabora / Nextcloud Office no instalado${RESET}"

    fi

    pause
;;
0) break ;;

*)
    echo -e "${RED}Opción inválida${RESET}"
    sleep 1
;;

esac

done
}

# ========= GESTIÓN INDIVIDUAL DE SERVICIOS PRO =========

SERVICIOS_BASE=(apache2 mysql redis-server cron jellyfin)

pausa(){ read -p "ENTER para continuar..."; }

# ===== SELECCIONAR SERVICIO =====
seleccionar_servicio(){

  while true; do

    clear
    echo -e "${BOLD}${BLUE}=== SELECCIONAR SERVICIO ===${NC}\n"

    # ===== SERVICIOS ACTIVOS =====
    mapfile -t ACTIVOS < <(systemctl list-units --type=service --state=running --no-legend | awk '{print $1}')

    # ===== SSH SIEMPRE =====
    mapfile -t SSH_SERV < <(systemctl list-unit-files --type=service --no-legend | awk '{print $1}' | grep -E '^ssh|^sshd')

    # ===== UNIFICAR =====
    SERVICIOS=("${SSH_SERV[@]}" "${SERVICIOS_BASE[@]}" "${ACTIVOS[@]}")

    # Quitar duplicados
    mapfile -t SERVICIOS < <(printf "%s\n" "${SERVICIOS[@]}" | sort -u)

    i=1
    for srv in "${SERVICIOS[@]}"; do

      estado=$(systemctl is-active "$srv" 2>/dev/null)

      case "$estado" in
        active) st="${GREEN}● Activo${NC}" ;;
        inactive) st="${RED}● Inactivo${NC}" ;;
        failed) st="${RED}● Fallando${NC}" ;;
        *) st="${YELLOW}● $estado${NC}" ;;
      esac

      echo -e "${YELLOW}$i)${NC} $srv -> $st"
      ((i++))
    done

    echo -e "\n${CYAN}0) Volver${NC}"
    echo ""

    read -rp "Selecciona número: " op

    # ===== ENTER VACÍO =====
    [[ -z "$op" ]] && continue

    # ===== VOLVER =====
    [[ "$op" == "0" ]] && return 1

    # ===== VALIDAR NÚMERO =====
    if ! [[ "$op" =~ ^[0-9]+$ ]]; then
      echo -e "${RED}Entrada inválida${NC}"
      pausa
      continue
    fi

    INDEX=$((op-1))
    SEL_SRV="${SERVICIOS[$INDEX]}"

    if [ -z "$SEL_SRV" ]; then
      echo -e "${RED}Opción fuera de rango${NC}"
      pausa
      continue
    fi

    return 0
  done
}

# ===== ACCIÓN =====
accion_servicio(){

  local accion="$1"

  seleccionar_servicio || return

  echo -e "\n${CYAN}>>> Ejecutando $accion en $SEL_SRV...${NC}\n"

  if systemctl "$accion" "$SEL_SRV" 2>/dev/null; then
    echo -e "${GREEN}✔ $SEL_SRV $accion correctamente${NC}"
  else
    echo -e "${RED}✘ Error al ejecutar $accion en $SEL_SRV${NC}"
    echo -e "\n${YELLOW}Últimos logs:${NC}"
    journalctl -u "$SEL_SRV" -n 10 --no-pager
  fi

  pausa
}

# ===== MENÚ =====
menu_servicios(){
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== GESTIÓN DE SERVICIOS ===${NC}"
    echo -e " ${YELLOW}1)${NC} Iniciar servicio"
    echo -e " ${YELLOW}2)${NC} Detener servicio"
    echo -e " ${YELLOW}3)${NC} Reiniciar servicio"
    echo -e " ${YELLOW}4)${NC} Ver estado rápido"
    echo -e " ${CYAN}0) Volver${NC}"

    read -rp "> " op

    case "$op" in
      "") continue ;;  # ENTER no hace nada
      1) accion_servicio start ;;
      2) accion_servicio stop ;;
      3) accion_servicio restart ;;
      4) seleccionar_servicio; pausa ;;
      0) return ;;
      *) echo -e "${RED}Opción inválida${NC}"; pausa ;;
    esac
  done
}


# ========= RESPALDO / RESTAURACIÓN MYSQL 2.0 =========

BACKUP_DIR="/root/BackupDB"

menu_mysql_backup(){

  pedir_root_pass
  mkdir -p "$BACKUP_DIR"

  while true; do
    clear

    echo -e "${CYAN}${BOLD}=== RESPALDO / RESTAURACIÓN MYSQL ===${NC}"
    echo -e " ${YELLOW}1)${NC} Respaldar BD MYSQL + Info"
    echo -e " ${YELLOW}2)${NC} Restaurar BD MYSQL Listado"
    echo -e " ${YELLOW}3)${NC} Listar respaldos MYSQL + Info"
	echo -e " ${YELLOW}4)${NC} Restaurar BD MYSQL Listado + Info"
	echo -e " ${YELLOW}5)${NC} Crear BD + Usuario MYSQL"
    echo -e " ${YELLOW}6)${NC} Eliminar BD + Usuario MYSQL"
	echo -e " ${YELLOW}7)${NC} Reiniciar servicio MySQL"
    echo -e " ${CYAN}0) Volver${NC}"

    read -rp "> " op

    case "$op" in

      1)

    echo -e "${YELLOW}Bases de datos disponibles:${NC}"

    DBS=$(mysql -uroot -p"$ROOT_PASS" -e "SHOW DATABASES;" \
      | grep -Ev "Database|information_schema|mysql|performance_schema|sys")

    echo -e "${CYAN}0) Cancelar${NC}"

    select db in $DBS; do

      [[ "$REPLY" == "0" ]] && {
        warn "Cancelado."
        break
      }

      [ -n "$db" ] || {
        warn "Selección inválida"
        break
      }

      FECHA=$(date +%F_%H-%M)

      # =========================================================
      # VERSION NEXTCLOUD
      # =========================================================

      if [ -f "$NC_DIR/occ" ]; then

        NC_VERSION=$(
          sudo -u "$WEB_USER" php "$NC_DIR/occ" status --output=json 2>/dev/null \
          | grep -oP '"version"\s*:\s*"\K[^"]+'
        )

      fi

      [ -z "$NC_VERSION" ] && NC_VERSION="unknown"

      # limpiar caracteres raros
      NC_VERSION_CLEAN=$(echo "$NC_VERSION" | tr '.' '_')

      # =========================================================
      # ARCHIVO BACKUP
      # =========================================================

      DB_BACKUP="$BACKUP_DIR/${db}_v${NC_VERSION_CLEAN}_${FECHA}.sql.gz"

      echo -e "${CYAN}========================================${RESET}"
      echo -e "${WHITE}      BACKUP DATABASE MYSQL${RESET}"
      echo -e "${CYAN}========================================${RESET}"
      echo

      echo -e "${GREEN}Base de datos:${RESET} $db"
      echo -e "${GREEN}Versión Nextcloud:${RESET} $NC_VERSION"
      echo -e "${GREEN}Destino:${RESET} $DB_BACKUP"
      echo

      mysqldump -uroot -p"$ROOT_PASS" "$db" | gzip > "$DB_BACKUP"

      if [ $? -eq 0 ]; then
        ok "Respaldo creado correctamente."
      else
        err "Error al crear respaldo."
      fi

      break

    done

    pausa
;;

     2)

   echo -e "${YELLOW}Respaldos disponibles:${NC}"

    FILES=$(ls "$BACKUP_DIR"/*.sql.gz 2>/dev/null)

    [ -z "$FILES" ] && {
      warn "No hay respaldos disponibles."
      pausa
      continue
    }

    echo -e "${CYAN}0) Cancelar${NC}"

    select file in $FILES; do

      [[ "$REPLY" == "0" ]] && {
        warn "Cancelado."
        break
      }

      [ -n "$file" ] || {
        warn "Selección inválida"
        break
      }

      echo
      echo -e "${YELLOW}Bases de datos disponibles:${NC}"

      DBS=$(mysql -uroot -p"$ROOT_PASS" -e "SHOW DATABASES;" \
        | grep -Ev "Database|information_schema|mysql|performance_schema|sys")

      echo -e "${CYAN}0) Cancelar${NC}"

      select db in $DBS; do
10
        [[ "$REPLY" == "0" ]] && {
          warn "Cancelado."
          break
        }

        [ -n "$db" ] || {
          warn "Selección inválida"
          break
        }

        echo
        echo -e "${YELLOW}Restaurando respaldo en:${NC} $db"

        gunzip < "$file" | mysql -uroot -p"$ROOT_PASS" "$db"

        if [ $? -eq 0 ]; then
          ok "BD restaurada correctamente en $db"
        else
          err "Error al restaurar BD"
        fi

        break

      done

      break

    done

    pausa
;;

3)

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}      RESPALDOS DISPONIBLES MYSQL DETALLE 2.0${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    if ls "$BACKUP_DIR"/*.sql.gz >/dev/null 2>&1; then

        for file in "$BACKUP_DIR"/*.sql.gz; do

            SIZE=$(du -h "$file" | awk '{print $1}')
            FECHA_MOD=$(date -r "$file" "+%Y-%m-%d %H:%M")
            NOMBRE=$(basename "$file")

            # =====================================================
            # EXTRAER DATOS DEL NOMBRE
            # FORMATO:
            # nextcloud_v29_0_4_1_2026-05-14_02-05.sql.gz
            # =====================================================

            DB_NAME=$(echo "$NOMBRE" | sed -E 's/_v[0-9_]+_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}\.sql\.gz//')

            VERSION=$(echo "$NOMBRE" \
              | sed -E 's/.*_v([0-9_]+)_[0-9]{4}-.*/\1/' \
              | tr '_' '.')

            echo -e "${GREEN}Archivo:${RESET} $NOMBRE"
            echo -e "${GREEN}Base de datos:${RESET} ${DB_NAME:-unknown}"
            echo -e "${GREEN}Versión Nextcloud:${RESET} ${VERSION:-unknown}"
            echo -e "${GREEN}Tamaño:${RESET} $SIZE"
            echo -e "${GREEN}Fecha:${RESET} $FECHA_MOD"

            echo -e "${CYAN}----------------------------------------${RESET}"

        done

    else

        warn "No hay respaldos disponibles en $BACKUP_DIR"

    fi

    pausa
;;

4)
    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}      RESTAURAR BACKUP MYSQL${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    mapfile -t FILES < <(find "$BACKUP_DIR" -maxdepth 1 -name "*.sql.gz" | sort)

    [ ${#FILES[@]} -eq 0 ] && {
        warn "No hay respaldos disponibles."
        pausa
        continue
    }

    # =====================================================
    # LISTAR RESPALDOS
    # =====================================================

    for i in "${!FILES[@]}"; do

        file="${FILES[$i]}"

        SIZE=$(du -h "$file" | awk '{print $1}')
        FECHA_MOD=$(date -r "$file" "+%Y-%m-%d %H:%M")
        NOMBRE=$(basename "$file")

        DB_NAME=$(echo "$NOMBRE" \
          | sed -E 's/_v[0-9_]+_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}\.sql\.gz//')

        VERSION=$(echo "$NOMBRE" \
          | sed -E 's/.*_v([0-9_]+)_[0-9]{4}-.*/\1/' \
          | tr '_' '.')

        echo -e "${YELLOW}$((i+1)))${NC} $NOMBRE"
        echo -e "   ${GREEN}Backup BD:${NC} ${DB_NAME:-unknown}"
        echo -e "   ${GREEN}Versión:${NC} ${VERSION:-unknown}"
        echo -e "   ${GREEN}Tamaño:${NC} $SIZE"
        echo -e "   ${GREEN}Fecha:${NC} $FECHA_MOD"
        echo

    done

    echo -e "${CYAN}0) Cancelar${NC}"
    echo

    read -rp "Selecciona respaldo: " opt

    [[ "$opt" == "0" ]] && continue

    [[ "$opt" =~ ^[0-9]+$ ]] || {
        warn "Opción inválida"
        pausa
        continue
    }

    (( opt >= 1 && opt <= ${#FILES[@]} )) || {
        warn "Número fuera de rango"
        pausa
        continue
    }

    file="${FILES[$((opt-1))]}"

    # =====================================================
    # LISTAR BASES DE DATOS DISPONIBLES
    # =====================================================

    echo
    echo -e "${YELLOW}Bases de datos disponibles:${NC}"
    echo

    DBS=$(mysql -uroot -p"$ROOT_PASS" -e "SHOW DATABASES;" \
      | grep -Ev "Database|information_schema|mysql|performance_schema|sys")

    select db in $DBS; do

        [ -n "$db" ] || {
            warn "Selección inválida"
            break
        }

        echo
        echo -e "${YELLOW}Restaurando respaldo en:${NC} $db"
        echo

        gunzip < "$file" | mysql -uroot -p"$ROOT_PASS" "$db"

        if [ $? -eq 0 ]; then
            ok "BD restaurada correctamente en $db"
        else
            err "Error al restaurar BD"
        fi

        break

    done

    pausa
;;

5)

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}      CREAR BASE DE DATOS MYSQL${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    read -rp "Nombre base de datos (0 cancelar): " NEW_DB

    [[ "$NEW_DB" == "0" ]] && {
        warn "Cancelado"
        pausa
        continue
    }

    read -rp "Usuario MYSQL (0 cancelar): " NEW_USER

    [[ "$NEW_USER" == "0" ]] && {
        warn "Cancelado"
        pausa
        continue
    }

    read -rsp "Contraseña MYSQL (0 cancelar): " NEW_PASS
    echo

    [[ "$NEW_PASS" == "0" ]] && {
        warn "Cancelado"
        pausa
        continue
    }

    # validar vacío
    [ -z "$NEW_DB" ] && {
        err "Nombre BD vacío"
        pausa
        continue
    }

    [ -z "$NEW_USER" ] && {
        err "Usuario vacío"
        pausa
        continue
    }

    mysql -uroot -p"$ROOT_PASS" -e "
    CREATE DATABASE \`$NEW_DB\`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;
    "

    if [ $? -ne 0 ]; then
        err "No se pudo crear la base de datos"
        pausa
        continue
    fi

    mysql -uroot -p"$ROOT_PASS" -e "
    CREATE USER '$NEW_USER'@'localhost' IDENTIFIED BY '$NEW_PASS';
    GRANT ALL PRIVILEGES ON \`$NEW_DB\`.* TO '$NEW_USER'@'localhost';
    FLUSH PRIVILEGES;
    "

    if [ $? -eq 0 ]; then

        echo
        ok "Base de datos creada correctamente"
        echo

        echo -e "${GREEN}Base de datos:${RESET} $NEW_DB"
        echo -e "${GREEN}Usuario:${RESET} $NEW_USER"
        echo -e "${GREEN}Contraseña:${RESET} $NEW_PASS"

    else

        err "Error al crear usuario MYSQL"

    fi

    pausa
;;

6)

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}      ELIMINAR BD + USUARIO MYSQL${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    DBS=$(mysql -uroot -p"$ROOT_PASS" -e "SHOW DATABASES;" \
      | grep -Ev "Database|information_schema|mysql|performance_schema|sys")

    echo -e "${YELLOW}Selecciona base de datos:${NC}"
    echo -e "${CYAN}0) Cancelar${NC}"

    select DEL_DB in $DBS; do

        [[ "$REPLY" == "0" ]] && {
            warn "Cancelado"
            break
        }

        [ -n "$DEL_DB" ] || {
            warn "Selección inválida"
            break
        }

        echo
        echo -e "${YELLOW}Usuarios MYSQL:${NC}"

        USERS=$(mysql -uroot -p"$ROOT_PASS" -N -e "
        SELECT User FROM mysql.user
        WHERE User NOT IN ('root','mysql','mariadb.sys');
        ")

        echo -e "${CYAN}0) Cancelar${NC}"

        select DEL_USER in $USERS; do

            [[ "$REPLY" == "0" ]] && {
                warn "Cancelado"
                break
            }

            [ -n "$DEL_USER" ] || {
                warn "Selección inválida"
                break
            }

            echo
            read -rp "Confirmar eliminación de BD '$DEL_DB' y usuario '$DEL_USER' ? (s/n): " CONFIRM

            [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]] && {
                warn "Cancelado"
                break
            }

            mysql -uroot -p"$ROOT_PASS" -e "
            DROP DATABASE \`$DEL_DB\`;
            DROP USER '$DEL_USER'@'localhost';
            FLUSH PRIVILEGES;
            "

            if [ $? -eq 0 ]; then
                ok "BD y usuario eliminados correctamente"
            else
                err "Error al eliminar BD o usuario"
            fi

            break

        done

        break

    done

    pausa
;;
      7) sudo systemctl restart mysql && ok "MySQL reiniciado." || err "Error reiniciando MySQL."; pausa ;;
      0)
        return
      ;;

      *)
        warn "Opción inválida"
        pausa
      ;;

    esac
  done
}

# ========= FUNCIONES AUXILIARES Nextcloud OCC =========
ok(){ echo -e "\e[32m$1\e[0m"; }
warn(){ echo -e "\e[33m$1\e[0m"; }
err(){ echo -e "\e[31m$1\e[0m"; }
pausa(){ read -rp "Presiona ENTER para continuar..."; }

confirmar(){
    read -rp "$1 (s/n): " c
    [[ "$c" =~ ^[sS]$ ]]
}
# ========= VER ERRORES NEXTCLOUD OCC =========
ver_errores_nc(){

    clear
    echo -e "${CYAN}${BOLD}=== ERRORES NEXTCLOUD ===${NC}"
    echo ""

    LOG_FILE="$NEXTCLOUD_DIR/data/nextcloud.log"

    if [ ! -f "$LOG_FILE" ]; then
        err "No se encontró el log"
        pausa
        return
    fi

    echo "Últimos 30 errores:"
    echo "-----------------------------------"
    tail -n 30 "$LOG_FILE"
    echo "-----------------------------------"

    echo ""
    echo "1) Ver en tiempo real"
    echo "2) Limpiar log"
    echo "0) Salir"
    echo ""

    read -rp "Seleccione: " op

    case "$op" in
        1)
            sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" log:tail
        ;;
        2)
            confirmar "¿Borrar log actual?" || return
            sudo truncate -s 0 "$LOG_FILE"
            ok "✔ Log limpiado"
        ;;
        0) return ;;
        *) err "Opción inválida" ;;
    esac

    pausa
}


# ========= REPARAR MIME TYPES OCC =========
reparar_mime_nc(){

    clear
    echo -e "${CYAN}${BOLD}=== Reparar Tipos MIME (Nextcloud) ===${NC}"

    echo "Esto puede tardar dependiendo del tamaño de tu servidor."
    echo ""

    confirmar "¿Ejecutar reparación completa de MIME?" || return

    echo ""
    echo "Activando modo mantenimiento..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --on

    echo "Ejecutando reparación (esto puede tardar)..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:repair --include-expensive

    echo "Desactivando modo mantenimiento..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --off

    ok "✔ Migración de tipos MIME completada"

    pausa
}

# ========= DETECTAR PHP.INI OCC =========
detectar_php_ini(){

    PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")

    if systemctl is-active --quiet apache2; then
        PHP_INI="/etc/php/$PHP_VERSION/apache2/php.ini"
        SERVICIO="apache2"
    else
        PHP_FPM=$(systemctl list-units --type=service | grep -oP "php$PHP_VERSION-fpm")

        if [ -n "$PHP_FPM" ]; then
            PHP_INI="/etc/php/$PHP_VERSION/fpm/php.ini"
            SERVICIO="$PHP_FPM"
        else
            echo "ERROR"
            return 1
        fi
    fi

    if [ ! -f "$PHP_INI" ]; then
        echo "ERROR"
        return 1
    fi

    echo "$PHP_INI|$SERVICIO"
}

# ========= OPCACHE FULL PRO OCC =========
opcache_full_pro_nc(){

    clear
    echo -e "${CYAN}${BOLD}=== OPcache FULL PRO (Nextcloud) ===${NC}"

    # ========= DETECCIÓN =========
 DATA=$(detectar_php_ini)
if [ $? -ne 0 ] || [ -z "$DATA" ]; then
    err "Error detectando php.ini"
    pausa
    return
fi

    PHP_INI=$(echo "$DATA" | cut -d'|' -f1)
    SERVICIO=$(echo "$DATA" | cut -d'|' -f2)

    if [ ! -f "$PHP_INI" ]; then
        err "No se encontró php.ini"
        pausa
        return
    fi

    echo -e "Archivo detectado: ${YELLOW}$PHP_INI${NC}"
    echo -e "Servicio detectado: ${YELLOW}$SERVICIO${NC}"

    # ========= VALORES ACTUALES =========
    echo ""
    echo "Valores actuales:"
    grep -E "opcache.memory_consumption|opcache.interned_strings_buffer|opcache.max_accelerated_files|opcache.revalidate_freq" "$PHP_INI" || echo "No definidos (usando defaults)"

    echo ""
    echo "=== PERFILES ==="
    echo "1) Básico (servidor pequeño) ✅"
    echo "2) Recomendado (Nextcloud normal) 🚀"
    echo "3) Alto rendimiento (servidor potente) 🔥"
    echo "4) Personalizado"
    echo "0) Cancelar"
    echo ""

    read -rp "Seleccione [2]: " op
    op=${op:-2}

    case "$op" in
        1)
            MEM=128
            STR=16
            FILES=10000
            REVAL=2
        ;;
        2)
            MEM=256
            STR=16
            FILES=20000
            REVAL=60
        ;;
        3)
            MEM=512
            STR=32
            FILES=100000
            REVAL=120
        ;;
        4)
            read -rp "memory_consumption (MB): " MEM
            read -rp "interned_strings_buffer (MB): " STR
            read -rp "max_accelerated_files: " FILES
            read -rp "revalidate_freq: " REVAL
        ;;
        0) return ;;
        *) err "Opción inválida"; pausa; return ;;
    esac

    echo ""
    confirmar "Aplicar configuración OPcache PRO?" || return

    # ========= FUNCIÓN ROBUSTA =========
    aplicar_config(){
        PARAM=$1
        VAL=$2

        if grep -Eq "^[;[:space:]]*$PARAM" "$PHP_INI"; then
            sudo sed -i "s|^[;[:space:]]*$PARAM.*|$PARAM=$VAL|" "$PHP_INI"
        else
            echo "$PARAM=$VAL" | sudo tee -a "$PHP_INI" > /dev/null
        fi
    }

    echo ""
    echo "Aplicando optimización..."

    aplicar_config "opcache.enable" "1"
    aplicar_config "opcache.memory_consumption" "$MEM"
    aplicar_config "opcache.interned_strings_buffer" "$STR"
    aplicar_config "opcache.max_accelerated_files" "$FILES"
    aplicar_config "opcache.revalidate_freq" "$REVAL"
    aplicar_config "opcache.save_comments" "1"
    aplicar_config "opcache.enable_cli" "1"

    ok "✔ Parámetros aplicados"

    # ========= REINICIO =========
    echo "Reiniciando servicio $SERVICIO..."
    sudo systemctl restart "$SERVICIO"

    if systemctl is-active --quiet "$SERVICIO"; then
        ok "✔ Servicio reiniciado correctamente"
    else
        err "Error al reiniciar servicio"
        pausa
        return
    fi

    # ========= VALIDACIÓN =========
    echo ""
    echo "Validando configuración aplicada..."

    sleep 2

    VAL_CHECK=$(php -i | grep "opcache.interned_strings_buffer" | awk '{print $5}')

    if [ -z "$VAL_CHECK" ]; then
        warn "No se pudo validar automáticamente (posible entorno distinto CLI/Web)"
    else
        echo "Valor detectado en CLI: $VAL_CHECK MB"

        if [ "$VAL_CHECK" -lt "$STR" ]; then
            warn "⚠ Posible php.ini incorrecto (CLI ≠ Apache/FPM)"
        else
            ok "✔ OPcache aplicado correctamente en CLI"
        fi
    fi

    # ========= CHECK NEXTCLOUD =========
    echo ""
    echo "Verificando estado en Nextcloud..."

    NC_CHECK=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:list system 2>/dev/null)

    if [ $? -eq 0 ]; then
        ok "✔ Nextcloud responde correctamente"
    else
        warn "No se pudo verificar Nextcloud (no crítico)"
    fi

    echo ""
    echo "=== RESULTADO FINAL ==="

    if [ "$STR" -ge 16 ]; then
        ok "✔ Buffer de strings optimizado (>=16MB)"
    else
        warn "Buffer bajo (puede seguir warning)"
    fi

    echo ""
    echo "Revisa en Nextcloud:"
    echo "→ Configuración → Administración → Información"

    echo ""
    echo "Si el warning sigue:"
    echo "- Recarga con Ctrl+F5"
    echo "- Espera 1-2 minutos (cache)"
    echo "- Verifica que no uses PHP-FPM aparte"

    echo ""
    ok "✔ Optimización OPcache FULL PRO completada"

    pausa
}

# == Autoreparacion Inteligente de Nextcloud occ ==
autoreparacion_nc() {
    echo "=== Autoreparacion Inteligente de Nextcloud ==="

    # Activar modo mantenimiento
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --on

    # Detectar version
    NC_VERSION=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" status --output=json | grep -oP '"version":\s*"\K[^"]+')
    echo "Nextcloud version: $NC_VERSION"

    # Detectar comandos disponibles
    OCC_CMDS=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" list)
    [[ "$OCC_CMDS" =~ "maintenance:repair" ]] && CMD_REPAIR="maintenance:repair" || CMD_REPAIR=""
    [[ "$OCC_CMDS" =~ "files:scan" ]] && CMD_SCAN="files:scan --all" || CMD_SCAN=""
    [[ "$OCC_CMDS" =~ "files:cleanup" ]] && CMD_CLEANUP="files:cleanup" || CMD_CLEANUP=""
    [[ "$OCC_CMDS" =~ "db:add-missing-indices" ]] && CMD_INDICES="db:add-missing-indices" || CMD_INDICES=""

    echo "Ejecutando reparaciones disponibles..."

    # 1. Reparacion general
    [ -n "$CMD_REPAIR" ] && sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" $CMD_REPAIR

    # 2. Limpieza de archivos huérfanos / inconsistentes
    [ -n "$CMD_CLEANUP" ] && sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" $CMD_CLEANUP

    # 3. Añadir índices faltantes (mejora rendimiento)
    [ -n "$CMD_INDICES" ] && sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" $CMD_INDICES

    # 4. Escaneo de todos los archivos para sincronizar DB
    [ -n "$CMD_SCAN" ] && sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" $CMD_SCAN

    # Apagar modo mantenimiento antes de listar apps y configuraciones
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --off

    # 5. Verificar apps instaladas
    echo "Verificando apps instaladas..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:list | grep -E "enabled|disabled"

    # 6. Revisar configuraciones criticas
    echo "Comprobando configuraciones criticas..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get dbhost
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get datadirectory

    echo "Autoreparacion inteligente completada para Nextcloud $NC_VERSION"
    read -p "Presiona ENTER para continuar..."
}

# =========================================================
# BACKUP DB NEXTCLOUD PRO
# =========================================================

backup_db_nc(){

    FECHA=$(date +%Y%m%d_%H%M%S)

    BACKUP_DIR="/root/BackupDB"
    mkdir -p "$BACKUP_DIR"

    # =========================================================
    # VALIDAR NEXTCLOUD
    # =========================================================

    if [ ! -f "$NC_DIR/occ" ]; then

        echo -e "${RED}❌ OCC no encontrado${RESET}"
        echo -e "${YELLOW}Ruta:${RESET} $NC_DIR/occ"

        return 1
    fi

    # =========================================================
    # VERSION NEXTCLOUD
    # =========================================================

    NC_VERSION=$(
        sudo -u "$WEB_USER" php "$NC_DIR/occ" status --output=json 2>/dev/null \
        | grep -oP '"version"\s*:\s*"\K[^"]+'
    )

    [ -z "$NC_VERSION" ] && NC_VERSION="unknown"

    # limpiar caracteres raros
    NC_VERSION_CLEAN=$(echo "$NC_VERSION" | tr '.' '_')

    # =========================================================
    # ARCHIVO BACKUP
    # =========================================================

    DB_BACKUP="$BACKUP_DIR/nextcloud_v${NC_VERSION_CLEAN}_${FECHA}.sql.gz"

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}      BACKUP DATABASE NEXTCLOUD${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    echo -e "${GREEN}Versión Nextcloud:${RESET} $NC_VERSION"
    echo

    # =========================================================
    # OBTENER CONFIG DB
    # =========================================================

    DB_NAME=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" config:system:get dbname 2>/dev/null)

    DB_USER=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" config:system:get dbuser 2>/dev/null)

    DB_PASS=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" config:system:get dbpassword 2>/dev/null)

    DB_HOST_RAW=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" config:system:get dbhost 2>/dev/null)

    # =========================================================
    # VALIDAR CONFIG
    # =========================================================

    if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ]; then

        echo -e "${RED}❌ No se pudo obtener configuración DB${RESET}"
        return 1

    fi

    # =========================================================
    # HOST / PUERTO
    # =========================================================

    DB_HOST=$(echo "$DB_HOST_RAW" | cut -d':' -f1)
    DB_PORT=$(echo "$DB_HOST_RAW" | cut -s -d':' -f2)

    [ -z "$DB_HOST" ] && DB_HOST="localhost"
    [ -z "$DB_PORT" ] && DB_PORT="3306"

    echo -e "${CYAN}Base:${RESET} $DB_NAME"
    echo -e "${CYAN}Usuario:${RESET} $DB_USER"
    echo -e "${CYAN}Host:${RESET} $DB_HOST"
    echo -e "${CYAN}Puerto:${RESET} $DB_PORT"

    echo
    echo -e "${YELLOW}➜ Creando backup comprimido...${RESET}"
    echo

    # =========================================================
    # MYSQLDUMP
    # =========================================================

    export MYSQL_PWD="$DB_PASS"

    mysqldump \
        --single-transaction \
        --quick \
        --lock-tables=false \
        --default-character-set=utf8mb4 \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        "$DB_NAME" 2>/tmp/nc_backup_error.log | gzip > "$DB_BACKUP"

    DUMP_STATUS=$?

    unset MYSQL_PWD

    # =========================================================
    # RESULTADO
    # =========================================================

    if [ "$DUMP_STATUS" = "0" ] && [ -f "$DB_BACKUP" ]; then

        SIZE=$(du -h "$DB_BACKUP" | awk '{print $1}')

        echo -e "${GREEN}✔ Backup completado${RESET}"
        echo -e "${CYAN}Archivo:${RESET} $DB_BACKUP"
        echo -e "${CYAN}Tamaño:${RESET} $SIZE"

        echo

        # devolver ruta para:
        # DB_BACKUP=$(backup_db_nc)

        echo "$DB_BACKUP"

        return 0

    else

        echo -e "${RED}❌ Error creando backup${RESET}"

        [ -f /tmp/nc_backup_error.log ] && cat /tmp/nc_backup_error.log

        rm -f "$DB_BACKUP"

        return 1

    fi
}

# ========= RESTORE DB =========
restore_db_nc(){
    DB_FILE="$1"

    DB_NAME=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get dbname)
    DB_USER=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get dbuser)
    DB_PASS=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get dbpassword)

    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$DB_FILE"
}
# =========================================
# DELETE BACKUPS NEXTCLOUD
# =========================================

nextcloud_delete_backups(){

    listar_backups_nextcloud || return 0

    echo -e "${RED}a)${NC} Eliminar TODOS"
    echo -e "${CYAN}0)${NC} Cancelar"

    echo

    read -rp "Seleccione opción: " OP || true

    [[ -z "$OP" ]] && return 0

    # =========================================
    # CANCELAR
    # =========================================

    if [[ "$OP" == "0" ]]; then

        info "Cancelado."

        echo
        read -rp "Presiona ENTER para continuar..." || true

        return 0
    fi

    # =========================================
    # ELIMINAR TODOS
    # =========================================

    if [[ "$OP" =~ ^[aA]$ ]]; then

        echo
        echo -e "${RED}⚠ Se eliminarán TODOS los backups.${NC}"
        echo

        read -rp "Confirmar eliminación total (s/n): " CONF || true

        if [[ "$CONF" =~ ^[sS]$ ]]; then

            for BACKUP in "${BACKUPS[@]}"; do
                rm -rf "$BACKUP"
            done

            echo
            ok "✔ Todos los backups eliminados."

        else

            warn "Operación cancelada."
        fi

        echo
        read -rp "Presiona ENTER para continuar..." || true

        return 0
    fi

    # =========================================
    # ELIMINAR UNO
    # =========================================

    if [[ "$OP" =~ ^[0-9]+$ ]] && (( OP >= 1 && OP <= ${#BACKUPS[@]} )); then

        BACKUP="${BACKUPS[$((OP-1))]}"

        echo
        echo -e "${YELLOW}Backup seleccionado:${NC}"
        echo "$BACKUP"

        echo

        read -rp "⚠ Confirmar eliminación (s/n): " CONF || true

        if [[ "$CONF" =~ ^[sS]$ ]]; then

            rm -rf "$BACKUP"

            echo
            ok "✔ Backup eliminado."

        else

            warn "Operación cancelada."
        fi

    else

        error "❌ Opción inválida."
    fi

    echo
    read -rp "Presiona ENTER para continuar..." || true
}

# ========= GESTIÓN APP API (TOGGLE PRO) =========
gestionar_appapi_nct(){

    clear
    echo -e "${CYAN}${BOLD}=== GESTIÓN APP API (Nextcloud) ===${NC}"
    echo ""

    # ===== VALIDAR NEXTCLOUD =====
    if [ ! -f "$NEXTCLOUD_DIR/occ" ]; then
        err "No se encontró Nextcloud en $NEXTCLOUD_DIR"
        pausa
        return
    fi

    # ===== VERIFICAR SI EXISTE =====
    if ! sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:list | grep -q "app_api"; then
        warn "AppAPI no está instalado en Nextcloud"
        pausa
        return
    fi

    # ===== DETECTAR ESTADO =====
    if sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:list | grep -A1 "Enabled:" | grep -q "app_api"; then
        ESTADO="ACTIVO"
    else
        ESTADO="INACTIVO"
    fi

    echo -e "Estado actual: ${YELLOW}$ESTADO${NC}"
    echo ""

    echo "1) Activar AppAPI"
    echo "2) Desactivar AppAPI"
    echo "3) Toggle automático (recomendado) 🔄"
    echo "0) Cancelar"
    echo ""

    read -rp "Seleccione [3]: " op
    op=${op:-3}

    case "$op" in
        1)
            ACCION="activar"
        ;;
        2)
            ACCION="desactivar"
        ;;
        3)
            if [ "$ESTADO" = "ACTIVO" ]; then
                ACCION="desactivar"
            else
                ACCION="activar"
            fi
        ;;
        0) return ;;
        *) err "Opción inválida"; pausa; return ;;
    esac

    echo ""
    confirmar "¿Desea $ACCION AppAPI?" || return

    echo ""

    # ===== EJECUTAR ACCIÓN =====
    if [ "$ACCION" = "activar" ]; then
        if sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:enable app_api; then
            ok "✔ AppAPI activado correctamente"
        else
            err "Error al activar AppAPI"
            pausa
            return
        fi
    else
        if sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:disable app_api; then
            ok "✔ AppAPI desactivado correctamente"
        else
            err "Error al desactivar AppAPI"
            pausa
            return
        fi
    fi

    # ===== VERIFICACIÓN FINAL =====
    echo ""
    echo "Verificando estado..."

    if sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:list | grep -A1 "Enabled:" | grep -q "app_api"; then
        NUEVO_ESTADO="ACTIVO"
    else
        NUEVO_ESTADO="INACTIVO"
    fi

    echo -e "Nuevo estado: ${GREEN}$NUEVO_ESTADO${NC}"

    ok "✔ Operación completada"

    pausa
}

# =========================================
# LISTAR BACKUPS NEXTCLOUD UPDATER PRO
# =========================================

listar_backups_nextcloud(){

    clear

    BACKUPS=()

    # =========================================
    # BUSCAR BACKUPS
    # =========================================

    while IFS= read -r -d '' dir; do
        BACKUPS+=("$dir")
    done < <(
        find "$NEXTCLOUD_DATA" \
            -mindepth 3 \
            -maxdepth 3 \
            -type d \
            -path "*/updater-*/backups/*" \
            -print0 2>/dev/null | sort -z
    )

    # =========================================
    # VALIDAR
    # =========================================

    if [ ${#BACKUPS[@]} -eq 0 ]; then

        warn "No se encontraron backups del updater."

        echo
        read -rp "Presiona ENTER para continuar..." || true

        return 1
    fi

    # =========================================
    # VERSION ACTUAL
    # =========================================

CURRENT_VERSION=$(
    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" status --output=json 2>/dev/null \
    | grep -oP '"version"\s*:\s*"\K[^"]+'
)

    # =========================================
    # HEADER
    # =========================================

    echo -e "${CYAN}=================================================${NC}"
    echo -e "${WHITE}         BACKUPS NEXTCLOUD UPDATER${NC}"
    echo -e "${CYAN}=================================================${NC}"

    echo -e "${GREEN}Versión actual:${NC} ${WHITE}${CURRENT_VERSION:-Desconocida}${NC}"

    echo

    TOTAL_SIZE=0

    # =========================================
    # MOSTRAR BACKUPS
    # =========================================

    for i in "${!BACKUPS[@]}"; do

        BACKUP="${BACKUPS[$i]}"

        NAME=$(basename "$BACKUP")

        # =========================================
        # VERSION BACKUP
        # =========================================

        VERSION="Desconocida"

        if [ -f "$BACKUP/version.php" ]; then

            VERSION=$(grep "\$OC_VersionString" \
                "$BACKUP/version.php" \
                | cut -d"'" -f2)
        fi

        # =========================================
        # SIZE
        # =========================================

        SIZE=$(du -sh "$BACKUP" 2>/dev/null | awk '{print $1}')

        SIZE_BYTES=$(du -sb "$BACKUP" 2>/dev/null | awk '{print $1}')

        TOTAL_SIZE=$((TOTAL_SIZE + SIZE_BYTES))

        # =========================================
        # FECHA
        # =========================================

        FECHA=$(stat -c '%y' "$BACKUP" \
            2>/dev/null | cut -d'.' -f1)

        # =========================================
        # ARCHIVOS
        # =========================================

        FILES=$(find "$BACKUP" -type f 2>/dev/null | wc -l)

        # =========================================
        # UPDATER
        # =========================================

        UPDATER=$(echo "$BACKUP" | grep -oP 'updater-[^/]+' || true)

        # =========================================
        # MOSTRAR INFO
        # =========================================

        echo -e "${YELLOW}$((i+1)))${NC} ${WHITE}$NAME${NC}"

        if [[ "$VERSION" == "$CURRENT_VERSION" ]]; then

            echo -e "   ${CYAN}Versión :${NC} ${GREEN}${VERSION} ✔ ACTUAL${NC}"

        else

            echo -e "   ${CYAN}Versión :${NC} ${VERSION:-?}"

        fi

        echo -e "   ${CYAN}Tamaño  :${NC} ${SIZE:-?}"
        echo -e "   ${CYAN}Fecha   :${NC} ${FECHA:-?}"
        echo -e "   ${CYAN}Archivos:${NC} $FILES"
        echo -e "   ${CYAN}Updater :${NC} ${UPDATER:-?}"
        echo -e "   ${CYAN}Ruta    :${NC} $BACKUP"

        echo
    done

    # =========================================
    # TOTAL
    # =========================================

    TOTAL_HUMAN=$(numfmt --to=iec "$TOTAL_SIZE" 2>/dev/null)

    echo -e "${CYAN}=================================================${NC}"
    echo -e "${GREEN}Total backups :${NC} ${#BACKUPS[@]}"
    echo -e "${GREEN}Espacio usado :${NC} ${TOTAL_HUMAN:-?}"
    echo -e "${CYAN}=================================================${NC}"

    echo

    return 0
}
# =========================================================
# REINSTALAR NEXTCLOUD DESDE INTERNET
# REPARA INSTALACION DAÑADA
# CONSERVA DB + DATA + CONFIG
# =========================================================

nextcloud_restore(){

    clear

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}   REINSTALAR NEXTCLOUD DESDE INTERNET${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    # =========================================================
    # VALIDAR NEXTCLOUD
    # =========================================================

    if [ ! -f "$NEXTCLOUD_DIR/version.php" ]; then

        echo -e "${RED}❌ No se encontró Nextcloud${RESET}"

        read -rp "ENTER para continuar..."
        return 1
    fi

    # =========================================================
    # DETECTAR VERSION
    # =========================================================

    echo -e "${CYAN}➜ Detectando versión instalada...${RESET}"

    VERSION_ACTUAL=$(
        grep "\$OC_VersionString" \
        "$NEXTCLOUD_DIR/version.php" \
        | cut -d"'" -f2
    )

    if [ -z "$VERSION_ACTUAL" ]; then

        VERSION_ACTUAL=$(
            sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
            status --output=json 2>/dev/null \
            | grep -oP '"version"\s*:\s*"\K[^"]+'
        )
    fi

    if [ -z "$VERSION_ACTUAL" ]; then

        echo -e "${RED}❌ No se pudo detectar la versión${RESET}"

        read -rp "ENTER para continuar..."
        return 1
    fi

    echo -e "${GREEN}✔ Versión detectada:${RESET} $VERSION_ACTUAL"
    echo

    confirmar "¿Reinstalar Nextcloud $VERSION_ACTUAL?" || return

    # =========================================================
    # OBTENER CONFIG
    # =========================================================

    DATA_DIR=$(
        sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
        config:system:get datadirectory 2>/dev/null
    )

    [ -z "$DATA_DIR" ] && DATA_DIR="/var/www/nextcloud-data"

    echo -e "${CYAN}Data directory:${RESET} $DATA_DIR"
    echo

    # =========================================================
    # MODO MANTENIMIENTO
    # =========================================================

    echo -e "${YELLOW}➜ Activando modo mantenimiento...${RESET}"

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
    maintenance:mode --on || true

    echo

    # =========================================================
    # DETENER SERVICIOS
    # =========================================================

    detener_servicios_nextcloud

    # =========================================================
    # TEMPORAL
    # =========================================================

    TMP_DIR="/tmp/nextcloud_reinstall"

    rm -rf "$TMP_DIR"

    mkdir -p "$TMP_DIR"

    cd "$TMP_DIR" || return 1

    # =========================================================
    # URLS DESCARGA
    # =========================================================

    BASE_URL="https://download.nextcloud.com/server/releases"

    ZIP_URL="$BASE_URL/nextcloud-$VERSION_ACTUAL.zip"

    TAR_URL="$BASE_URL/nextcloud-$VERSION_ACTUAL.tar.bz2"

    # =========================================================
    # DESCARGA
    # =========================================================

    echo -e "${CYAN}➜ Descargando Nextcloud $VERSION_ACTUAL...${RESET}"
    echo

    FORMATO=""

    if wget -q --spider "$ZIP_URL"; then

        echo -e "${GREEN}✔ ZIP encontrado${RESET}"

        wget -O nextcloud.zip "$ZIP_URL"

        ARCHIVO="nextcloud.zip"

        FORMATO="zip"

    else

        echo -e "${YELLOW}⚠ ZIP no disponible${RESET}"
        echo -e "${CYAN}Intentando TAR.BZ2...${RESET}"

        if wget -q --spider "$TAR_URL"; then

            echo -e "${GREEN}✔ TAR.BZ2 encontrado${RESET}"

            wget -O nextcloud.tar.bz2 "$TAR_URL"

            ARCHIVO="nextcloud.tar.bz2"

            FORMATO="tar"

        else

            echo -e "${RED}❌ No existe la versión:${RESET} $VERSION_ACTUAL"

            iniciar_servicios_nextcloud

            read -rp "ENTER para continuar..."
            return 1
        fi
    fi

    echo
    echo -e "${GREEN}✔ Descarga completada${RESET}"
    echo

    # =========================================================
    # EXTRAER
    # =========================================================

    echo -e "${CYAN}➜ Extrayendo archivos...${RESET}"

    if [ "$FORMATO" = "zip" ]; then

        unzip -q "$ARCHIVO"

    else

        tar -xjf "$ARCHIVO"

    fi

    if [ ! -d "$TMP_DIR/nextcloud" ]; then

        echo -e "${RED}❌ Error extrayendo Nextcloud${RESET}"

        iniciar_servicios_nextcloud
        return 1
    fi

    echo -e "${GREEN}✔ Archivos extraídos${RESET}"
    echo

    # =========================================================
    # BACKUP CONFIG
    # =========================================================

    echo -e "${CYAN}➜ Resguardando config.php...${RESET}"

    mkdir -p /tmp/nc_restore_backup

    cp "$NEXTCLOUD_DIR/config/config.php" \
       /tmp/nc_restore_backup/config.php.bak

    # =========================================================
    # ELIMINAR INSTALACION DAÑADA
    # =========================================================

    echo -e "${CYAN}➜ Eliminando instalación dañada...${RESET}"

    find "$NEXTCLOUD_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        ! -name "data" \
        -exec rm -rf {} +

    echo

    # =========================================================
    # COPIAR NUEVA INSTALACION
    # =========================================================

    echo -e "${CYAN}➜ Instalando nueva copia...${RESET}"

    rsync -Aax --info=progress2 \
        "$TMP_DIR/nextcloud"/ \
        "$NEXTCLOUD_DIR"/

    if [ $? != 0 ]; then

        echo -e "${RED}❌ Error copiando archivos${RESET}"

        iniciar_servicios_nextcloud
        return 1
    fi

    echo
    echo -e "${GREEN}✔ Archivos instalados${RESET}"
    echo

    # =========================================================
    # RESTAURAR CONFIG
    # =========================================================

    mkdir -p "$NEXTCLOUD_DIR/config"

    cp /tmp/nc_restore_backup/config.php.bak \
       "$NEXTCLOUD_DIR/config/config.php"

    echo -e "${GREEN}✔ Config restaurado${RESET}"
    echo

    # =========================================================
    # DATA DIRECTORY
    # =========================================================

    mkdir -p "$DATA_DIR"

    touch "$DATA_DIR/.ocdata"

    # =========================================================
    # PERMISOS
    # =========================================================

    echo -e "${CYAN}➜ Corrigiendo permisos...${RESET}"

    chown -R "$USER_WEB:$USER_WEB" "$NEXTCLOUD_DIR"

    find "$NEXTCLOUD_DIR" -type d -exec chmod 750 {} \;

    find "$NEXTCLOUD_DIR" -type f -exec chmod 640 {} \;

    chmod +x "$NEXTCLOUD_DIR/occ"

    echo

    # =========================================================
    # INICIAR SERVICIOS
    # =========================================================

    iniciar_servicios_nextcloud
# =========================================================
# UPGRADE NEXTCLOUD
# =========================================================

echo
echo -e "${YELLOW}➜ Ejecutando upgrade...${RESET}"
echo

sudo -u "$USER_WEB" php \
-d memory_limit=1G \
"$NEXTCLOUD_DIR/occ" upgrade

UPGRADE_STATUS=$?

echo

if [ "$UPGRADE_STATUS" != "0" ]; then

    echo -e "${RED}❌ Upgrade terminó con errores${RESET}"
    echo

    sudo -u "$USER_WEB" php \
    "$NEXTCLOUD_DIR/occ" maintenance:mode --off || true

    iniciar_servicios_nextcloud

    read -rp "ENTER para continuar..."
    return 1
fi

echo -e "${GREEN}✔ Upgrade completado${RESET}"
echo

    # =========================================================
    # REPARACION
    # =========================================================

    echo -e "${CYAN}➜ Reparando instalación...${RESET}"

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" maintenance:repair || true

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" db:add-missing-indices || true

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" db:add-missing-columns || true

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" db:add-missing-primary-keys || true

    echo

    # =========================================================
    # MAINTENANCE OFF
    # =========================================================

    echo -e "${CYAN}➜ Desactivando mantenimiento...${RESET}"

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
    maintenance:mode --off || true

    echo

    # =========================================================
    # LIMPIEZA
    # =========================================================

    rm -rf "$TMP_DIR"

    # =========================================================
    # VERSION FINAL
    # =========================================================

    VERSION_FINAL=$(
        sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
        status --output=json 2>/dev/null \
        | grep -oP '"version"\s*:\s*"\K[^"]+'
    )

    # =========================================================
    # FINAL
    # =========================================================

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${GREEN}✔ NEXTCLOUD REINSTALADO${RESET}"
    echo -e "${GREEN}Versión:${RESET} $VERSION_FINAL"
    echo -e "${CYAN}========================================${RESET}"

    echo

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" check || true

    echo
    read -rp "ENTER para continuar..."
}

# ========= FIN RESTORE =========

# ========= RESTORE COPIA DE SEGURIDAD FORZADO =========

restaurar_backup_forzado(){
echo -e "${YELLOW}📂 Buscando backups disponibles...${NC}"
  listar_backups_nextcloud || return

  read -rp "Selecciona la copia a restaurar (0=cancelar): " n
  [[ "$n" == "0" ]] && warn "Cancelado." && return
  [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#BACKUPS[@]} )) || { err "Número inválido."; return; }

  SELECTED_BACKUP="${BACKUPS[$((n-1))]}"
echo
echo -e "${CYAN}📦 Backup seleccionado:${NC} ${WHITE}$SELECTED_BACKUP${NC}"
  confirmar "¿Restaurar desde $SELECTED_BACKUP?" || return

echo
echo -e "${YELLOW}🔍 Verificando dependencia pv...${NC}"

  # ===== Verificar pv (sin cortar ejecución) =====
USE_PV=true

if ! command -v pv >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠ pv no está instalado. Intentando instalar...${NC}"
  
  if apt update -qq && apt install -y -qq pv; then
    echo -e "${GREEN}✔ pv instalado correctamente${NC}"
  else
    echo -e "${RED}❌ No se pudo instalar pv, continuando sin barra de progreso...${NC}"
    USE_PV=false
  fi
fi

echo -e "${YELLOW}⛔ Deteniendo servicios Nextcloud...${NC}"
  detener_servicios_nextcloud

  echo
  echo -e "${CYAN}🧹 Eliminando instalación actual...${NC}"

  # BORRADO TOTAL (fuerza bruta)
  rm -rf "$NEXTCLOUD_DIR"/*
  echo -e "${GREEN}✔ Instalación anterior eliminada${NC}"

  echo
  echo -e "${CYAN}📥 Restaurando archivos desde backup...${NC}"
  
  # ===== RESTORE CON PROGRESO (MISMA LÓGICA CP) =====
TOTAL_FILES=$(find "$SELECTED_BACKUP" -type f | wc -l)
  echo -e "${WHITE}📄 Total de archivos a restaurar:${NC} $TOTAL_FILES"
cd "$SELECTED_BACKUP" || return

find . -type f -print0 | pv -0 -l -s "$TOTAL_FILES" -w 80 \
-F "Progreso: [%b] %p%% (%c/$TOTAL_FILES archivos) ETA %t" \
| while IFS= read -r -d '' file; do
  mkdir -p "$NEXTCLOUD_DIR/$(dirname "$file")"
  cp -a "$file" "$NEXTCLOUD_DIR/$file"
done

echo

  echo
  echo -e "${YELLOW}🔐 Aplicando permisos seguros...${NC}"
  # PERMISOS

# PROPIETARIO
chown -R $USER_WEB:$USER_WEB "$NEXTCLOUD_DIR"
echo -e "${YELLOW}🔐 Aplicado Permisos Propietario...${NC}"

# PERMISOS SEGUROS
find "$NEXTCLOUD_DIR" -type d -exec chmod 750 {} \;
find "$NEXTCLOUD_DIR" -type f -exec chmod 640 {} \;
echo -e "${YELLOW}🔐 Aplicado Permisos Nextcloud chmod 750/640...${NC}"

# OCC EJECUTABLE
chmod +x "$NEXTCLOUD_DIR/occ"
echo -e "${YELLOW}🔐 Aplicado Permiso Ejecutable OCC...${NC}"

# CARPETAS QUE NEXTCLOUD NECESITA ESCRIBIR

chmod -R 770 "$NEXTCLOUD_DIR/config"
chmod -R 770 "$NEXTCLOUD_DIR/apps"
chmod -R 770 "$NEXTCLOUD_DIR/custom_apps"
chmod -R 770 "$NEXTCLOUD_DIR/updater"
echo -e "${YELLOW}🔐 Aplicado Permiso Carpetas que necesta Escribir...${NC}"
# DATA
chown -R $USER_WEB:$USER_WEB "$DATA_DIR"
find "$DATA_DIR" -type d -exec chmod 750 {} \;
find "$DATA_DIR" -type f -exec chmod 640 {} \; 
echo -e "${YELLOW}🔐 Aplicado Permisos nextcloud-data 750/640...${NC}"
echo
echo
echo -e "${GREEN}✔ Permisos aplicados${NC}"  
  
  echo
  echo -e "${YELLOW}▶ Iniciando servicios Nextcloud...${NC}"
  iniciar_servicios_nextcloud
  
  echo -e "${YELLOW}Intentando upgrade...${NC}"
  sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" upgrade 2>/dev/null
  
  echo -e "${YELLOW} Deshabilitando modo mantenimiento ${NC}"
  sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off
  
  # REPARACION BASICA
  echo -e "${YELLOW}Ejecutando reparación básica...${NC}"
  sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:repair 2>/dev/null
  
printf "\n"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}   ✔ Restauración completada correctamente  ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo
echo -e "${CYAN}📌 Presiona Enter para volver al menú...${NC}"
read

}

# ========= FIN RESTORE COPIA DE SEGURIDAD FORZADO =========

# INICIAR SERVICIOS DE Nextcloud

iniciar_servicios_nextcloud() {
    echo -e "${CYAN}Iniciando servicios de Nextcloud...${NC}"

    systemctl start apache2 2>/dev/null
    systemctl start nginx 2>/dev/null

    systemctl start php8.3-fpm 2>/dev/null
    systemctl start php8.2-fpm 2>/dev/null
    systemctl start php8.1-fpm 2>/dev/null

    echo -e "${GREEN}✔ Servicios iniciados${NC}"
}

# FIN INICIAR SERVICIOS DE Nextcloud

# DETENER SERVICIOS DE Nextcloud
detener_servicios_nextcloud() {
    echo -e "${CYAN}Deteniendo servicios de Nextcloud...${NC}"

    # Apache
    systemctl stop apache2 2>/dev/null

    # Nginx
    systemctl stop nginx 2>/dev/null

    # PHP-FPM (varias versiones posibles)
    systemctl stop php8.3-fpm 2>/dev/null
    systemctl stop php8.2-fpm 2>/dev/null
    systemctl stop php8.1-fpm 2>/dev/null

    # Cron de Nextcloud (www-data normalmente)
    crontab -u www-data -l 2>/dev/null | grep -v "cron.php" | crontab -u www-data -

    echo -e "${GREEN}✔ Servicios detenidos${NC}"
}
# FIN DETENER SERVICIOS DE Nextcloud


# ========= MENU NEXTCLOUD =========
menu_nextcloud_occ(){
  while true; do
    clear
    echo -e "${CYAN}${BOLD}=== Restaurar y Reparar Nextcloud ===${NC}"
    echo -e " ${YELLOW}1)${NC} Mantenimiento ON"
    echo -e " ${YELLOW}2)${NC} Mantenimiento OFF"
    echo -e " ${YELLOW}3)${NC} Actualizar y Repara Instalación/DB (occ upgrade)"
    echo -e " ${YELLOW}4)${NC} Actualizar apps (occ app:update --all)"
    echo -e " ${YELLOW}5)${NC} Activa/Desactivar APP API"
    echo -e " ${YELLOW}6)${NC} ${YELLOW}Restaurar Nextcloud Online ${CYAN}Seguro"
    echo -e " ${YELLOW}7)${NC} Eliminar Copias de Seguridad Antiguas"
    echo -e " ${YELLOW}8)${NC} Reparación Nextcloud Inteligente"
    echo -e " ${YELLOW}9)${NC} ${YELLOW}Actualizar Nextcloud ${CYAN} Versión Nueva (updater.phar)"
    echo -e " ${YELLOW}10)${NC} OPcache FULL PRO (optimización total PHP)"
    echo -e " ${YELLOW}11)${NC} Reparar tipos MIME (puede tardar)"
    echo -e " ${YELLOW}12)${NC} Ver Errores Nextcloud (nextcloud.log)" 
	echo -e " ${YELLOW}13)${NC} Gestión de usuarios Nextcloud "
	echo -e " ${YELLOW}14)${NC} ${YELLOW}Restaurar ${CYAN}Copias de Seguridad Old/New FORZADO/SEGURO"
	echo -e " ${YELLOW}15)${NC} Ver Estado de Nextcloud ${CYAN} / Vercion/Servicios/App"
	echo -e " ${YELLOW}16)${NC} ${GREEN}Menu Office ${CYAN} DocumentServer / Collabora Online/App"
    echo -e " ${CYAN}0) Volver${NC}"

    read -rp "> " op

# ===== FUNCIONES AVANCE PRO =====

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null 2>&1; do
        printf " [%c]  " "$spinstr"
        spinstr=${spinstr#?}${spinstr%"${spinstr#?}"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "      \b\b\b\b\b\b"
}

run_live() {
    local MSG="$1"
    shift

    echo -e "${CYAN}${MSG}${NC}"

    START=$(date +%s)

    "$@" 2>&1 | while IFS= read -r line; do
        echo -e "  ${YELLOW}➜${NC} $line"
    done

    STATUS=${PIPESTATUS[0]}
    END=$(date +%s)

    if [[ $STATUS -eq 0 ]]; then
        echo -e "${GREEN}✔ Completado en $((END-START))s${NC}"
        return 0
    else
        echo -e "${RED}✘ Error en: $MSG${NC}"
        return 1
    fi
}
# CIERRE FUNCION AVANCE
    case "$op" in
      1) sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --on; pausa ;;
      2) sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --off; pausa ;;

      3)
        sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --on
        sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" upgrade
        autoreparacion_nc
      ;;

      4)
        sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --on
        sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:update --all
        sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" upgrade
        autoreparacion_nc
      ;;

      5) gestionar_appapi_nct ;;

      6) nextcloud_restore ;;

      7) nextcloud_delete_backups ;;

      8)
        sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --on
        autoreparacion_nc
      ;;


      9)
    echo -e "${CYAN}Buscando nueva versión de Nextcloud...${NC}"

    VERSION_ACTUAL=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" status --output=json | grep -oP '"version":\s*"\K[^"]+')
    echo -e "Versión actual: ${YELLOW}$VERSION_ACTUAL${NC}"

    CHECK=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" update:check)
    echo "$CHECK"

    NUEVA_VERSION=$(echo "$CHECK" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)

    if [[ -z "$NUEVA_VERSION" || "$NUEVA_VERSION" == "$VERSION_ACTUAL" ]]; then
        warn "No hay nueva versión disponible"
        pausa
        break
    fi

    echo -e "${GREEN}Nueva versión detectada: $NUEVA_VERSION${NC}"
    confirmar "¿Actualizar de $VERSION_ACTUAL a $NUEVA_VERSION?" || break

    # ===== BACKUP Base de Datos en /root/BackupDB =====
    echo -e "${CYAN}Realizando backup de base de datos...${NC}"
    DB_BACKUP=$(backup_db_nc) || { err "Error backup DB"; break; }
    echo -e "${GREEN}✔ Backup listo: $DB_BACKUP${NC}"

    # ===== MODO MANTENIMIENTO =====
    run_live "Activando modo mantenimiento" \
        sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --on || break

    # ===== UPDATER =====
    run_live "Ejecutando updater oficial (descarga + instalación)" \
        sudo -u $USER_WEB php "$NEXTCLOUD_DIR/updater/updater.phar" --no-interaction || {
            err "Error en actualización → rollback"
            restore_db_nc "$DB_BACKUP"
            sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --off
            break
    }

    # ===== UPGRADE =====
    run_live "Aplicando upgrade de base de datos" \
        sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" upgrade || {
            err "Error en upgrade → rollback"
            restore_db_nc "$DB_BACKUP"
            sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --off
            break
    }

    # ===== REPARACIÓN =====
    run_live "Ejecutando autoreparación" autoreparacion_nc

    # ===== SALIDA =====
    run_live "Desactivando modo mantenimiento" \
        sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --off

    echo -e "${GREEN}✔ Nextcloud actualizado correctamente${NC}"

         ;;

10)
    opcache_full_pro_nc
    ;;

      11) reparar_mime_nc ;;

      12) ver_errores_nc ;;
	  
	  13) menu_usuarios_nextcloud ;;
      
	  14) restaurar_backup_forzado ;;
	  
	  15) status_services ;;
	   
	  16) menu_office_app ;;
      
	  0) return ;;

      *) warn "Opción inválida"; pausa ;;
    esac
  done
}

# Menu CONFIGURACIÓN APACHE / NEXTCLOUD #
menu_config_nextcloud(){
  while true; do
    clear
    echo -e "${CYAN}${BOLD}=== CONFIGURACIÓN APACHE / NEXTCLOUD v24.3.2 ===${NC}"
    echo -e " ${YELLOW}1)${NC} Editar VirtualHost Apache"
    echo -e " ${YELLOW}2)${NC} Editar config.php de Nextcloud"
    echo -e " ${YELLOW}3)${NC} Verificar configuración de Apache"
    echo -e " ${YELLOW}4)${NC} Habilitar VirtualHost"
    echo -e " ${YELLOW}5)${NC} Deshabilitar VirtualHost"
    echo -e " ${YELLOW}6)${NC} Editar puertos Apache (ports.conf)"
    echo -e " ${YELLOW}7)${NC} Crear VirtualHost Genérico / Reverse Proxy"
    echo -e " ${YELLOW}8)${NC} Eliminar VirtualHost"
    echo -e " ${YELLOW}9)${NC} Listar VirtualHosts"
    echo -e " ${CYAN}0) Volver${NC}"
    echo

    read -rp "> " op

    case "$op" in

      1)
        echo "=== Editar VirtualHost Apache ==="
        echo

        mapfile -t FILES < <(find "$APACHE_SITES" -maxdepth 1 -name "*.conf")

        if [ ${#FILES[@]} -eq 0 ]; then
            warn "No se encontraron VirtualHosts."
            pausa
            continue
        fi

        echo "0) Volver"

        select f in "${FILES[@]}"; do
            [[ "$REPLY" == "0" ]] && break

            if [ -n "$f" ]; then
                sudo "$EDITOR_BIN" "$f"

                echo
                echo "Validando configuración Apache..."

                if apachectl configtest; then
                    sudo systemctl reload apache2
                    ok "Apache recargado correctamente"
                else
                    warn "Error en configuración Apache. No se recargó."
                fi
                break
            else
                warn "Selección inválida"
            fi
        done
        pausa
      ;;

      2)
        sudo "$EDITOR_BIN" "$NEXTCLOUD_DIR/config/config.php"
        pausa
      ;;

      3)
        sudo apache2ctl -t
        pausa
      ;;

      4)
        mapfile -t FILES < <(find "$APACHE_SITES" -maxdepth 1 -name "*.conf" -printf "%f\n")

        if [ ${#FILES[@]} -eq 0 ]; then
          warn "No hay VirtualHosts disponibles."
          pausa
          continue
        fi

        echo "0) Volver"

        select sitio in "${FILES[@]}"; do
          [[ "$REPLY" == "0" ]] && break

          if [ -n "$sitio" ]; then
            sudo a2ensite "$sitio"
            sudo systemctl reload apache2
            ok "Sitio $sitio habilitado."
            break
          else
            warn "Selección inválida"
          fi
        done
        pausa
      ;;

      5)
        mapfile -t FILES < <(find "$APACHE_SITES" -maxdepth 1 -name "*.conf" -printf "%f\n")

        if [ ${#FILES[@]} -eq 0 ]; then
          warn "No hay VirtualHosts disponibles."
          pausa
          continue
        fi

        echo "0) Volver"

        select sitio in "${FILES[@]}"; do
          [[ "$REPLY" == "0" ]] && break

          if [ -n "$sitio" ]; then
            sudo a2dissite "$sitio"
            sudo systemctl reload apache2
            ok "Sitio $sitio deshabilitado."
            break
          else
            warn "Selección inválida"
          fi
        done
        pausa
      ;;

      6)
        sudo "$EDITOR_BIN" /etc/apache2/ports.conf
        pausa
      ;;
# Crear Vhost #
7)

read -rp "Nombre del VirtualHost (ej: ejemplo.conf): " vhost
read -rp "Dominio / ServerName: " dominio

puerto_http="80"
puerto_https="443"

crear_http=false
crear_https=false
forzar_https=false

########################################
# PROTOCOLO
########################################

echo
echo "Protocolo del VirtualHost:"
echo "1) HTTP (:80)"
echo "2) HTTPS (:443)"
echo "3) HTTP + HTTPS"
echo "4) Manual (ingresar puertos personalizados)"
echo "0) Volver"

read -rp "> " proto_vhost

case "$proto_vhost" in
    0)
        continue
    ;;
    1)
        crear_http=true
        crear_https=false
    ;;
    2)
        crear_http=false
        crear_https=true
    ;;
    3)
        crear_http=true
        crear_https=true
    ;;
    4)
        read -rp "Puerto HTTP personalizado [8080]: " puerto_http
        puerto_http="${puerto_http:-8080}"

        read -rp "Puerto HTTPS personalizado [4443]: " puerto_https
        puerto_https="${puerto_https:-4443}"

        crear_http=true
        crear_https=true
    ;;
    *)
        warn "Opción inválida"
        pausa
        continue
    ;;
esac

########################################
# REDIRECCIÓN HTTPS
########################################

if [ "$crear_http" = true ] && [ "$crear_https" = true ]; then
    echo
    echo "¿Forzar redirección HTTP → HTTPS?"
    echo "1) Sí"
    echo "2) No"
    echo "0) Volver"

    read -rp "> " redir_https

    case "$redir_https" in
        1)
            forzar_https=true
        ;;
        2)
            forzar_https=false
        ;;
        0)
            continue
        ;;
        *)
            warn "Opción inválida"
            pausa
            continue
        ;;
    esac
fi

########################################
# SSL
########################################

cert_file=""
cert_key=""

if [ "$crear_https" = true ]; then
    echo
    echo "Tipo de certificado SSL:"
    echo "1) Let's Encrypt"
    echo "2) TurnKey Linux"
    echo "3) Snakeoil"
    echo "4) Ruta personalizada"
    echo "0) Volver"

    read -rp "> " ssl_tipo

    case "$ssl_tipo" in
        1)
            cert_file="/etc/letsencrypt/live/$dominio/fullchain.pem"
            cert_key="/etc/letsencrypt/live/$dominio/privkey.pem"
        ;;
        2)
            cert_file="/etc/ssl/private/cert.pem"
            cert_key="/etc/ssl/private/cert.key"
        ;;
        3)
            cert_file="/etc/ssl/certs/ssl-cert-snakeoil.pem"
            cert_key="/etc/ssl/private/ssl-cert-snakeoil.key"
        ;;
        4)
            read -rp "Ruta certificado (.crt/.pem): " cert_file
            read -rp "Ruta clave privada (.key): " cert_key
        ;;
        0)
            continue
        ;;
        *)
            warn "Opción inválida"
            pausa
            continue
        ;;
    esac
fi

########################################
# TIPO VHOST
########################################

echo
echo "Tipo de VirtualHost:"
echo "1) Sitio web normal"
echo "2) Reverse Proxy"
echo "3) Alias"
echo "0) Volver"

read -rp "> " tipo

conf=""

case "$tipo" in

########################################
# SITIO WEB
########################################
1)

    read -rp "Ruta DocumentRoot: " docroot

    sudo mkdir -p "$docroot"
    sudo chown -R "$USER_WEB:$USER_WEB" "$docroot"

    if [ "$crear_http" = true ]; then
        if [ "$forzar_https" = true ]; then
conf+="
<VirtualHost *:$puerto_http>
    ServerName $dominio
    Redirect permanent / https://$dominio/
</VirtualHost>

"
        else
conf+="
<VirtualHost *:$puerto_http>
    ServerName $dominio
    DocumentRoot $docroot

    <Directory $docroot>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

"
        fi
    fi

    if [ "$crear_https" = true ]; then
        sudo a2enmod ssl >/dev/null 2>&1

conf+="
<VirtualHost *:$puerto_https>
    ServerName $dominio
    DocumentRoot $docroot

    SSLEngine on
    SSLCertificateFile $cert_file
    SSLCertificateKeyFile $cert_key

    <Directory $docroot>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

"
    fi
;;

########################################
# REVERSE PROXY
########################################
2)

    read -rp "IP backend [127.0.0.1]: " backend_ip
    backend_ip="${backend_ip:-127.0.0.1}"

    echo
    echo "Protocolo backend:"
    echo "1) HTTP"
    echo "2) HTTPS"
    echo "0) Volver"
    read -rp "> " backend_proto_sel

    case "$backend_proto_sel" in
        1)
            backend_proto="http"
            default_port="80"
        ;;
        2)
            backend_proto="https"
            default_port="443"
        ;;
        0)
            continue
        ;;
        *)
            warn "Opción inválida"
            pausa
            continue
        ;;
    esac

    read -rp "Puerto backend [$default_port]: " backend_port
    backend_port="${backend_port:-$default_port}"

    sudo a2enmod proxy proxy_http proxy_ssl headers rewrite >/dev/null 2>&1

    if [ "$crear_http" = true ]; then
        if [ "$forzar_https" = true ]; then
conf+="
<VirtualHost *:$puerto_http>
    ServerName $dominio
    Redirect permanent / https://$dominio/
</VirtualHost>

"
        else
conf+="
<VirtualHost *:$puerto_http>
    ServerName $dominio
    ProxyPreserveHost On
    ProxyPass / ${backend_proto}://$backend_ip:$backend_port/
    ProxyPassReverse / ${backend_proto}://$backend_ip:$backend_port/
</VirtualHost>

"
        fi
    fi

    if [ "$crear_https" = true ]; then
        sudo a2enmod ssl >/dev/null 2>&1

conf+="
<VirtualHost *:$puerto_https>
    ServerName $dominio

    SSLEngine on
    SSLCertificateFile $cert_file
    SSLCertificateKeyFile $cert_key

    ProxyPreserveHost On
    ProxyPass / ${backend_proto}://$backend_ip:$backend_port/
    ProxyPassReverse / ${backend_proto}://$backend_ip:$backend_port/
</VirtualHost>

"
    fi
;;

########################################
# ALIAS
########################################
3)

    read -rp "Ruta real del directorio: " docroot
    read -rp "Alias (ej: /zabbix): " alias

conf+="
<VirtualHost *:$puerto_http>
    ServerName $dominio

    Alias $alias $docroot

    <Directory $docroot>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
"
;;

0)
continue
;;
*)
warn "Opción inválida"
pausa
continue
;;
esac

echo "$conf" | sudo tee "$APACHE_SITES/$vhost" >/dev/null
sudo a2ensite "$vhost" >/dev/null 2>&1

if sudo apachectl configtest; then
    sudo systemctl reload apache2
    ok "VirtualHost creado correctamente."
else
    warn "Error en configuración Apache"
    sudo apachectl configtest
fi

pausa
;;

# Crear Vhost #
      8)
        mapfile -t FILES < <(find "$APACHE_SITES" -maxdepth 1 -name "*.conf" -printf "%f\n")

        if [ ${#FILES[@]} -eq 0 ]; then
          warn "No hay VirtualHosts para eliminar."
          pausa
          continue
        fi

        echo "0) Volver"

        select vhost in "${FILES[@]}"; do
          [[ "$REPLY" == "0" ]] && break

          if [ -n "$vhost" ]; then
            sudo a2dissite "$vhost" 2>/dev/null
            sudo rm -f "$APACHE_SITES/$vhost"
            sudo systemctl reload apache2
            ok "VirtualHost $vhost eliminado."
            break
          else
            warn "Selección inválida"
          fi
        done
        pausa
      ;;

      9)
        echo
        echo "=========== VIRTUALHOSTS ==========="
        echo

        encontrados=0

        for f in "$APACHE_SITES"/*.conf; do
          [ -e "$f" ] || continue

          encontrados=1
          sitio=$(basename "$f")

          if [ -L "/etc/apache2/sites-enabled/$sitio" ]; then
            estado="${GREEN}ACTIVO${NC}"
          else
            estado="${RED}DESACTIVADO${NC}"
          fi

          echo -e "• $sitio → $estado"
        done

        if [ "$encontrados" = "0" ]; then
          warn "No se encontraron VirtualHosts."
        fi

        echo
        pausa
      ;;

      0)
        return
      ;;

      *)
        warn "Opción inválida"
        pausa
      ;;

    esac
  done
}
# Menu CONFIGURACIÓN APACHE / NEXTCLOUD #

# ========= Ajustes de Red =========
menu_red(){
  while true; do
    clear
    echo -e "${CYAN}${BOLD}=== AJUSTES DE RED ===${NC}"
    echo -e " ${YELLOW}1)${NC} Editar configuración de red (/etc/network/interfaces)"
    echo -e " ${YELLOW}2)${NC} Reiniciar servicio de red"
    echo -e " ${YELLOW}3)${NC} Abrir puerto en firewall (iptables)"
    echo -e " ${CYAN}0) Volver${NC}"
    read -rp "> " op
    case "$op" in
      1) sudo $EDITOR_BIN /etc/network/interfaces; pausa ;;
      2) sudo systemctl restart networking && ok "Servicio de red reiniciado." || err "Error al reiniciar red."; pausa ;;
      3) read -rp "Número de puerto a permitir: " p; sudo iptables -A INPUT -p tcp --dport "$p" -j ACCEPT && ok "Puerto $p permitido." || err "Error al abrir puerto."; pausa ;;
      0) return ;;
      *) warn "Opción inválida"; pausa ;;
    esac
  done
}

# ========= Gestión de Utilidades =========
menu_instala_utilidades(){
  while true; do
    clear
    echo -e "${CYAN}${BOLD}=== GESTIÓN DE UTILIDADES ===${NC}"
    echo -e " ${YELLOW}1)${NC} Instalar servidor web (Apache)"
    echo -e " ${YELLOW}2)${NC} Instalar base de datos (MariaDB)"
    echo -e " ${YELLOW}3)${NC} Instalar PHP"
	echo -e " ${YELLOW}4)${NC} Actualizar PHP 8.2 → 8.3"
	echo -e " ${YELLOW}5)${NC} Ajustar memoria PHP (Nextcloud)"
    echo -e " ${YELLOW}6)${NC} Instalar SSH Server"
    echo -e " ${YELLOW}7)${NC} Instalar SSH Client"
    echo -e " ${YELLOW}8)${NC} Configurar SSH"
    echo -e " ${YELLOW}9)${NC} Instalar utilidades recomendadas (UFW, Fail2Ban, Git, Curl, Htop)"
    echo -e " ${CYAN}0) Volver${NC}"
    read -rp "> " op
    case "$op" in
      1) instalar_paquete_utilidades "Servidor Web Apache" "apache2"; pausa ;;
      2) instalar_paquete_utilidades "MariaDB" "mariadb-server"; pausa ;;
      3) instalar_paquete_utilidades "PHP" "php libapache2-mod-php php-mysql"; pausa ;;
	  4) actualizar_php_83 "Actualizar PHP 8.2 → 8.3"; pausa ;;
	  5) ajustar_memoria_php "Ajustar memoria PHP (Nextcloud"; pausa ;;
      6) instalar_paquete_utilidades "SSH Server" "openssh-server"; pausa ;;
      7) instalar_paquete_utilidades "SSH Client" "openssh-client"; pausa ;;
      8) configurar_ssh_utilidades ;;
      9) instalar_utilidades_recomendadas ;;
      0) return ;;
      *) warn "Opción inválida"; pausa ;;
    esac
  done
}

instalar_paquete_utilidades(){
  local nombre="$1"
  local paquetes="$2"
  echo -e "${CYAN}Instalando $nombre...${NC}"
  sudo apt-get update -y && sudo apt-get install -y $paquetes
  if [ $? -eq 0 ]; then
    ok "$nombre instalado correctamente."
  else
    err "Error instalando $nombre."
  fi
}

configurar_ssh_utilidades(){
  while true; do
    clear
    echo -e "${CYAN}${BOLD}=== CONFIGURACIÓN SSH ===${NC}"
    echo -e " ${YELLOW}1)${NC} Permitir root login por SSH"
    echo -e " ${YELLOW}2)${NC} Restablecer contraseña de un usuario"
    echo -e " ${CYAN}0) Volver${NC}"
    read -rp "> " op
    case "$op" in
      1)
        sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
        sudo systemctl restart ssh
        ok "Acceso root habilitado por SSH."
        pausa
        ;;
      2)
        read -rp "Ingrese el usuario: " usuario
        sudo passwd "$usuario"
        pausa
        ;;
      0) return ;;
      *) warn "Opción inválida"; pausa ;;
    esac
  done
}

instalar_utilidades_recomendadas(){
  echo -e "${CYAN}Instalando utilidades recomendadas...${NC}"
  instalar_paquete_utilidades "UFW" "ufw"
  instalar_paquete_utilidades "Fail2Ban" "fail2ban"
  instalar_paquete_utilidades "Git" "git"
  instalar_paquete_utilidades "Curl" "curl"
  instalar_paquete_utilidades "Htop" "htop"
  ok "Todas las utilidades recomendadas han sido instaladas."
}

# ========= Ajustes SAMBA =========
menu_samba(){
  while true; do
    clear
    echo -e "${CYAN}${BOLD}=== AJUSTES SAMBA ===${NC}"
    echo
    echo -e " ${YELLOW}1)${NC} Instalar Samba"
    echo -e " ${YELLOW}2)${NC} Crear carpeta compartida sin credenciales"
    echo -e " ${YELLOW}3)${NC} Reiniciar Samba"
    echo -e " ${YELLOW}4)${NC} Ver estado Samba"
    echo -e " ${YELLOW}5)${NC} Editar configuración Samba"
	echo -e " ${YELLOW}6)${NC} Desactivar carpeta compartida"
    echo -e " ${CYAN}0)${NC} Volver"
    echo

    read -rp "> " op

    case "$op" in

      1)
        apt update &&
        apt install -y samba samba-common-bin &&
        systemctl enable smbd --now &&
        ok "Samba instalado correctamente." ||
        err "Error instalando Samba."
        pausa
        ;;

      2)
        read -rp "Ruta carpeta (default /srv/samba/public): " carpeta
        carpeta="${carpeta:-/srv/samba/public}"

        mkdir -p "$carpeta"

        chown -R nobody:nogroup "$carpeta"
        chmod -R 775 "$carpeta"

        cp /etc/samba/smb.conf /etc/samba/smb.conf.backup.$(date +%F-%H%M)

        if ! grep -q "^\[Public\]" /etc/samba/smb.conf; then

cat >> /etc/samba/smb.conf <<EOF

[Public]
   path = $carpeta
   browseable = yes
   writable = yes
   guest ok = yes
   read only = no
   force user = nobody
   force group = nogroup
EOF

        fi

        testparm

        systemctl restart smbd

        ok "Compartición creada: $carpeta"
        pausa
        ;;

      3)
        systemctl restart smbd
        ok "Samba reiniciado."
        pausa
        ;;

      4)
        systemctl status smbd --no-pager
        pausa
        ;;

      5)
        nano /etc/samba/smb.conf
        systemctl restart smbd
        pausa
        ;;
      6)
        cp /etc/samba/smb.conf /etc/samba/smb.conf.backup.$(date +%F-%H%M)

        if grep -q "^\[Public\]" /etc/samba/smb.conf; then

          sed -i '/^\[Public\]/,/^$/ s/^/#/' /etc/samba/smb.conf

          systemctl restart smbd

          ok "Carpeta compartida Public desactivada."
        else
          warn "No se encontró la compartición Public."
        fi

        pausa
        ;;
      0)
        return
        ;;

      *)
        warn "Opción inválida"
        pausa
        ;;

    esac
  done
}

actualizar_php_83(){

  echo -e "${CYAN}=== ACTUALIZACIÓN PHP 8.2 → 8.3 (NEXTCLOUD SAFE) ===${NC}"

  NC_PATH="/var/www/nextcloud"
  NC_USER="www-data"
  MODO_MANTENIMIENTO=0

  # ===== DETECTAR NEXTCLOUD =====
  if [ -f "$NC_PATH/occ" ]; then
    echo -e "${CYAN}Nextcloud detectado, activando modo mantenimiento...${NC}"
    sudo -u $NC_USER php "$NC_PATH/occ" maintenance:mode --on && MODO_MANTENIMIENTO=1
  else
    echo -e "${YELLOW}Nextcloud no detectado, continuando sin modo mantenimiento...${NC}"
  fi

  # ===== VERIFICAR PHP ACTUAL =====
  PHP_ACTUAL=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
  echo -e "${CYAN}Versión actual de PHP: ${PHP_ACTUAL}${NC}"

  if [[ "$PHP_ACTUAL" == "8.3" ]]; then
    warn "Ya estás usando PHP 8.3"
    [ $MODO_MANTENIMIENTO -eq 1 ] && sudo -u $NC_USER php "$NC_PATH/occ" maintenance:mode --off
    pausa
    return
  fi

  # ===== REPO SURY =====
  if [ ! -f /etc/apt/sources.list.d/php.list ]; then
    echo -e "${CYAN}Agregando repositorio Sury...${NC}"

    sudo apt-get update -y
    sudo apt-get install -y apt-transport-https lsb-release ca-certificates curl

    sudo curl -sSLo /usr/share/keyrings/php.gpg https://packages.sury.org/php/apt.gpg

    echo "deb [signed-by=/usr/share/keyrings/php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" | \
    sudo tee /etc/apt/sources.list.d/php.list
  else
    echo -e "${YELLOW}Repositorio PHP ya existe${NC}"
  fi

  sudo apt-get update -y

  # ===== INSTALAR PHP 8.3 =====
  echo -e "${CYAN}Instalando PHP 8.3 y módulos...${NC}"

  sudo apt-get install -y php8.3 php8.3-cli php8.3-common \
  php8.3-mysql php8.3-xml php8.3-gd php8.3-curl php8.3-zip \
  php8.3-mbstring php8.3-intl php8.3-bcmath php8.3-gmp php8.3-imagick \
  php8.3-apcu php8.3-redis \
  libapache2-mod-php8.3

  if [ $? -ne 0 ]; then
    err "Error instalando PHP 8.3"
    [ $MODO_MANTENIMIENTO -eq 1 ] && sudo -u $NC_USER php "$NC_PATH/occ" maintenance:mode --off
    pausa
    return
  fi

  # ===== CAMBIAR APACHE =====
  echo -e "${CYAN}Configurando Apache...${NC}"

  sudo a2dismod php8.2 2>/dev/null
  sudo a2enmod php8.3
  sudo systemctl restart apache2

  # ===== CAMBIAR CLI =====
  echo -e "${CYAN}Configurando PHP CLI...${NC}"
  sudo update-alternatives --set php /usr/bin/php8.3 2>/dev/null

  # ===== VERIFICAR NEXTCLOUD =====
  if [ -f "$NC_PATH/occ" ]; then
    echo -e "${CYAN}Verificando Nextcloud...${NC}"
    sudo -u $NC_USER php "$NC_PATH/occ" status
  fi

  # ===== DESACTIVAR MANTENIMIENTO =====
  if [ $MODO_MANTENIMIENTO -eq 1 ]; then
    echo -e "${CYAN}Desactivando modo mantenimiento...${NC}"
    sudo -u $NC_USER php "$NC_PATH/occ" maintenance:mode --off
  fi

  # ===== RESULTADO FINAL =====
  VERSION=$(php -v | head -n 1)

  ok "PHP actualizado correctamente"
  echo -e "${GREEN}$VERSION${NC}"

  pausa
}
ajustar_memoria_php(){

  while true; do
    clear
    echo -e "${CYAN}${BOLD}=== AJUSTAR MEMORIA PHP ===${NC}"
    echo -e " ${YELLOW}1)${NC} 512 MB (recomendado mínimo Nextcloud)"
    echo -e " ${YELLOW}2)${NC} 1024 MB (1 GB - recomendado)"
    echo -e " ${CYAN}0) Volver${NC}"
    read -rp "> " op

    case "$op" in
      1) MEM="512M" ;;
      2) MEM="1024M" ;;
      0) return ;;
      *) warn "Opción inválida"; pausa; continue ;;
    esac

    echo -e "${CYAN}Aplicando memory_limit = $MEM...${NC}"

    # Detectar versiones instaladas
    PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")

    # Archivos php.ini
    APACHE_INI="/etc/php/$PHP_VERSION/apache2/php.ini"
    CLI_INI="/etc/php/$PHP_VERSION/cli/php.ini"

    # Cambiar configuración
    if [ -f "$APACHE_INI" ]; then
      sudo sed -i "s/^memory_limit = .*/memory_limit = $MEM/" "$APACHE_INI"
    fi

    if [ -f "$CLI_INI" ]; then
      sudo sed -i "s/^memory_limit = .*/memory_limit = $MEM/" "$CLI_INI"
    fi

    # Reiniciar servicios
    sudo systemctl restart apache2 2>/dev/null

    # Verificación
    NUEVO=$(php -i | grep memory_limit | head -n 1)

    ok "Memoria PHP actualizada correctamente"
    echo -e "${GREEN}$NUEVO${NC}"

    pausa
    return
  done
}

# ========= Gestión Adminer/Webmin =========
menu_adminer_webmin(){
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== GESTIÓN ADMINER / WEBMIN ===${NC}"
    echo -e " ${YELLOW}1)${NC} Activar Adminer"
    echo -e " ${YELLOW}2)${NC} Desactivar Adminer"
    echo -e " ${YELLOW}3)${NC} Activar Webmin"
    echo -e " ${YELLOW}4)${NC} Desactivar Webmin"
    echo -e " ${YELLOW}5)${NC} Ver estado"
    echo -e " ${CYAN}0)${NC} Volver"
    
    read -rp "> " opt
    case "$opt" in
      1)
        ok "Activando Adminer..."
        sudo a2ensite adminer.conf >/dev/null 2>&1
        sudo systemctl reload apache2
        ok "Adminer activado (puerto 12322)"
        pausa
        ;;
      2)
        warn "Desactivando Adminer..."
        sudo a2dissite adminer.conf >/dev/null 2>&1
        sudo systemctl reload apache2
        ok "Adminer desactivado"
        pausa
        ;;
      3)
        ok "Activando Webmin..."
        sudo systemctl start webmin
        sudo systemctl enable webmin >/dev/null
        ok "Webmin activado (puerto 10000)"
        pausa
        ;;
      4)
        warn "Desactivando Webmin..."
        sudo systemctl stop webmin
        sudo systemctl disable webmin >/dev/null
        ok "Webmin desactivado"
        pausa
        ;;
      5)
        echo -e "${CYAN}Estado actual:${NC}"
        
        # Estado Adminer
        if [ -L /etc/apache2/sites-enabled/adminer.conf ]; then
          echo -e " ${GREEN}✅${NC} Adminer: ACTIVADO (puerto 12322)"
        else
          echo -e " ${RED}❌${NC} Adminer: DESACTIVADO"
        fi
        
        # Estado Webmin
        if systemctl is-active --quiet webmin; then
          echo -e " ${GREEN}✅${NC} Webmin: ACTIVADO (puerto 10000)"
        else
          echo -e " ${RED}❌${NC} Webmin: DESACTIVADO"
        fi
        pausa
        ;;
      0) return ;;
      *) warn "Opción inválida"; pausa ;;
    esac
  done
}

# ===== MÓDULO DUCKDNS PRO ULTRA =====
menu_duckdns(){

# ===== COLORES =====
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
BOLD="\e[1m"
NC="\e[0m"

DUCK_DIR="$HOME/duckdns"

ok(){ echo -e "${GREEN}✔ $1${NC}"; }
warn(){ echo -e "${YELLOW}⚠ $1${NC}"; }
err(){ echo -e "${RED}✖ $1${NC}"; }
pausa(){ read -p "Presiona Enter para continuar..." ; }

# ===== IP PUBLICA =====
ver_ip(){
  clear
  echo -e "${BOLD}=== IP PÚBLICA ===${NC}\n"
  curl -s ifconfig.me
  echo ""
  pausa
}

# ===== LISTA BASE =====
listar_base(){
  FILES=($DUCK_DIR/duck_*.sh)

  if [ ! -e "${FILES[0]}" ]; then
    warn "No hay configuraciones"
    return 1
  fi

  i=1
  for f in "${FILES[@]}"; do
    NAME=$(basename "$f" | sed 's/duck_//;s/.sh//')
    DOMAIN=$(grep domains "$f" | cut -d= -f2 | cut -d'&' -f1)

    if crontab -l 2>/dev/null | grep -q "duckdns-$NAME"; then
      if crontab -l 2>/dev/null | grep "duckdns-$NAME" | grep -q "^#"; then
        STATUS="${YELLOW}OFF${NC}"
      else
        STATUS="${GREEN}ON${NC}"
      fi
    else
      STATUS="${RED}SIN CRON${NC}"
    fi

    DNS=$(getent hosts "$DOMAIN.duckdns.org" | awk '{print $1}')

    echo -e "$i) $NAME -> $STATUS | $DOMAIN.duckdns.org -> ${CYAN}${DNS:-NO RESUELVE}${NC}"
    ((i++))
  done

  return 0
}

# ===== CREAR =====
crear_duckdns(){
  clear
  echo -e "${BOLD}${CYAN}=== NUEVA CONFIGURACIÓN ===${NC}"

  read -p "Nombre: " NAME
  read -p "Dominio: " DOMAIN
  read -p "Token: " TOKEN

  SCRIPT="$DUCK_DIR/duck_${NAME}.sh"
  LOG="$DUCK_DIR/duck_${NAME}.log"

  if [ -f "$SCRIPT" ]; then
    err "Ya existe"
    pausa
    return
  fi

  mkdir -p "$DUCK_DIR"

  cat <<EOF > "$SCRIPT"
#!/bin/bash
echo url="https://www.duckdns.org/update?domains=${DOMAIN}&token=${TOKEN}&ip=" | curl -k -o ${LOG} -K -
EOF

  chmod 700 "$SCRIPT"

  (crontab -l 2>/dev/null; echo "*/5 * * * * $SCRIPT >/dev/null 2>&1 # duckdns-$NAME") | crontab -

  ok "Configuración creada"

  # ejecución inmediata
  bash "$SCRIPT"
  sleep 1

  if grep -q "OK" "$LOG"; then
    ok "Primera ejecución OK"
  else
    err "Falló"
    cat "$LOG"
  fi

  pausa
}

# ===== SELECCIONAR =====
seleccionar_script(){
  listar_base || return 1
  echo ""
  read -p "Selecciona número: " op

  FILES=($DUCK_DIR/duck_*.sh)
  INDEX=$((op-1))
  SCRIPT="${FILES[$INDEX]}"

  if [ ! -f "$SCRIPT" ]; then
    err "Opción inválida"
    return 1
  fi

  NAME=$(basename "$SCRIPT" | sed 's/duck_//;s/.sh//')
  return 0
}

# ===== PROBAR UNO =====
probar_uno(){
  clear
  echo -e "${BOLD}=== PROBAR CONFIGURACIÓN ===${NC}\n"

  seleccionar_script || { pausa; return; }

  bash "$SCRIPT"
  sleep 1

  cat "$DUCK_DIR/duck_${NAME}.log"

  pausa
}

# ===== PROBAR TODOS =====
probar_todos(){
  clear
  echo -e "${BOLD}=== PROBANDO TODOS ===${NC}\n"

  FILES=($DUCK_DIR/duck_*.sh)

  for f in "${FILES[@]}"; do
    NAME=$(basename "$f" | sed 's/duck_//;s/.sh//')
    LOG="$DUCK_DIR/duck_${NAME}.log"

    echo -e "${CYAN}>>> $NAME${NC}"
    bash "$f"
    sleep 1

    if grep -q "OK" "$LOG"; then
      ok "OK"
    else
      err "FAIL"
    fi
    echo ""
  done

  pausa
}

# ===== EDITAR =====
editar_duckdns(){
  clear
  echo -e "${BOLD}=== EDITAR SCRIPT ===${NC}\n"
  seleccionar_script || { pausa; return; }
  nano "$SCRIPT"
}

# ===== ACTIVAR =====
activar_duckdns(){
  clear
  seleccionar_script || { pausa; return; }
  crontab -l 2>/dev/null | sed "s/^#\(.*duckdns-$NAME\)/\1/" | crontab -
  ok "Activado"
  pausa
}

# ===== DESACTIVAR =====
desactivar_duckdns(){
  clear
  seleccionar_script || { pausa; return; }
  crontab -l 2>/dev/null | sed "s/^\(.*duckdns-$NAME\)/#\1/" | crontab -
  warn "Desactivado"
  pausa
}

# ===== VER LOG =====
ver_log(){
  clear
  seleccionar_script || { pausa; return; }
  cat "$DUCK_DIR/duck_${NAME}.log"
  pausa
}

# ===== ELIMINAR =====
eliminar_duckdns(){
  clear
  seleccionar_script || { pausa; return; }
  crontab -l 2>/dev/null | grep -v "duckdns-$NAME" | crontab -
  rm -f "$SCRIPT" "$DUCK_DIR/duck_${NAME}.log"
  ok "Eliminado"
  pausa
}

# ===== EDITAR CRON DUCKDNS =====
editar_cron(){
  echo -e "${CYAN}Abriendo crontab con nano...${RESET}"
  EDITOR=nano crontab -e
}

# ===== MENÚ =====
while true; do
  clear
  echo -e "${BOLD}${CYAN}=== DUCKDNS PRO ULTRA MAX ===${NC}"
  echo -e " ${YELLOW}1)${NC} Crear Actualizacion Dinamica DuckDns"
  echo -e " ${YELLOW}2)${NC} Listar estado + DNS"
  echo -e " ${YELLOW}3)${NC} Probar uno"
  echo -e " ${YELLOW}4)${NC} Probar todos"
  echo -e " ${YELLOW}5)${NC} Activar Actualizacion Dinamica DuckDns"
  echo -e " ${YELLOW}6)${NC} Desactivar Actualizacion Dinamica DuckDns"
  echo -e " ${YELLOW}7)${NC} Editar Script Duckdns (lo ejecuta crontab)"
  echo -e " ${YELLOW}8)${NC} Ver log"
  echo -e " ${YELLOW}9)${NC} Eliminar Actualizacion de Crontab"
  echo -e " ${YELLOW}10)${NC} Ver IP pública"
  echo -e " ${YELLOW}11)${NC} Editar crontab"
  echo -e " ${CYAN}0) Volver${NC}"

  read -p "> " op

  case $op in
    1) crear_duckdns ;;
    2) clear; listar_base; pausa ;;
    3) probar_uno ;;
    4) probar_todos ;;
    5) activar_duckdns ;;
    6) desactivar_duckdns ;;
    7) editar_duckdns ;;
    8) ver_log ;;
    9) eliminar_duckdns ;;
    10) ver_ip ;;
    11) editar_cron ;;
    0) break ;;
    *) warn "Opcion invalida"; sleep 1 ;;
  esac
done

}

# ========= VARIABLES (AJUSTAR SI ES NECESARIO) =========
WEB_USER="www-data"
DATA_PATH="/var/www/nextcloud-data"
NC_PATH="/var/www/nextcloud"
PHP_BIN="php"

# ========= COLORES =========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========= VER DISCOS MONTADOS =========
ver_discos_montados_nct(){
    echo -e "${CYAN}=== Dispositivos montados ===${NC}"
    printf "%-12s %-10s %-8s %-30s\n" "DISPOSITIVO" "TAMAÑO" "TIPO" "MONTAJE"
    echo "---------------------------------------------------------------------"

    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT -nr | while read NAME SIZE FSTYPE MOUNT; do
        if [ -n "$MOUNT" ]; then
            printf "/dev/%-8s %-10s %-8s %-30s\n" "$NAME" "$SIZE" "$FSTYPE" "$MOUNT"
        fi
    done
}



# ========= PostgreSQL =========
BACKUP_DIR_POSTGRES="/var/backups/postgres"

install_postgresql() {
    echo -e "${YELLOW}Instalando PostgreSQL...${NC}"
    apt update -y
    apt install -y gnupg lsb-release curl software-properties-common
    apt install -y postgresql-15 postgresql-client-15 postgresql-contrib-15 libpq-dev python3-psycopg2

    id postgres &>/dev/null || useradd -m -s /bin/bash postgres

    if [ ! -d /etc/postgresql/15/main ]; then
        echo -e "${CYAN}Creando clúster PostgreSQL 15...${NC}"
        pg_createcluster 15 main --start
    fi

    systemctl enable postgresql
    systemctl start postgresql

    if [ -f /etc/postgresql/15/main/postgresql.conf ]; then
        sed -i "s/^#listen_addresses = .*/listen_addresses = 'localhost'/" /etc/postgresql/15/main/postgresql.conf
        sed -i "s/^#port = .*/port = 5432/" /etc/postgresql/15/main/postgresql.conf
    fi

    if [ -f /etc/postgresql/15/main/pg_hba.conf ]; then
        grep -q "local   all   all" /etc/postgresql/15/main/pg_hba.conf || {
            echo "local   all   all   peer" >> /etc/postgresql/15/main/pg_hba.conf
        }
    fi

    systemctl restart postgresql

    mkdir -p "$BACKUP_DIR_POSTGRES"
    chown postgres:postgres "$BACKUP_DIR_POSTGRES"
    chmod 755 "$BACKUP_DIR_POSTGRES"

    ok "PostgreSQL instalado correctamente."
    echo -e "${CYAN}Información:${NC}"
    su - postgres -c "psql -c 'SELECT version();'"
    echo -e "Puerto: 5432"
    echo -e "Usuario: postgres"
    echo -e "Respaldos: $BACKUP_DIR_POSTGRES"
}

uninstall_postgresql() {
    echo -e "${RED}Esto eliminará PostgreSQL completamente.${NC}"
    confirmar "¿Continuar?" || return
    systemctl stop postgresql 2>/dev/null
    systemctl disable postgresql 2>/dev/null
    apt remove --purge -y postgresql* libpq-dev python3-psycopg2*
    apt autoremove -y
    rm -rf /var/lib/postgresql/ /etc/postgresql/ /var/log/postgresql/ "$BACKUP_DIR_POSTGRES"
    deluser postgres 2>/dev/null || true
    ok "PostgreSQL eliminado completamente."
}

create_postgresql_database() {
    read -rp "Nombre de la base: " DB_NAME
    read -rp "Usuario propietario [${DB_NAME}]: " USER_NAME
    USER_NAME=${USER_NAME:-$DB_NAME}

    if ! su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='$USER_NAME'\"" | grep -q 1; then
        read -rsp "Contraseña para $USER_NAME: " USER_PASS
        echo
        su - postgres -c "psql -c \"CREATE USER $USER_NAME WITH PASSWORD '$USER_PASS';\""
        ok "Usuario $USER_NAME creado."
    fi

    su - postgres -c "psql -c \"CREATE DATABASE $DB_NAME OWNER $USER_NAME;\""
    ok "Base de datos $DB_NAME creada."
}

create_postgresql_user() {
    read -rp "Nombre del usuario: " USER_NAME
    read -rsp "Contraseña: " USER_PASS
    echo

    if su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='$USER_NAME'\"" | grep -q 1; then
        warn "El usuario ya existe."
        read -rp "¿Cambiar contraseña? [s/N]: " CAMB
        [[ "$CAMB" =~ ^[sS]$ ]] && su - postgres -c "psql -c \"ALTER USER $USER_NAME WITH PASSWORD '$USER_PASS';\""
    else
        su - postgres -c "psql -c \"CREATE USER $USER_NAME WITH PASSWORD '$USER_PASS';\""
        ok "Usuario $USER_NAME creado."
    fi
}

change_postgres_password() {
    read -rsp "Nueva contraseña para usuario postgres: " NEW_PASS
    echo
    su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '$NEW_PASS';\""
    ok "Contraseña del usuario postgres actualizada."
}

respaldar_db_postgresql() {
    echo -e "${CYAN}Bases disponibles:${NC}"
    su - postgres -c "psql -At -c \"SELECT datname FROM pg_database WHERE datistemplate = false;\""
    read -rp "Base a respaldar: " DB_NAME
    FILE="$BACKUP_DIR_POSTGRES/${DB_NAME}_$(date +%F_%H-%M-%S).sql"
    if su - postgres -c "pg_dump $DB_NAME > $FILE"; then
        ok "Respaldo guardado en $FILE ($(du -h "$FILE" | cut -f1))"
    else
        err "Error al crear respaldo."
    fi
}

restaurar_db_postgresql() {
    echo -e "${CYAN}Archivos disponibles:${NC}"
    ls -lh "$BACKUP_DIR_POSTGRES"
    read -rp "Archivo: " FILE
    read -rp "Base destino: " DB_NAME
    [ ! -f "$BACKUP_DIR_POSTGRES/$FILE" ] && err "Archivo no existe." && return
    if ! su - postgres -c "psql -lqt" | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        su - postgres -c "psql -c \"CREATE DATABASE $DB_NAME;\""
    fi
    if su - postgres -c "psql $DB_NAME < $BACKUP_DIR_POSTGRES/$FILE"; then
        ok "Restauración completada."
    else
        err "Error al restaurar."
    fi
}

listar_db_postgresql() {
    echo -e "${CYAN}Bases de datos:${NC}"
    su - postgres -c "psql -c '\l'"
    echo -e "\n${CYAN}Usuarios:${NC}"
    su - postgres -c "psql -c '\du'"
}

estado_postgresql() {
    echo -e "${CYAN}Estado del servicio:${NC}"
    systemctl status postgresql --no-pager -l | head -n 15
    echo -e "\n${CYAN}Versión:${NC}"
    su - postgres -c "psql -c 'SELECT version();'"
}

reiniciar_postgresql() {
    systemctl restart postgresql && ok "PostgreSQL reiniciado correctamente."
}

menu_postgresql(){
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== GESTIÓN DE POSTGRESQL ===${NC}"
    echo -e " ${YELLOW}1)${NC} Instalar PostgreSQL"
    echo -e " ${YELLOW}2)${NC} Desinstalar PostgreSQL"
    echo -e " ${YELLOW}3)${NC} Crear base de datos"
    echo -e " ${YELLOW}4)${NC} Crear usuario"
    echo -e " ${YELLOW}5)${NC} Cambiar contraseña usuario postgres"
    echo -e " ${YELLOW}6)${NC} Respaldar base de datos"
    echo -e " ${YELLOW}7)${NC} Restaurar base de datos"
    echo -e " ${YELLOW}8)${NC} Listar bases y usuarios"
    echo -e " ${YELLOW}9)${NC} Estado del servicio"
    echo -e " ${YELLOW}10)${NC} Reiniciar servicio"
    echo -e " ${CYAN}0)${NC} Volver"
    read -rp "> " op
    case "$op" in
      1) install_postgresql; pausa ;;
      2) uninstall_postgresql; pausa ;;
      3) create_postgresql_database; pausa ;;
      4) create_postgresql_user; pausa ;;
      5) change_postgres_password; pausa ;;
      6) respaldar_db_postgresql; pausa ;;
      7) restaurar_db_postgresql; pausa ;;
      8) listar_db_postgresql; pausa ;;
      9) estado_postgresql; pausa ;;
      10) reiniciar_postgresql; pausa ;;
      0) return ;;
      *) warn "Opción inválida."; pausa ;;
    esac
  done
}

# ========= VARIABLES =========
SWAPFILE="/swapfile"

# ========= COLORES =========
BOLD="\e[1m"
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"

# ========= FUNCIONES SWAP =========

ver_swap_estado() {
  echo "=== ESTADO DEL SWAP ==="
  swapon --show
  echo ""
  free -h
}

desactivar_todo_swap() {
  echo "[INFO] Desactivando TODO el swap..."
  swapoff -a
  echo "[OK] Swap desactivado"
}

desactivar_swapfile() {
  if swapon --show | grep -q "$SWAPFILE"; then
    swapoff "$SWAPFILE"
    echo "[OK] Swapfile desactivado"
  else
    echo "[INFO] Swapfile no está activo"
  fi
}

desactivar_particion_swap() {
  echo "[INFO] Desactivando swap en fstab..."
  cp /etc/fstab /etc/fstab.bak
  sed -i '/ swap / s/^/#/' /etc/fstab
  echo "[OK] Swap deshabilitado en arranque"
  echo "[INFO] Reinicia para aplicar completamente"
}

eliminar_swapfile_completo() {
  if [ -f "$SWAPFILE" ]; then
    echo "[INFO] Desactivando swapfile..."
    swapoff "$SWAPFILE" 2>/dev/null

    echo "[INFO] Eliminando archivo..."
    rm -f "$SWAPFILE"

    echo "[INFO] Limpiando fstab..."
    sed -i '\|/swapfile|d' /etc/fstab

    echo "[OK] Swapfile eliminado completamente"
  else
    echo "[INFO] No existe swapfile"
  fi
}

crear_swapfile() {
  RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
  RECOMENDADO=2

  echo "RAM detectada: ${RAM_GB} GB"
  echo "Recomendado: ${RECOMENDADO} GB"

  read -p "Tamaño del swap en GB (Enter = recomendado): " SIZE

  if [ -z "$SIZE" ]; then
    SIZE=$RECOMENDADO
  fi

  if ! [[ "$SIZE" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Valor inválido"
    return
  fi

  echo "[INFO] Creando swapfile de ${SIZE}G..."

  fallocate -l ${SIZE}G "$SWAPFILE"
  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE"
  swapon "$SWAPFILE"

  grep -q "$SWAPFILE" /etc/fstab || echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab

  if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
    echo "vm.swappiness=10" >> /etc/sysctl.conf
  else
    sed -i 's/vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
  fi

  sysctl -p > /dev/null

  echo "[OK] Swapfile creado y activado"
}

limpiar_swap_huerfano() {
  if grep -q "/swapfile" /etc/fstab && [ ! -f "$SWAPFILE" ]; then
    echo "[WARN] Swapfile no existe pero está en fstab"
    echo "[INFO] Corrigiendo..."
    sed -i '\|/swapfile|d' /etc/fstab
    echo "[OK] fstab limpio"
  fi
}

# ========= NUEVA FUNCION =========

activar_swap_seleccion() {
  echo "=== SWAP DISPONIBLES ==="

  mapfile -t SWAPS < <(blkid -t TYPE="swap" -o device)

  if [ ${#SWAPS[@]} -eq 0 ]; then
    echo "[INFO] No se encontraron particiones swap"
  else
    for i in "${!SWAPS[@]}"; do
      echo "$((i+1))) ${SWAPS[$i]}"
    done
  fi

  # agregar swapfile si existe
  if [ -f "$SWAPFILE" ]; then
    SWAPS+=("$SWAPFILE")
    echo "$(( ${#SWAPS[@]} ))) $SWAPFILE (swapfile)"
  fi

  echo ""
  read -p "Selecciona número para activar (0 cancelar): " SEL

  if [[ "$SEL" == "0" ]]; then
    return
  fi

  IDX=$((SEL-1))

  if [ -z "${SWAPS[$IDX]}" ]; then
    echo "[ERROR] Selección inválida"
    return
  fi

  swapon "${SWAPS[$IDX]}" && echo "[OK] Swap activado: ${SWAPS[$IDX]}"
}

# ========= inicio Ejecutar Comando a Varios PC / CLUSTER PRO SSH =========
# =========================================================
# MODULO CLUSTER SSH
# =========================================================

# ========= CONFIG =========

CLUSTER_MAX_JOBS=10
CLUSTER_LOG_DIR="./logs_cluster"

mkdir -p "$CLUSTER_LOG_DIR"

# =========================================================
# VERIFICAR DEPENDENCIAS
# =========================================================

cluster_check_dependencies(){

    if ! command -v sshpass >/dev/null 2>&1; then

        echo
        echo -e "${RED}❌ sshpass no está instalado${RESET}"
        echo

        read -p "Instalar sshpass ahora? (s/n): " INSTALL_SSHPASS

        if [[ "$INSTALL_SSHPASS" =~ ^[Ss]$ ]]; then

            if command -v apt >/dev/null 2>&1; then
                apt update && apt install -y sshpass
            elif command -v dnf >/dev/null 2>&1; then
                dnf install -y sshpass
            elif command -v yum >/dev/null 2>&1; then
                yum install -y sshpass
            else
                echo -e "${RED}No se pudo detectar gestor de paquetes${RESET}"
                return 1
            fi

        else
            return 1
        fi
    fi

    return 0
}

# =========================================================
# PARSEAR RANGO
# =========================================================

cluster_parse_rango(){

    local RANGO=$1

    if [[ "$RANGO" == *"-"* ]]; then

        local IP_BASE
        local INICIO
        local FIN

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
# CHECK HOST
# =========================================================

cluster_check_host(){

    ping -c 1 -W 1 "$1" >/dev/null 2>&1

}

# =========================================================
# EJECUTAR COMANDO
# =========================================================

cluster_run_command(){

    cluster_check_dependencies || return

    local USER
    local PASS
    local CMD
    local ROOT
    local RANGO

    read -p "Usuario SSH: " USER
    read -s -p "Password SSH: " PASS
    echo

    read -p "Comando: " CMD
    read -p "Ejecutar como root? (s/n): " ROOT

    echo
    echo -e "${GREEN}✔ Ejemplo rango:${RESET} 192.168.0.100-120"

    read -p "IP o rango: " RANGO

    local HOSTS
    mapfile -t HOSTS < <(cluster_parse_rango "$RANGO")

    local TOTAL=${#HOSTS[@]}

    echo
    echo -e "${YELLOW}🚀 Ejecutando comando en $TOTAL hosts...${RESET}"
    echo

    local COUNT=0

    for HOST in "${HOSTS[@]}"; do

        (
            LOG="$CLUSTER_LOG_DIR/$HOST-command.log"

            if cluster_check_host "$HOST"; then

                echo "[+] $HOST conectado" > "$LOG"

                if [[ "$ROOT" =~ ^[Ss]$ ]]; then
                    REMOTE_CMD="echo '$PASS' | sudo -S $CMD"
                else
                    REMOTE_CMD="$CMD"
                fi

                sshpass -p "$PASS" ssh \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    -o ConnectTimeout=5 \
                    -o LogLevel=ERROR \
                    "$USER@$HOST" "$REMOTE_CMD" >> "$LOG" 2>&1

                echo "[OK] $HOST" >> "$LOG"

            else

                echo "[X] $HOST no responde" > "$LOG"

            fi

        ) &

        ((COUNT++))

        PCT=$((COUNT * 100 / TOTAL))

        echo -ne "\r${CYAN}Progreso:${RESET} $COUNT/$TOTAL (${GREEN}$PCT%${RESET})"

        while [ "$(jobs -r | wc -l)" -ge "$CLUSTER_MAX_JOBS" ]; do
            sleep 0.2
        done

    done

    wait

    echo
    echo
    echo -e "${GREEN}✔ Ejecución terminada${RESET}"
    echo -e "${YELLOW}📂 Logs:${RESET} $CLUSTER_LOG_DIR"
}

# =========================================================
# COPIAR ARCHIVO
# =========================================================

cluster_copy_file(){

    cluster_check_dependencies || return

    local USER
    local PASS
    local FILE
    local DEST
    local RANGO
    local PERM_OP

    read -p "Usuario SSH: " USER
    read -s -p "Password SSH: " PASS
    echo

    read -p "Archivo local: " FILE
    read -p "Ruta destino remota: " DEST

    echo
    echo -e "${GREEN}✔ Ejemplo rango:${RESET} 192.168.0.100-120"

    read -p "IP o rango: " RANGO

    echo
    echo "1) chmod +x"
    echo "2) chmod u+rw"

    while true; do

        read -p "Opción: " PERM_OP

        [[ "$PERM_OP" == "1" || "$PERM_OP" == "2" ]] && break

        echo -e "${RED}Opción inválida${RESET}"

    done

    local HOSTS
    mapfile -t HOSTS < <(cluster_parse_rango "$RANGO")

    local TOTAL=${#HOSTS[@]}

    echo
    echo -e "${YELLOW}🚀 Copiando archivo a $TOTAL hosts...${RESET}"
    echo

    local COUNT=0

    for HOST in "${HOSTS[@]}"; do

        (
            LOG="$CLUSTER_LOG_DIR/$HOST-copy.log"

            if cluster_check_host "$HOST"; then

                sshpass -p "$PASS" scp \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    "$FILE" "$USER@$HOST:$DEST" >> "$LOG" 2>&1

                if [[ "$PERM_OP" == "1" ]]; then
                    CHMOD_CMD="chmod +x $DEST/$(basename "$FILE")"
                else
                    CHMOD_CMD="chmod u+rw $DEST/$(basename "$FILE")"
                fi

                sshpass -p "$PASS" ssh \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    "$USER@$HOST" "$CHMOD_CMD" >> "$LOG" 2>&1

                echo "[OK] Archivo copiado en $HOST" >> "$LOG"

            else

                echo "[X] $HOST no responde" > "$LOG"

            fi

        ) &

        ((COUNT++))

        PCT=$((COUNT * 100 / TOTAL))

        echo -ne "\r${CYAN}Progreso:${RESET} $COUNT/$TOTAL (${GREEN}$PCT%${RESET})"

        while [ "$(jobs -r | wc -l)" -ge "$CLUSTER_MAX_JOBS" ]; do
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

cluster_run_script(){

    cluster_check_dependencies || return

    local USER
    local PASS
    local SCRIPT
    local RANGO
    local PERM_OP

    read -p "Usuario SSH: " USER
    read -s -p "Password SSH: " PASS
    echo

    read -p "Script local (.sh): " SCRIPT

    echo
    echo -e "${GREEN}✔ Ejemplo rango:${RESET} 192.168.0.100-120"

    read -p "IP o rango: " RANGO

    echo
    echo "1) chmod +x"
    echo "2) chmod u+rw"

    while true; do

        read -p "Opción: " PERM_OP

        [[ "$PERM_OP" == "1" || "$PERM_OP" == "2" ]] && break

        echo -e "${RED}Opción inválida${RESET}"

    done

    local HOSTS
    mapfile -t HOSTS < <(cluster_parse_rango "$RANGO")

    local TOTAL=${#HOSTS[@]}

    echo
    echo -e "${YELLOW}🚀 Ejecutando scripts en $TOTAL hosts...${RESET}"
    echo

    local COUNT=0

    for HOST in "${HOSTS[@]}"; do

        (
            LOG="$CLUSTER_LOG_DIR/$HOST-script.log"

            if cluster_check_host "$HOST"; then

                sshpass -p "$PASS" scp \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    "$SCRIPT" "$USER@$HOST:/tmp/script.sh" >/dev/null 2>&1

                if [[ "$PERM_OP" == "1" ]]; then
                    CHMOD_CMD="chmod +x /tmp/script.sh"
                else
                    CHMOD_CMD="chmod u+rw /tmp/script.sh"
                fi

                sshpass -p "$PASS" ssh \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    "$USER@$HOST" \
                    "$CHMOD_CMD && bash /tmp/script.sh" >> "$LOG" 2>&1

                echo "[OK] Script ejecutado en $HOST" >> "$LOG"

            else

                echo "[X] $HOST no responde" > "$LOG"

            fi

        ) &

        ((COUNT++))

        PCT=$((COUNT * 100 / TOTAL))

        echo -ne "\r${CYAN}Progreso:${RESET} $COUNT/$TOTAL (${GREEN}$PCT%${RESET})"

        while [ "$(jobs -r | wc -l)" -ge "$CLUSTER_MAX_JOBS" ]; do
            sleep 0.2
        done

    done

    wait

    echo
    echo
    echo -e "${GREEN}✔ Scripts ejecutados${RESET}"
}

# =========================================================
# MENU CLUSTER SSH
# =========================================================

cluster_menu(){

    while true; do

        clear

        echo -e "${CYAN}╔══════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║${RESET}${YELLOW}              CLUSTER SSH                  ${RESET}${CYAN}║${RESET}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${RESET}"

        echo
        echo -e " ${GREEN}1)${YELLOW} Ejecutar comando en múltiples hosts"
        echo -e " ${GREEN}2)${YELLOW} Copiar archivo a múltiples hosts"
        echo -e " ${GREEN}3)${YELLOW} Ejecutar script .sh en múltiples hosts"
        echo -e " ${RED}0)${CYAN} Volver"

        echo

        read -p "Seleccione una opción: " OPCION_CLUSTER

        case "$OPCION_CLUSTER" in

            1)
                clear
                cluster_run_command
                echo
                read -p "ENTER para continuar..."
                ;;

            2)
                clear
                cluster_copy_file
                echo
                read -p "ENTER para continuar..."
                ;;

            3)
                clear
                cluster_run_script
                echo
                read -p "ENTER para continuar..."
                ;;

            0)
                break
                ;;

            *)
                echo
                echo -e "${RED}❌ Opción inválida${RESET}"
                sleep 1
                ;;

        esac

    done
}
# ========= fin Ejecutar Comando a Varios PC / CLUSTER PRO SSH =========

# ========= MENÚ SWAP =========

menu_swap() {
  limpiar_swap_huerfano

  while true; do
    clear   

    echo -e "${BOLD}${CYAN}====== MENU SWAP ======${RESET}"
    echo -e "${YELLOW}1)${RESET} Ver estado del swap"
    echo -e "${YELLOW}2)${RESET} Desactivar TODO el swap"
    echo -e "${YELLOW}3)${RESET} Desactivar solo swapfile"
    echo -e "${YELLOW}4)${RESET} Desactivar partición swap (fstab)"
    echo -e "${YELLOW}5)${RESET} Eliminar swapfile"
    echo -e "${YELLOW}6)${RESET} Crear swapfile"
    echo -e "${YELLOW}7)${RESET} Activar swap (elegir)"
    echo -e "${CYAN}0) Volver${RESET}"

    echo ""
    read -p "Selecciona una opción: " OPCION

    case $OPCION in
      1) ver_swap_estado ;;
      2) desactivar_todo_swap ;;
      3) desactivar_swapfile ;;
      4) desactivar_particion_swap ;;
      5) eliminar_swapfile_completo ;;
      6) crear_swapfile ;;
      7) activar_swap_seleccion ;;
      0) break ;;
      *) echo "[ERROR] Opción inválida" ;;
    esac

    echo ""
    read -p "Presiona ENTER para continuar..."
  done
}

# =======================================================
# FAIL2BAN PRO QUITA BANEO DE IP
# =======================================================

menu_fail2ban(){

    # ===== COLORES =====
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'

    pausar(){ read -p "ENTER para continuar..."; }

    while true; do
        clear
        echo -e "${CYAN}=========== FAIL2BAN PRO ===========${NC}"
        echo -e "${YELLOW}1)${NC} Ver estado general"
        echo -e "${YELLOW}2)${NC} Ver IPs baneadas (sshd)"
        echo -e "${YELLOW}3)${NC} Desbanear MI IP automáticamente"
        echo -e "${YELLOW}4)${NC} Desbanear IP manual"
        echo -e "${YELLOW}5)${NC} Reiniciar Fail2Ban"
        echo -e "${YELLOW}0)${NC} Volver"
        read -p "Selecciona opción: " OP

        case "$OP" in

        1)
            echo -e "${CYAN}Estado Fail2Ban:${NC}"
            sudo fail2ban-client status
            pausar
        ;;

        2)
            echo -e "${CYAN}IPs baneadas en SSH:${NC}"
            sudo fail2ban-client status sshd
            pausar
        ;;

        3)
            echo -e "${CYAN}Detectando tu IP pública...${NC}"
            MI_IP=$(curl -s ifconfig.me)

            if [ -z "$MI_IP" ]; then
                echo -e "${RED}No se pudo detectar la IP${NC}"
                pausar
                continue
            fi

            echo -e "${YELLOW}Tu IP detectada:${NC} $MI_IP"

            sudo fail2ban-client set sshd unbanip "$MI_IP" \
                && echo -e "${GREEN}✔ IP desbaneada${NC}" \
                || echo -e "${RED}✘ No estaba baneada o error${NC}"

            pausar
        ;;

        4)
            read -p "Ingresa IP a desbanear: " IP

            if [[ ! "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo -e "${RED}IP inválida${NC}"
                pausar
                continue
            fi

            sudo fail2ban-client set sshd unbanip "$IP" \
                && echo -e "${GREEN}✔ IP desbaneada${NC}" \
                || echo -e "${RED}✘ Error o IP no baneada${NC}"

            pausar
        ;;

        5)
            echo -e "${CYAN}Reiniciando Fail2Ban...${NC}"
            sudo systemctl restart fail2ban

            if systemctl is-active --quiet fail2ban; then
                echo -e "${GREEN}✔ Fail2Ban reiniciado${NC}"
            else
                echo -e "${RED}✘ Error al reiniciar${NC}"
            fi

            pausar
        ;;

        0) break ;;

        *)
            echo -e "${RED}Opción inválida${NC}"
            pausar
        ;;

        esac
    done
}
# ========= LIMPIAR HISTORIAL + CONTROL =========
limpiar_historial() {

    echo -e "\n${CYAN}⚠ Esto eliminará TODO el historial (memoria + archivo)${NC}"
    read -p "¿Estás seguro? (s/n): " CONFIRMAR

    if [[ "$CONFIRMAR" =~ ^[sS]$ ]]; then

        echo -e "${YELLOW}Limpiando historial...${NC}"

        # limpiar memoria
        history -c

        # borrar archivo
        rm -f ~/.bash_history

        echo -e "${GREEN}✔ Historial eliminado completamente${NC}"

        echo ""
        echo "¿Deseas seguir guardando historial?"
        echo "1) Sí, activar historial"
        echo "2) No, modo privado (no guardar)"
        echo ""

        read -p "Selecciona opción: " OPC

        case $OPC in
            1)
                export HISTFILE=~/.bash_history
                export HISTSIZE=1000
                export HISTFILESIZE=2000
                echo -e "${GREEN}✔ Historial ACTIVADO${NC}"
                ;;
            2)
                unset HISTFILE
                export HISTSIZE=0
                export HISTFILESIZE=0
                echo -e "${GREEN}✔ Historial DESACTIVADO (modo privado)${NC}"
                ;;
            *)
                echo -e "${RED}Opción inválida, se mantiene configuración actual${NC}"
                ;;
        esac

    else
        echo -e "${RED}❌ Operación cancelada${NC}"
    fi

    read -p "Presiona ENTER para volver al menú..."
}

# ========= REPARAR ERROR FECHA / APT =========
fix_fecha_apt() {

    clear

    CYAN="\e[36m"
    GREEN="\e[32m"
    RED="\e[31m"
    YELLOW="\e[33m"
    NC="\e[0m"

    while true; do

        echo -e "${CYAN}====== REPARAR ERROR FECHA / APT ======${NC}"
        echo
        echo -e "${YELLOW}1)${NC} Ver fecha actual"
        echo -e "${YELLOW}2)${NC} Sincronizar con NTP (rápido)"
        echo -e "${YELLOW}3)${NC} Reparación Fecha completa (recomendada)"
        echo -e "${YELLOW}4)${NC} Ajustar fecha manual"
        echo -e "${YELLOW}5)${NC} Probar apt update"
		echo -e "${YELLOW}6)${NC} ARREGLAR APT / Borra List/Archives"
		echo -e "${YELLOW}7)${NC} ARREGLAR APT HASH SUM MISMATCH (modo fuerte)"
		echo -e "${YELLOW}8)${NC} ARREGLAR APT HASH SUM MISMATCH (NIVEL DIOS)"
        echo -e "${YELLOW}0)${NC} Volver"
        echo
        read -p "Selecciona: " OP

        case $OP in

        # ===============================
        # VER FECHA
        # ===============================
        1)
            echo -e "${CYAN}Fecha actual:${NC}"
            date
            timedatectl status | grep "System clock"
            read -p "ENTER..."
        ;;

        # ===============================
        # NTP RÁPIDO
        # ===============================
        2)
            echo -e "${CYAN}Sincronizando con NTP...${NC}"

            apt install -y ntpdate >/dev/null 2>&1

            timedatectl set-ntp false >/dev/null 2>&1
            ntpdate pool.ntp.org
            timedatectl set-ntp true >/dev/null 2>&1

            echo -e "${GREEN}✔ Hora sincronizada${NC}"
            date

            read -p "ENTER..."
        ;;

        # ===============================
        # REPARACIÓN COMPLETA
        # ===============================
        3)
            echo -e "${CYAN}Reparación completa del sistema de tiempo...${NC}"

            apt install -y ntpdate systemd-timesyncd >/dev/null 2>&1

            systemctl stop systemd-timesyncd >/dev/null 2>&1
            timedatectl set-ntp false >/dev/null 2>&1

            ntpdate pool.ntp.org

            systemctl start systemd-timesyncd >/dev/null 2>&1
            timedatectl set-ntp true >/dev/null 2>&1

            hwclock --systohc 2>/dev/null

            echo -e "${GREEN}✔ Sistema de hora reparado${NC}"
            date

            read -p "ENTER..."
        ;;

        # ===============================
        # MANUAL
        # ===============================
        4)
            read -p "Ingrese fecha (YYYY-MM-DD HH:MM:SS): " NUEVA_FECHA

            timedatectl set-time "$NUEVA_FECHA"

            echo -e "${GREEN}✔ Fecha actualizada${NC}"
            date

            read -p "ENTER..."
        ;;

        # ===============================
        # TEST APT
        # ===============================
        5)
            echo -e "${CYAN}Probando apt update...${NC}"

            if apt update; then
                echo -e "${GREEN}✔ APT funcionando correctamente${NC}"
            else
                echo -e "${RED}✖ Aún hay problemas${NC}"
                echo -e "${YELLOW}→ Ejecuta opción 3${NC}"
            fi

            read -p "ENTER..."
        ;;
		
        # ===============================
        # SOLUCIÓN RÁPIDA (ARREGLAR APT)
        # ===============================
		6)
		
		rm -rf /var/lib/apt/lists/*
        rm -rf /var/cache/apt/archives/*
        apt clean
        apt update -o Acquire::CompressionTypes::Order::=gz
		
		;;
		# ===============================
        # SI AÚN FALLA (modo fuerte)
        # ===============================
        
        7)
            echo "===== REPARANDO APT HASH SUM MISMATCH (MODO FUERTE) ====="

            # Detener procesos apt/dpkg colgados
            killall apt apt-get dpkg 2>/dev/null

            # Limpiar caché local
            apt clean
            apt autoclean
            rm -rf /var/lib/apt/lists/*
            rm -rf /var/cache/apt/archives/*.deb

            # Recrear listas
            mkdir -p /var/lib/apt/lists/partial

            # Forzar IPv4
            echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4

            # Forzar gzip
            echo 'Acquire::CompressionTypes::Order:: "gz";' > /etc/apt/apt.conf.d/99fixbadproxy

            # Desactivar pipelining problemático
            echo 'Acquire::http::Pipeline-Depth "0";' > /etc/apt/apt.conf.d/99nopipeline

            # Reconfigurar fuentes si hay mirror roto
            sed -i 's|http://security.debian.org|http://deb.debian.org/debian-security|g' /etc/apt/sources.list

            # Actualizar
            apt update --fix-missing

            # Reparar paquetes
            dpkg --configure -a
            apt --fix-broken install -y

            # Upgrade seguro
            apt upgrade -y --fix-missing

            echo "===== APT REPARADO ====="
            read -p "Presiona Enter para continuar..."
            ;;
			
	
		8)
		
# ============================================
# REPARACIÓN NIVEL DIOS — HASH SUM MISMATCH
# Debian 12 / TurnKey / Nextcloud / Proxmox
# ============================================

# 1) Detener procesos apt/dpkg
sudo killall apt apt-get dpkg 2>/dev/null

# 2) Eliminar listas corruptas
sudo rm -rf /var/lib/apt/lists/*
sudo rm -rf /var/lib/apt/lists/partial/*
sudo rm -rf /var/cache/apt/archives/*
sudo rm -rf /var/cache/apt/archives/partial/*

# 3) Limpiar cache
sudo apt clean
sudo apt autoclean

# 4) Forzar IPv4 (muchos CDN fallan por IPv6)
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4

# 5) Desactivar pipelining y cache rota
cat <<EOF | sudo tee /etc/apt/apt.conf.d/99fixbadproxy
Acquire::http::Pipeline-Depth "0";
Acquire::http::No-Cache "true";
Acquire::BrokenProxy "true";
EOF

# 6) Cambiar mirror principal a deb.debian.org limpio
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak

cat <<EOF | sudo tee /etc/apt/sources.list
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

# 7) Actualizar con compresión gzip
sudo apt update -o Acquire::CompressionTypes::Order::=gz

# 8) Reparar paquetes rotos
sudo dpkg --configure -a
sudo apt --fix-broken install -y

# 9) Reintentar descarga
sudo apt update --fix-missing
sudo apt upgrade -y

            echo "===== APT REPARADO NIVEL DIOS ====="
            read -p "Presiona Enter para continuar..."
            ;;


 0)
            break
        ;;

        esac

        clear
    done
}
# ========= INSTALAR SUDO + INSTALAR SCRIPT =========
instalar_sudo(){

  clear
  echo -e "${BOLD}${BLUE}=== INSTALAR SUDO + MENU ===${NC}"

  # ===== VALIDAR ROOT =====
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Debes ejecutar como root${NC}"
    pausa
    return
  fi

  # ===== INSTALAR SUDO SI NO EXISTE =====
  if command -v sudo >/dev/null 2>&1; then
    echo -e "${GREEN}✔ sudo ya está instalado${NC}"
  else
    echo -e "${YELLOW}Instalando sudo...${NC}"
    apt update
    apt install -y sudo

    if command -v sudo >/dev/null 2>&1; then
      echo -e "${GREEN}✔ sudo instalado correctamente${NC}"
    else
      echo -e "${RED}Error al instalar sudo${NC}"
      pausa
      return
    fi
  fi

  # ===== INSTALAR SCRIPT COMO menu =====
  echo ""
  echo -e "${CYAN}Instalando script en /usr/local/bin/menu...${NC}"

  cp "$0" /usr/local/bin/menu
  chmod +x /usr/local/bin/menu

  echo -e "${GREEN}✔ Script instalado como 'menu'${NC}"
  echo -e "${YELLOW}Ahora puedes ejecutar el script escribiendo: menu${NC}"

  pausa
}

#!/bin/bash

# ========= VARIABLES =========
NC_PATH="/var/www/nextcloud"
DATA_PATH="/var/www/nextcloud-data"
USER_WEB="www-data"

# COLORES
CYAN="\e[36m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
NC="\e[0m"

# ========= MENSAJES =========
ok(){ echo -e "${GREEN}✔ $1${NC}"; }
error(){ echo -e "${RED}❌ $1${NC}"; }
confirmar(){
    read -rp "$1 (s/N): " r
    [[ "$r" =~ ^[sS]$ ]]
}

# ========= AGREGA A JELLYFIN AL GRUPO WWW-DATA =========
preparar_grupos_nct(){
    if id jellyfin &>/dev/null; then
        if id -nG jellyfin | grep -qw www-data; then
            echo -e "${CYAN}jellyfin ya pertenece a www-data${NC}"
        else
            usermod -aG www-data jellyfin
            echo -e "${GREEN}jellyfin agregado a grupo www-data${NC}"
        fi
    else
        echo -e "${YELLOW}Usuario jellyfin no existe${NC}"
    fi
}

# ========= ESCANEA CARPETA DE USUARIO NEXTCLOUD =========
escanear_carpeta_nct(){

    local BASE="/var/www/nextcloud-data"
    local NEXTCLOUD_DIR="${NC_PATH:-/var/www/nextcloud}"
    local USER_WEB="${USER_WEB:-www-data}"

    echo -e "${BOLD}${CYAN}=== ESCANEO NEXTCLOUD PRO ===${NC}"
    echo ""

    # ===== TIPO =====
    echo -e "${YELLOW}1)${NC} Solo Nextcloud"
    echo -e "${YELLOW}2)${NC} Nextcloud + Jellyfin"
    echo -e "${CYAN}0)${NC} Cancelar"
    echo ""
    read -rp "Selecciona tipo: " TIPO

    case $TIPO in
        1) MODO_APP="nc" ;;
        2) MODO_APP="nc_jellyfin" ;;
        0) echo "Cancelado"; return 0 ;;
        *) error "Opción inválida"; return 1 ;;
    esac

    # ===== PERMISOS =====
    echo ""
    echo -e "${YELLOW}Permisos:${NC}"
    echo "1) No aplicar permisos"
    echo "2) Permisos genéricos"
    echo "3) ACL"
    read -rp "Opción: " PERM_TIPO

    # ===== TIPO DE ESCANEO =====
    echo ""
    echo -e "${YELLOW}1)${NC} Usuario Nextcloud"
    echo -e "${YELLOW}2)${NC} Ruta desde /mnt"
    echo -e "${YELLOW}3)${NC} Ruta manual"
    echo -e "${CYAN}0)${NC} Cancelar"
    echo ""
    read -rp "Opción: " TIPO_SCAN

    case $TIPO_SCAN in

    # =========================
    # 🔹 NEXTCLOUD
    # =========================
    1)
        mapfile -t users < <(find "$BASE" -mindepth 1 -maxdepth 1 -type d \
            ! -name "appdata_*" ! -name "updater-*" ! -name ".*")

        for i in "${!users[@]}"; do
            echo -e "${YELLOW}$((i+1)))${NC} $(basename "${users[$i]}")"
        done

        read -rp "Usuario: " u
        USER_NC="$(basename "${users[$((u-1))]}")"
        USER_PATH="${users[$((u-1))]}/files"

        echo "1) Todo"
        echo "2) Carpeta"
        read -rp "Opción: " OPC

        if [ "$OPC" == "1" ]; then
            RUTA_REAL="$USER_PATH"
            SCAN_PATH="$USER_NC"
        else
            mapfile -t dirs < <(find "$USER_PATH" -mindepth 1 -maxdepth 1 -type d)
            for i in "${!dirs[@]}"; do
                echo "$((i+1))) $(basename "${dirs[$i]}")"
            done

            read -rp "Carpeta: " c
            CARPETA="$(basename "${dirs[$((c-1))]}")"

            RUTA_REAL="$USER_PATH/$CARPETA"
            SCAN_PATH="$USER_NC/files/$CARPETA"
        fi
        ;;

    # =========================
    # 🔹 /MNT
    # =========================
    2)
        mapfile -t mnts < <(find /mnt -mindepth 1 -maxdepth 1 -type d)

        for i in "${!mnts[@]}"; do
            echo "$((i+1))) ${mnts[$i]}"
        done

        read -rp "Disco: " d
        BASE_MNT="${mnts[$((d-1))]}"

        mapfile -t dirs < <(find "$BASE_MNT" -mindepth 1 -maxdepth 1 -type d)

        for i in "${!dirs[@]}"; do
            echo "$((i+1))) ${dirs[$i]}"
        done

        read -rp "Carpeta: " c
        RUTA_REAL="${dirs[$((c-1))]}"

        read -rp "Usuario Nextcloud: " USER_NC
        SCAN_PATH="$USER_NC/files/$(basename "$RUTA_REAL")"
        ;;

    # =========================
    # 🔹 MANUAL
    # =========================
    3)
        read -rp "Ruta: " RUTA_REAL
        read -rp "Usuario Nextcloud: " USER_NC
        SCAN_PATH="$USER_NC/files/$(basename "$RUTA_REAL")"
        ;;

    0) return ;;
    *) error "Opción inválida"; return ;;
    esac

    # ===== PERMISOS (APLICAR) =====
    if [ "$PERM_TIPO" != "1" ]; then

        echo ""
        echo -e "${CYAN}Aplicando permisos...${NC}"

        case $PERM_TIPO in

        # 🔹 GENÉRICOS
        2)
            chown -R www-data:www-data "$RUTA_REAL"
            find "$RUTA_REAL" -type d -exec chmod 750 {} \;
            find "$RUTA_REAL" -type f -exec chmod 640 {} \;

            if [ "$MODO_APP" == "nc_jellyfin" ]; then
                setfacl -R -m g:jellyfin:rx "$RUTA_REAL"
                setfacl -R -d -m g:jellyfin:rx "$RUTA_REAL"
            fi
            ;;

        # 🔹 ACL
        3)
            setfacl -R -m u:www-data:rwx "$RUTA_REAL"
            setfacl -R -d -m u:www-data:rwx "$RUTA_REAL"

            if [ "$MODO_APP" == "nc_jellyfin" ]; then
                setfacl -R -m g:jellyfin:r-x "$RUTA_REAL"
                setfacl -R -d -m g:jellyfin:r-x "$RUTA_REAL"
            fi
            ;;

        esac
    fi

    # ===== ESCANEO =====
    echo ""
    echo -e "${CYAN}Escaneando en Nextcloud...${NC}"

    if [[ "$SCAN_PATH" == "$USER_NC" ]]; then
        sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" files:scan "$USER_NC"
    else
        sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" files:scan --path="$SCAN_PATH"
    fi

    echo ""
    ok "✔ Escaneo finalizado"
}

# ========= REPARAR PERMISOS PARA NEXTCLOUD + JELLYFIN =========
permisos_nc_jellyfin(){

preparar_grupos_nct

    local BASE="/var/www/nextcloud-data"
    local NEXTCLOUD_DIR="${NC_PATH:-/var/www/nextcloud}"
    local USER_WEB="${USER_WEB:-www-data}"
    local USER_NC=""
    local RUTA_FINAL=""
    local NOMBRE_CARPETA=""
    local TIPO
    local METODO
    local ORIGEN
    local FS_TYPE

    echo -e "${BOLD}${CYAN}=== PERMISOS NEXTCLOUD ULTRA PRO MAX ===${NC}"
    echo ""

    # ===== TIPO =====
    echo -e "${YELLOW}1)${NC} Solo Nextcloud"
    echo -e "${YELLOW}2)${NC} Nextcloud + Jellyfin"
    echo -e "${CYAN}0)${NC} Cancelar"
    read -rp "Selecciona tipo: " TIPO

    case $TIPO in
        1|2) ;;
        0) return 0 ;;
        *) echo -e "${RED}Opción inválida${NC}"; return 1 ;;
    esac

    echo ""

    # ===== MÉTODO =====
    echo -e "${YELLOW}1)${NC} chmod"
    echo -e "${YELLOW}2)${NC} ACL (inteligente)"
    echo -e "${CYAN}0)${NC} Cancelar"
    read -rp "Selecciona método: " METODO

    case $METODO in
        1|2) ;;
        0) return 0 ;;
        *) echo -e "${RED}Opción inválida${NC}"; return 1 ;;
    esac

    echo ""

    # ===== ORIGEN =====
    echo -e "${YELLOW}1)${NC} Desde Nextcloud"
    echo -e "${YELLOW}2)${NC} Desde /mnt"
    echo -e "${YELLOW}3)${NC} Ruta manual"
    echo -e "${CYAN}0)${NC} Cancelar"
    read -rp "Opción: " ORIGEN

    case $ORIGEN in

    1)
        mapfile -t users < <(find "$BASE" -mindepth 1 -maxdepth 1 -type d \
            ! -name "appdata_*" ! -name "updater-*" ! -name ".*" 2>/dev/null)

        [ ${#users[@]} -eq 0 ] && echo -e "${RED}No hay usuarios${NC}" && return 1

        for i in "${!users[@]}"; do
            echo -e "${YELLOW}$((i+1)))${NC} $(basename "${users[$i]}")"
        done

        read -rp "Usuario: " u
        [[ ! "$u" =~ ^[0-9]+$ || $u -lt 1 || $u -gt ${#users[@]} ]] && echo -e "${RED}Inválido${NC}" && return 1

        USER_NC="$(basename "${users[$((u-1))]}")"
        USER_PATH="${users[$((u-1))]}/files"

        mapfile -t dirs < <(find "$USER_PATH" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

        [ ${#dirs[@]} -eq 0 ] && echo -e "${RED}Sin carpetas${NC}" && return 1

        for i in "${!dirs[@]}"; do
            echo -e "${YELLOW}$((i+1)))${NC} $(basename "${dirs[$i]}")"
        done

        read -rp "Carpeta: " c
        [[ ! "$c" =~ ^[0-9]+$ || $c -lt 1 || $c -gt ${#dirs[@]} ]] && echo -e "${RED}Inválido${NC}" && return 1

        RUTA_FINAL="${dirs[$((c-1))]}"
        NOMBRE_CARPETA="$(basename "$RUTA_FINAL")"
        ;;

    2)
        mapfile -t mnts < <(find /mnt -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

        [ ${#mnts[@]} -eq 0 ] && echo -e "${RED}No hay discos en /mnt${NC}" && return 1

        for i in "${!mnts[@]}"; do
            echo -e "${YELLOW}$((i+1)))${NC} ${mnts[$i]}"
        done

        read -rp "Disco: " d
        [[ ! "$d" =~ ^[0-9]+$ || $d -lt 1 || $d -gt ${#mnts[@]} ]] && echo -e "${RED}Inválido${NC}" && return 1

        BASE_MNT="${mnts[$((d-1))]}"

        mapfile -t dirs < <(find "$BASE_MNT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

        [ ${#dirs[@]} -eq 0 ] && echo -e "${RED}Sin carpetas${NC}" && return 1

        for i in "${!dirs[@]}"; do
            echo -e "${YELLOW}$((i+1)))${NC} ${dirs[$i]}"
        done

        read -rp "Carpeta: " c
        [[ ! "$c" =~ ^[0-9]+$ || $c -lt 1 || $c -gt ${#dirs[@]} ]] && echo -e "${RED}Inválido${NC}" && return 1

        RUTA_FINAL="${dirs[$((c-1))]}"
        NOMBRE_CARPETA="$(basename "$RUTA_FINAL")"

        read -rp "Usuario Nextcloud: " USER_NC
        ;;

    3)
        read -rp "Ruta completa: " RUTA_FINAL
        [ ! -d "$RUTA_FINAL" ] && echo -e "${RED}No existe la ruta${NC}" && return 1

        read -rp "Usuario Nextcloud: " USER_NC
        NOMBRE_CARPETA="$(basename "$RUTA_FINAL")"
        ;;

    *)
        echo "Cancelado"
        return 0
        ;;
    esac

    # ===== VALIDACIÓN =====
    [ ! -d "$RUTA_FINAL" ] && echo -e "${RED}Ruta inválida${NC}" && return 1

    echo ""
    echo -e "${CYAN}Ruta:${NC} $RUTA_FINAL"
    echo ""

    read -rp "¿Aplicar permisos? (s/n): " CONF
    [[ "$CONF" != "s" ]] && return 0

    # ===== DETECTAR FILESYSTEM =====
    FS_TYPE=$(df -T "$RUTA_FINAL" | awk 'NR==2 {print $2}')
    echo -e "${CYAN}Filesystem:${NC} $FS_TYPE"

    if [[ "$FS_TYPE" =~ ^(ntfs|fuseblk|exfat|vfat|fat32)$ ]]; then
        echo -e "${YELLOW}⚠️ Sin soporte ACL → usando chmod${NC}"
        METODO=1
    fi

    # ===== INSTALAR ACL SI CORRESPONDE =====
    if [ "$METODO" == "2" ]; then
        if ! command -v setfacl >/dev/null 2>&1; then
            echo -e "${YELLOW}ACL no detectado → intentando reparar...${NC}"
            if declare -f check_dependencias_discos_nct >/dev/null 2>&1; then
                check_dependencias_discos_nct
            else
                echo -e "${RED}check_dependencias_discos_nct no disponible${NC}"
            fi
        fi

        if ! command -v setfacl >/dev/null 2>&1; then
            echo -e "${RED}ACL sigue sin estar disponible → usando chmod${NC}"
            METODO=1
        fi
    fi

    # ===== GRUPO JELLYFIN =====
    if [ "$TIPO" == "2" ] && id jellyfin &>/dev/null; then
        usermod -aG "$USER_WEB" jellyfin
    fi

    echo ""
    echo -e "${YELLOW}Aplicando permisos en $RUTA_FINAL...${NC}"

    if [ "$METODO" == "1" ]; then
        # chmod normal
        chown -R "$USER_WEB:$USER_WEB" "$RUTA_FINAL"
        if [ "$TIPO" == "1" ]; then
            find "$RUTA_FINAL" -type d -exec chmod 750 {} \;
            find "$RUTA_FINAL" -type f -exec chmod 640 {} \;
        else
            find "$RUTA_FINAL" -type d -exec chmod 775 {} \;
            find "$RUTA_FINAL" -type f -exec chmod 664 {} \;
            chmod g+s "$RUTA_FINAL"
        fi
    else
        # ACL seguro para ext4
        chown -R "$USER_WEB:$USER_WEB" "$RUTA_FINAL"

        setfacl -R -m u:$USER_WEB:rwx "$RUTA_FINAL"
        setfacl -R -m d:u:$USER_WEB:rwx "$RUTA_FINAL"

        if [ "$TIPO" == "2" ] && id jellyfin &>/dev/null; then
            setfacl -R -m u:jellyfin:rx "$RUTA_FINAL"
            setfacl -R -m d:u:jellyfin:rx "$RUTA_FINAL"
        fi
    fi

    echo -e "${GREEN}✔ Permisos aplicados${NC}"

    # ===== ESCANEO =====
    echo ""
    read -rp "¿Escanear en Nextcloud? (s/N): " SCAN

    if [[ "$SCAN" =~ ^[sS]$ ]] && [ -n "$USER_NC" ]; then
        echo -e "${CYAN}Escaneando...${NC}"
        sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" files:scan --path="$USER_NC/files/$NOMBRE_CARPETA"
        echo -e "${GREEN}✔ Escaneo completado${NC}"
    fi
}

# ========= COPIAR A NEXTCLOUD ULTRA PRO =========

copiar_a_nextcloud_nct(){

    preparar_grupos_nct

    local DATA_PATH="${DATA_PATH:-/var/www/nextcloud-data}"
    local NC_PATH="${NC_PATH:-/var/www/nextcloud}"
    local USER_WEB="${USER_WEB:-www-data}"
    local LOG_FILE="/var/log/copia_total_$(date +%F_%H-%M-%S).log"

    echo -e "${BOLD}${CYAN}=== COPIA TOTAL PRO ===${NC}"
    echo ""

    # ===== SELECCION NEXTCLOUD =====
    seleccionar_nextcloud(){
    echo -e "${CYAN}Detectando usuarios en: $DATA_PATH${NC}"

    [ ! -d "$DATA_PATH" ] && error "DATA_PATH no existe: $DATA_PATH" && return 1

    # Listar usuarios que tengan carpeta /files
    mapfile -t users < <(
        for d in "$DATA_PATH"/*; do
            [ -d "$d/files" ] && basename "$d"
        done
    )

    if [ ${#users[@]} -eq 0 ]; then
        error "No se encontraron usuarios"
        return 1
    fi

    echo ""
    for i in "${!users[@]}"; do
        echo -e "${YELLOW}$((i+1)))${NC} ${users[$i]}"
    done
    echo -e "${YELLOW}0)${NC} Usar /User/files - (Carpeta de Usuario)"

    read -rp "Usuario: " u

    if [ "$u" = "0" ]; then
        # Selección directa /files
        echo ""
        echo "Selecciona usuario para usar /files:"
        for i in "${!users[@]}"; do
            echo -e "${YELLOW}$((i+1)))${NC} ${users[$i]}/files"
        done
        read -rp "Usuario: " u
        [[ ! "$u" =~ ^[0-9]+$ || $u -lt 1 || $u -gt ${#users[@]} ]] && error "Inválido" && return 1

        USER_SEL="${users[$((u-1))]}"
        RUTA_SELECCIONADA="$DATA_PATH/$USER_SEL/files"
        USER_PATH="$RUTA_SELECCIONADA"

        echo -e "${CYAN}Usando ruta directa del usuario: $RUTA_SELECCIONADA${NC}"

        # Listar subcarpetas (informativo)
        mapfile -t subdirs < <(find "$RUTA_SELECCIONADA" -mindepth 1 -maxdepth 1 -type d)
        if [ ${#subdirs[@]} -gt 0 ]; then
            echo -e "${CYAN}Subcarpetas dentro de $RUTA_SELECCIONADA:${NC}"
            for sub in "${subdirs[@]}"; do
                echo " - $(basename "$sub")"
            done
        else
            echo -e "${YELLOW}No hay subcarpetas en /files${NC}"
        fi

    else
        # Selección normal de usuario y carpeta
        [[ ! "$u" =~ ^[0-9]+$ || $u -lt 1 || $u -gt ${#users[@]} ]] && error "Inválido" && return 1

        USER_SEL="${users[$((u-1))]}"
        BASE_USER="$DATA_PATH/$USER_SEL/files"

        [ ! -d "$BASE_USER" ] && error "No existe: $BASE_USER" && return 1

        mapfile -t dirs < <(find "$BASE_USER" -mindepth 1 -maxdepth 1 -type d)

        [ ${#dirs[@]} -eq 0 ] && error "Sin carpetas" && return 1

        echo ""
        for i in "${!dirs[@]}"; do
            echo -e "${YELLOW}$((i+1)))${NC} $(basename "${dirs[$i]}")"
        done

        read -rp "Carpeta: " c
        [[ ! "$c" =~ ^[0-9]+$ || $c -lt 1 || $c -gt ${#dirs[@]} ]] && error "Inválido" && return 1

        RUTA_SELECCIONADA="${dirs[$((c-1))]}"
        USER_PATH="$RUTA_SELECCIONADA"
    fi
}

    # ===== SELECCION /mnt =====
    seleccionar_mnt(){

        mapfile -t mnts < <(find /mnt -mindepth 1 -maxdepth 1 -type d)

        for i in "${!mnts[@]}"; do
            echo -e "${YELLOW}$((i+1)))${NC} ${mnts[$i]}"
        done

        read -rp "Disco: " d
        BASE="${mnts[$((d-1))]}"

        mapfile -t dirs < <(find "$BASE" -mindepth 1 -maxdepth 1 -type d)

        echo ""
        for i in "${!dirs[@]}"; do
            echo -e "${YELLOW}$((i+1)))${NC} ${dirs[$i]}"
        done

        read -rp "Carpeta: " c
        RUTA_SELECCIONADA="${dirs[$((c-1))]}"
    }

    # ===== ORIGEN =====
    echo -e "${CYAN}=== ORIGEN ===${NC}"
    echo "1) Desde Nextcloud"
    echo "2) Desde /mnt"
    echo "3) Ruta manual"
    read -rp "Opción: " ORIG_OPC

    case $ORIG_OPC in
        1)
            seleccionar_nextcloud
            ORIGEN="$RUTA_SELECCIONADA"
            ;;
        2)
            seleccionar_mnt
            ORIGEN="$RUTA_SELECCIONADA"
            ;;
        3)
            read -rp "Ruta: " ORIGEN
            ;;
        *)
            error "Opción inválida"; return ;;
    esac

    [ ! -e "$ORIGEN" ] && error "Origen inválido" && return

    # ===== DESTINO =====
    echo ""
    echo -e "${CYAN}=== DESTINO ===${NC}"
    echo "1) Desde Nextcloud"
    echo "2) Desde /mnt"
    echo "3) Ruta manual"
    read -rp "Opción: " DEST_OPC

    case $DEST_OPC in
        1)
            seleccionar_nextcloud
            DESTINO="$RUTA_SELECCIONADA"

            echo ""
            read -rp "¿Crear subcarpeta? (ej: peliculas/nuevo) o ENTER para no: " SUB
            [ -n "$SUB" ] && DESTINO="$DESTINO/$SUB" && mkdir -p "$DESTINO"
            ;;
        2)
            seleccionar_mnt
            DESTINO="$RUTA_SELECCIONADA"
            ;;
        3)
            read -rp "Ruta destino: " DESTINO
            ;;
        *)
            error "Opción inválida"; return ;;
    esac

    mkdir -p "$DESTINO"

    echo ""
    echo -e "Origen: ${CYAN}$ORIGEN${NC}"
    echo -e "Destino: ${CYAN}$DESTINO${NC}"

    # ===== TIPO COPIA =====
    echo ""
    echo "1) Copiar carpeta completa"
    echo "2) Solo contenido"
    read -rp "Tipo: " TIPO

    confirmar "¿Continuar?" || return

    echo "===== INICIO =====" | tee -a "$LOG_FILE"

    if [ "$TIPO" = "2" ]; then
        rsync -avh --info=progress2 "$ORIGEN/" "$DESTINO/" | tee -a "$LOG_FILE"
    else
        rsync -avh --info=progress2 "$ORIGEN" "$DESTINO/" | tee -a "$LOG_FILE"
    fi

    # ===== PERMISOS =====
    echo ""
    echo "Permisos:"
    echo "1) Sin permisos"
    echo "2) Genéricos"
    echo "3) ACL"
    read -rp "Tipo: " PTYPE

    if [ "$PTYPE" != "1" ]; then
        echo ""
        echo "1) Solo Nextcloud"
        echo "2) Nextcloud + Jellyfin"
        read -rp "Modo: " PMODE
    fi

    case $PTYPE in
        2)
            chown -R www-data:www-data "$DESTINO"

            if [ "$PMODE" = "1" ]; then
                find "$DESTINO" -type d -exec chmod 750 {} \;
                find "$DESTINO" -type f -exec chmod 640 {} \;
            else
                find "$DESTINO" -type d -exec chmod 775 {} \;
                find "$DESTINO" -type f -exec chmod 664 {} \;
                chmod g+s "$DESTINO"
            fi
            ;;
        3)
            chown -R www-data:www-data "$DESTINO"

            setfacl -R -m u:www-data:rwx "$DESTINO"
            setfacl -R -m d:u:www-data:rwx "$DESTINO"

            if [ "$PMODE" = "2" ]; then
                setfacl -R -m u:jellyfin:rx "$DESTINO"
                setfacl -R -m d:u:jellyfin:rx "$DESTINO"
            fi
            ;;
    esac

    # ===== ESCANEO FINAL =====
    echo ""
    echo "1) Escanear en Nextcloud"
    echo "2) No escanear"
    read -rp "Opción: " SCAN_OPC

    if [ "$SCAN_OPC" = "1" ]; then

        if [[ "$DESTINO" == *"/files"* ]]; then

            USER_NC=$(echo "$DESTINO" | awk -F'/files' '{print $1}' | awk -F'/' '{print $NF}')
            REL=$(realpath --relative-to="$DATA_PATH/$USER_NC/files" "$DESTINO" 2>/dev/null)

            echo -e "${CYAN}Escaneando ruta...${NC}" | tee -a "$LOG_FILE"

            if [ -n "$REL" ]; then
                sudo -u "$USER_WEB" php "$NC_PATH/occ" files:scan "$USER_NC" --path="$USER_NC/files/$REL" | tee -a "$LOG_FILE"
            else
                sudo -u "$USER_WEB" php "$NC_PATH/occ" files:scan "$USER_NC" | tee -a "$LOG_FILE"
            fi

            echo -e "${CYAN}Limpiando caché...${NC}" | tee -a "$LOG_FILE"
            sudo -u "$USER_WEB" php "$NC_PATH/occ" files:cleanup | tee -a "$LOG_FILE"

        else
            echo -e "${YELLOW}No es ruta Nextcloud → no se escanea${NC}" | tee -a "$LOG_FILE"
        fi
    fi

    echo "===== FIN =====" | tee -a "$LOG_FILE"

    ok "✔ Copia total completada PRO"
}

# ========= COPIA GENERICA A HDD/USB + ANTIDUPLICADOS =========
copiar_generico_nct(){
preparar_grupos_nct

    local USER_WEB="${USER_WEB:-www-data}"
    local NEXTCLOUD_DIR="${NC_PATH:-/var/www/nextcloud}"

    echo -e "${CYAN}=== Copia PRO sin duplicados (tiempo real) ===${NC}"

    read -rp "Ruta ORIGEN: " ORIGEN
    read -rp "Ruta DESTINO: " DESTINO

    [ ! -d "$ORIGEN" ] && error "Origen inválido" && return
    mkdir -p "$DESTINO"

    # ===== HASH AUTOMÁTICO =====
    if command -v md5sum >/dev/null 2>&1; then
        HASH_CMD="md5sum"
    elif command -v sha1sum >/dev/null 2>&1; then
        HASH_CMD="sha1sum"
    else
        HASH_CMD="sha256sum"
    fi

    echo -e "${YELLOW}Usando hash:${NC} $HASH_CMD"
    echo ""

    # ===== INDEXAR DESTINO =====
    echo -e "${CYAN}Indexando destino...${NC}"

    declare -A HASH_DEST

    while IFS= read -r -d '' file; do
        hash=$($HASH_CMD "$file" | awk '{print $1}')
        HASH_DEST["$hash"]=1
    done < <(find "$DESTINO" -type f -print0)

    echo -e "${GREEN}Indexación completa (${#HASH_DEST[@]} archivos)${NC}"
    echo ""

    # ===== COPIA INTELIGENTE =====
    COPIADOS=0
    OMITIDOS=0

    echo -e "${CYAN}Procesando archivos...${NC}"

    while IFS= read -r -d '' file; do

        hash=$($HASH_CMD "$file" | awk '{print $1}')

        if [[ -n "${HASH_DEST[$hash]}" ]]; then
            echo -e "${YELLOW}Duplicado omitido:${NC} $file"
            ((OMITIDOS++))
        else
            echo -e "${GREEN}Copiando:${NC} $file"
            cp -a "$file" "$DESTINO/"
            HASH_DEST["$hash"]=1
            ((COPIADOS++))
        fi

    done < <(find "$ORIGEN" -type f -print0)

    echo ""
    echo -e "${CYAN}Resumen:${NC}"
    echo -e "Copiados: ${GREEN}$COPIADOS${NC}"
    echo -e "Omitidos: ${YELLOW}$OMITIDOS${NC}"

    # ===== PERMISOS =====
    echo ""
    echo -e "${YELLOW}Permisos:${NC}"
    echo "1) Sin permisos"
    echo "2) Genéricos"
    echo "3) ACL"
    read -rp "Opción: " PERM_TIPO

    if [ "$PERM_TIPO" != "1" ]; then
        echo ""
        echo "1) Solo Nextcloud"
        echo "2) Nextcloud + Jellyfin"
        read -rp "Aplicar a: " PERM_APP

        case $PERM_TIPO in
            2)
                chown -R www-data:www-data "$DESTINO"
                find "$DESTINO" -type d -exec chmod 750 {} \;
                find "$DESTINO" -type f -exec chmod 640 {} \;

                if [ "$PERM_APP" == "2" ]; then
                    setfacl -R -m g:jellyfin:rx "$DESTINO"
                    setfacl -R -d -m g:jellyfin:rx "$DESTINO"
                fi
                ;;
            3)
                setfacl -R -m u:www-data:rwx "$DESTINO"
                setfacl -R -d -m u:www-data:rwx "$DESTINO"

                if [ "$PERM_APP" == "2" ]; then
                    setfacl -R -m g:jellyfin:r-x "$DESTINO"
                    setfacl -R -d -m g:jellyfin:r-x "$DESTINO"
                fi
                ;;
        esac
    fi

    # ===== ESCANEO =====
    echo ""
    read -rp "¿Escanear en Nextcloud? (s/N): " SCAN

    if [[ "$DESTINO" == *"/files/"* && "$SCAN" =~ ^[sS]$ ]]; then
        USER_NC=$(echo "$DESTINO" | awk -F'/files/' '{print $1}' | awk -F'/' '{print $NF}')
        sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" files:scan "$USER_NC"
    fi

    ok "✔ Copia inteligente finalizada"
}

# ========= Mover y Escanear =========
mover_y_escanear_nct(){

    preparar_grupos_nct

    local DATA_PATH="${DATA_PATH:-/var/www/nextcloud-data}"
    local NC_PATH="${NC_PATH:-/var/www/nextcloud}"
    local USER_WEB="${USER_WEB:-www-data}"
    local LOG_FILE="/var/log/mover_$(date +%F_%H-%M-%S).log"

    echo -e "${CYAN}=== MOVER NEXTCLOUD PRO ULTRA ===${NC}"
    echo ""

    # ===== USUARIOS =====
    mapfile -t USERS < <(find "$DATA_PATH" -mindepth 1 -maxdepth 1 -type d \
        ! -name "appdata_*" ! -name "updater-*" ! -name ".*")

    [ ${#USERS[@]} -eq 0 ] && error "No hay usuarios" && return

    for i in "${!USERS[@]}"; do
        echo -e "${YELLOW}$((i+1)))${NC} $(basename "${USERS[$i]}")"
    done

    read -rp "Selecciona usuario: " u
    USER="$(basename "${USERS[$((u-1))]}")"

    BASE_USER="$DATA_PATH/$USER/files"

    # ===== ORIGEN =====
    echo ""
    echo -e "${CYAN}=== ORIGEN ===${NC}"
    mapfile -t ORIG_DIRS < <(find "$BASE_USER" -mindepth 1 -maxdepth 1 -type d)

    for i in "${!ORIG_DIRS[@]}"; do
        echo -e "${YELLOW}$((i+1)))${NC} $(basename "${ORIG_DIRS[$i]}")"
    done

    read -rp "Carpeta origen: " o
    SRC="${ORIG_DIRS[$((o-1))]}"

    [ ! -e "$SRC" ] && error "Origen inválido" && return

    # ===== DESTINO =====
    echo ""
    echo -e "${CYAN}=== DESTINO ===${NC}"
    mapfile -t DEST_DIRS < <(find "$BASE_USER" -mindepth 1 -maxdepth 1 -type d)

    for i in "${!DEST_DIRS[@]}"; do
        echo -e "${YELLOW}$((i+1)))${NC} $(basename "${DEST_DIRS[$i]}")"
    done

    echo -e "${YELLOW}0)${NC} Escribir nueva ruta"
    read -rp "Destino: " d

    if [ "$d" = "0" ]; then
        read -rp "Nueva carpeta destino (ej: media/nuevo): " NEW_PATH
        DST="$BASE_USER/$NEW_PATH"
        mkdir -p "$DST"
    else
        DST="${DEST_DIRS[$((d-1))]}"
    fi

    echo ""
    echo -e "Origen: ${CYAN}$SRC${NC}"
    echo -e "Destino: ${CYAN}$DST${NC}"

    # ===== TIPO =====
    echo ""
    echo "1) Mover carpeta completa"
    echo "2) Mover solo contenido"
    read -rp "Opción: " TIPO

    confirmar "¿Continuar?" || return

    echo "========== INICIO ==========" | tee -a "$LOG_FILE"

    if [ "$TIPO" = "2" ]; then
        shopt -s dotglob nullglob
        mv "$SRC"/* "$DST"/ 2>/dev/null | tee -a "$LOG_FILE"
        shopt -u dotglob nullglob
    else
        BASENAME=$(basename "$SRC")
        mv "$SRC" "$DST/$BASENAME" | tee -a "$LOG_FILE"
        DST="$DST/$BASENAME"
    fi

    # ===== PERMISOS =====
    echo ""
    echo "Permisos:"
    echo "1) No aplicar"
    echo "2) Genéricos"
    echo "3) ACL"
    read -rp "Tipo: " PTYPE

    if [ "$PTYPE" != "1" ]; then
        echo ""
        echo "1) Solo Nextcloud"
        echo "2) Nextcloud + Jellyfin"
        read -rp "Modo: " PMODE
    fi

    case $PTYPE in
        2)
            chown -R www-data:www-data "$DST"

            if [ "$PMODE" = "1" ]; then
                find "$DST" -type d -exec chmod 750 {} \;
                find "$DST" -type f -exec chmod 640 {} \;
            else
                find "$DST" -type d -exec chmod 775 {} \;
                find "$DST" -type f -exec chmod 664 {} \;
                chmod g+s "$DST"
            fi
            ;;
        3)
            chown -R www-data:www-data "$DST"

            setfacl -R -m u:www-data:rwx "$DST"
            setfacl -R -m d:u:www-data:rwx "$DST"

            if [ "$PMODE" = "2" ]; then
                setfacl -R -m u:jellyfin:rx "$DST"
                setfacl -R -m d:u:jellyfin:rx "$DST"
            fi
            ;;
    esac

    # ===== ESCANEO =====
    echo ""
    read -rp "¿Escanear en Nextcloud? (s/n): " SCAN

    if [[ "$SCAN" =~ ^[sS]$ ]]; then

        REL_DST=$(realpath --relative-to="$BASE_USER" "$DST")

        echo -e "${CYAN}Escaneando destino...${NC}" | tee -a "$LOG_FILE"
        sudo -u "$USER_WEB" php "$NC_PATH/occ" files:scan "$USER" --path="$USER/files/$REL_DST" | tee -a "$LOG_FILE"

        echo -e "${CYAN}Limpiando caché origen...${NC}" | tee -a "$LOG_FILE"
        sudo -u "$USER_WEB" php "$NC_PATH/occ" files:cleanup | tee -a "$LOG_FILE"
    fi

    echo "=========== FIN ===========" | tee -a "$LOG_FILE"

    ok "✔ Movimiento completado PRO"
}

#===   BORRAR NEXTCLOUD PRO   ==

borrar_y_escanear_nct(){

    local DATA_PATH="${DATA_PATH:-/var/www/nextcloud-data}"
    local NC_PATH="${NC_PATH:-/var/www/nextcloud}"
    local USER_WEB="${USER_WEB:-www-data}"
    local LOG_FILE="/var/log/borrar_$(date +%F_%H-%M-%S).log"

    echo -e "${CYAN}=== BORRAR NEXTCLOUD PRO ===${NC}"
    echo ""

    # ===== LISTAR USUARIOS =====
    mapfile -t USERS < <(find "$DATA_PATH" -mindepth 1 -maxdepth 1 -type d \
        ! -name "appdata_*" ! -name "updater-*" ! -name ".*")

    [ ${#USERS[@]} -eq 0 ] && error "No hay usuarios" && return

    for i in "${!USERS[@]}"; do
        echo -e "${YELLOW}$((i+1)))${NC} $(basename "${USERS[$i]}")"
    done

    read -rp "Selecciona usuario: " u
    USER="$(basename "${USERS[$((u-1))]}")"

    BASE_USER="$DATA_PATH/$USER/files"

    # ===== LISTAR CARPETAS =====
    echo ""
    mapfile -t DIRS < <(find "$BASE_USER" -mindepth 1 -maxdepth 1 -type d)

    [ ${#DIRS[@]} -eq 0 ] && error "No hay carpetas" && return

    for i in "${!DIRS[@]}"; do
        echo -e "${YELLOW}$((i+1)))${NC} $(basename "${DIRS[$i]}")"
    done

    echo -e "${YELLOW}0)${NC} Escribir ruta manual"
    read -rp "Carpeta: " c

    if [ "$c" = "0" ]; then
        read -rp "Ruta (ej: media/peliculas): " RUTA
        FULL="$BASE_USER/$RUTA"
    else
        FULL="${DIRS[$((c-1))]}"
    fi

    [ ! -e "$FULL" ] && error "Ruta inválida" && return

    echo ""
    echo -e "Ruta seleccionada: ${CYAN}$FULL${NC}"

    # ===== TIPO BORRADO =====
    echo ""
    echo "1) Borrar carpeta completa"
    echo "2) Borrar solo contenido"
    read -rp "Opción: " TIPO

    # ===== DOBLE CONFIRMACIÓN =====
    echo ""
    read -rp "Escribe BORRAR para confirmar: " CONFIRM

    [ "$CONFIRM" != "BORRAR" ] && echo "Cancelado" && return

    confirmar "¿Seguro?" || return

    echo "========== INICIO ==========" | tee -a "$LOG_FILE"

    if [ "$TIPO" = "2" ]; then
        shopt -s dotglob nullglob
        rm -rf "$FULL"/* 2>/dev/null | tee -a "$LOG_FILE"
        shopt -u dotglob nullglob
    else
        rm -rf "$FULL" | tee -a "$LOG_FILE"
    fi

    # ===== ESCANEO =====
    echo ""
    read -rp "¿Escanear en Nextcloud? (s/n): " SCAN

    if [[ "$SCAN" =~ ^[sS]$ ]]; then
        echo -e "${CYAN}Escaneando usuario...${NC}" | tee -a "$LOG_FILE"
        sudo -u "$USER_WEB" php "$NC_PATH/occ" files:scan "$USER" | tee -a "$LOG_FILE"

        echo -e "${CYAN}Limpiando caché...${NC}" | tee -a "$LOG_FILE"
        sudo -u "$USER_WEB" php "$NC_PATH/occ" files:cleanup | tee -a "$LOG_FILE"
    fi

    echo "=========== FIN ===========" | tee -a "$LOG_FILE"

    ok "✔ Borrado completado PRO"
}

# ========= MONTAR HDD/USB SIN FORMATEAR PERMISOS GENERICOS/ALC =========
montar_sin_formato_nct(){

    echo -e "${CYAN}=== Montar disco ===${NC}"

    WEB_USER="www-data"
    NC_PATH="/var/www/nextcloud"

    mapfile -t DISKS < <(lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT -nr | grep part)

    [ ${#DISKS[@]} -eq 0 ] && echo -e "${RED}❌ No hay particiones${NC}" && return

    i=1
    for d in "${DISKS[@]}"; do
        echo "$i) $d"
        ((i++))
    done

    read -rp "Selecciona número: " NUM

    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || [ "$NUM" -lt 1 ] || [ "$NUM" -gt ${#DISKS[@]} ]; then
        echo -e "${RED}❌ Selección inválida${NC}"
        return
    fi

    DEV_NAME=$(echo "${DISKS[$((NUM-1))]}" | awk '{print $1}')
    DEV="/dev/$DEV_NAME"

    if findmnt -rn -S "$DEV" >/dev/null; then
        echo -e "${YELLOW}⚠ Ya está montado${NC}"
        return
    fi

    MNT="/mnt/$DEV_NAME"
    mkdir -p "$MNT"

    FSTYPE=$(blkid -s TYPE -o value "$DEV" 2>/dev/null)
    UUID=$(blkid -s UUID -o value "$DEV")

    echo -e "${CYAN}FS: ${FSTYPE:-desconocido}${NC}"

    case "$FSTYPE" in
        exfat)
            mount -t exfat "$DEV" "$MNT" -o uid=$WEB_USER,gid=$WEB_USER,umask=002
            OPTIONS="defaults,uid=$WEB_USER,gid=$WEB_USER,umask=002"
        ;;
        ntfs)
            mount -t ntfs-3g "$DEV" "$MNT" -o uid=$WEB_USER,gid=$WEB_USER,umask=002
            OPTIONS="defaults,uid=$WEB_USER,gid=$WEB_USER,umask=002"
        ;;
        vfat)
            mount -t vfat "$DEV" "$MNT" -o uid=$WEB_USER,gid=$WEB_USER,umask=002
            OPTIONS="defaults,uid=$WEB_USER,gid=$WEB_USER,umask=002"
        ;;
        ext4|ext3|xfs)
            mount "$DEV" "$MNT"
            chown -R $WEB_USER:$WEB_USER "$MNT"
            chmod -R 750 "$MNT"
            OPTIONS="defaults"
        ;;
        *)
            mount "$DEV" "$MNT"
            OPTIONS="defaults"
        ;;
    esac

    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error al montar${NC}"
        return
    fi

    echo -e "${GREEN}✔ Montado en $MNT${NC}"

    # FSTAB
    echo
    read -rp "¿Agregar montaje automático al iniciar (fstab)? (s/n): " RESP

    if [[ "$RESP" =~ ^[sS]$ ]]; then
        if grep -q "$UUID" /etc/fstab; then
            echo -e "${YELLOW}⚠ Ya existe en fstab${NC}"
        else
            echo "UUID=$UUID $MNT $FSTYPE $OPTIONS 0 2" >> /etc/fstab
            echo -e "${GREEN}✔ Añadido a /etc/fstab${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ No persistente${NC}"
    fi

    # SCAN NEXTCLOUD
    echo
    read -rp "Usuario Nextcloud: " NC_USER
    read -rp "Carpeta interna (default files/$DEV_NAME): " NC_FOLDER

    NC_FOLDER=${NC_FOLDER:-files/$DEV_NAME}

    echo -e "${CYAN}Escaneando: $NC_USER/$NC_FOLDER${NC}"

    sudo -u $WEB_USER php "$NC_PATH/occ" files:scan --path="$NC_USER/$NC_FOLDER"

    echo -e "${GREEN}✔ Escaneo completado${NC}"
}

# ------------ DESMONTAR USB/HDD Y LIMPIAR DE FSTAB + ESCANEO AUTOMÁTICO -------------------
desmontar_y_limpiar_nct() {
    echo -e "${CYAN}=== Dispositivos montados ===${NC}"
    echo -e "NUM  DISPOSITIVO       MONTAJE      USUARIO"
    echo "------------------------------------------------------"

    # Listar montajes en /mnt y en /files/<usuario>
    mapfile -t MOUNTS < <(
        lsblk -o NAME,MOUNTPOINT,FSTYPE,SIZE -nr | awk '$2 ~ "^/mnt" || $2 ~ "/files/" {print $1 "|" $2 "|" $3 "|" $4}'
    )

    if [ ${#MOUNTS[@]} -eq 0 ]; then
        echo -e "${YELLOW}⚠ No se detectaron discos montados en /mnt o /files/${NC}"
        return
    fi

    # Construir listado y mostrar
    i=1
    declare -A MNT_USER_MAP
    for m in "${MOUNTS[@]}"; do
        DEV="/dev/${m%%|*}"
        MP=$(echo "$m" | cut -d'|' -f2)
        FS=$(echo "$m" | cut -d'|' -f3)
        SIZE=$(echo "$m" | cut -d'|' -f4)
        # Detectar usuario si está en /files/<usuario>
        if [[ "$MP" =~ "/files/" ]]; then
            USER_NAME=$(echo "$MP" | sed -E 's#.*/files/([^/]+).*#\1#')
        else
            USER_NAME="-"
        fi
        MNT_USER_MAP[$i]="$MP|$USER_NAME"
        echo "$i) $DEV -> $MP  [$FS $SIZE]  Usuario: $USER_NAME"
        ((i++))
    done

    # Selección
    read -rp "Selecciona el disco a desmontar: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || [ "$NUM" -lt 1 ] || [ "$NUM" -ge "$i" ]; then
        echo -e "${RED}Opción inválida${NC}"
        return
    fi

    SELECTED="${MNT_USER_MAP[$NUM]}"
    MNT_PATH=$(echo "$SELECTED" | cut -d'|' -f1)
    USER_NAME=$(echo "$SELECTED" | cut -d'|' -f2)
    DEV_PATH=$(lsblk -nr | awk -v mp="$MNT_PATH" '$7==mp {print "/dev/"$1}')

    # Desmontar a la fuerza
    echo -e "${CYAN}Desmontando $DEV_PATH -> $MNT_PATH ...${NC}"
    umount -l "$MNT_PATH" &>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✔ Desmontado correctamente${NC}"
    else
        echo -e "${RED}❌ Error al desmontar${NC}"
        return
    fi

    # Preguntar si borrar fstab
    read -rp "¿Eliminar entrada de fstab? (s/n): " RESP
    if [[ "$RESP" =~ ^[sS]$ ]]; then
        sed -i "\|$MNT_PATH|d" /etc/fstab
        echo -e "${GREEN}✔ Entrada eliminada de fstab${NC}"
    fi

    # ------------------ ESCANEO AUTOMÁTICO ------------------
    if [[ "$MNT_PATH" =~ "/files/" && "$USER_NAME" != "-" ]]; then
        echo -e "${CYAN}Escaneando usuario Nextcloud: $USER_NAME ...${NC}"
        sudo -u www-data php /var/www/nextcloud/occ files:scan "$USER_NAME"
        echo -e "${GREEN}✔ Escaneo completado para $USER_NAME${NC}"
    elif [[ "$MNT_PATH" =~ "^/mnt" ]]; then
        echo -e "${CYAN}Escaneando almacenamiento externo en Nextcloud ...${NC}"
        sudo -u www-data php /var/www/nextcloud/occ files_external:scan --all
        echo -e "${GREEN}✔ Escaneo de almacenamiento externo completado${NC}"
    fi
}

# ------------------ Formatear y Montar + Permisos ACL/Genericos ------------------
formatear_y_montar_nct() {
    echo -e "${CYAN}=== FORMATEO SEGURO EXTREMO ===${NC}"
    echo

    WEB_USER="www-data"

    # ------------------ FUNCION DEPENDENCIAS ------------------
    check_dependencias_discos_nct

    # ------------------ SELECCIÓN DE DISCO ------------------
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,MODEL
    echo
    read -rp "Disco a formatear (ej: /dev/sdb): " DISK
    [ ! -b "$DISK" ] && echo -e "${RED}Disco inválido${NC}" && return

    ROOT_DISK=$(lsblk -no PKNAME $(findmnt -n -o SOURCE /) | head -n1)
    if [[ "$DISK" == "/dev/$ROOT_DISK" ]]; then
        echo -e "${RED}❌ ESTE ES EL DISCO DEL SISTEMA ($DISK). OPERACIÓN BLOQUEADA${NC}"
        return
    fi

    echo -e "${YELLOW}Información del disco:${NC}"
    lsblk "$DISK"
    echo
    read -rp "⚠ Escribe EXACTAMENTE el disco para confirmar ($DISK): " CONFIRM_DISK
    [ "$CONFIRM_DISK" != "$DISK" ] && echo "Cancelado" && return
    read -rp "⚠ ÚLTIMA CONFIRMACIÓN (yes/no): " CONF
    [[ "$CONF" != "yes" ]] && echo "Cancelado" && return

    # ------------------ DESMONTAR Y MATAR PROCESOS ------------------
    MOUNTED_PARTS=$(lsblk -ln "$DISK" | awk '$7!="" {print $1}')
    if [ -n "$MOUNTED_PARTS" ]; then
        echo -e "${CYAN}Desmontando particiones montadas y matando procesos...${NC}"
        for part in $MOUNTED_PARTS; do
            fuser -km "/dev/$part" 2>/dev/null
            umount -l "/dev/$part" 2>/dev/null
        done
        sleep 2
    fi

    # ------------------ LIMPIEZA PROFUNDA ------------------
    echo -e "${CYAN}Limpiando firmas (wipefs) sobre $DISK...${NC}"
    wipefs -a "$DISK"

    # ------------------ CREAR TABLA Y PARTICIÓN ------------------
    echo -e "${CYAN}Creando tabla GPT y partición única...${NC}"
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart primary 0% 100%
    partprobe "$DISK"
    sleep 2
    DEV="${DISK}1"
    [ ! -b "$DEV" ] && echo -e "${RED}No se creó la partición${NC}" && return

    # ------------------ ELEGIR FILESYSTEM ------------------
    echo
    echo "Sistema de archivos:"
    echo "1) ext4 (RECOMENDADO Nextcloud/Jellyfin)"
    echo "2) ntfs"
    echo "3) exfat"
    echo "4) fat32"
    read -rp "Opción: " FS

    case $FS in
        1) mkfs.ext4 -F "$DEV"; FSTYPE="ext4" ;;
        2) mkfs.ntfs -f "$DEV"; FSTYPE="ntfs" ;;
        3) mkfs.exfat "$DEV"; FSTYPE="exfat" ;;
        4) mkfs.vfat "$DEV"; FSTYPE="vfat" ;;
        *) echo -e "${RED}Opción inválida${NC}"; return ;;
    esac

    # ------------------ ELEGIR PUNTO DE MONTAJE ------------------
    echo
    echo "Montar disco en:"
    echo "1) /mnt/<dispositivo>"
    echo "2) /files/<dispositivo> (usuarios Nextcloud)"
    read -rp "Opción: " MNT_OPC

    case "$MNT_OPC" in
        1)
            DEV_NAME=$(basename "$DEV")
            MNT="/mnt/$DEV_NAME"
            mkdir -p "$MNT"
            ;;
        2)
            echo -e "${CYAN}Detectando usuarios Nextcloud...${NC}"
            DATA_PATH="/var/www/nextcloud-data"
            [ ! -d "$DATA_PATH" ] && echo -e "${RED}No existe: $DATA_PATH${NC}" && return
            mapfile -t USERS < <(for d in "$DATA_PATH"/*; do [ -d "$d/files" ] && basename "$d"; done)
            if [ ${#USERS[@]} -eq 0 ]; then
                echo -e "${RED}No se encontraron usuarios${NC}" && return
            fi
            echo ""
            for i in "${!USERS[@]}"; do
                echo "$((i+1))) ${USERS[$i]}"
            done
            read -rp "Usuario: " U_SEL
            USER_NAME="${USERS[$((U_SEL-1))]}"
            MNT="/var/www/nextcloud-data/$USER_NAME/files/$(basename "$DEV")"
            mkdir -p "$MNT"
            ;;
        *)
            echo -e "${RED}Opción inválida${NC}" && return ;;
    esac

    # ------------------ PERMISOS ------------------
    if [[ "$FSTYPE" == "ext4" ]]; then
        echo
        echo "Tipo de permisos para Nextcloud y Jellyfin:"
        echo "1) Estándar (chown www-data:www-data + chmod 750)"
        echo "2) ACL extendidos (setfacl)"
        read -rp "Opción: " PERM_OPT
    else
        echo -e "${YELLOW}⚠ Permisos estándar aplicados automáticamente para $FSTYPE${NC}"
        PERM_OPT=1
    fi

    # ------------------ MONTAJE ------------------
    case "$FSTYPE" in
        ntfs|exfat|vfat)
            mount "$DEV" "$MNT" -o uid=$(id -u $WEB_USER),gid=$(id -g $WEB_USER),umask=002
            ;;
        ext4)
            mount -o acl "$DEV" "$MNT"
            if [ $? -ne 0 ]; then echo -e "${RED}Error al montar $DEV${NC}" && return; fi
            if [[ "$PERM_OPT" == 1 ]]; then
                chown -R $WEB_USER:$WEB_USER "$MNT"
                find "$MNT" -type d -exec chmod 750 {} \;
                find "$MNT" -type f -exec chmod 640 {} \;
            else
                chown -R $WEB_USER:$WEB_USER "$MNT"
                setfacl -R -m u:$WEB_USER:rwx "$MNT"
                setfacl -R -m d:u:$WEB_USER:rwx "$MNT"
                if id jellyfin &>/dev/null; then
                    setfacl -R -m u:jellyfin:rx "$MNT"
                    setfacl -R -m d:u:jellyfin:rx "$MNT"
                fi
            fi
            ;;
    esac

    # ------------------ LIMPIAR ENTRADAS ANTIGUAS DE FSTAB ------------------
# Elimina cualquier línea que contenga el punto de montaje o el UUID del dispositivo
sed -i "\|$MNT|d" /etc/fstab
UUID=$(blkid -s UUID -o value "$DEV")
sed -i "\|$UUID|d" /etc/fstab

# ------------------ NUEVA ENTRADA ------------------
case "$FSTYPE" in
    ext4)
        # Montaje de disco ext4 con opciones seguras y nofail
        echo "UUID=$UUID $MNT ext4 defaults,acl,noatime,nofail 0 2" >> /etc/fstab
        ;;
    *)
        # Montaje de otros sistemas de archivos (NTFS, exFAT, etc.) con uid/gid y nofail
        echo "UUID=$UUID $MNT $FSTYPE defaults,uid=$(id -u $WEB_USER),gid=$(id -g $WEB_USER),umask=002,nofail 0 0" >> /etc/fstab
        ;;
esac

echo "✔ Entrada agregada a /etc/fstab con 'nofail'"

    # ------------------ REMONTAJE REAL ------------------
    echo -e "${CYAN}Recargando systemd y aplicando montaje limpio desde fstab...${NC}"
    systemctl daemon-reload
    umount "$MNT" 2>/dev/null
    mount -a

    # 🔍 VERIFICACIÓN FINAL ACL
    if [[ "$FSTYPE" == "ext4" ]]; then
        echo -e "${CYAN}Verificando ACL real en $MNT...${NC}"
        touch "$MNT"/.acl_test &>/dev/null
        setfacl -m u:$WEB_USER:rwx "$MNT"/.acl_test &>/dev/null
        if [ $? -eq 0 ]; then
            rm -f "$MNT"/.acl_test
            echo -e "${GREEN}✔ ACL ACTIVO correctamente${NC}"
        else
            echo -e "${RED}❌ ACL NO ACTIVO en $MNT${NC}"
        fi
    fi

    # ------------------ ESCANEO NEXTCLOUD SI APLICA ------------------
    if [[ "$MNT_OPC" == "2" ]]; then
        echo -e "${CYAN}Escaneando Nextcloud para usuario $USER_NAME...${NC}"
        NC_PATH="/var/www/nextcloud"
        REL=$(realpath --relative-to="/var/www/nextcloud-data/$USER_NAME/files" "$MNT" 2>/dev/null)
        sudo -u $WEB_USER php "$NC_PATH/occ" files:scan "$USER_NAME" --path="$USER_NAME/files/$REL"
        sudo -u $WEB_USER php "$NC_PATH/occ" files:cleanup
    fi

    echo -e "${GREEN}✔ DISCO FORMATEADO, MONTADO Y LISTO${NC}"
}

# ------------------ MONTAR CARPETA /FILES DE USUARIOS NEXTCLOUD ------------------
montar_files_user_nct() {
    read -rp "Usuario Nextcloud: " USER_NC
    BASE="/var/www/nextcloud-data/$USER_NC/files"
    [ ! -d "$BASE" ] && echo -e "${RED}Ruta no existe: $BASE${NC}" && return

    echo -e "${CYAN}Listando carpetas de /files de $USER_NC:${NC}"
    mapfile -t DIRS < <(find "$BASE" -mindepth 1 -maxdepth 1 -type d)
    for i in "${!DIRS[@]}"; do
        echo -e "$((i+1))) ${DIRS[$i]}"
    done
    echo "0) Usar /files directo"
    read -rp "Selecciona carpeta: " SEL

    if [[ "$SEL" == "0" ]]; then
        MNT="$BASE"
    else
        MNT="${DIRS[$((SEL-1))]}"
    fi

    mkdir -p "$MNT"
    sed -i "\|$MNT|d" /etc/fstab
    echo "$MNT $MNT none bind 0 0" >> /etc/fstab
    mount -a

    echo -e "${GREEN}✔ Carpeta $MNT montada correctamente y persistente${NC}"
}

# ========= INSTALAR DEPENDENCIAS PARA FORMATEAR DISCOS =========
check_dependencias_discos_nct() {
    echo -e "${CYAN}=== Verificando dependencias para gestión de discos ===${NC}"

    DEPENDENCIAS=(parted partprobe mkfs.ext4 mkfs.ntfs mkfs.exfat mkfs.vfat rsync ntfs-3g setfacl)

    for CMD in "${DEPENDENCIAS[@]}"; do
        if ! command -v "$CMD" &>/dev/null; then
            echo -e "${YELLOW}⚠ $CMD no encontrado, instalando...${NC}"
            case "$CMD" in
                parted|partprobe|mkfs.ext4|mkfs.vfat)
                    apt install -y parted util-linux
                    ;;
                mkfs.ntfs|ntfs-3g)
                    apt install -y ntfs-3g
                    ;;
                mkfs.exfat)
                    apt install -y exfat-fuse exfatprogs
                    ;;
                rsync)
                    apt install -y rsync
                    ;;
                setfacl)
                    apt install -y acl
                    ;;
                *)
                    echo -e "${RED}❌ No se puede instalar $CMD automáticamente${NC}"
                    ;;
            esac

            # Verificar nuevamente
            if ! command -v "$CMD" &>/dev/null; then
                echo -e "${RED}❌ Error instalando $CMD, revisa manualmente${NC}"
            else
                echo -e "${GREEN}✔ $CMD instalado correctamente${NC}"
            fi
        else
            echo -e "${GREEN}✔ $CMD encontrado${NC}"
        fi
    done

    echo -e "${CYAN}✅ Todas las dependencias revisadas${NC}"
}

# ========= INSTALA SOPORTE PARA MONTAR NTFS/XFAT/FAT32 =========

instalar_soporte_discos_nct(){
    apt update
    apt install -y exfat-fuse exfatprogs ntfs-3g dosfstools
    ok "Soporte instalado"
}

# ========= Reparar permisos Nextcloud + Jellyfin =========
reparar_permisos_nct(){
    preparar_grupos_nct
    permisos_nc_jellyfin
}

# =======================================================
# NEXTCLOUD - CONTRASEÑAS DE APLICACIÓN (TOKENS)
# =======================================================
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

NC_PATH="/var/www/nextcloud"
PHP_BIN="php"
WWW_USER="www-data"
DB="/root/tokens.db"

# =======================================================
# SELECCIONAR USUARIO
# =======================================================
seleccionar_usuario() {
    clear
    echo -e "${CYAN}=== SELECCIONAR USUARIO ===${NC}"

    mapfile -t USERS < <(sudo -u $WWW_USER $PHP_BIN $NC_PATH/occ user:list | awk -F: '/- / {print $2}' | sed 's/ //g')

    if [ ${#USERS[@]} -eq 0 ]; then
        echo -e "${RED}No hay usuarios${NC}"
        sleep 1
        return 1
    fi

    for i in "${!USERS[@]}"; do
        echo -e "${YELLOW}$((i+1)))${NC} ${USERS[$i]}"
    done

    echo -e "${YELLOW}0)${NC} Volver"
    echo ""

    read -p "Selecciona usuario: " OPC
    [[ "$OPC" == "0" ]] && return 1
    INDEX=$((OPC-1))
    USUARIO="${USERS[$INDEX]}"

    [[ -z "$USUARIO" ]] && echo -e "${RED}Opción inválida${NC}" && sleep 1 && return 1
    return 0
}

# =======================================================
# CREAR TOKEN CON ALIAS
# =======================================================
crear_token() {
    clear
    echo -e "${CYAN}=== CREAR TOKEN NEXTCLOUD CON ALIAS ===${NC}"

    if ! seleccionar_usuario; then return; fi

    echo -e "Usuario: ${PURPLE}$USUARIO${NC}"
    read -p "Alias del token: " ALIAS
    [[ -z "$ALIAS" ]] && echo -e "${RED}Alias vacío${NC}" && sleep 1 && return

    # ⚡ Verificar duplicado
    if grep -q "^$USUARIO|$ALIAS|" "$DB" 2>/dev/null; then
        echo -e "${RED}Ya existe un token con este alias para este usuario${NC}"
        sleep 2
        return
    fi

    read -s -p "Contraseña de Nextcloud: " PASS
    echo ""
    [[ -z "$PASS" ]] && echo -e "${RED}Contraseña vacía${NC}" && sleep 1 && return

    echo "Creando token..."
    RESULT=$(sudo -u $WWW_USER NC_PASS="$PASS" $PHP_BIN $NC_PATH/occ user:auth-tokens:add "$USUARIO" --password-from-env 2>&1)

    if [[ $? -eq 0 ]]; then
        TOKEN=$(echo "$RESULT" | tail -n1)
        echo "$USUARIO|$ALIAS|$TOKEN" >> "$DB"
        echo -e "${GREEN}✔ Token creado correctamente${NC}"
        echo -e "Usuario: ${PURPLE}$USUARIO${NC}  Alias: ${CYAN}$ALIAS${NC}"
        echo -e "Token: ${YELLOW}$TOKEN${NC}"
    else
        echo -e "${RED}✖ Error al crear token${NC}"
        echo "$RESULT"
    fi
    read -p "ENTER para continuar..."
}

# =======================================================
# VER TOKENS
# =======================================================
ver_tokens() {
    clear
    echo -e "${CYAN}=== TOKENS GUARDADOS ===${NC}"
    echo ""
    [[ ! -f "$DB" ]] && echo -e "${RED}No hay tokens${NC}" && read -p "ENTER para continuar..." && return
    column -t -s '|' "$DB"
    echo ""
    read -p "ENTER para continuar..."
}

# =======================================================
# ELIMINAR TOKEN POR ALIAS
# =======================================================
eliminar_token() {
    if ! seleccionar_usuario; then return; fi
    clear
    echo -e "${CYAN}=== ELIMINAR TOKEN ===${NC}"

    grep "^$USUARIO|" "$DB" 2>/dev/null || { echo -e "${RED}No hay tokens para este usuario${NC}"; read -p "ENTER" && return; }

    column -t -s '|' <(grep "^$USUARIO|" "$DB")
    echo ""
    read -p "Alias a eliminar: " ALIAS
    [[ -z "$ALIAS" ]] && echo -e "${RED}Alias vacío${NC}" && sleep 1 && return

    TOKEN_ID=$(sudo -u $WWW_USER $PHP_BIN $NC_PATH/occ user:auth-tokens:list "$USUARIO" | grep -i "$ALIAS" | awk '{print $1}' 2>/dev/null)
    
    # ⚡ Eliminar en Nextcloud si existe ID
    if [[ -n "$TOKEN_ID" ]]; then
        sudo -u $WWW_USER $PHP_BIN $NC_PATH/occ user:auth-tokens:delete "$USUARIO" "$TOKEN_ID"
    fi

    # ⚡ Eliminar del archivo local
    sed -i "/^$USUARIO|$ALIAS|/d" "$DB"
    echo -e "${GREEN}✔ Token eliminado${NC}"
    read -p "ENTER para continuar..."
}

# =======================================================
# MENÚ PRINCIPAL
# =======================================================
menu_tokens_api() {
    while true; do
        clear
        echo -e "${CYAN}=== GESTIÓN TOKENS NEXTCLOUD NIVEL PRO ===${NC}"
        echo -e "${YELLOW}1)${NC} Crear token con alias"
        echo -e "${YELLOW}2)${NC} Ver tokens"
        echo -e "${YELLOW}3)${NC} Eliminar token por alias"
        echo -e "${YELLOW}0)${NC} Volver"
        echo ""
        read -p "Selecciona opción: " OPC
        case $OPC in
            1) crear_token ;;
            2) ver_tokens ;;
            3) eliminar_token ;;
            0) break ;;
			*) echo -e "${RED}Opción inválida${NC}"; sleep 1 ;;
        esac
    done
}



# ===== GESTIÓN DE DISCOS / FSTAB ======
gestionar_fstab_nct(){
  while true; do
    clear
    echo -e "${BOLD}${CYAN}=== GESTIÓN DE DISCOS / FSTAB ===${NC}"
echo -e "${YELLOW}1)${NC} Ver discos montados"
echo -e "${YELLOW}2)${NC} Agregar disco a /etc/fstab"
echo -e "${YELLOW}3)${NC} Eliminar disco de /etc/fstab"
echo -e "${YELLOW}4)${NC} Ver fstab"
echo -e "${YELLOW}5)${NC} Restaurar backup de fstab"
echo -e "${YELLOW}0)${NC} Salir"
    echo

    read -rp "Opción: " OPC

    case $OPC in
      1)
        echo -e "${CYAN}Discos y particiones montadas:${NC}"
        lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
        read -p "ENTER para continuar..."
        ;;

      2)
        echo -e "${CYAN}Discos disponibles:${NC}"
        mapfile -t DISKS < <(lsblk -lnpo NAME,SIZE,FSTYPE,MOUNTPOINT | grep -v "MOUNTPOINT")
        i=1
        for d in "${DISKS[@]}"; do
          echo "$i) $d"
          ((i++))
        done
        read -rp "Selecciona número: " NUM
        if ! [[ "$NUM" =~ ^[0-9]+$ ]] || [ "$NUM" -lt 1 ] || [ "$NUM" -gt ${#DISKS[@]} ]; then
            echo -e "${RED}❌ Selección inválida${NC}"
            read -p "ENTER..." 
            continue
        fi

        DEV=$(echo "${DISKS[$((NUM-1))]}" | awk '{print $1}')
        if [ ! -b "$DEV" ]; then
            echo -e "${RED}❌ Disco inválido${NC}"
            read -p "ENTER..." 
            continue
        fi

        # Detectar FS automáticamente
        FSTYPE=$(blkid -s TYPE -o value "$DEV")
        echo "FS detectado: $FSTYPE"

        # Sugerir opciones seguras según FS
        case "$FSTYPE" in
          ntfs|exfat|vfat)
            OPTS="defaults,uid=1000,gid=1000,umask=002"
            echo "Se usarán opciones seguras para usuario: $OPTS"
            ;;
          ext4|ext3|xfs)
            OPTS="defaults"
            ;;
          *)
            OPTS="defaults"
            echo -e "${YELLOW}FS desconocido, se usarán opciones por defecto${NC}"
            ;;
        esac

        MNT="/mnt/$(basename $DEV)"
        mkdir -p "$MNT"

        UUID=$(blkid -s UUID -o value "$DEV")
        if grep -q "$UUID" /etc/fstab; then
          echo -e "${YELLOW}⚠ Ya existe en fstab${NC}"
        else
          echo "UUID=$UUID $MNT $FSTYPE $OPTS 0 2" >> /etc/fstab
          echo -e "${GREEN}✔ Agregado a /etc/fstab${NC}"
        fi

        read -p "ENTER para continuar..."
        ;;

      3)
        echo -e "${CYAN}Eliminar disco de /etc/fstab${NC}"
echo "Entradas activas:"
awk '!/^#/ && NF' /etc/fstab | nl -w2 -s') '
echo

read -rp "Número de línea a eliminar (o 'c' para cancelar): " LINE
if [[ "$LINE" =~ ^[0-9]+$ ]]; then
    # Obtener línea real del archivo
    TARGET=$(awk '!/^#/ && NF' /etc/fstab | sed -n "${LINE}p")
    if [ -n "$TARGET" ]; then
        cp /etc/fstab /etc/fstab.bak_$(date +%F_%H-%M-%S)
        # Escapamos caracteres especiales para sed
        ESC_TARGET=$(printf '%s\n' "$TARGET" | sed -e 's/[\/&]/\\&/g')
        sed -i "/$ESC_TARGET/d" /etc/fstab
        echo -e "${GREEN}✔ Entrada eliminada (backup creado)${NC}"
    else
        echo -e "${RED}❌ Línea inválida${NC}"
    fi
else
    echo "Cancelado"
fi
read -p "ENTER para continuar..."
        ;;

      4)
        echo -e "${CYAN}Contenido activo de /etc/fstab:${NC}"
        awk '!/^#/ && NF' /etc/fstab | nl -w2 -s') '
        read -p "ENTER para continuar..."
        ;;

      5)
        echo -e "${CYAN}Restaurar backup de fstab${NC}"
        if [ -f /etc/fstab.bak ]; then
            cp /etc/fstab.bak /etc/fstab
            echo -e "${GREEN}✔ Restaurado desde /etc/fstab.bak${NC}"
        else
            echo -e "${RED}❌ No existe backup de fstab${NC}"
        fi
        read -p "ENTER para continuar..."
        ;;

      0)
        break
        ;;

      *)
        echo "Opción inválida"
        sleep 1
        ;;
    esac
  done
}
# ========= CIERRE =========

# =======================================================
#   MODULO WEBDAV / RCLONE / CRON PRO (COMPLETO FINAL)
# =======================================================

# ===================== COLORES ==========================
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
RED="\033[1;31m"
NC="\033[0m"

# ===================== CORE PRO =========================
LOG_FILE="/var/log/webdav_pro.log"

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$LOG_FILE"
}

# =======================================================
# INSTALAR SI FALTA PARA WEBDAV/RCLONE
# =======================================================
instalar_si_falta() {
    PKG=$1

    if dpkg -s "$PKG" >/dev/null 2>&1; then
        echo -e "${GREEN}✔ $PKG ya está instalado${NC}"
        return 0
    fi

    echo -e "${YELLOW}⚠ $PKG no está instalado → instalando automático...${NC}"

    # Evitar bloqueos de APT
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo -e "${CYAN}⏳ Esperando que APT se libere...${NC}"
        sleep 2
    done

    # Configuración automática para davfs2 (sin preguntas)
    if [[ "$PKG" == "davfs2" ]]; then
        echo "davfs2 davfs2/mount_webdav boolean true" | debconf-set-selections
    fi

    # Update una sola vez por ejecución (optimizado)
    if [ -z "$APT_UPDATED" ]; then
        if ! apt update; then
            echo -e "${RED}Error APT → corrigiendo hora...${NC}"

            apt install -y ntpdate >/dev/null 2>&1
            timedatectl set-ntp false >/dev/null 2>&1
            ntpdate pool.ntp.org >/dev/null 2>&1
            timedatectl set-ntp true >/dev/null 2>&1

            apt update || return 1
        fi
        APT_UPDATED=1
    fi

    # Instalación silenciosa
    DEBIAN_FRONTEND=noninteractive apt install -y "$PKG" \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        -o Dpkg::Progress-Fancy="1" || return 1

    echo -e "${GREEN}✔ $PKG instalado correctamente${NC}"
}
# =======================================================
# VALIDA WEBDAV
# =======================================================
validar_webdav() {
    URL=$1
    USER=$2
    PASS=$3

    curl -u "$USER:$PASS" -s -o /dev/null -w "%{http_code}" "$URL" | grep -q "200\|207"
}
# =======================================================
# VALIDA RUTA
# =======================================================
validar_ruta() {
    [ -z "$1" ] && return 1
    return 0
}

# =======================================================
# CONFIGURAR REMOTO RCLONE
# =======================================================

configurar_remoto_inteligente() {

    instalar_si_falta rclone || return

    echo -e "${CYAN}Configurando remoto Rclone${NC}"
    read -p "Nombre del remoto Eje: webdav-servidor: " REMOTO

    if rclone listremotes | grep -q "^$REMOTO:$"; then
        echo "El remoto '$REMOTO' ya existe."
        echo -e "${YELLOW}1)${NC} Mantenerlo"
        echo -e "${YELLOW}2)${NC} Reconfigurar (borrar y crear de nuevo)"
        echo -e "${YELLOW}3)${NC} Eliminar remoto"
        read -p "Selecciona opción: " EXIST_OP

        case $EXIST_OP in
            1)
                echo "Se mantiene el remoto existente."
                read -p "ENTER..."
                return
            ;;
            2)
                echo "Reconfigurando remoto..."
                rclone config delete "$REMOTO"
            ;;
            3)
                echo "Eliminando remoto..."
                rclone config delete "$REMOTO"
                echo -e "${GREEN}✔ Remoto eliminado${NC}"
                read -p "ENTER..."
                return
            ;;
            *)
                echo "Opción inválida, se mantiene el remoto."
                read -p "ENTER..."
                return
            ;;
        esac
    fi
    echo -ne "${CYAN}URL WebDAV Eje: ${YELLOW}https://mi.server/remote.php/dav/files/user${NC}: "
    read URL    
    read -p "Usuario: " USER
    read -s -p "Contraseña: " PASS
    echo

    echo "Selecciona Vendor:"
    echo -e "${YELLOW}1)${NC} nextcloud"
    echo -e "${YELLOW}2)${NC} owncloud"
    read -p "Opción: " V_OPT

    case $V_OPT in
        1) VENDOR="nextcloud" ;;
        2) VENDOR="owncloud" ;;
        *) echo "Opción inválida, usando nextcloud"; VENDOR="nextcloud" ;;
    esac

    # ================= VALIDACIÓN REAL =================
    echo -e "${CYAN}Validando conexión WebDAV...${NC}"

    STATUS=$(curl -u "$USER:$PASS" -s -o /dev/null -w "%{http_code}" "$URL")

    if [[ "$STATUS" != "200" && "$STATUS" != "207" ]]; then
        echo -e "${RED}✖ Error de conexión o credenciales incorrectas (HTTP $STATUS)${NC}"
        read -p "ENTER..."
        return
    fi

    echo -e "${GREEN}✔ Conexión válida${NC}"

    # ================= CREAR REMOTO =================
    rclone config create "$REMOTO" webdav \
        url "$URL" \
        vendor "$VENDOR" \
        user "$USER" \
        pass "$PASS"

    log_action "Remoto creado: $REMOTO ($URL)"

    echo -e "${GREEN}✔ Remoto '$REMOTO' creado y listo${NC}"
    read -p "ENTER..."
}

# =======================================================
# MONTAR REMOTO TEMPORAL / PERMANENTE RCLONE (FSTAB - SERVICE)
# =======================================================

montar_remoto() {

    # ===== COLORES =====
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'

    LOG="/tmp/rclone_pro.log"

    log_action() { echo "$(date '+%F %T') - $1" >> "$LOG"; }
    pausar() { read -p "ENTER para continuar..."; }

    while true; do
        clear
        echo -e "${CYAN}=== RCLONE REMOTOS ===${NC}"
        echo -e "${YELLOW}1)${NC} Montar remoto / hacer permanente"
        echo -e "${YELLOW}2)${NC} Listar montajes y servicios"
        echo -e "${YELLOW}3)${NC} Desmontar / eliminar fstab y servicios"
        echo -e "${YELLOW}0)${NC} Salir"
        read -p "Selecciona opción: " MENU_OP

        case "$MENU_OP" in
            1)
                # ===== LISTAR REMOTOS =====
                REMOTOS=$(rclone listremotes)
                if [[ -z "$REMOTOS" ]]; then
                    echo -e "${RED}✘ No hay remotos configurados${NC}"
                    pausar
                    continue
                fi
                echo -e "${CYAN}Remotos disponibles:${NC}"
                i=1; declare -A REMAP
                for R in $REMOTOS; do
                    echo -e "${YELLOW}$i)${NC} ${R%:}"
                    REMAP[$i]="${R%:}"
                    ((i++))
                done
                read -p "Selecciona el remoto: " SEL
                REMOTO="${REMAP[$SEL]}"
                [[ -z "$REMOTO" ]] && echo -e "${RED}✘ Opción inválida${NC}" && pausar && continue

                # ===== RUTAS =====
                read -p "Ruta remota (ej: /backup, Enter para todo): " REMOTE_PATH
                read -p "Ruta local (ej: /mnt/webdav/nombre): " LOCAL_PATH
                [[ -z "$LOCAL_PATH" ]] && echo -e "${RED}✘ Ruta local obligatoria${NC}" && pausar && continue
                mkdir -p "$LOCAL_PATH"

                # ===== Usuario Nextcloud =====
                read -p "Usuario Nextcloud (ej: www-data) para permisos: " NC_USER
                [[ -z "$NC_USER" ]] && NC_USER="www-data"
                NC_UID=$(id -u $NC_USER 2>/dev/null)
                NC_GID=$(id -g $NC_USER 2>/dev/null)
                [[ -z "$NC_UID" || -z "$NC_GID" ]] && echo -e "${RED}Usuario Nextcloud no existe${NC}" && pausar && continue

                # ===== Montaje temporal =====
                echo -e "${CYAN}Montando $REMOTO temporalmente...${NC}"
                rclone mount "$REMOTO:$REMOTE_PATH" "$LOCAL_PATH" \
                    --daemon \
                    --vfs-cache-mode writes \
                    --log-file="/tmp/rclone_mount_$REMOTO.log" \
                    --log-level INFO \
                    --allow-other \
                    --uid $NC_UID \
                    --gid $NC_GID
                sleep 2
                if mountpoint -q "$LOCAL_PATH"; then
                    echo -e "${GREEN}✔ Montado correctamente en $LOCAL_PATH${NC}"
                    log_action "MOUNT TEMP $REMOTO:$REMOTE_PATH -> $LOCAL_PATH"
                else
                    echo -e "${RED}✘ Error al montar temporal${NC}"
                    pausar
                    continue
                fi

                # ===== OPCIONES DE PERMANENCIA =====
                echo
                echo "Opciones de montaje permanente:"
                echo -e "${YELLOW}1)${NC} Fstab (_netdev,nofail)"
                echo -e "${YELLOW}2)${NC} Crear systemd service"
                echo -e "${YELLOW}3)${NC} Ambos (fstab + systemd)"
                echo -e "${YELLOW}0)${NC} Ninguno"
                read -p "Selecciona opción: " PERM_OP

                case "$PERM_OP" in
                    1|3)
                        FSTAB_LINE="$REMOTO:$REMOTE_PATH $LOCAL_PATH fuse.rclone _netdev,nofail,allow-other,uid=$NC_UID,gid=$NC_GID,umask=002 0 0"
                        if grep -q "^$REMOTO:$REMOTE_PATH" /etc/fstab 2>/dev/null; then
                            sudo sed -i "s|^$REMOTO:$REMOTE_PATH.*|$FSTAB_LINE|" /etc/fstab
                            echo "✔ Entrada fstab actualizada"
                        else
                            echo "$FSTAB_LINE" | sudo tee -a /etc/fstab > /dev/null
                            echo "✔ Entrada fstab agregada"
                        fi
                        ;;
                esac

                if [[ "$PERM_OP" == "2" || "$PERM_OP" == "3" ]]; then
                    SERVICE_NAME="rclone-${REMOTO// /_}.service"
                    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
                    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Montaje Rclone $REMOTO
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$NC_USER
Group=$NC_USER
ExecStart=/usr/bin/rclone mount $REMOTO:$REMOTE_PATH $LOCAL_PATH --vfs-cache-mode writes --allow-other --uid $NC_UID --gid $NC_GID
ExecStop=/bin/fusermount -u $LOCAL_PATH
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
                    sudo systemctl daemon-reload
                    sudo systemctl enable "$SERVICE_NAME"
                    sudo systemctl start "$SERVICE_NAME"
                    echo "✔ Service systemd $SERVICE_NAME creado y activado"
                fi

                pausar
                ;;
            2)
                # ===== LISTAR MONTAJES =====
                echo -e "${CYAN}Montajes activos:${NC}"
                mount | grep rclone || echo "No hay montajes activos"
                echo
                echo -e "${CYAN}Servicios Rclone creados:${NC}"
                systemctl list-units --type=service | grep rclone || echo "No hay servicios rclone"
                pausar
                ;;
            3)
                # ===== DESMONTAR / ELIMINAR =====
                echo -e "${CYAN}Montajes activos:${NC}"
                mapfile -t MONTES < <(mount | grep rclone | awk '{print $3}')
                if [ ${#MONTES[@]} -eq 0 ]; then echo "No hay montajes"; pausar; continue; fi
                for i in "${!MONTES[@]}"; do echo "$((i+1))) ${MONTES[$i]}"; done
                read -p "Selecciona montaje a desmontar (ENTER para cancelar): " NUM
                [[ -z "$NUM" ]] && continue
                [[ ! "$NUM" =~ ^[0-9]+$ || "$NUM" -lt 1 || "$NUM" -gt ${#MONTES[@]} ]] && echo "Opción inválida" && pausar && continue
                LOCAL_PATH="${MONTES[$((NUM-1))]}"
                REMOTE_URL=$(grep " $LOCAL_PATH " /etc/fstab | awk '{print $1}')

                # Desmontar si está activo
                if mountpoint -q "$LOCAL_PATH"; then
                    sudo umount "$LOCAL_PATH" 2>/dev/null || sudo umount -l "$LOCAL_PATH"
                    echo -e "${GREEN}✔ Desmontado $LOCAL_PATH${NC}"
                fi

                # Eliminar fstab
                # Buscar línea exacta en fstab usando el punto de montaje
LINEA=$(awk -v mnt="$LOCAL_PATH" '$2 == mnt {print $0}' /etc/fstab)

if [ -z "$LINEA" ]; then
    echo -e "${YELLOW}No se encontró en fstab${NC}"
else
    echo
    echo -e "${CYAN}Se eliminará esta línea de fstab:${NC}"
    echo -e "${YELLOW}$LINEA${NC}"
    echo

    read -p "¿Confirmar eliminación? (s/n): " CONF
    [[ ! "$CONF" =~ ^[sS]$ ]] && {
        echo "Cancelado"
        pausar
        continue
    }

    # Obtener URL
    REMOTE_URL=$(echo "$LINEA" | awk '{print $1}')

    # Backup
    sudo cp /etc/fstab /etc/fstab.bak.$(date +%Y%m%d_%H%M%S)

    # Eliminar línea exacta
    sudo grep -vF "$LINEA" /etc/fstab | sudo tee /etc/fstab > /dev/null

    echo -e "${GREEN}✔ Entrada fstab eliminada correctamente${NC}"
fi

                # Eliminar service
                SERVICE_NAME="rclone-${REMOTE_URL// /_}.service"
                SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
                if [ -f "$SERVICE_FILE" ]; then
                    sudo systemctl stop "$SERVICE_NAME"
                    sudo systemctl disable "$SERVICE_NAME"
                    sudo rm -f "$SERVICE_FILE"
                    sudo systemctl daemon-reload
                    echo -e "${GREEN}✔ Service $SERVICE_NAME eliminado${NC}"
                fi

                pausar
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}Opción inválida${NC}"
                pausar
                ;;
        esac
    done
}

# =======================================================
# Listar Carpeta Remota Configurada
# =======================================================
listar_archivos_remoto() {

    instalar_si_falta rclone || return

    # Obtener lista de remotos
    mapfile -t REMOTOS < <(rclone listremotes)

    # 🔴 Validar si hay remotos configurados
    if [ ${#REMOTOS[@]} -eq 0 ]; then
        echo -e "${RED}❌ No hay remotos configurados${NC}"
        read -p "Presiona ENTER para continuar..."
        return 1
    fi

    echo -e "${CYAN}Remotos disponibles:${NC}"
    for i in "${!REMOTOS[@]}"; do
        echo "$((i+1))) ${REMOTOS[$i]}"
    done

    echo
    read -p "Selecciona un remoto: " OPCION

    # 🔴 Validación de la opción
    if ! [[ "$OPCION" =~ ^[0-9]+$ ]] || [ "$OPCION" -lt 1 ] || [ "$OPCION" -gt ${#REMOTOS[@]} ]; then
        echo -e "${RED}Opción inválida${NC}"
        read -p "Presiona ENTER para continuar..."
        return 1
    fi

    REM="${REMOTOS[$((OPCION-1))]}"

    echo -e "${CYAN}Listando contenido de $REM...${NC}"
    rclone lsd "$REM"

    echo
    read -p "Presiona ENTER para continuar..." 
}

# =======================================================
# RCLONE COPIA DE SEGURIDAD AL MISMO SERVER
# =======================================================
rclone_copy() {

    echo -e "${CYAN}=== RCLONE PRO ===${NC}"

    # -------- ORIGEN --------
    read -p "Ruta ORIGEN (ej: /mnt/webdav/user): " ORIGEN < /dev/tty

    # -------- DESTINO --------
    read -p "Ruta DESTINO en remoto del user (ej: /backup): " DEST < /dev/tty

    # -------- REMOTO --------
    echo
    echo "Remoto:"
    echo "1) Elegir de la lista (Recomendado)"
    echo "2) Escribir manual (Listar antes para ver)"

    read -p "Opción: " OPC < /dev/tty

    case "$OPC" in
        1)
            mapfile -t REMOTOS < <(rclone listremotes 2>/dev/null | sed 's/://')

            if [ ${#REMOTOS[@]} -eq 0 ]; then
                echo -e "${RED}No hay remotos configurados${NC}"
                read -p "ENTER..." < /dev/tty
                return
            fi

            echo
            echo "Remotos disponibles:"
            for i in "${!REMOTOS[@]}"; do
                echo "$((i+1))) ${REMOTOS[$i]}"
            done

            read -p "Número: " NUM < /dev/tty

            if [[ "$NUM" =~ ^[0-9]+$ ]] && [ "$NUM" -ge 1 ] && [ "$NUM" -le ${#REMOTOS[@]} ]; then
                REMOTO="${REMOTOS[$((NUM-1))]}"
            else
                echo "Selección inválida"
                return
            fi
        ;;
        2)
            read -p "Remoto: " REMOTO < /dev/tty
        ;;
        *) echo "Opción inválida"; return ;;
    esac

    # -------- MODO --------
    echo
    echo "Modo de copia:"
    echo "1) Copy (seguro, no borra nada)"
    echo "2) Sync (modo espejo, BORRA en destino)"

    read -p "Opción: " MODO < /dev/tty

    case "$MODO" in
        1)
            CMD="rclone copy \"$ORIGEN\" \"$REMOTO:$DEST\" --progress"
            ;;
        2)
            echo
            echo -e "${RED}⚠️ MODO ESPEJO:${NC} borrará archivos en el destino"
            read -p "¿Continuar? (s/n): " CONFIRM < /dev/tty
            [[ ! "$CONFIRM" =~ ^[sS]$ ]] && echo "Cancelado" && return

            CMD="rclone sync \"$ORIGEN\" \"$REMOTO:$DEST\" --progress"
            ;;
        *)
            echo "Opción inválida"
            return
            ;;
    esac

    # -------- RESUMEN --------
    echo
    echo -e "${CYAN}Resumen:${NC}"
    echo "Origen : $ORIGEN"
    echo "Destino: $REMOTO:$DEST"
    echo "Comando: $CMD"

    # -------- EJECUTAR --------
    echo
    read -p "¿Ejecutar ahora? (s/n): " RUN < /dev/tty
    if [[ "$RUN" =~ ^[sS]$ ]]; then
        eval "$CMD"
    fi

    # -------- CRON --------
    echo
    read -p "¿Programar automático? (s/n): " AUTO < /dev/tty
    if [[ "$AUTO" =~ ^[sS]$ ]]; then

        echo
        echo "Frecuencia:"
        echo "1) Cada 5 minutos"
        echo "2) Cada 1 hora"
        echo "3) Diario (03:00)"
        echo "4) Semanal (domingo 03:00)"
        echo "5) Personalizado"

        read -p "Opción: " FREQ < /dev/tty

        case "$FREQ" in
            1) CRON="*/5 * * * *" ;;
            2) CRON="0 * * * *" ;;
            3) CRON="0 3 * * *" ;;
            4) CRON="0 3 * * 0" ;;
            5)
                echo "Formato: MIN HORA DIA MES DIA_SEMANA"
                read -p "Cron: " CRON < /dev/tty
                ;;
            *)
                echo "Opción inválida"
                return
                ;;
        esac

        # evitar duplicados
        (crontab -l 2>/dev/null | grep -v -F "$CMD"; echo "$CRON $CMD") | crontab -

        echo -e "${GREEN}✔ Tarea programada${NC}"
        echo "Cron: $CRON"
    fi

    log_action "RCLONE $CMD"

    echo
    read -p "ENTER para continuar..." < /dev/tty
}
# =======================================================
# BORRAR CONFIGURACION REMOTA / RCLONE
# =======================================================
borrar_config_remota() {

    mapfile -t REMOTOS < <(rclone listremotes)

    if [ ${#REMOTOS[@]} -eq 0 ]; then
        echo "No hay remotos configurados"
        return 1
    fi

    echo -e "${CYAN}Remotos disponibles:${NC}"
    for i in "${!REMOTOS[@]}"; do
        echo "$((i+1))) ${REMOTOS[$i]}"
    done

    echo
    read -p "Selecciona número a eliminar: " OPCION

    # Validación
    if ! [[ "$OPCION" =~ ^[0-9]+$ ]] || [ "$OPCION" -lt 1 ] || [ "$OPCION" -gt ${#REMOTOS[@]} ]; then
        echo -e "${RED}Opción inválida${NC}"
        return 1
    fi

    REM="${REMOTOS[$((OPCION-1))]}"
    REM="${REM%:}"   # quitar ":" final

    read -p "¿Seguro que deseas eliminar '$REM'? (s/n): " CONF
    [[ "$CONF" =~ ^[sS]$ ]] || return

    rclone config delete "$REM"

    echo -e "${GREEN}✔ Remoto eliminado: $REM${NC}"
    log_action "Remoto eliminado: $REM"
}

# ===============================
# GESTION DE CRONTAB (EDITART/BORRAR/CREAR TAREAS)
# ===============================
gestionar_editar_cron() {

    HISTORIAL="/tmp/cron_historial.log"

    # ================= COLORES =================
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'

    validar_cron() {
        [[ "$1" =~ ^([0-9*/,-]+\ ){4}[0-9*/,-]+$ ]]
    }

    validar_numero() {
        [[ "$1" =~ ^[0-9]+$ ]]
    }

    pausar() {
        read -p "Presiona ENTER para continuar..."
    }

    while true; do
        clear
        echo -e "${CYAN}=== GESTIONAR CRONTAB ===${NC}"
        echo
        echo -e "${YELLOW}1)${NC} Agregar tarea"
        echo -e "${YELLOW}2)${NC} Listar tareas"
        echo -e "${YELLOW}3)${NC} Editar tarea"
        echo -e "${YELLOW}4)${NC} Eliminar tarea"
        echo -e "${YELLOW}5)${NC} Activar/Desactivar tarea"
        echo -e "${YELLOW}6)${NC} Historial"
		echo -e "${YELLOW}7)${NC} Editar con nano (modo avanzado)"
        echo -e "${CYAN}0)${NC} Volver"
        echo

        read -p "Selecciona: " OPC

        CRON_LIST=$(crontab -l 2>/dev/null)

        case $OPC in

        # ================= AGREGAR =================
        1)
            echo
            read -p "Etiqueta: " TAG
            read -p "Comando: " CMD

            if [[ -z "$CMD" ]]; then
                echo -e "${RED}✘ Comando vacío${NC}"
                pausar
                continue
            fi

            echo
            echo "Modo:"
            echo "1) Cada 5 min"
            echo "2) Cada hora"
            echo "3) Diario"
            echo "4) Manual"
            read -p "Selecciona: " MODO

            case $MODO in
                1) CRON_EXPR="*/5 * * * *" ;;
                2) CRON_EXPR="0 * * * *" ;;
                3)
                    read -p "Hora (0-23): " H
                    read -p "Minuto (0-59): " M
                    CRON_EXPR="$M $H * * *"
                ;;
                4)
                    read -p "Expresión cron: " CRON_EXPR
                ;;
                *) echo -e "${RED}Opción inválida${NC}"; pausar; continue ;;
            esac

            if ! validar_cron "$CRON_EXPR"; then
                echo -e "${RED}✘ Cron inválido${NC}"
                pausar
                continue
            fi

            NUEVA="$CRON_EXPR $CMD #$TAG"

            if echo "$CRON_LIST" | grep -Fxq "$NUEVA"; then
                echo -e "${YELLOW}⚠ Ya existe${NC}"
            else
                (crontab -l 2>/dev/null; echo "$NUEVA") | crontab -
                echo "$(date) + $NUEVA" >> "$HISTORIAL"
                echo -e "${GREEN}✔ Tarea agregada${NC}"
            fi

            pausar
        ;;

        # ================= LISTAR =================
        2)
            echo -e "${CYAN}=== LISTA DE TAREAS ===${NC}"
            echo

            if [[ -z "$CRON_LIST" ]]; then
                echo -e "${YELLOW}No hay tareas${NC}"
            else
                echo "$CRON_LIST" | nl | sed 's/#OFF/🔴 OFF/g'
                echo
                echo -e "Estado: ${GREEN}Activo${NC} | 🔴 OFF"
            fi

            pausar
        ;;

        # ================= EDITAR =================
        3)
            if [[ -z "$CRON_LIST" ]]; then
                echo -e "${YELLOW}No hay tareas${NC}"
                pausar
                continue
            fi

            echo "$CRON_LIST" | nl
            echo
            read -p "Número: " NUM

            if [[ -z "$NUM" ]] || ! validar_numero "$NUM"; then
                echo -e "${RED}✘ Número inválido${NC}"
                pausar
                continue
            fi

            LINEA=$(echo "$CRON_LIST" | sed -n "${NUM}p")

            if [[ -z "$LINEA" ]]; then
                echo -e "${RED}✘ No existe esa línea${NC}"
                pausar
                continue
            fi

            CRON_ACTUAL=$(echo "$LINEA" | awk '{print $1,$2,$3,$4,$5}')
            CMD_ACTUAL=$(echo "$LINEA" | cut -d' ' -f6-)

            echo -e "${CYAN}Actual:${NC} $LINEA"
            echo
            echo "1) Solo horario"
            echo "2) Solo comando"
            echo "3) Ambos"
            read -p "Opción: " OPC2

            NUEVO_CRON="$CRON_ACTUAL"
            NUEVO_CMD="$CMD_ACTUAL"

            [[ "$OPC2" == "1" || "$OPC2" == "3" ]] && read -p "Nuevo cron: " NUEVO_CRON
            [[ "$OPC2" == "2" || "$OPC2" == "3" ]] && read -p "Nuevo comando: " NUEVO_CMD

            if ! validar_cron "$NUEVO_CRON"; then
                echo -e "${RED}✘ Cron inválido${NC}"
                pausar
                continue
            fi

            TMP=$(mktemp)
            echo "$CRON_LIST" | sed "${NUM}s|.*|$NUEVO_CRON $NUEVO_CMD|" > "$TMP"
            crontab "$TMP"
            rm "$TMP"

            echo "$(date) ~ EDIT $LINEA -> $NUEVO_CRON $NUEVO_CMD" >> "$HISTORIAL"

            echo -e "${GREEN}✔ Editado correctamente${NC}"
            pausar
        ;;

        # ================= ELIMINAR =================
        4)
            if [[ -z "$CRON_LIST" ]]; then
                echo -e "${YELLOW}No hay tareas para eliminar${NC}"
                pausar
                continue
            fi

            echo "$CRON_LIST" | nl
            echo
            read -p "Número a eliminar: " NUM

            if [[ -z "$NUM" ]] || ! validar_numero "$NUM"; then
                echo -e "${RED}✘ Número inválido${NC}"
                pausar
                continue
            fi

            LINEA=$(echo "$CRON_LIST" | sed -n "${NUM}p")

            if [[ -z "$LINEA" ]]; then
                echo -e "${RED}✘ Línea no existe${NC}"
                pausar
                continue
            fi

            echo
            echo -e "${YELLOW}Vas a eliminar:${NC}"
            echo "$LINEA"
            echo
            read -p "¿Confirmar? (s/n): " CONFIRM

            if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
                echo -e "${CYAN}Cancelado${NC}"
                pausar
                continue
            fi

            crontab -l 2>/dev/null | sed "${NUM}d" | crontab -

            echo "$(date) - $LINEA" >> "$HISTORIAL"

            echo -e "${GREEN}✔ Eliminado correctamente${NC}"
            pausar
        ;;

        # ================= ON/OFF =================
        5)
            if [[ -z "$CRON_LIST" ]]; then
                echo -e "${YELLOW}No hay tareas${NC}"
                pausar
                continue
            fi

            echo "$CRON_LIST" | nl
            read -p "Número: " NUM

            if [[ -z "$NUM" ]] || ! validar_numero "$NUM"; then
                echo -e "${RED}✘ Número inválido${NC}"
                pausar
                continue
            fi

            LINEA=$(echo "$CRON_LIST" | sed -n "${NUM}p")

            if [[ -z "$LINEA" ]]; then
                echo -e "${RED}✘ Línea no existe${NC}"
                pausar
                continue
            fi

            if echo "$LINEA" | grep -q "#OFF"; then
                NUEVA=$(echo "$LINEA" | sed 's/#OFF//')
                ESTADO="ACTIVADO"
            else
                NUEVA="$LINEA #OFF"
                ESTADO="DESACTIVADO"
            fi

            TMP=$(mktemp)
            echo "$CRON_LIST" | sed "${NUM}s|.*|$NUEVA|" > "$TMP"
            crontab "$TMP"
            rm "$TMP"

            echo "$(date) * $ESTADO $LINEA" >> "$HISTORIAL"

            echo -e "${GREEN}✔ Tarea $ESTADO${NC}"
            pausar
        ;;

        # ================= HISTORIAL =================
        6)
            echo -e "${CYAN}=== HISTORIAL ===${NC}"
            echo
            cat "$HISTORIAL" 2>/dev/null || echo "Vacío"
            echo
            pausar
        ;;
		
        # ================= NANO =================
        7)
            echo -e "${CYAN}Abriendo crontab en nano...${NC}"
            sleep 1

            EDITOR=nano crontab -e < /dev/tty > /dev/tty 2>&1
			
            echo
            echo -e "${GREEN}✔ Editor cerrado${NC}"
            echo "Recuerda: guarda con CTRL+O y sal con CTRL+X"

            pausar
        ;;
        0) break ;;

        *) echo -e "${RED}Opción inválida${NC}"; sleep 1 ;;

        esac
    done
}

# =======================================================
# MONTAR WEBDAV TEMPORAL
# =======================================================

montar_webdav_temporal() {

    instalar_si_falta davfs2 || return

    echo -ne "${CYAN}URL WebDAV Eje: ${YELLOW}https://mi.server/remote.php/dav/files/user${NC}: "
    read URL
    read -p "Usuario: " USER
    read -s -p "Contraseña: " PASS
    echo
    read -p "Ruta local Eje: /mnt/webdav/servidor: " RUTA

    mkdir -p "$RUTA"

    # 🔍 Verificar si ya está montado
    if mount | grep -q "on $RUTA "; then
        echo -e "${YELLOW}⚠ Ya está montado en $RUTA${NC}"
        read -p "ENTER..."
        return
    fi

    # 🔐 Validar credenciales (si tienes función)
    if type validar_webdav >/dev/null 2>&1; then
        if ! validar_webdav "$URL" "$USER" "$PASS"; then
            echo -e "${RED}✖ Credenciales incorrectas${NC}"
            read -p "ENTER..."
            return
        else
            echo -e "${GREEN}✔ Credenciales válidas${NC}"
        fi
    fi

    # 🔑 Guardar credenciales
    sed -i "\|$URL|d" /etc/davfs2/secrets 2>/dev/null
    echo "$URL $USER $PASS" >> /etc/davfs2/secrets
    chmod 600 /etc/davfs2/secrets

    # 🚀 Montar
    if mount -t davfs "$URL" "$RUTA"; then
        echo -e "${GREEN}✔ WebDAV montado correctamente en $RUTA${NC}"
        log_action "WebDAV montado: $URL -> $RUTA"
    else
        echo -e "${RED}✖ Error montando WebDAV${NC}"
    fi

    read -p "ENTER..."
}

# =======================================================
# WEBDAV PRO (fstab + systemd + permisos Nextcloud)
# =======================================================

montar_webdav_permanente() {

    instalar_si_falta davfs2 || return

    # ===== COLORES =====
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'

    pausar() { read -p "ENTER para continuar..."; }

    while true; do
        clear
        echo -e "${CYAN}========== WEBDAV PRO ==========${NC}"
        echo -e "${YELLOW}1)${NC} Listar WebDAV montados"
        echo -e "${YELLOW}2)${NC} Hacer permanente (fstab / service / ambos)"
        echo -e "${YELLOW}3)${NC} Desmontar / eliminar todo"
        echo -e "${YELLOW}0)${NC} Volver"
        read -p "Selecciona opción: " OPCION

        case "$OPCION" in

        1)
            mapfile -t MONTES < <(mount | grep davfs | awk '{print $3}')
            if [ ${#MONTES[@]} -eq 0 ]; then
                echo -e "${RED}No hay WebDAV montados${NC}"
            else
                echo -e "${GREEN}Montajes activos:${NC}"
                for i in "${!MONTES[@]}"; do
                    echo -e "${YELLOW}$((i+1)))${NC} ${MONTES[$i]}"
                done
            fi
            pausar
        ;;

        2)
            mapfile -t MONTES < <(mount | grep davfs | awk '{print $3}')
            if [ ${#MONTES[@]} -eq 0 ]; then
                echo -e "${RED}No hay WebDAV montados${NC}"
                pausar
                continue
            fi

            echo -e "${CYAN}Selecciona montaje:${NC}"
            for i in "${!MONTES[@]}"; do
                echo -e "${YELLOW}$((i+1)))${NC} ${MONTES[$i]}"
            done

            read -p "Opción: " NUM
            [[ -z "$NUM" ]] && continue

            LOCAL_PATH="${MONTES[$((NUM-1))]}"

            read -p $'\e[1;33mURL WebDAV (ej: https://server/remote.php/dav/files/user): \e[0m' WEBDAV_URL
            read -p "Usuario: " USUARIO
            read -s -p "Contraseña: " PASSWORD
            echo

            # ===== Usuario Nextcloud =====
            read -p "Usuario sistema (ej: www-data): " NC_USER
            [[ -z "$NC_USER" ]] && NC_USER="www-data"

            NC_UID=$(id -u $NC_USER 2>/dev/null)
            NC_GID=$(id -g $NC_USER 2>/dev/null)

            if [[ -z "$NC_UID" || -z "$NC_GID" ]]; then
                echo -e "${RED}Usuario inválido${NC}"
                pausar
                continue
            fi

            # ===== Guardar credenciales =====
            CRED_LINE="$WEBDAV_URL $USUARIO $PASSWORD"
            if grep -q "^$WEBDAV_URL" /etc/davfs2/secrets 2>/dev/null; then
                sudo sed -i "s|^$WEBDAV_URL.*|$CRED_LINE|" /etc/davfs2/secrets
            else
                echo "$CRED_LINE" | sudo tee -a /etc/davfs2/secrets > /dev/null
            fi
            sudo chmod 600 /etc/davfs2/secrets

            # ===== Opciones =====
            echo
            echo "Opciones:"
            echo -e "${YELLOW}1)${NC} fstab"
            echo -e "${YELLOW}2)${NC} systemd"
            echo -e "${YELLOW}3)${NC} ambos"
            echo -e "${YELLOW}0)${NC} cancelar"
            read -p "Selecciona: " PERM

            # ===== FSTAB =====
            if [[ "$PERM" == "1" || "$PERM" == "3" ]]; then
                FSTAB_LINE="$WEBDAV_URL $LOCAL_PATH davfs _netdev,rw,user,nofail,uid=$NC_UID,gid=$NC_GID,umask=002 0 0"

                if grep -q " $LOCAL_PATH " /etc/fstab; then
                    sudo sed -i "s|.* $LOCAL_PATH .*|$FSTAB_LINE|" /etc/fstab
                    echo -e "${GREEN}✔ fstab actualizado${NC}"
                else
                    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab > /dev/null
                    echo -e "${GREEN}✔ agregado a fstab${NC}"
                fi
            fi

            # ===== SYSTEMD =====
            if [[ "$PERM" == "2" || "$PERM" == "3" ]]; then
                SERVICE_NAME="webdav-$(basename $LOCAL_PATH).service"
                SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

                sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=WebDAV $LOCAL_PATH
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$NC_USER
Group=$NC_USER
ExecStart=/usr/bin/mount.davfs $WEBDAV_URL $LOCAL_PATH
ExecStop=/bin/umount $LOCAL_PATH
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF

                sudo systemctl daemon-reload
                sudo systemctl enable "$SERVICE_NAME"
                sudo systemctl start "$SERVICE_NAME"

                echo -e "${GREEN}✔ service creado: $SERVICE_NAME${NC}"
            fi

            echo -e "${GREEN}✔ Configuración permanente lista${NC}"
            pausar
        ;;

        3)
            mapfile -t MONTES < <(mount | grep davfs | awk '{print $3}')
            mapfile -t SERVICES < <(systemctl list-unit-files | grep webdav | awk '{print $1}')

            echo -e "${CYAN}Selecciona:${NC}"
            INDEX=1
            declare -A MAP

            for M in "${MONTES[@]}"; do
                echo -e "${YELLOW}$INDEX)${NC} Montaje: $M"
                MAP[$INDEX]="mnt:$M"
                ((INDEX++))
            done

            for S in "${SERVICES[@]}"; do
                echo -e "${YELLOW}$INDEX)${NC} Service: $S"
                MAP[$INDEX]="srv:$S"
                ((INDEX++))
            done

            read -p "Opción: " SEL
            ITEM="${MAP[$SEL]}"
            TYPE="${ITEM%%:*}"
            NAME="${ITEM#*:}"

            # ===== ELIMINAR FSTAB =====
            if [[ "$TYPE" == "mnt" ]]; then

                LINEA=$(awk -v mnt="$NAME" '$2 == mnt {print $0}' /etc/fstab)

                if [ -z "$LINEA" ]; then
                    echo -e "${RED}No encontrado en fstab${NC}"
                    pausar
                    continue
                fi

                echo -e "${YELLOW}$LINEA${NC}"
                read -p "Confirmar (s/n): " CONF
                [[ ! "$CONF" =~ ^[sS]$ ]] && continue

                WEBDAV_URL=$(echo "$LINEA" | awk '{print $1}')

                sudo umount "$NAME" 2>/dev/null || sudo umount -l "$NAME"

                sudo cp /etc/fstab /etc/fstab.bak.$(date +%F_%T)

                sudo grep -vF -- "$LINEA" /etc/fstab | sudo tee /etc/fstab > /dev/null

                sudo grep -vF -- "$WEBDAV_URL" /etc/davfs2/secrets | sudo tee /etc/davfs2/secrets > /dev/null

                echo -e "${GREEN}✔ eliminado completamente${NC}"
            fi

            # ===== ELIMINAR SERVICE =====
            if [[ "$TYPE" == "srv" ]]; then
                sudo systemctl stop "$NAME"
                sudo systemctl disable "$NAME"
                sudo rm -f "/etc/systemd/system/$NAME"
                sudo systemctl daemon-reload
                echo -e "${GREEN}✔ service eliminado${NC}"
            fi

            pausar
        ;;

        0) break ;;
        *) echo -e "${RED}Opción inválida${NC}"; pausar ;;

        esac
    done
}
 
# =======================================================
# DESMONTAR WEBDAV
# =======================================================
desmontar_webdav() {

    mapfile -t MONTES < <(mount | grep davfs | awk '{print $3}')

    # 🔴 Si no hay montajes
    if [ ${#MONTES[@]} -eq 0 ]; then
        echo "No hay WebDAV montados"
        read -p "Presiona ENTER para continuar..."
        return
    fi

    echo -e "${CYAN}Montajes WebDAV activos:${NC}"
    for i in "${!MONTES[@]}"; do
        echo "$((i+1))) ${MONTES[$i]}"
    done

    echo
    read -p "Selecciona (ENTER para cancelar): " NUM

    # 🔴 Cancelar
    if [ -z "$NUM" ]; then
        echo "Cancelado"
        read -p "Presiona ENTER para continuar..."
        return
    fi

    # 🔴 Validar número
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || [ "$NUM" -lt 1 ] || [ "$NUM" -gt ${#MONTES[@]} ]; then
        echo "Opción inválida"
        read -p "Presiona ENTER para continuar..."
        return
    fi

    RUTA="${MONTES[$((NUM-1))]}"

    # 🔴 Confirmación
    read -p "¿Seguro que deseas desmontar '$RUTA'? (s/n): " CONF
    [[ "$CONF" =~ ^[sS]$ ]] || {
        echo "Cancelado"
        read -p "Presiona ENTER para continuar..."
        return
    }

    umount "$RUTA" 2>/dev/null || umount -l "$RUTA"

    log_action "Desmontado WebDAV $RUTA"
    echo -e "${GREEN}✔ Desmontado $RUTA${NC}"

    read -p "Presiona ENTER para continuar..."
}
# =======================================================
# BACKUP WEBDAV INTERACTIVO MEJORADO
# =======================================================
# PROGRAMAR CRON
# =======================================================
programar_cron() {

    echo
    echo -e "${CYAN}Frecuencia:${NC}"
    echo "1) Cada 5 minutos"
    echo "2) Cada 1 hora"
    echo "3) Diario (03:00)"
    echo "4) Semanal (domingo 03:00)"
    echo "5) Personalizado"

    read -p "Opción: " FREQ < /dev/tty

    case "$FREQ" in
        1) CRON="*/5 * * * *"; DESC="Cada 5 minutos" ;;
        2) CRON="0 * * * *"; DESC="Cada 1 hora" ;;
        3) CRON="0 3 * * *"; DESC="Todos los días a las 03:00" ;;
        4) CRON="0 3 * * 0"; DESC="Domingos a las 03:00" ;;
        5)
            echo
            echo "Formato: MIN HORA DIA MES DIA_SEMANA"
            echo "Ejemplo: 0 2 * * *"
            read -p "Cron: " CRON < /dev/tty
            DESC="Personalizado ($CRON)"
            ;;
        *)
            echo "Opción inválida"
            return
            ;;
    esac

    (crontab -l 2>/dev/null | grep -v -F "$CMD"; echo "$CRON $CMD") | crontab -

    echo
    echo -e "${GREEN}✔ Backup programado${NC}"
    echo "Frecuencia: $DESC"
}

# =======================================================
# PROGRAMAR COPIA INTERACTIVA CRON
# =======================================================
backup_interactivo() {

    echo -e "${CYAN}=== COPIA DE DATOS ===${NC}"

    echo
    echo "Ejemplos:"
    echo "WebDAV montado: /mnt/webdav/server"
    echo "Local: /mnt/sdb1/backup"
    echo

    # -------- ORIGEN --------
    read -p "Ruta ORIGEN: " ORIGEN < /dev/tty

    # -------- DESTINO --------
    read -p "Ruta DESTINO: " DESTINO < /dev/tty

    if [ -z "$ORIGEN" ] || [ -z "$DESTINO" ]; then
        echo "Datos inválidos"
        read -p "ENTER para continuar..." < /dev/tty
        return
    fi

    # -------- MÉTODO --------
    echo
    echo "Método:"
    echo "1) rsync (recomendado) Repara Permisos"
    echo "2) rclone (pro)"
    echo "3) cp (básico) Repara Permisos "
    read -p "Opción: " METODO < /dev/tty

    # -------- SYNC --------
    echo
    read -p "¿Modo espejo (sync)? (s/n): " SYNC < /dev/tty

    # ⚠️ ALERTA
    if [[ "$SYNC" =~ ^[sS]$ ]]; then
        echo
        echo -e "${RED}⚠️ ATENCIÓN:${NC} Esto puede borrar archivos en el DESTINO"
        read -p "¿Continuar? (s/n): " CONFIRM < /dev/tty
        [[ ! "$CONFIRM" =~ ^[sS]$ ]] && echo "Cancelado" && return
    fi

    # -------- USUARIO NEXTCLOUD --------
    read -p "Grupo Nextcloud (ej: www-data) para permisos: " NC_USER
    [[ -z "$NC_USER" ]] && NC_USER="www-data"

    # -------- COMANDO --------
    case "$METODO" in
        1)
            CMD="rsync -avh --chown=$NC_USER:$NC_USER"
            [[ "$SYNC" =~ ^[sS]$ ]] && CMD="$CMD --delete"
            CMD="$CMD \"$ORIGEN\" \"$DESTINO\""
            ;;
        2)
            if [[ "$SYNC" =~ ^[sS]$ ]]; then
                CMD="rclone sync \"$ORIGEN\" \"$DESTINO\" --progress"
            else
                CMD="rclone copy \"$ORIGEN\" \"$DESTINO\" --progress"
            fi
            ;;
        3)
            CMD="cp -r \"$ORIGEN\" \"$DESTINO\""
            ;;
        *)
            echo "Opción inválida"; return ;;
    esac

    # -------- RESUMEN --------
    echo
    echo -e "${CYAN}Resumen:${NC}"
    echo "Origen : $ORIGEN"
    echo "Destino: $DESTINO"
    echo "Comando: $CMD"
    echo "Permisos para usuario Nextcloud: $NC_USER"

    # -------- EJECUTAR --------
    echo
    read -p "¿Ejecutar ahora? (s/n): " RUN < /dev/tty
    if [[ "$RUN" =~ ^[sS]$ ]]; then
        eval "$CMD"
        # Ajustar permisos después de copiar
        echo -e "${CYAN}Ajustando permisos para Nextcloud...${NC}"
        sudo chown -R "$NC_USER":"$NC_USER" "$DESTINO"
        sudo find "$DESTINO" -type d -exec chmod 750 {} \;
        sudo find "$DESTINO" -type f -exec chmod 640 {} \;
        echo -e "${GREEN}✔ Permisos ajustados${NC}"
    fi

    # -------- CRON --------
    read -p "¿Programar automático? (s/n): " AUTO < /dev/tty
    if [[ "$AUTO" =~ ^[sS]$ ]]; then
        programar_cron
    fi

    log_action "Copia: $CMD"

    echo
    read -p "ENTER para continuar..." < /dev/tty
}

# =======================================================
# LISTAR WEBDAV MONTADOS
# =======================================================
listar_webdav_montados() {

    mapfile -t MONTES < <(mount | grep davfs | awk '{print $3}')

    if [ ${#MONTES[@]} -eq 0 ]; then
        echo -e "${RED}No hay WebDAV montados${NC}"
        read -p "Presiona ENTER para continuar..."
        return 1
    fi

    echo -e "${CYAN}WebDAV montados actualmente:${NC}"
    for i in "${!MONTES[@]}"; do
        echo "$((i+1))) ${MONTES[$i]}"
    done

    echo
    read -p "Presiona ENTER para continuar..."
}

# =======================================================
# VER LOG
# =======================================================
ver_logs() {
    echo -e "${CYAN}=== LOGS ===${NC}"
    tail -n 50 "$LOG_FILE"
    read -p "ENTER..."
}

# =======================================================
# MENU PRINCIPAL
# =======================================================

menu_webdav_pro() {

while true; do
    clear
    echo -e "${CYAN}=== Configurar Rclone/Webdav / Backup Local Server ===${NC}"
    echo -e "${YELLOW}1)${NC} Configurar remoto Rclone/WebDav Interactivo"
    echo -e "${YELLOW}2)${NC} Montar Remoto Configurado Permanete/Temporal"
	echo
    echo -e "${YELLOW}3)${NC} Listar Archivos Remoto / Configurado"
    echo -e "${YELLOW}4)${NC} Copy/Sync Al Mismo Server Remoto + (Crontab)"
    echo -e "${YELLOW}5)${NC} Borrar Configuración Remota / Rclone/WebDav"
    echo
    echo -e "${CYAN}=====  Montar/Desmontar WebDAV / Backup External Server =====${NC}"
    echo -e "${YELLOW}6)${NC} Montar WebDAV Temporal / Se Desmonta al Reinicio"
	echo -e "${YELLOW}7)${NC} Desmontar WebDAV Temporal"
	echo
    echo -e "${CYAN}=====   WebDAV Permanente  (Fstab - systemd Service) Inicio Seguro =====${NC}"
	echo -e "${YELLOW}8)${NC} Hacer Permanente WebDAV Montado / No Desmonta al Reinicio"
	echo
    echo -e "${CYAN}=====  Programar Backup WebDAV (Copy/Sync) + (Crontab) =====${NC}"
    echo -e "${YELLOW}9)${NC} Programar Backup WebDAV (Copy/Sync) + (Crontab)"
    echo -e "${YELLOW}10)${NC} Gestionar CRON (Crear/borrar/editar)"
	echo -e "${YELLOW}11)${NC} Listar WebDAV Montados "
	echo -e "${YELLOW}12)${NC} Gestionar Fstab HDD (Agregar/Borrar/Listar)"
	echo -e "${YELLOW}13)${NC} Contraseñas API - TOKEN (Crear/Borrar/Listar)"
    echo -e "${YELLOW}14)${NC} Ver logs"

    echo -e "${CYAN}0) Volver${NC}"

    read -p "Opción: " op

    case $op in
        1) configurar_remoto_inteligente ;;
        2) montar_remoto ;;
        3) listar_archivos_remoto ;;
        4) rclone_copy ;;
        5) borrar_config_remota ;;
        6) montar_webdav_temporal ;;
		7) desmontar_webdav ;;
		8) montar_webdav_permanente ;;
        9) backup_interactivo ;;
        10) gestionar_editar_cron ;;
		11) listar_webdav_montados ;;
		12) gestionar_fstab_nct ;;
		13) menu_tokens_api ;;
        14) ver_logs ;;
        0) break ;;
    esac
done

}

# ========= GESTIÓN DISCO /PERMISOS/ARCHIVOS/ FSTAB/NEXTCLOUD =========
usb_disco_externo(){
  while true; do
    clear
echo -e "${BOLD}${CYAN}========= GESTIÓN DISCO /PERMISOS/ARCHIVOS/ FSTAB/NEXTCLOUD =========${NC}"
echo -e "${YELLOW}1)${NC} Copiar a Nextcloud Carpeta/Archivos"
echo -e "${YELLOW}2)${NC} Copiar a HDD/USB ANTIDUPLICADOS"
echo -e "${YELLOW}3)${NC} Mover Carpeta/Archivos a Nextcloud"
echo -e "${YELLOW}4)${NC} Borrar carpeta de Nextcloud"
echo -e "${YELLOW}5)${NC} Escanear Carpeta de Nextcloud + Permisos Nextcloud/Jellyfin"
echo -e "${YELLOW}6)${NC} Reparar permisos Nextcloud + Agrega Jellyfin a www-data"
echo -e "${YELLOW}7)${NC} Dependencias para Formatear/Permisos ALC"
echo -e "${YELLOW}8)${NC} Formatear/Montar HDD/USB + Fstab + Permisos ACL/Genérico"
echo -e "${YELLOW}9)${NC} Desmontar y limpiar Fstab"
echo -e "${YELLOW}10)${NC} Instalar soporte exFAT/NTFS/FAT32 para montar"
echo -e "${YELLOW}11)${NC} Montar USB/HDD sin formatear + Fstab"
echo -e "${YELLOW}12)${NC} Ver discos montados"
echo -e "${YELLOW}13)${NC} Gestionar Fstab HDD (Agregar/Borrar/Listar)"
echo -e "${YELLOW}14)${NC} Montaje WebDAV (Sync espejo/Rclone/Crontab)"
echo -e "${CYAN}0)${NC} Salir"

    read -rp "Opción: " OPC

    case $OPC in
        1) copiar_a_nextcloud_nct ;;
        2) copiar_generico_nct ;;
        3) mover_y_escanear_nct ;; 
        4) borrar_y_escanear_nct ;;
        5) escanear_carpeta_nct ;;
        6) reparar_permisos_nct ;;
        7) check_dependencias_discos_nct ;;
        8) formatear_y_montar_nct ;;
        9) desmontar_y_limpiar_nct ;;
       10) instalar_soporte_discos_nct ;;
       11) montar_sin_formato_nct ;;
       12) ver_discos_montados_nct ;;
       13) gestionar_fstab_nct ;;
	   14) menu_webdav_pro ;;
       0) break ;;
        *) echo "Opción inválida" ;;
    esac

    read -p "ENTER para continuar..."
  done
}

# ========= MENÚ NEXTCLOUD OCC Full  =========
menu_nextcloud_occ_pro(){
  while true; do
    clear
echo -e "${BOLD}${CYAN}=== MENÚ NEXTCLOUD - Turnkey ${YELLOW}v24.3.2 ${CYAN}===${NC}"
echo -e " ${YELLOW}↑"
echo -e " ${YELLOW}1)${NC} Configuración Nextcloud (Vhost/Config.php/Puertos)"
echo -e " ${YELLOW}2)${NC} Reparar/Actualizar Nextcloud (OCC/Upgrade/Backup/Apps)"
echo -e " ${YELLOW}*"
echo -e " ${YELLOW}3)${NC} Respaldos MySQL (Restaurar/Backup/Crear/Borrar BD)"
echo -e " ${YELLOW}4)${NC} PostgreSQL (DB/Usuarios/Backups)"
echo -e " ${YELLOW}*"
echo -e " ${YELLOW}5)${NC} Red (Firewall/IP Manual)"
echo -e " ${YELLOW}6)${NC} Instalar Servicios (SSH/PHP/MariaDB/Apache2/Curl/Git)"
echo -e " ${YELLOW}7)${NC} Samba (Instalación/Carpetas compartidas)"
echo -e " ${YELLOW}8)${NC} Ejecutar Comando a Varios PC / CLUSTER PRO SSH (CON PROGRESO)"
echo -e " ${YELLOW}9)${NC} SWAP (Ver/Crear/Activar/Desactivar)"
echo -e " ${YELLOW}*"
echo -e " ${YELLOW}10)${NC} Activar/Desactivar (Adminer/Webmin)"
echo -e " ${YELLOW}11)${NC} DuckDNS + Cron (IP dinámica automática)"
echo -e " ${YELLOW}*"
echo -e " ${YELLOW}12)${NC} Montar HDD/USB/WebDav/Rclone /Copiar/Borrar/Escanear/Permisos"
echo -e " ${YELLOW}*"
echo -e " ${YELLOW}13)${NC} Servicios (Stop/Start/Restart)"
echo -e " ${YELLOW}14)${NC} Reparar error de fecha / Arreglar APT / Fix"
echo -e " ${YELLOW}15)${NC} Gestión Fail2Ban (Quita Baneo de SSH)"
echo -e " ${YELLOW}16)${NC}${CYAN} Limpiar Historial bash ${YELLOW} root@nextcloud ~# ${GREEN}source menu${NC}${YELLOW}"
echo -e " ${YELLOW}17)${NC}${GREEN} Instalar SUDO + Script ${YELLOW} root@nextcloud ~# ${GREEN}menu${NC}${YELLOW}"
echo -e " ${YELLOW}↓"
echo -e " ${CYAN}0)${CYAN}${CYAN} [Volver al Menu Principal]"

  read -rp "> " opc
  case "$opc" in
    1) menu_config_nextcloud ;;
	2) menu_nextcloud_occ ;;
    3) menu_mysql_backup ;;
    4) menu_postgresql ;;
    5) menu_red ;;
    6) menu_instala_utilidades ;;
    7) menu_samba ;;
    8) cluster_menu ;;
	9) menu_swap ;;
    10) menu_adminer_webmin ;;
    11) menu_duckdns ;;
    12) usb_disco_externo ;;
	13) menu_servicios ;;
  	14) fix_fecha_apt ;;
	15) menu_fail2ban ;;
	16) limpiar_historial ;;
    17) instalar_sudo ;;
      0) return ;;
      *) warn "Opción inválida"; pausa ;;
    esac
  done
}
# =========================================================
# DEPENDENCIAS
# =========================================================
install_dependencies(){

echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN}     INSTALADOR DEPENDENCIAS${RESET}"
echo -e "${CYAN}========================================${RESET}"

check_internet

PACKAGES=(
sudo
apache2
mariadb-server
mariadb-client
libapache2-mod-php
php
php-cli
php-common
php-gd
php-curl
php-zip
php-xml
php-mbstring
php-intl
php-bcmath
php-gmp
php-bz2
php-imagick
php-mysql
php-apcu
php-redis
redis-server
curl
wget
unzip
ffmpeg
imagemagick
cron
certbot
python3-certbot-apache
dnsutils
)

INSTALLED=()
MISSING=()
FAILED=()

echo
echo -e "${YELLOW}Verificando paquetes...${RESET}"
echo

# =========================================================
# VERIFICAR
# =========================================================

for pkg in "${PACKAGES[@]}"; do

    if dpkg -s "$pkg" &>/dev/null; then

        INSTALLED+=("$pkg")

    else

        MISSING+=("$pkg")

    fi

done

# =========================================================
# MOSTRAR INSTALADOS
# =========================================================

echo -e "${GREEN}Paquetes ya instalados:${RESET}"
echo

if [ ${#INSTALLED[@]} -eq 0 ]; then

    echo "Ninguno"

else

    for pkg in "${INSTALLED[@]}"; do
        echo -e "${GREEN}✔${RESET} $pkg"
    done

fi

echo

# =========================================================
# INSTALAR FALTANTES
# =========================================================


if [ ${#MISSING[@]} -gt 0 ]; then

    echo -e "${YELLOW}Paquetes faltantes:${RESET}"
    echo

    for pkg in "${MISSING[@]}"; do
        echo -e "${YELLOW}➜${RESET} $pkg"
    done

    echo
    read -rp "¿Deseas instalar los paquetes faltantes? [s/N]: " RESP

    case "$RESP" in
        s|S|si|SI|y|Y)

            echo
            echo -e "${CYAN}Actualizando repositorios...${RESET}"
            echo

            apt update

            echo
            echo -e "${CYAN}Instalando paquetes faltantes...${RESET}"
            echo

            for pkg in "${MISSING[@]}"; do

                echo -e "${BLUE}Instalando:${RESET} $pkg"

                if apt install -y "$pkg"; then

                    echo -e "${GREEN}✔ Instalado:${RESET} $pkg"

                else

                    echo -e "${RED}✘ Error:${RESET} $pkg"

                    FAILED+=("$pkg")

                fi

                echo

            done
            ;;

        *)

            echo
            echo -e "${RED}Instalación cancelada${RESET}"
            pause
            return 1
            ;;

    esac

else

    echo -e "${GREEN}✔ Todas las dependencias ya están instaladas${RESET}"

fi

echo

# =========================================================
# DETECTAR PHP
# =========================================================

detect_php

if [ ! -f "$PHPINI" ]; then

    echo -e "${RED}No existe:${RESET} $PHPINI"
    pause
    return

fi

# =========================================================
# APACHE
# =========================================================

echo -e "${CYAN}Configurando Apache...${RESET}"

a2enmod rewrite headers env dir mime ssl >/dev/null 2>&1

a2enmod http2 >/dev/null 2>&1 || true

systemctl enable apache2 mariadb redis-server cron >/dev/null 2>&1

systemctl restart apache2
systemctl restart mariadb
systemctl restart redis-server

# =========================================================
# PHP
# =========================================================

echo -e "${CYAN}Optimizando PHP...${RESET}"

sed -i 's/^memory_limit.*/memory_limit = 1024M/' $PHPINI
sed -i 's/^upload_max_filesize.*/upload_max_filesize = 10G/' $PHPINI
sed -i 's/^post_max_size.*/post_max_size = 10G/' $PHPINI
sed -i 's/^max_execution_time.*/max_execution_time = 360/' $PHPINI
sed -i 's/^max_input_time.*/max_input_time = 360/' $PHPINI

grep -q "date.timezone" $PHPINI \
&& sed -i 's|^;*date.timezone.*|date.timezone = America/Santiago|' $PHPINI \
|| echo "date.timezone = America/Santiago" >> $PHPINI

grep -q "opcache.enable=1" $PHPINI \
|| echo "opcache.enable=1" >> $PHPINI

grep -q "opcache.memory_consumption" $PHPINI \
|| echo "opcache.memory_consumption=256" >> $PHPINI

systemctl restart apache2

echo

# =========================================================
# RESUMEN FINAL
# =========================================================

echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN}            RESUMEN FINAL${RESET}"
echo -e "${CYAN}========================================${RESET}"

echo

echo -e "${GREEN}Instalados correctamente:${RESET}"

for pkg in "${PACKAGES[@]}"; do

    if dpkg -s "$pkg" &>/dev/null; then
        echo -e "${GREEN}✔${RESET} $pkg"
    fi

done

echo

echo -e "${RED}No instalados / errores:${RESET}"

if [ ${#FAILED[@]} -eq 0 ]; then

    echo -e "${GREEN}Ninguno${RESET}"

else

    for pkg in "${FAILED[@]}"; do
        echo -e "${RED}✘${RESET} $pkg"
    done

fi

echo
echo -e "${GREEN}✔ Proceso finalizado${RESET}"

pause
}
# =========================================================
# CREAR BASE DE DATOS INSTALACION (CONFIG.PHP)
# =========================================================

setup_database(){

echo
echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN}     CONFIGURACIÓN BASE DE DATOS (config.php)${RESET}"
echo -e "${CYAN}========================================${RESET}"
echo

DEFAULT_DB_NAME="nextcloud"
DEFAULT_DB_USER="usernc"
DEFAULT_DB_PASS=$(openssl rand -base64 12)

echo -e "${YELLOW}1)${RESET} ${GREEN}Crear Base de Datos Automática${RESET}"
echo -e "${YELLOW}2)${RESET} ${CYAN}Configuración Personalizada${RESET}"
echo

read -rp "Selecciona una opción: " DB_OPTION

echo

case "$DB_OPTION" in

1)

    DB_NAME="$DEFAULT_DB_NAME"
    DB_USER="$DEFAULT_DB_USER"
    DB_PASS="$DEFAULT_DB_PASS"

    echo -e "${GREEN}Usando configuración automática:${RESET}"
    echo
    echo -e "${CYAN}DB:${RESET} $DB_NAME"
    echo -e "${CYAN}Usuario:${RESET} $DB_USER"
    echo -e "${CYAN}Password:${RESET} $DB_PASS"
    ;;

2)

    echo -e "${CYAN}Configuración personalizada:${RESET}"
    echo

    read -rp "DB [$DEFAULT_DB_NAME]: " DB_NAME
    DB_NAME=${DB_NAME:-$DEFAULT_DB_NAME}

    read -rp "Usuario [$DEFAULT_DB_USER]: " DB_USER
    DB_USER=${DB_USER:-$DEFAULT_DB_USER}

    read -rp "Password [$DEFAULT_DB_PASS]: " DB_PASS
    DB_PASS=${DB_PASS:-$DEFAULT_DB_PASS}
    ;;

*)

    echo -e "${RED}✘ Opción inválida${RESET}"
    pause
    return
    ;;

esac

DB_HOST="localhost"

# =========================================================
# OPTIMIZAR MARIADB
# =========================================================

echo
echo -e "${CYAN}Configurando MariaDB para Nextcloud...${RESET}"

CONF="/etc/mysql/mariadb.conf.d/50-server.cnf"

grep -q "nextcloud-opt" "$CONF" || cat >> "$CONF" <<EOF

# nextcloud-opt
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
transaction_isolation = READ-COMMITTED
binlog_format = ROW
innodb_file_per_table = 1
innodb_buffer_pool_size = 512M
EOF

systemctl restart mariadb

# =========================================================
# CREAR DB
# =========================================================

echo
echo -e "${CYAN}Creando base de datos...${RESET}"

mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"

# =========================================================
# CREAR USUARIO
# =========================================================

echo
echo -e "${CYAN}Creando usuario MariaDB...${RESET}"

mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"

# =========================================================
# PERMISOS
# =========================================================

echo
echo -e "${CYAN}Asignando permisos...${RESET}"

mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"

mysql -e "FLUSH PRIVILEGES;"

# =========================================================
# Crear copia de seguridad nextcloud_db.conf
# =========================================================
echo -e "${YELLOW} Renombrando nextcloud_db.conf...${RESET}"
[ -f /root/nextcloud_db.conf ] && \
mv /root/nextcloud_db.conf "/root/nextcloud_db_$(date +%F_%H-%M-%S).conf"
echo -e "${GREEN}✔ Archivo Renombrado ${RESET}"
echo

if [ -f "$DB_FILE" ]; then
    echo -e "${YELLOW}Eliminando configuración anterior si existe...${RESET}"
    rm -f "$DB_FILE"
    echo -e "${GREEN}✔ Archivo eliminado${RESET}"
else
    echo -e "${CYAN}No existe configuración anterior${RESET}"
fi
# =========================================================
# GUARDAR CONFIG
# =========================================================

cat > "$DB_FILE" <<EOF
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASS="${DB_PASS}"
DB_HOST="${DB_HOST}"
EOF

chmod 600 "$DB_FILE"

# =========================================================
# FINAL
# =========================================================

echo
echo -e "${GREEN}========================================${RESET}"
echo -e "${GREEN}     BASE DE DATOS CONFIGURADA${RESET}"
echo -e "${GREEN}========================================${RESET}"

echo
echo -e "${CYAN}DB:${RESET} $DB_NAME"
echo -e "${CYAN}Usuario:${RESET} $DB_USER"
echo -e "${CYAN}Host:${RESET} $DB_HOST"

echo
echo -e "${GREEN}✔ Base de datos creada correctamente${RESET}"
echo

pause

}

# =========================================================
# DETECTAR LTS
# =========================================================

is_lts() {

    local ver="$1"
    local major="${ver%%.*}"

    # Ajusta aquí las versiones LTS reales
    if [[ "$major" -le 31 ]]; then
        echo "LTS"
    else
        echo "STABLE"
    fi
}

# =========================================================
# VERSION
# =========================================================

select_version(){

check_internet

    get_nextcloud_versions || return

    echo
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW} Selecciona versión de Nextcloud${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo

    MENU=()

    i=1
    for v in $VERSIONS; do

        TYPE=$(is_lts "$v")

        if [[ "$TYPE" == "LTS" ]]; then
            LABEL="${GREEN}$v (LTS)${RESET}"
        else
            LABEL="${CYAN}$v (STABLE)${RESET}"
        fi

        MENU+=("$v")
        echo -e "${YELLOW}$i)${RESET} $LABEL"
        ((i++))

    done

    echo -e "${YELLOW}l)${RESET} latest"
    echo

    read -rp "Selecciona opción: " opt

    if [[ "$opt" == "l" ]]; then
        VERSION="latest"
        return
    fi

    if [[ "$opt" =~ ^[0-9]+$ ]] && (( opt >= 1 && opt <= ${#MENU[@]} )); then
        VERSION="${MENU[$((opt-1))]}"
    else
        echo -e "${RED}✘ Selección inválida${RESET}"
        return 1
    fi

    echo -e "${GREEN}✔ Versión seleccionada: $VERSION${RESET}"

}
# =========================================================
# Obteniendo versiones disponibles
# =========================================================
get_nextcloud_versions() {

    echo -e "${CYAN}Obteniendo versiones disponibles...${RESET}"

    VERSIONS=$(curl -s https://download.nextcloud.com/server/releases/ \
        | grep -oP 'nextcloud-\K[0-9]+\.[0-9]+\.[0-9]+' \
        | sort -Vr \
        | uniq \
        | head -n 10)

    if [[ -z "$VERSIONS" ]]; then
        echo -e "${RED}✘ No se pudieron obtener versiones${RESET}"
        return 1
    fi
}
# =========================================================
# VHOST
# =========================================================
create_vhost(){

echo -ne "${YELLOW}Dominio ${CYAN}Eje: nextcloud.ddns.net:${RESET} "
read DOMAIN
echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN}           CONFIGURAR SSL${RESET}"
echo -e "${CYAN}========================================${RESET}"

echo -e "${YELLOW}1)${RESET} TurnKey (.pem)"
echo -e "${YELLOW}2)${RESET} Let's Encrypt"
echo -e "${YELLOW}3)${RESET} Sin SSL"

echo
echo -ne "${GREEN}SSL:${RESET} "
read SSL

CONF="/etc/apache2/sites-available/nextcloud.conf"

if [ "$SSL" == "1" ]; then

cat > $CONF <<EOF
<VirtualHost *:80>
ServerName $DOMAIN
Redirect / https://$DOMAIN/
</VirtualHost>

<VirtualHost *:443>
ServerName $DOMAIN
DocumentRoot $NC_DIR
SSLEngine on
SSLCertificateFile /etc/ssl/private/cert.pem
SSLCertificateKeyFile /etc/ssl/private/cert.key
<Directory $NC_DIR/>
Require all granted
AllowOverride All
</Directory>
</VirtualHost>
EOF

elif [ "$SSL" == "2" ]; then

apt install -y certbot python3-certbot-apache

cat > $CONF <<EOF
<VirtualHost *:80>
ServerName $DOMAIN
DocumentRoot $NC_DIR
</VirtualHost>
EOF

a2ensite nextcloud.conf
systemctl reload apache2
certbot --apache -d $DOMAIN

else

cat > $CONF <<EOF
<VirtualHost *:80>
ServerName $DOMAIN
DocumentRoot $NC_DIR
</VirtualHost>
EOF

fi

a2ensite nextcloud.conf
systemctl reload apache2

echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN}           VHOST CONFIGURADO ${RESET}"
echo -e "${CYAN}========================================${RESET}"
pause
}

# =========================================================
# PERMISOS
# =========================================================

fix_permissions(){

chown -R $WEB_USER:$WEB_USER $NC_DIR
chown -R $WEB_USER:$WEB_USER $DATA_DIR

find $NC_DIR -type d -exec chmod 750 {} \;
find $NC_DIR -type f -exec chmod 640 {} \;

chmod 770 $DATA_DIR

}

# =========================================================
# REDIS
# =========================================================

configure_redis(){

[ ! -f "$NC_DIR/config/config.php" ] && return

sudo -u $WEB_USER php -d memory_limit=1G $NC_DIR/occ config:system:set memcache.local --value='\OC\Memcache\APCu'

sudo -u $WEB_USER php -d memory_limit=1G $NC_DIR/occ config:system:set memcache.locking --value='\OC\Memcache\Redis'

sudo -u $WEB_USER php -d memory_limit=1G $NC_DIR/occ config:system:set redis host --value='127.0.0.1'

sudo -u $WEB_USER php -d memory_limit=1G $NC_DIR/occ config:system:set redis port --value='6379'

}

# =========================================================
# CRON
# =========================================================

configure_cron(){

(crontab -u www-data -l 2>/dev/null; \
echo "*/5 * * * * php -f $NC_DIR/cron.php") | crontab -u www-data -

sudo -u $WEB_USER php -d memory_limit=1G $NC_DIR/occ background:cron

}
# =========================================================
# VERIFICAR INSTALACIÓN NEXTCLOUD
# =========================================================

check_nextcloud_installed() {

    echo
    echo -e "${CYAN}Verificando instalación de Nextcloud...${RESET}"
    echo

    NEXTCLOUD_FOUND=false

    # Posibles rutas
    POSSIBLE_DIRS=(
        "/var/www/nextcloud"
        "/var/www/html/nextcloud"
        "/srv/www/nextcloud"
    )

    NC_PATH=""
    NC_VERSION=""
    VHOST_FILES=()
    DOMAINS=()

    # =====================================================
    # BUSCAR INSTALLATION
    # =====================================================

    for dir in "${POSSIBLE_DIRS[@]}"; do

        if [ -f "$dir/version.php" ]; then
            NEXTCLOUD_FOUND=true
            NC_PATH="$dir"
            break
        fi

    done

    # Buscar en Apache si no encontró ruta conocida
    if [ "$NEXTCLOUD_FOUND" = false ]; then

        FOUND=$(find /var/www -maxdepth 3 -type f -name version.php 2>/dev/null \
            | grep nextcloud | head -n1)

        if [ -n "$FOUND" ]; then
            NEXTCLOUD_FOUND=true
            NC_PATH=$(dirname "$FOUND")
        fi

    fi

    # =====================================================
    # SI NEXTCLOUD EXISTE
    # =====================================================

    if [ "$NEXTCLOUD_FOUND" = true ]; then

        # Obtener versión
        if [ -f "$NC_PATH/version.php" ]; then

            NC_VERSION=$(php -r "
                include '$NC_PATH/version.php';
                echo \$OC_VersionString;
            " 2>/dev/null)

        fi

        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${GREEN}NEXTCLOUD YA ESTÁ INSTALADO${RESET}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo

        echo -e "${CYAN}Versión:${RESET} ${YELLOW}${NC_VERSION:-Desconocida}${RESET}"
        echo -e "${CYAN}Ruta:${RESET} ${YELLOW}$NC_PATH${RESET}"
        echo

        # =================================================
        # BUSCAR VHOSTS APACHE
        # =================================================

        echo -e "${CYAN}VirtualHosts detectados:${RESET}"
        echo

        while IFS= read -r file; do

            if grep -qi "DocumentRoot.*$NC_PATH" "$file"; then
                VHOST_FILES+=("$file")
            fi

        done < <(find /etc/apache2/sites-enabled \
                        /etc/apache2/sites-available \
                        -type f -name "*.conf" 2>/dev/null)

        if [ ${#VHOST_FILES[@]} -eq 0 ]; then

            echo -e "${YELLOW}No se encontraron VirtualHosts asociados.${RESET}"

        else

            for vh in "${VHOST_FILES[@]}"; do

                echo -e "${GREEN}Archivo:${RESET} $vh"

                SERVERNAME=$(grep -i "ServerName" "$vh" \
                    | awk '{print $2}' \
                    | head -n1)

                SERVERALIAS=$(grep -i "ServerAlias" "$vh" \
                    | cut -d' ' -f2-)

                DOCROOT=$(grep -i "DocumentRoot" "$vh" \
                    | awk '{print $2}' \
                    | head -n1)

                [ -n "$SERVERNAME" ] && \
                    echo -e "  ${CYAN}DNS:${RESET} $SERVERNAME"

                [ -n "$SERVERALIAS" ] && \
                    echo -e "  ${CYAN}Alias:${RESET} $SERVERALIAS"

                [ -n "$DOCROOT" ] && \
                    echo -e "  ${CYAN}DocumentRoot:${RESET} $DOCROOT"

                echo

            done

        fi

        echo -e "${GREEN}⚠ Nextcloud ya está instalado.${RESET}"
        echo -e "${YELLOW}Debes desinstalar Nextcloud antes de continuar.${RESET}"
        echo
        echo
        echo
        printf "${CYAN}Presiona ENTER para continuar...${RESET}"
        read _
        return 1


    fi

    # =====================================================
    # NO INSTALADO
    # =====================================================

    echo -e "${GREEN}✔ No se encontró una instalación de Nextcloud.${RESET}"
    echo -e "${GREEN}Continuando instalación...${RESET}"
    echo

    return 0
}
# =========================================================
# INSTALL NEXTCLOUD PRO (FIXED) - Instalador Inteligente PRO
# =========================================================

install_nextcloud(){
check_nextcloud_installed || return
install_dependencies
setup_database
select_version

source "$DB_FILE"

cd /tmp || return

rm -f nextcloud.zip

# =========================================================
# CONSTRUIR URL DE DESCARGA SEGURA
# =========================================================

if [[ "$VERSION" == "latest" ]]; then

    DL="https://download.nextcloud.com/server/releases/latest.zip"

else

    # validar formato versión (ej: 29.0.6)
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}✘ Versión inválida: $VERSION${RESET}"
        pause
        return 1
    fi

    DL="https://download.nextcloud.com/server/releases/nextcloud-${VERSION}.zip"

    # validar existencia URL
    if ! curl -s --head --fail "$DL" >/dev/null; then
        echo -e "${RED}✘ No existe esta versión en Nextcloud:${RESET} $VERSION"
        pause
        return 1
    fi

fi

# =========================================================
# DESCARGAR NEXTCLOUD
# =========================================================

echo
echo -e "${YELLOW}Descargando Nextcloud...${RESET}"
echo "$DL"
echo

wget -q --show-progress -O nextcloud.zip "$DL" || {
    echo -e "${RED}✘ Error descargando Nextcloud${RESET}"
    pause
    return 1
}

# =========================================================
# VALIDAR TIPO ARCHIVO
# =========================================================

if ! file nextcloud.zip | grep -q "Zip archive"; then
    echo -e "${RED}✘ El archivo descargado no es un ZIP válido${RESET}"
    pause
    return 1
fi

# =========================================================
# VALIDAR ZIP
# =========================================================

echo
echo -e "${CYAN}Verificando integridad ZIP...${RESET}"

if ! unzip -t nextcloud.zip &>/dev/null; then
    echo -e "${RED}✘ ZIP corrupto${RESET}"
    pause
    return 1
fi

echo -e "${GREEN}✔ Archivo verificado${RESET}"

# =========================================================
# ELIMINAR INSTALACION ANTERIOR
# =========================================================
NC_DIR="/var/www/nextcloud"
echo
echo -e "${CYAN}Eliminando instalación anterior...${RESET}"

rm -rf "$NC_DIR"

# =========================================================
# EXTRAER
# =========================================================

echo
echo -e "${CYAN}Extrayendo archivos...${RESET}"
echo

unzip -o nextcloud.zip >/dev/null || {
    echo -e "${RED}✘ Error extrayendo archivos${RESET}"
    pause
    return 1
}

echo
echo -e "${GREEN}✔ Archivos extraídos${RESET}"

# =========================================================
# MOVER
# =========================================================

echo
echo -e "${CYAN}Moviendo carpeta Nextcloud a $NC_DIR ...${RESET}"
echo

mv nextcloud "$NC_DIR" || {
    echo -e "${RED}✘ Error moviendo Nextcloud${RESET}"
    pause
    return 1
}

echo
echo -e "${GREEN}✔ Movido con éxito${RESET}"

# =========================================================
# CREAR DATA DIR
# =========================================================
DATA_DIR="/var/www/nextcloud-data"
mkdir -p "$DATA_DIR"

# =========================================================
# PERMISOS
# =========================================================

echo
echo -e "${CYAN}Aplicando permisos...${RESET}"

fix_permissions

# =========================================================
# APACHE
# =========================================================

echo
echo -e "${CYAN}Creando VirtualHost Apache...${RESET}"
echo
echo
create_vhost

# =========================================================
# ADMIN
# =========================================================

echo
echo -e "${YELLOW}==================================================${RESET}"
echo -e "${YELLOW}     Configuración Crear Administrador            ${RESET}"
echo -e "${CYAN}  Puedes Crear User Que Tenga Carpeta en DATA        ${RESET}"
echo -e "${YELLOW}==================================================${RESET}"

read -rp "Usuario admin: " ADMIN_USER
read -srp "Password admin: " ADMIN_PASS
echo

# =========================================================
# LIMPIAR RESIDUOS DATA NEXTCLOUD
# =========================================================

if [ -d "$DATA_DIR" ] && [ "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then

    echo
    echo -e "${YELLOW}⚠ DATA existente detectado${RESET}"
    echo -e "${CYAN}Ruta:${RESET} $DATA_DIR"
    echo

    printf "${CYAN}¿Limpiar residuos de instalación anterior? (s/n): ${RESET}"
    read CLEAN_DATA

    if [[ "$CLEAN_DATA" =~ ^[sS]$ ]]; then

        echo
        echo -e "${CYAN}Limpiando residuos Nextcloud...${RESET}"

        # =====================================================
        # CARPETAS APPDATA Y UPDATER
        # =====================================================

        echo
        echo -e "${CYAN}Eliminando cache appdata...${RESET}"

        rm -rf "$DATA_DIR"/appdata_* 2>/dev/null
        rm -rf "$DATA_DIR"/updater-* 2>/dev/null

        echo -e "${GREEN}✔ Cache eliminada${RESET}"

        # =====================================================
        # LOGS
        # =====================================================

        echo
        echo -e "${CYAN}Eliminando logs Nextcloud...${RESET}"

        rm -f "$DATA_DIR/nextcloud.log" 2>/dev/null

        find "$DATA_DIR" -type f -name "*.log" -delete 2>/dev/null

        echo -e "${GREEN}✔ Logs eliminados${RESET}"

        # =====================================================
        # ARCHIVOS TEMPORALES
        # =====================================================

        echo
        echo -e "${CYAN}Eliminando archivos temporales...${RESET}"

        find "$DATA_DIR" -type f \( \
            -name "*.html" -o \
            -name "*.txt"  -o \
            -name "*.config" -o \
            -name "*.bak" -o \
            -name "*.old" \
        \) -delete 2>/dev/null

        echo -e "${GREEN}✔ Temporales eliminados${RESET}"

        # =====================================================
        # REPARAR PERMISOS
        # =====================================================

        echo
        echo -e "${CYAN}Corrigiendo permisos...${RESET}"

        chown -R "$WEB_USER:$WEB_USER" "$DATA_DIR"

        find "$DATA_DIR" -type d -exec chmod 750 {} \;
        find "$DATA_DIR" -type f -exec chmod 640 {} \;

        echo -e "${GREEN}✔ Permisos corregidos${RESET}"

        echo
        echo -e "${GREEN}✔ Residuos eliminados correctamente${RESET}"

    else

        echo
        echo -e "${YELLOW}Limpieza cancelada${RESET}"

    fi

fi

# =========================================================
# INSTALAR NEXTCLOUD
# REUTILIZANDO DATA EXISTENTE DEL ADMIN
# =========================================================

echo
echo -e "${CYAN}Instalando Nextcloud...${RESET}"

USER_DATA_DIR="$DATA_DIR/$ADMIN_USER"
TEMP_BACKUP="${DATA_DIR}/.${ADMIN_USER}_backup_$(date +%s)"

RESTORE_ADMIN=0

# =========================================================
# DETECTAR DATA EXISTENTE
# =========================================================

if [ -d "$USER_DATA_DIR" ]; then

    echo
    echo -e "${YELLOW}⚠ DATA existente detectada para:${RESET} $ADMIN_USER"
    echo -e "${CYAN}Ruta:${RESET} $USER_DATA_DIR"
    echo

    printf "${CYAN}¿Reutilizar archivos existentes? (s/n): ${RESET}"
    read REUSE_ADMIN

    if [[ "$REUSE_ADMIN" =~ ^[sS]$ ]]; then

        echo
        echo -e "${CYAN}Respaldando carpeta temporalmente...${RESET}"

        mv "$USER_DATA_DIR" "$TEMP_BACKUP"

        if [ $? -ne 0 ]; then
            echo -e "${RED}✘ Error moviendo carpeta${RESET}"
            return
        fi

        RESTORE_ADMIN=1

        echo -e "${GREEN}✔ Respaldo realizado${RESET}"

    fi
fi

# =========================================================
# LIMPIAR RESIDUOS
# =========================================================

rm -rf "$DATA_DIR"/appdata_* 2>/dev/null
rm -rf "$DATA_DIR"/updater-* 2>/dev/null
rm -f "$DATA_DIR"/nextcloud.log 2>/dev/null

# =========================================================
# INSTALAR NEXTCLOUD
# =========================================================

echo
echo -e "${CYAN}Ejecutando instalación...${RESET}"

sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" maintenance:install \
--database "mysql" \
--database-name "$DB_NAME" \
--database-user "$DB_USER" \
--database-pass "$DB_PASS" \
--admin-user "$ADMIN_USER" \
--admin-pass "$ADMIN_PASS" \
--data-dir "$DATA_DIR"

# =========================================================
# VALIDAR INSTALACIÓN
# =========================================================

if [ $? -ne 0 ]; then

    echo
    echo -e "${RED}✘ Error instalando Nextcloud${RESET}"

    # Restaurar carpeta original
    if [ "$RESTORE_ADMIN" = "1" ] && [ -d "$TEMP_BACKUP" ]; then
        mv "$TEMP_BACKUP" "$USER_DATA_DIR"
    fi

    return
fi

# =========================================================
# RESTAURAR ARCHIVOS ADMIN
# =========================================================

if [ "$RESTORE_ADMIN" = "1" ]; then

    echo
    echo -e "${CYAN}Restaurando archivos del administrador...${RESET}"

    mkdir -p "$USER_DATA_DIR/files"

    # Restaurar SOLO archivos útiles
    if [ -d "$TEMP_BACKUP/files" ]; then

        rsync -a \
          --exclude="cache" \
          --exclude="uploads" \
          --exclude="files_trashbin" \
          --exclude="files_versions" \
          --exclude="appdata_*" \
          --exclude=".cache" \
          "$TEMP_BACKUP/files/" "$USER_DATA_DIR/files/"

    fi

    # Limpiar residuos
    rm -rf "$USER_DATA_DIR/files/cache" 2>/dev/null
    rm -rf "$USER_DATA_DIR/files/uploads" 2>/dev/null
    rm -rf "$USER_DATA_DIR/files/files_trashbin" 2>/dev/null
    rm -rf "$USER_DATA_DIR/files/files_versions" 2>/dev/null

    # Eliminar backup temporal
    rm -rf "$TEMP_BACKUP"

    echo -e "${GREEN}✔ Archivos restaurados${RESET}"

fi

# =========================================================
# REPARAR PERMISOS
# =========================================================

echo
echo -e "${CYAN}Corrigiendo permisos...${RESET}"

chown -R "$WEB_USER:$WEB_USER" "$DATA_DIR"

find "$DATA_DIR" -type d -exec chmod 750 {} \;
find "$DATA_DIR" -type f -exec chmod 640 {} \;

echo -e "${GREEN}✔ Permisos corregidos${RESET}"

# =========================================================
# REINDEXAR ARCHIVOS
# =========================================================

echo
echo -e "${CYAN}Escaneando archivos...${RESET}"

sudo -u "$WEB_USER" php "$NC_DIR/occ" files:scan --path="$ADMIN_USER/files"

echo -e "${GREEN}✔ Archivos indexados${RESET}"

echo
echo -e "${GREEN}✔ Nextcloud instalado correctamente${RESET}"

# =========================================================
# CONTINUAR SCRIPT
# =========================================================

# NO pausa
# NO return
# continúa automáticamente con el resto del script

# =========================================================
# REDIS + CRON
# =========================================================

echo
echo -e "${CYAN}Configurando REDIS...${RESET}"
configure_redis
echo
echo -e "${CYAN}REDIS Configurado ...${RESET}"
echo
echo -e "${CYAN}Configurando CRON...${RESET}"
configure_cron
echo
echo -e "${CYAN}CRON Configurado ...${RESET}"
# =========================================================
# REPARAR NEXTCLOUD
# =========================================================

echo
echo -e "${CYAN}Reparando instalación...${RESET}"

sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" maintenance:repair || true

# =========================================================
# DB FIXES
# =========================================================

echo
echo -e "${CYAN}Agregando índices faltantes...${RESET}"

sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" db:add-missing-indices || true

echo
echo -e "${CYAN}Agregando columnas faltantes...${RESET}"

sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" db:add-missing-columns || true

# =========================================================
# ESCANEO DE ARCHIVOS (IMPORTANTE)
# =========================================================

echo
echo -e "${CYAN}Escaneando archivos de usuarios...${RESET}"
echo -e "${YELLOW}Esto puede tardar dependiendo del tamaño del DATA...${RESET}"

sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" files:scan --all

echo -e "${GREEN}✔ Escaneo completado${RESET}"

# =========================================================
# TRUSTED DOMAINS
# =========================================================

echo
echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN} Agrega Dominio/IP a trusted_domains (config.php) ${RESET}"
echo -e "${CYAN}========================================${RESET}"
echo
echo -e "${YELLOW} Ingresa Dominios o IP WAN/LAN (de uno en uno)"
echo
echo -e "${CYAN} Ejemplos:"
echo
echo -e "${YELLOW}  llancor-nextcloud.duckdns.org"
echo
echo -e "${YELLOW}  192.168.10.100"
echo
echo -e "${CYAN} Escribe 'fin' Para Terminar"
echo

DOMAINS=()

while true; do

printf "${CYAN}INGRESAR Dominio / IP:${RESET} "
read domain

    domain=$(echo "$domain" | tr -d '\r\n ')

    # salir
    [[ "$domain" == "fin" ]] && break

    # vacío
    if [[ -z "$domain" ]]; then
        echo -e "${YELLOW}⚠ Campo vacío ignorado${RESET}"
        continue
    fi

    # duplicado
    if [[ " ${DOMAINS[*]} " =~ " $domain " ]]; then
        echo -e "${YELLOW}⚠ Ya existe:${RESET} $domain"
        continue
    fi

    DOMAINS+=("$domain")

done

# fallback
if [ ${#DOMAINS[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠ No se ingresaron dominios, usando IP local${RESET}"
    DOMAINS+=("$(hostname -I | awk '{print $1}')")
fi

# =========================================================
# APLICAR TRUSTED DOMAINS
# =========================================================

echo
echo -e "${CYAN}Aplicando trusted_domains...${RESET}"

i=0

for domain in "${DOMAINS[@]}"; do

    echo -e "${CYAN}→ Agregando:${RESET} $domain"

    sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" \
        config:system:set trusted_domains "$i" --value="$domain"

    ((i++))

done

echo
echo -e "${GREEN}✔ trusted_domains configurado correctamente${RESET}"

# =========================================================
# PERMISOS FINALES
# =========================================================

echo
echo -e "${CYAN}Aplicando permisos finales...${RESET}"

fix_permissions

# =========================================================
# RESTART APACHE
# =========================================================

echo
echo -e "${CYAN}Reiniciando Apache...${RESET}"

systemctl restart apache2 || {
    echo -e "${RED}✘ Error reiniciando Apache${RESET}"
    pause
    return 1
}
# =========================================================
# OBTENER INFORMACIÓN
# =========================================================

IP=$(hostname -I | awk '{print $1}')

# versión Nextcloud
NC_VERSION=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" status \
    | grep "version:" | awk '{print $2}')

# PHP
PHP_VERSION=$(php -v | head -n1)

# MariaDB
MARIADB_VERSION=$(mysql -V)

# Redis
REDIS_VERSION=$(redis-server --version | head -n1)

# estado apache
if systemctl is-active --quiet apache2; then
    APACHE_STATUS="ACTIVO"
else
    APACHE_STATUS="DETENIDO"
fi

# estado redis
if systemctl is-active --quiet redis-server; then
    REDIS_STATUS="ACTIVO"
else
    REDIS_STATUS="DETENIDO"
fi

# estado cron
if systemctl is-active --quiet cron; then
    CRON_STATUS="ACTIVO"
else
    CRON_STATUS="DETENIDO"
fi

# =========================================================
# ARCHIVO RESUMEN
# =========================================================

INFO_FILE="/root/nextcloud_install_$(date +%F_%H-%M-%S).txt"

# =========================================================
# MOSTRAR EN PANTALLA
# =========================================================

echo
echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}        NEXTCLOUD INSTALADO CORRECTAMENTE${RESET}"
echo -e "${GREEN}====================================================${RESET}"

echo
echo -e "${CYAN}Versión Nextcloud:${RESET} $NC_VERSION"
echo -e "${CYAN}PHP:${RESET} $PHP_VERSION"

echo
echo -e "${CYAN}Directorio NC:${RESET} $NC_DIR"
echo -e "${CYAN}Data Directory:${RESET} $DATA_DIR"

echo
echo -e "${CYAN}Acceso local:${RESET} http://$IP"

echo
echo -e "${CYAN}Trusted Domains:${RESET}"

for domain in "${DOMAINS[@]}"; do
    echo " - $domain"
done

echo
echo -e "${CYAN}Usuario administrador:${RESET} $ADMIN_USER"

echo
echo -e "${CYAN}Estado servicios:${RESET}"
echo -e " Apache : $APACHE_STATUS"
echo -e " Redis  : $REDIS_STATUS"
echo -e " Cron   : $CRON_STATUS"

# =========================================================
# GUARDAR INFO EN ARCHIVO
# =========================================================

{
echo "===================================================="
echo "        NEXTCLOUD INSTALADO CORRECTAMENTE"
echo "===================================================="
echo

echo "Fecha                 : $(date)"
echo "Versión Nextcloud     : $NC_VERSION"

echo
echo "PHP                   : $PHP_VERSION"
echo "MariaDB               : $MARIADB_VERSION"
echo "Redis                 : $REDIS_VERSION"

echo
echo "Directorio NC         : $NC_DIR"
echo "Data Directory        : $DATA_DIR"

echo
echo "Acceso local          : http://$IP"

echo
echo "Trusted Domains:"

for domain in "${DOMAINS[@]}"; do
    echo " - $domain"
done

echo
echo "Usuario administrador : $ADMIN_USER"

echo
echo "Estado servicios:"
echo " Apache               : $APACHE_STATUS"
echo " Redis                : $REDIS_STATUS"
echo " Cron                 : $CRON_STATUS"

echo
echo "===================================================="

} > "$INFO_FILE"

chmod 600 "$INFO_FILE"

echo
echo -e "${GREEN}✔ Resumen guardado:${RESET}"
echo -e "${CYAN}$INFO_FILE${RESET}"
echo

pause
}

# =========================================================
# STATUS SERVICIOS NEXTCLOUD PRO
# =========================================================

status_services(){

clear

echo -e "${CYAN}========================================${RESET}"
echo -e "${WHITE}        ESTADO NEXTCLOUD PRO${RESET}"
echo -e "${CYAN}========================================${RESET}"

echo

# =========================================================
# SERVICIOS
# =========================================================

check_service(){

SERVICE_NAME="$1"
DISPLAY_NAME="$2"

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${GREEN}✔${RESET} $DISPLAY_NAME: active"
else
    echo -e "${RED}✘${RESET} $DISPLAY_NAME: inactive"
fi

}

check_service apache2 "Apache"
check_service mariadb "MariaDB"
check_service redis-server "Redis"

echo

# =========================================================
# PHP
# =========================================================

PHP_VERSION=$(php -v 2>/dev/null | head -n 1)

echo -e "${CYAN}PHP:${RESET} ${PHP_VERSION:-No instalado}"

echo

# =========================================================
# RAM / DISCO
# =========================================================

echo -e "${CYAN}RAM:${RESET}"
free -h | awk 'NR==2 {print "Usada: "$3" / Total: "$2}'

echo

echo -e "${CYAN}DISCO:${RESET}"
df -h / | awk 'NR==2 {print "Usado: "$3" / Total: "$2" ("$5")"}'

echo

# =========================================================
# NEXTCLOUD
# =========================================================

if [ -f "$NC_DIR/occ" ]; then

    STATUS=$(
        sudo -u "$WEB_USER" php \
        -d memory_limit=1G \
        "$NC_DIR/occ" status 2>/dev/null || true
    )

    VERSION=$(echo "$STATUS" \
    | grep "version:" \
    | head -n1 \
    | cut -d':' -f2 \
    | xargs)

    INSTALLED=$(echo "$STATUS" \
    | grep "installed:" \
    | head -n1 \
    | cut -d':' -f2 \
    | xargs)

    MAINT=$(echo "$STATUS" \
    | grep "maintenance:" \
    | head -n1 \
    | cut -d':' -f2 \
    | xargs)

    EDITION=$(echo "$STATUS" \
    | grep "edition:" \
    | head -n1 \
    | cut -d':' -f2 \
    | xargs)

    echo -e "${GREEN}✔ Nextcloud instalado${RESET}"

    echo
    echo -e "${CYAN}Versión:${RESET} ${VERSION:-Desconocida}"
    echo -e "${CYAN}Instalado:${RESET} ${INSTALLED:-Unknown}"
    echo -e "${CYAN}Maintenance:${RESET} ${MAINT:-Unknown}"

    [ -n "$EDITION" ] && \
    echo -e "${CYAN}Edition:${RESET} $EDITION"

    echo


# =========================================================
# URL DESDE VHOST NEXTCLOUD
# =========================================================

VHOST_FILE=$(find /etc/apache2/sites-enabled \
-name "*nextcloud*.conf" 2>/dev/null | head -n1)

if [ -z "$VHOST_FILE" ]; then
    VHOST_FILE=$(find /etc/apache2/sites-available \
    -name "*nextcloud*.conf" 2>/dev/null | head -n1)
fi

if [ -n "$VHOST_FILE" ]; then

    DOMAIN=$(grep -i "^ServerName" "$VHOST_FILE" \
    | awk '{print $2}' \
    | head -n1)

    SSL_ENABLED="false"

    if grep -qi "SSLEngine on" "$VHOST_FILE"; then
        SSL_ENABLED="true"
    fi

    if [ -n "$DOMAIN" ]; then

        if [ "$SSL_ENABLED" = "true" ]; then
            echo -e "${CYAN}URL:${RESET} https://$DOMAIN"
        else
            echo -e "${CYAN}URL:${RESET} http://$DOMAIN"
        fi

    else

        echo -e "${YELLOW}ServerName no detectado${RESET}"

    fi

else

    echo -e "${YELLOW}VHost Nextcloud no encontrado${RESET}"

fi

echo

    # =========================================================
    # DATA DIRECTORY
    # =========================================================

    DATA_DIR=$(grep "'datadirectory'" "$NC_DIR/config/config.php" \
    | cut -d"'" -f4)

    echo -e "${CYAN}Data:${RESET} ${DATA_DIR:-No detectado}"

    echo

    # =========================================================
    # APPS IMPORTANTES
    # =========================================================

    echo -e "${CYAN}Apps:${RESET}"

    APPS=(
        "files"
        "activity"
        "calendar"
        "contacts"
        "music"
        "onlyoffice"
        "richdocuments"
        "spreed"
    )

    ENABLED_APPS=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list 2>/dev/null)

    for APP in "${APPS[@]}"; do

        if echo "$ENABLED_APPS" \
        | grep -A999 "Enabled:" \
        | grep -q " - $APP"; then

            echo -e "${GREEN}✔${RESET} $APP"

        else

            echo -e "${RED}✘${RESET} $APP"

        fi

    done

    echo

    # =========================================================
    # CRON
    # =========================================================

    echo -e "${CYAN}Cron:${RESET}"

    if crontab -u "$WEB_USER" -l 2>/dev/null | grep -q "cron.php"; then
        echo -e "${GREEN}✔ Cron configurado${RESET}"
    else
        echo -e "${RED}✘ Cron NO configurado${RESET}"
    fi

else

    echo -e "${RED}❌ Nextcloud NO instalado${RESET}"

fi

echo
echo -e "${CYAN}========================================${RESET}"

pause
}


# =========================================================
# UPDATE NEXTCLOUD PRO
# =========================================================

update_nextcloud(){

    clear

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}     UPDATE NEXTCLOUD PRO${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    # =========================================
    # VALIDAR NEXTCLOUD
    # =========================================

    if [ ! -f "$NC_DIR/occ" ]; then
        echo -e "${RED}❌ No se encontró Nextcloud.${RESET}"
        read -rp "Presiona ENTER para continuar..." || true
        return 0
    fi

    # =========================================
    # VALIDAR UPDATER
    # =========================================

    if [ ! -f "$NC_DIR/updater/updater.phar" ]; then
        echo -e "${RED}❌ No se encontró updater.phar${RESET}"
        read -rp "Presiona ENTER para continuar..." || true
        return 0
    fi

    # =========================================
    # VERSION ACTUAL
    # =========================================

    VERSION_ACTUAL=$(
        sudo -u "$WEB_USER" php "$NC_DIR/occ" status --output=json 2>/dev/null \
        | grep -oP '"version"\s*:\s*"\K[^"]+'
    )

    [ -z "$VERSION_ACTUAL" ] && VERSION_ACTUAL="Desconocida"

    # =========================================
    # VERSION DISPONIBLE
    # =========================================

    echo -e "${CYAN}Buscando nueva versión de Nextcloud...${RESET}"
    echo

    CHECK_UPDATE=$(
        sudo -u "$WEB_USER" php "$NC_DIR/occ" update:check 2>/dev/null
    )

    echo "$CHECK_UPDATE"
    echo

    VERSION_NUEVA=$(
        echo "$CHECK_UPDATE" \
        | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' \
        | head -n1
    )

    # =========================================
    # VALIDAR RESULTADO
    # =========================================

    if [[ -z "$VERSION_NUEVA" || "$VERSION_NUEVA" == "$VERSION_ACTUAL" ]]; then
        VERSION_NUEVA="Sin actualizaciones"
    fi

    # =========================================
    # MOSTRAR VERSIONES
    # =========================================

    echo -e "${GREEN}Versión actual:${RESET} ${VERSION_ACTUAL}"
    echo -e "${CYAN}Nueva versión:${RESET} ${VERSION_NUEVA}"
    echo

    # =========================================
    # YA ACTUALIZADO
    # =========================================

    if [ "$VERSION_NUEVA" = "Sin actualizaciones" ]; then
        echo -e "${GREEN}✔ Nextcloud ya está actualizado.${RESET}"
        echo
        read -rp "Presiona ENTER para continuar..." || true
        return 0
    fi

    # =========================================
    # CONFIRMAR ACTUALIZACION
    # =========================================

    read -rp "¿Deseas actualizar Nextcloud? [s/N]: " CONFIRM_UPDATE

    case "$CONFIRM_UPDATE" in
        s|S|si|SI|y|Y)
            echo
            echo -e "${GREEN}Iniciando actualización...${RESET}"
            ;;
        *)
            echo
            echo -e "${YELLOW}Actualización cancelada.${RESET}"
            read -rp "Presiona ENTER para continuar..." || true
            return 0
            ;;
    esac

    # =========================================
    # INFO SISTEMA
    # =========================================

    echo -e "${CYAN}Espacio disponible:${RESET}"
    df -h /

    echo
    echo -e "${CYAN}Memoria:${RESET}"
    free -h

    echo

    # =========================================
    # DATA DIRECTORY
    # =========================================

    DATA_DIR=$(
        sudo -u "$WEB_USER" php "$NC_DIR/occ" \
        config:system:get datadirectory 2>/dev/null
    )

    echo -e "${CYAN}Directorio de datos:${RESET} ${DATA_DIR:-No detectado}"
    echo

    # =========================================
    # BACKUP DB
    # =========================================

    echo -e "${CYAN}➜ Realizando backup de base de datos...${RESET}"

    DB_BACKUP=$(backup_db_nc)

    if [ -z "$DB_BACKUP" ]; then
        echo -e "${RED}❌ Error creando backup DB.${RESET}"
        read -rp "Presiona ENTER para continuar..." || true
        return 1
    fi

    echo -e "${GREEN}✔ Backup DB:${RESET} $DB_BACKUP"
    echo

    # =========================================
    # MAINTENANCE MODE ON
    # =========================================

    echo -e "${YELLOW}➜ Activando modo mantenimiento...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:mode --on || true

    echo

    # =========================================
    # UPDATER
    # =========================================

    echo -e "${CYAN}➜ Ejecutando updater...${RESET}"
    echo

    LOG_UPDATE="/tmp/nextcloud_update.log"

    sudo -u "$WEB_USER" php \
        -d memory_limit=1G \
        -d max_execution_time=0 \
        "$NC_DIR/updater/updater.phar" \
        --no-interaction | tee "$LOG_UPDATE"

    UPDATE_STATUS=${PIPESTATUS[0]}

    echo

    # =========================================
    # VALIDAR BACKUP UPDATER
    # =========================================

    UPDATER_BACKUP=$(find "$DATA_DIR" -type d -path "*/backups" 2>/dev/null | head -n 1)

    if [ -n "$UPDATER_BACKUP" ]; then
        echo -e "${GREEN}✔ Backup updater creado:${RESET}"
        echo "$UPDATER_BACKUP"
    else
        echo -e "${YELLOW}⚠ No se encontró backup del updater.${RESET}"
    fi

    echo

    # =========================================
    # VALIDAR SI YA ESTA ACTUALIZADO
    # =========================================

    if grep -qiE \
"No update available|Nothing to do|is up to date|already latest|No hay actualizaciones disponibles|Ya está actualizado|Nextcloud ya está actualizado" \
"$LOG_UPDATE"; then

        echo -e "${GREEN}✔ Nextcloud ya está actualizado.${RESET}"

        sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:mode --off || true

        echo
        read -rp "Presiona ENTER para continuar..." || true
        return 0
    fi

    # =========================================
    # VALIDAR ERROR UPDATE
    # =========================================

    if [ "$UPDATE_STATUS" != "0" ]; then

        echo -e "${RED}❌ Error durante actualización.${RESET}"

        echo
        echo -e "${YELLOW}Log:${RESET} $LOG_UPDATE"

        sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:mode --off || true

        echo
        read -rp "Presiona ENTER para continuar..." || true
        return 1
    fi

# =========================================
# OCC UPGRADE
# =========================================

echo -e "${CYAN}➜ Ejecutando OCC upgrade...${RESET}"
echo

OCC_LOG="/tmp/nextcloud_occ_upgrade.log"

sudo -u "$WEB_USER" php \
-d memory_limit=1G \
"$NC_DIR/occ" upgrade 2>&1 | tee "$OCC_LOG"

OCC_STATUS=${PIPESTATUS[0]}

echo

# =========================================
# VALIDAR OCC
# =========================================

if [ "$OCC_STATUS" != "0" ]; then

    echo -e "${RED}❌ Error durante OCC upgrade${RESET}"
    echo

    echo -e "${YELLOW}Log:${RESET}"
    echo "$OCC_LOG"

    echo
    echo -e "${YELLOW}Últimas líneas:${RESET}"
    tail -20 "$OCC_LOG"

    echo

    sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:mode --off || true

    read -rp "Presiona ENTER para continuar..." || true

    return 1

fi

    # =========================================
    # REPARACIONES
    # =========================================

    echo -e "${CYAN}➜ Reparando instalación...${RESET}"
    echo

    sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:repair 
    sudo -u "$WEB_USER" php "$NC_DIR/occ" db:add-missing-indices
    sudo -u "$WEB_USER" php "$NC_DIR/occ" db:add-missing-columns
    sudo -u "$WEB_USER" php "$NC_DIR/occ" db:add-missing-primary-keys

    echo

    # =========================================
    # LIMPIEZA
    # =========================================

    echo -e "${CYAN}➜ Limpiando archivos temporales...${RESET}"

    rm -rf /tmp/nextcloud_update.log.old 2>/dev/null || true

    echo

    # =========================================
    # PERMISOS
    # =========================================

    echo -e "${CYAN}➜ Corrigiendo permisos...${RESET}"

    fix_permissions || true

    echo

    # =========================================
    # RESTART APACHE
    # =========================================

    echo -e "${CYAN}➜ Reiniciando Apache...${RESET}"

    systemctl restart apache2 || true

    echo

    # =========================================
    # MAINTENANCE MODE OFF
    # =========================================

    echo -e "${YELLOW}➜ Desactivando modo mantenimiento...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:mode --off || true

    echo

    # =========================================
    # VERSION FINAL
    # =========================================

    NUEVA_VERSION=$(
        sudo -u "$WEB_USER" php "$NC_DIR/occ" status --output=json 2>/dev/null \
        | grep -oP '"version"\s*:\s*"\K[^"]+'
    )

    # =========================================
    # STATUS FINAL
    # =========================================

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${GREEN}✔ UPDATE COMPLETADO${RESET}"
    echo -e "${GREEN}Versión:${RESET} ${VERSION_ACTUAL:-?} → ${NUEVA_VERSION:-?}"
    echo -e "${CYAN}========================================${RESET}"

    echo

    # =========================================
    # VERIFICACION FINAL
    # =========================================

    echo -e "${CYAN}➜ Verificando estado final...${RESET}"
    echo

    sudo -u "$WEB_USER" php "$NC_DIR/occ" check

    echo
    read -rp "Presiona ENTER para continuar..." || true
}

# =========================================================
# BACKUP
# =========================================================

backup_nextcloud(){

source $DB_FILE

DATE=$(date +%F-%H%M)

BACKUP_DIR="/root/nextcloud-backups/$DATE"

mkdir -p $BACKUP_DIR

sudo -u $WEB_USER php -d memory_limit=1G $NC_DIR/occ maintenance:mode --on || true

mysqldump $DB_NAME > $BACKUP_DIR/db.sql

cp -a $NC_DIR $BACKUP_DIR/
cp -a $DATA_DIR $BACKUP_DIR/

tar -czf /root/nextcloud-backup-$DATE.tar.gz $BACKUP_DIR

sudo -u $WEB_USER php -d memory_limit=1G $NC_DIR/occ maintenance:mode --off || true

echo -e "${GREEN}✔ Backup realizado${RESET}"

pause
}

# =========================================================
# UNINSTALL NEXTCLOUD PRO COMPLETO
# =========================================================
NC_DIR="/var/www/nextcloud"
DATA_DIR="/var/www/nextcloud-data"
WEB_USER="www-data"

uninstall_nextcloud(){

echo
echo -e "${RED}========================================${RESET}"
echo -e "${RED} DESINSTALADOR NEXTCLOUD PRO${RESET}"
echo -e "${RED}========================================${RESET}"
echo

# =========================================================
# CARGAR DB
# =========================================================

source "$DB_FILE" 2>/dev/null || true

# =========================================================
# CONFIRMACIONES
# =========================================================

printf "${CYAN}¿Eliminar instalación Nextcloud? (s/n): ${RESET}"
read DEL_NC

printf "${YELLOW}¿Eliminar directorio NEXTCLOUD-DATA? (s/n): ${RESET}"
read DEL_DATA

printf "${CYAN}¿Eliminar base de datos MySQL? (s/n): ${RESET}"
read DEL_DB

printf "${YELLOW}¿Eliminar VirtualHost Apache? (s/n): ${RESET}"
read DEL_VHOST

printf "${CYAN}¿Eliminar cron jobs Nextcloud? (s/n): ${RESET}"
read DEL_CRON

printf "${YELLOW}¿Limpiar Redis cache? (s/n): ${RESET}"
read DEL_REDIS

echo

# =========================================================
# CONFIRMACION FINAL
# =========================================================

echo -e "${YELLOW}⚠ ADVERTENCIA FINAL${RESET}"
echo -e "${CYAN} Esta operación puede eliminar completamente Nextcloud."
echo

read -rp "$(echo -e "${YELLOW}Escribe YES para continuar:${RESET} ")" FINAL_CONFIRM

if [[ "$(echo "$FINAL_CONFIRM" | tr '[:lower:]' '[:upper:]')" != "YES" ]]; then

    echo -e "${YELLOW}Operación cancelada${RESET}"
    return

fi

# =========================================================
# DETENER SERVICIOS
# =========================================================

echo
echo -e "${CYAN}Deteniendo servicios...${RESET}"

systemctl stop apache2 >/dev/null 2>&1 || true

echo -e "${GREEN}✔ Servicios detenidos${RESET}"

# =========================================================
# ELIMINAR NEXTCLOUD
# =========================================================

if [[ "$DEL_NC" =~ ^[sS]$ ]]; then

    echo
    echo -e "${CYAN}Eliminando instalación Nextcloud...${RESET}"

    rm -rf "$NC_DIR"

    echo -e "${GREEN}✔ Instalación eliminada${RESET}"

fi

# =========================================================
# ELIMINAR DATA
# =========================================================

if [[ "$DEL_DATA" =~ ^[sS]$ ]]; then

    echo
    echo -e "${YELLOW}⚠ ADVERTENCIA${RESET}"
    echo -e "${CYAN}Esto eliminará TODOS los archivos de usuarios.${RESET}"
    echo -e "${YELLOW}Directorio:${RESET} $DATA_DIR"
    echo

read -rp "$(echo -e "${YELLOW}Escribe DELETE para confirmar:${RESET} ")" CONFIRM_DATA

    if [[ "$(echo "$CONFIRM_DATA" | tr '[:lower:]' '[:upper:]')" == "DELETE" ]]; then

        echo
        echo -e "${CYAN}Eliminando directorio DATA...${RESET}"

        echo "Ruta detectada: $DATA_DIR"

        if [[ -d "$DATA_DIR" ]]; then
            rm -rf -- "$DATA_DIR"
        fi

        if [[ ! -e "$DATA_DIR" ]]; then
            echo -e "${GREEN}✔ DATA eliminada${RESET}"
        else
            echo -e "${RED}✘ No se pudo eliminar:${RESET} $DATA_DIR"
            ls -ld "$DATA_DIR"
        fi

    else

        echo
        echo -e "${YELLOW}⚠ Eliminación DATA cancelada${RESET}"

    fi

fi

# =========================================================
# ELIMINAR BASE DE DATOS (SELECCIÓN MANUAL)
# =========================================================

if [[ "$DEL_DB" =~ ^[sS]$ ]]; then

    echo
    echo -e "${CYAN}Listando bases de datos MySQL...${RESET}"
    echo

    DBS=($(mysql -N -e "SHOW DATABASES;" \
        | grep -Ev "information_schema|mysql|performance_schema|sys"))

    if [ ${#DBS[@]} -eq 0 ]; then
        echo -e "${RED}✘ No se encontraron bases de datos${RESET}"
        return 1
    fi

    echo -e "${YELLOW}Elija la Base de Datos a Borrar ${CYAN}(MySQL):${RESET}"
    echo

    select DB_TO_DELETE in "${DBS[@]}"; do
        if [ -n "$DB_TO_DELETE" ]; then
            break
        else
            echo -e "${RED}Selección inválida${RESET}"
        fi
    done

    echo
    echo -e "${YELLOW}⚠ BASE SELECCIONADA:${RESET} $DB_TO_DELETE"
    echo

read -rp "$(echo -e "${YELLOW}Escribe DELETE para confirmar:${RESET} ")" CONFIRM_DB

if [[ "$(echo "$CONFIRM_DB" | tr '[:lower:]' '[:upper:]')" == "DELETE" ]]; then

        echo
        echo -e "${CYAN}Eliminando base de datos...${RESET}"

        mysql -e "DROP DATABASE IF EXISTS \`$DB_TO_DELETE\`;"

        echo -e "${GREEN}✔ Base de datos eliminada${RESET}"

        echo
        echo -e "${CYAN}Eliminando usuario MySQL...${RESET}"

        mysql -e "DROP USER IF EXISTS '$DB_USER'@'localhost';"
        mysql -e "FLUSH PRIVILEGES;"

        echo -e "${GREEN}✔ Usuario eliminado${RESET}"

    else

        echo -e "${YELLOW}⚠ Eliminación cancelada${RESET}"

    fi

fi

# =========================================================
# ELIMINAR APACHE VHOST
# =========================================================

if [[ "$DEL_VHOST" =~ ^[sS]$ ]]; then

    echo
    echo -e "${CYAN}Eliminando VirtualHost Apache...${RESET}"

    a2dissite nextcloud.conf >/dev/null 2>&1 || true

    rm -f /etc/apache2/sites-enabled/nextcloud.conf
    rm -f /etc/apache2/sites-available/nextcloud.conf

    echo -e "${GREEN}✔ VirtualHost eliminado${RESET}"

fi

# =========================================================
# ELIMINAR CRON
# =========================================================

if [[ "$DEL_CRON" =~ ^[sS]$ ]]; then

    echo
    echo -e "${CYAN}Eliminando cron jobs Nextcloud...${RESET}"

    crontab -u "$WEB_USER" -l 2>/dev/null | \
    grep -v "$NC_DIR" | crontab -u "$WEB_USER" -

    echo -e "${GREEN}✔ Cron limpiado${RESET}"

fi

# =========================================================
# LIMPIAR REDIS
# =========================================================

if [[ "$DEL_REDIS" =~ ^[sS]$ ]]; then

    echo
    echo -e "${CYAN}Limpiando Redis cache...${RESET}"

    redis-cli FLUSHALL >/dev/null 2>&1 || true

    echo -e "${GREEN}✔ Redis limpiado${RESET}"

fi

# =========================================================
# LIMPIAR TEMPORALES
# =========================================================

echo
echo -e "${CYAN}Limpiando archivos temporales...${RESET}"

rm -f /tmp/nextcloud.zip
rm -rf /tmp/nextcloud

echo -e "${GREEN}✔ Temporales eliminados${RESET}"

# =========================================================
# REINICIAR SERVICIOS
# =========================================================

echo
echo -e "${CYAN}Reiniciando Apache...${RESET}"

systemctl restart apache2 >/dev/null 2>&1 || true

echo -e "${GREEN}✔ Apache reiniciado${RESET}"

# =========================================================
# FINAL
# =========================================================

echo
echo -e "${GREEN}========================================${RESET}"
echo -e "${GREEN} NEXTCLOUD ELIMINADO CORRECTAMENTE${RESET}"
echo -e "${GREEN}========================================${RESET}"

echo
pause

}

# =========================================================
# FUNCIONES AVANCE PRO
# =========================================================

spinner() {

    local pid=$1
    local delay=0.1
    local spinstr='|/-\'

    while ps -p "$pid" > /dev/null 2>&1; do

        printf " [%c]  " "$spinstr"
        spinstr=${spinstr#?}${spinstr%"${spinstr#?}"}

        sleep $delay

        printf "\b\b\b\b\b\b"

    done

    printf "      \b\b\b\b\b\b"
}

run_live() {

    local MSG="$1"
    shift

    echo -e "${CYAN}${MSG}${NC}"

    local START
    START=$(date +%s)

    "$@" 2>&1 | while IFS= read -r line; do
        echo -e "  ${YELLOW}➜${NC} $line"
    done

    local STATUS=${PIPESTATUS[0]}

    local END
    END=$(date +%s)

    if [[ $STATUS -eq 0 ]]; then

        echo -e "${GREEN}✔ Completado en $((END-START))s${NC}"
        return 0

    else

        echo -e "${RED}✘ Error en: $MSG${NC}"
        return 1

    fi
}


# ========= FUNCIONES AUXILIARES Nextcloud OCC =========
ok(){ echo -e "\e[32m$1\e[0m"; }
warn(){ echo -e "\e[33m$1\e[0m"; }
err(){ echo -e "\e[31m$1\e[0m"; }
pausa(){ read -rp "Presiona ENTER para continuar..."; }

confirmar(){
    read -rp "$1 (s/n): " c
    [[ "$c" =~ ^[sS]$ ]]
}
# ========= VER ERRORES NEXTCLOUD OCC =========
ver_errores_nc(){

    clear
    echo -e "${CYAN}${BOLD}=== ERRORES NEXTCLOUD ===${NC}"
    echo ""

    LOG_FILE="$NEXTCLOUD_DIR/data/nextcloud.log"

    if [ ! -f "$LOG_FILE" ]; then
        err "No se encontró el log"
        pausa
        return
    fi

    echo "Últimos 30 errores:"
    echo "-----------------------------------"
    tail -n 30 "$LOG_FILE"
    echo "-----------------------------------"

    echo ""
    echo "1) Ver en tiempo real"
    echo "2) Limpiar log"
    echo "0) Salir"
    echo ""

    read -rp "Seleccione: " op

    case "$op" in
        1)
            sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" log:tail
        ;;
        2)
            confirmar "¿Borrar log actual?" || return
            sudo truncate -s 0 "$LOG_FILE"
            ok "✔ Log limpiado"
        ;;
        0) return ;;
        *) err "Opción inválida" ;;
    esac

    pausa
}


# ========= REPARAR MIME TYPES OCC =========
reparar_mime_nc(){

    clear
    echo -e "${CYAN}${BOLD}=== Reparar Tipos MIME (Nextcloud) ===${NC}"

    echo "Esto puede tardar dependiendo del tamaño de tu servidor."
    echo ""

    confirmar "¿Ejecutar reparación completa de MIME?" || return

    echo ""
    echo "Activando modo mantenimiento..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --on

    echo "Ejecutando reparación (esto puede tardar)..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:repair --include-expensive

    echo "Desactivando modo mantenimiento..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --off

    ok "✔ Migración de tipos MIME completada"

    pausa
}

# ========= DETECTAR PHP.INI OCC =========
detectar_php_ini(){

    PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")

    if systemctl is-active --quiet apache2; then
        PHP_INI="/etc/php/$PHP_VERSION/apache2/php.ini"
        SERVICIO="apache2"
    else
        PHP_FPM=$(systemctl list-units --type=service | grep -oP "php$PHP_VERSION-fpm")

        if [ -n "$PHP_FPM" ]; then
            PHP_INI="/etc/php/$PHP_VERSION/fpm/php.ini"
            SERVICIO="$PHP_FPM"
        else
            echo "ERROR"
            return 1
        fi
    fi

    if [ ! -f "$PHP_INI" ]; then
        echo "ERROR"
        return 1
    fi

    echo "$PHP_INI|$SERVICIO"
}

# ========= OPCACHE FULL PRO OCC =========
opcache_full_pro_nc(){

    clear
    echo -e "${CYAN}${BOLD}=== OPcache FULL PRO (Nextcloud) ===${NC}"

    # ========= DETECCIÓN =========
 DATA=$(detectar_php_ini)
if [ $? -ne 0 ] || [ -z "$DATA" ]; then
    err "Error detectando php.ini"
    pausa
    return
fi

    PHP_INI=$(echo "$DATA" | cut -d'|' -f1)
    SERVICIO=$(echo "$DATA" | cut -d'|' -f2)

    if [ ! -f "$PHP_INI" ]; then
        err "No se encontró php.ini"
        pausa
        return
    fi

    echo -e "Archivo detectado: ${YELLOW}$PHP_INI${NC}"
    echo -e "Servicio detectado: ${YELLOW}$SERVICIO${NC}"

    # ========= VALORES ACTUALES =========
    echo ""
    echo "Valores actuales:"
    grep -E "opcache.memory_consumption|opcache.interned_strings_buffer|opcache.max_accelerated_files|opcache.revalidate_freq" "$PHP_INI" || echo "No definidos (usando defaults)"

    echo ""
    echo "=== PERFILES ==="
    echo "1) Básico (servidor pequeño) ✅"
    echo "2) Recomendado (Nextcloud normal) 🚀"
    echo "3) Alto rendimiento (servidor potente) 🔥"
    echo "4) Personalizado"
    echo "0) Cancelar"
    echo ""

    read -rp "Seleccione [2]: " op
    op=${op:-2}

    case "$op" in
        1)
            MEM=128
            STR=16
            FILES=10000
            REVAL=2
        ;;
        2)
            MEM=256
            STR=16
            FILES=20000
            REVAL=60
        ;;
        3)
            MEM=512
            STR=32
            FILES=100000
            REVAL=120
        ;;
        4)
            read -rp "memory_consumption (MB): " MEM
            read -rp "interned_strings_buffer (MB): " STR
            read -rp "max_accelerated_files: " FILES
            read -rp "revalidate_freq: " REVAL
        ;;
        0) return ;;
        *) err "Opción inválida"; pausa; return ;;
    esac

    echo ""
    confirmar "Aplicar configuración OPcache PRO?" || return

    # ========= FUNCIÓN ROBUSTA =========
    aplicar_config(){
        PARAM=$1
        VAL=$2

        if grep -Eq "^[;[:space:]]*$PARAM" "$PHP_INI"; then
            sudo sed -i "s|^[;[:space:]]*$PARAM.*|$PARAM=$VAL|" "$PHP_INI"
        else
            echo "$PARAM=$VAL" | sudo tee -a "$PHP_INI" > /dev/null
        fi
    }

    echo ""
    echo "Aplicando optimización..."

    aplicar_config "opcache.enable" "1"
    aplicar_config "opcache.memory_consumption" "$MEM"
    aplicar_config "opcache.interned_strings_buffer" "$STR"
    aplicar_config "opcache.max_accelerated_files" "$FILES"
    aplicar_config "opcache.revalidate_freq" "$REVAL"
    aplicar_config "opcache.save_comments" "1"
    aplicar_config "opcache.enable_cli" "1"

    ok "✔ Parámetros aplicados"

    # ========= REINICIO =========
    echo "Reiniciando servicio $SERVICIO..."
    sudo systemctl restart "$SERVICIO"

    if systemctl is-active --quiet "$SERVICIO"; then
        ok "✔ Servicio reiniciado correctamente"
    else
        err "Error al reiniciar servicio"
        pausa
        return
    fi

    # ========= VALIDACIÓN =========
    echo ""
    echo "Validando configuración aplicada..."

    sleep 2

    VAL_CHECK=$(php -i | grep "opcache.interned_strings_buffer" | awk '{print $5}')

    if [ -z "$VAL_CHECK" ]; then
        warn "No se pudo validar automáticamente (posible entorno distinto CLI/Web)"
    else
        echo "Valor detectado en CLI: $VAL_CHECK MB"

        if [ "$VAL_CHECK" -lt "$STR" ]; then
            warn "⚠ Posible php.ini incorrecto (CLI ≠ Apache/FPM)"
        else
            ok "✔ OPcache aplicado correctamente en CLI"
        fi
    fi

    # ========= CHECK NEXTCLOUD =========
    echo ""
    echo "Verificando estado en Nextcloud..."

    NC_CHECK=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:list system 2>/dev/null)

    if [ $? -eq 0 ]; then
        ok "✔ Nextcloud responde correctamente"
    else
        warn "No se pudo verificar Nextcloud (no crítico)"
    fi

    echo ""
    echo "=== RESULTADO FINAL ==="

    if [ "$STR" -ge 16 ]; then
        ok "✔ Buffer de strings optimizado (>=16MB)"
    else
        warn "Buffer bajo (puede seguir warning)"
    fi

    echo ""
    echo "Revisa en Nextcloud:"
    echo "→ Configuración → Administración → Información"

    echo ""
    echo "Si el warning sigue:"
    echo "- Recarga con Ctrl+F5"
    echo "- Espera 1-2 minutos (cache)"
    echo "- Verifica que no uses PHP-FPM aparte"

    echo ""
    ok "✔ Optimización OPcache FULL PRO completada"

    pausa
}

# == Autoreparacion Inteligente de Nextcloud occ ==
autoreparacion_nc() {
    echo "=== Autoreparacion Inteligente de Nextcloud ==="

    # Activar modo mantenimiento
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --on

    # Detectar version
    NC_VERSION=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" status --output=json | grep -oP '"version":\s*"\K[^"]+')
    echo "Nextcloud version: $NC_VERSION"

    # Detectar comandos disponibles
    OCC_CMDS=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" list)
    [[ "$OCC_CMDS" =~ "maintenance:repair" ]] && CMD_REPAIR="maintenance:repair" || CMD_REPAIR=""
    [[ "$OCC_CMDS" =~ "files:scan" ]] && CMD_SCAN="files:scan --all" || CMD_SCAN=""
    [[ "$OCC_CMDS" =~ "files:cleanup" ]] && CMD_CLEANUP="files:cleanup" || CMD_CLEANUP=""
    [[ "$OCC_CMDS" =~ "db:add-missing-indices" ]] && CMD_INDICES="db:add-missing-indices" || CMD_INDICES=""

    echo "Ejecutando reparaciones disponibles..."

    # 1. Reparacion general
    [ -n "$CMD_REPAIR" ] && sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" $CMD_REPAIR

    # 2. Limpieza de archivos huérfanos / inconsistentes
    [ -n "$CMD_CLEANUP" ] && sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" $CMD_CLEANUP

    # 3. Añadir índices faltantes (mejora rendimiento)
    [ -n "$CMD_INDICES" ] && sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" $CMD_INDICES

    # 4. Escaneo de todos los archivos para sincronizar DB
    [ -n "$CMD_SCAN" ] && sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" $CMD_SCAN

    # Apagar modo mantenimiento antes de listar apps y configuraciones
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --off

    # 5. Verificar apps instaladas
    echo "Verificando apps instaladas..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:list | grep -E "enabled|disabled"

    # 6. Revisar configuraciones criticas
    echo "Comprobando configuraciones criticas..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get dbhost
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get datadirectory

    echo "Autoreparacion inteligente completada para Nextcloud $NC_VERSION"
    read -p "Presiona ENTER para continuar..."
}

# =========================================================
# BACKUP DB NEXTCLOUD PRO
# =========================================================

backup_db_nc(){

    FECHA=$(date +%Y%m%d_%H%M%S)

    BACKUP_DIR="/root/BackupDB"
    mkdir -p "$BACKUP_DIR"

    # =========================================================
    # VALIDAR NEXTCLOUD
    # =========================================================

    if [ ! -f "$NC_DIR/occ" ]; then

        echo -e "${RED}❌ OCC no encontrado${RESET}"
        echo -e "${YELLOW}Ruta:${RESET} $NC_DIR/occ"

        return 1
    fi

    # =========================================================
    # VERSION NEXTCLOUD
    # =========================================================

    NC_VERSION=$(
        sudo -u "$WEB_USER" php "$NC_DIR/occ" status --output=json 2>/dev/null \
        | grep -oP '"version"\s*:\s*"\K[^"]+'
    )

    [ -z "$NC_VERSION" ] && NC_VERSION="unknown"

    # limpiar caracteres raros
    NC_VERSION_CLEAN=$(echo "$NC_VERSION" | tr '.' '_')

    # =========================================================
    # ARCHIVO BACKUP
    # =========================================================

    DB_BACKUP="$BACKUP_DIR/nextcloud_v${NC_VERSION_CLEAN}_${FECHA}.sql.gz"

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}      BACKUP DATABASE NEXTCLOUD${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    echo -e "${GREEN}Versión Nextcloud:${RESET} $NC_VERSION"
    echo

    # =========================================================
    # OBTENER CONFIG DB
    # =========================================================

    DB_NAME=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" config:system:get dbname 2>/dev/null)

    DB_USER=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" config:system:get dbuser 2>/dev/null)

    DB_PASS=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" config:system:get dbpassword 2>/dev/null)

    DB_HOST_RAW=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" config:system:get dbhost 2>/dev/null)

    # =========================================================
    # VALIDAR CONFIG
    # =========================================================

    if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ]; then

        echo -e "${RED}❌ No se pudo obtener configuración DB${RESET}"
        return 1

    fi

    # =========================================================
    # HOST / PUERTO
    # =========================================================

    DB_HOST=$(echo "$DB_HOST_RAW" | cut -d':' -f1)
    DB_PORT=$(echo "$DB_HOST_RAW" | cut -s -d':' -f2)

    [ -z "$DB_HOST" ] && DB_HOST="localhost"
    [ -z "$DB_PORT" ] && DB_PORT="3306"

    echo -e "${CYAN}Base:${RESET} $DB_NAME"
    echo -e "${CYAN}Usuario:${RESET} $DB_USER"
    echo -e "${CYAN}Host:${RESET} $DB_HOST"
    echo -e "${CYAN}Puerto:${RESET} $DB_PORT"

    echo
    echo -e "${YELLOW}➜ Creando backup comprimido...${RESET}"
    echo

    # =========================================================
    # MYSQLDUMP
    # =========================================================

    export MYSQL_PWD="$DB_PASS"

    mysqldump \
        --single-transaction \
        --quick \
        --lock-tables=false \
        --default-character-set=utf8mb4 \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        "$DB_NAME" 2>/tmp/nc_backup_error.log | gzip > "$DB_BACKUP"

    DUMP_STATUS=$?

    unset MYSQL_PWD

    # =========================================================
    # RESULTADO
    # =========================================================

    if [ "$DUMP_STATUS" = "0" ] && [ -f "$DB_BACKUP" ]; then

        SIZE=$(du -h "$DB_BACKUP" | awk '{print $1}')

        echo -e "${GREEN}✔ Backup completado${RESET}"
        echo -e "${CYAN}Archivo:${RESET} $DB_BACKUP"
        echo -e "${CYAN}Tamaño:${RESET} $SIZE"

        echo

        # devolver ruta para:
        # DB_BACKUP=$(backup_db_nc)

        echo "$DB_BACKUP"

        return 0

    else

        echo -e "${RED}❌ Error creando backup${RESET}"

        [ -f /tmp/nc_backup_error.log ] && cat /tmp/nc_backup_error.log

        rm -f "$DB_BACKUP"

        return 1

    fi
}

# ========= RESTORE DB =========
restore_db_nc(){
    DB_FILE="$1"

    DB_NAME=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get dbname)
    DB_USER=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get dbuser)
    DB_PASS=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get dbpassword)

    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$DB_FILE"
}

# =========================================
# DELETE BACKUPS NEXTCLOUD
# =========================================

nextcloud_delete_backups(){

    listar_backups_nextcloud || return 0

    echo -e "${RED}a)${NC} Eliminar TODOS"
    echo -e "${CYAN}0)${NC} Cancelar"

    echo

    read -rp "Seleccione opción: " OP || true

    [[ -z "$OP" ]] && return 0

    # =========================================
    # CANCELAR
    # =========================================

    if [[ "$OP" == "0" ]]; then

        info "Cancelado."

        echo
        read -rp "Presiona ENTER para continuar..." || true

        return 0
    fi

    # =========================================
    # ELIMINAR TODOS
    # =========================================

    if [[ "$OP" =~ ^[aA]$ ]]; then

        echo
        echo -e "${RED}⚠ Se eliminarán TODOS los backups.${NC}"
        echo

        read -rp "Confirmar eliminación total (s/n): " CONF || true

        if [[ "$CONF" =~ ^[sS]$ ]]; then

            for BACKUP in "${BACKUPS[@]}"; do
                rm -rf "$BACKUP"
            done

            echo
            ok "✔ Todos los backups eliminados."

        else

            warn "Operación cancelada."
        fi

        echo
        read -rp "Presiona ENTER para continuar..." || true

        return 0
    fi

    # =========================================
    # ELIMINAR UNO
    # =========================================

    if [[ "$OP" =~ ^[0-9]+$ ]] && (( OP >= 1 && OP <= ${#BACKUPS[@]} )); then

        BACKUP="${BACKUPS[$((OP-1))]}"

        echo
        echo -e "${YELLOW}Backup seleccionado:${NC}"
        echo "$BACKUP"

        echo

        read -rp "⚠ Confirmar eliminación (s/n): " CONF || true

        if [[ "$CONF" =~ ^[sS]$ ]]; then

            rm -rf "$BACKUP"

            echo
            ok "✔ Backup eliminado."

        else

            warn "Operación cancelada."
        fi

    else

        error "❌ Opción inválida."
    fi

    echo
    read -rp "Presiona ENTER para continuar..." || true
}


# ========= GESTIÓN APP API (TOGGLE PRO) =========
gestionar_appapi_nct(){

    clear
    echo -e "${CYAN}${BOLD}=== GESTIÓN APP API (Nextcloud) ===${NC}"
    echo ""

    # ===== VALIDAR NEXTCLOUD =====
    if [ ! -f "$NEXTCLOUD_DIR/occ" ]; then
        err "No se encontró Nextcloud en $NEXTCLOUD_DIR"
        pausa
        return
    fi

    # ===== VERIFICAR SI EXISTE =====
    if ! sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:list | grep -q "app_api"; then
        warn "AppAPI no está instalado en Nextcloud"
        pausa
        return
    fi

    # ===== DETECTAR ESTADO =====
    if sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:list | grep -A1 "Enabled:" | grep -q "app_api"; then
        ESTADO="ACTIVO"
    else
        ESTADO="INACTIVO"
    fi

    echo -e "Estado actual: ${YELLOW}$ESTADO${NC}"
    echo ""

    echo "1) Activar AppAPI"
    echo "2) Desactivar AppAPI"
    echo "3) Toggle automático (recomendado) 🔄"
    echo "0) Cancelar"
    echo ""

    read -rp "Seleccione [3]: " op
    op=${op:-3}

    case "$op" in
        1)
            ACCION="activar"
        ;;
        2)
            ACCION="desactivar"
        ;;
        3)
            if [ "$ESTADO" = "ACTIVO" ]; then
                ACCION="desactivar"
            else
                ACCION="activar"
            fi
        ;;
        0) return ;;
        *) err "Opción inválida"; pausa; return ;;
    esac

    echo ""
    confirmar "¿Desea $ACCION AppAPI?" || return

    echo ""

    # ===== EJECUTAR ACCIÓN =====
    if [ "$ACCION" = "activar" ]; then
        if sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:enable app_api; then
            ok "✔ AppAPI activado correctamente"
        else
            err "Error al activar AppAPI"
            pausa
            return
        fi
    else
        if sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:disable app_api; then
            ok "✔ AppAPI desactivado correctamente"
        else
            err "Error al desactivar AppAPI"
            pausa
            return
        fi
    fi

    # ===== VERIFICACIÓN FINAL =====
    echo ""
    echo "Verificando estado..."

    if sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:list | grep -A1 "Enabled:" | grep -q "app_api"; then
        NUEVO_ESTADO="ACTIVO"
    else
        NUEVO_ESTADO="INACTIVO"
    fi

    echo -e "Nuevo estado: ${GREEN}$NUEVO_ESTADO${NC}"

    ok "✔ Operación completada"

    pausa
}
# =========================================
# LISTAR BACKUPS NEXTCLOUD UPDATER PRO
# =========================================

listar_backups_nextcloud(){

    clear

    BACKUPS=()

    # =========================================
    # BUSCAR BACKUPS
    # =========================================

    while IFS= read -r -d '' dir; do
        BACKUPS+=("$dir")
    done < <(
        find "$NEXTCLOUD_DATA" \
            -mindepth 3 \
            -maxdepth 3 \
            -type d \
            -path "*/updater-*/backups/*" \
            -print0 2>/dev/null | sort -z
    )

    # =========================================
    # VALIDAR
    # =========================================

    if [ ${#BACKUPS[@]} -eq 0 ]; then

        warn "No se encontraron backups del updater."

        echo
        read -rp "Presiona ENTER para continuar..." || true

        return 1
    fi

    # =========================================
    # VERSION ACTUAL
    # =========================================

CURRENT_VERSION=$(
    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" status --output=json 2>/dev/null \
    | grep -oP '"version"\s*:\s*"\K[^"]+'
)

    # =========================================
    # HEADER
    # =========================================

    echo -e "${CYAN}=================================================${NC}"
    echo -e "${WHITE}         BACKUPS NEXTCLOUD UPDATER${NC}"
    echo -e "${CYAN}=================================================${NC}"

    echo -e "${GREEN}Versión actual:${NC} ${WHITE}${CURRENT_VERSION:-Desconocida}${NC}"

    echo

    TOTAL_SIZE=0

    # =========================================
    # MOSTRAR BACKUPS
    # =========================================

    for i in "${!BACKUPS[@]}"; do

        BACKUP="${BACKUPS[$i]}"

        NAME=$(basename "$BACKUP")

        # =========================================
        # VERSION BACKUP
        # =========================================

        VERSION="Desconocida"

        if [ -f "$BACKUP/version.php" ]; then

            VERSION=$(grep "\$OC_VersionString" \
                "$BACKUP/version.php" \
                | cut -d"'" -f2)
        fi

        # =========================================
        # SIZE
        # =========================================

        SIZE=$(du -sh "$BACKUP" 2>/dev/null | awk '{print $1}')

        SIZE_BYTES=$(du -sb "$BACKUP" 2>/dev/null | awk '{print $1}')

        TOTAL_SIZE=$((TOTAL_SIZE + SIZE_BYTES))

        # =========================================
        # FECHA
        # =========================================

        FECHA=$(stat -c '%y' "$BACKUP" \
            2>/dev/null | cut -d'.' -f1)

        # =========================================
        # ARCHIVOS
        # =========================================

        FILES=$(find "$BACKUP" -type f 2>/dev/null | wc -l)

        # =========================================
        # UPDATER
        # =========================================

        UPDATER=$(echo "$BACKUP" | grep -oP 'updater-[^/]+' || true)

        # =========================================
        # MOSTRAR INFO
        # =========================================

        echo -e "${YELLOW}$((i+1)))${NC} ${WHITE}$NAME${NC}"

        if [[ "$VERSION" == "$CURRENT_VERSION" ]]; then

            echo -e "   ${CYAN}Versión :${NC} ${GREEN}${VERSION} ✔ ACTUAL${NC}"

        else

            echo -e "   ${CYAN}Versión :${NC} ${VERSION:-?}"

        fi

        echo -e "   ${CYAN}Tamaño  :${NC} ${SIZE:-?}"
        echo -e "   ${CYAN}Fecha   :${NC} ${FECHA:-?}"
        echo -e "   ${CYAN}Archivos:${NC} $FILES"
        echo -e "   ${CYAN}Updater :${NC} ${UPDATER:-?}"
        echo -e "   ${CYAN}Ruta    :${NC} $BACKUP"

        echo
    done

    # =========================================
    # TOTAL
    # =========================================

    TOTAL_HUMAN=$(numfmt --to=iec "$TOTAL_SIZE" 2>/dev/null)

    echo -e "${CYAN}=================================================${NC}"
    echo -e "${GREEN}Total backups :${NC} ${#BACKUPS[@]}"
    echo -e "${GREEN}Espacio usado :${NC} ${TOTAL_HUMAN:-?}"
    echo -e "${CYAN}=================================================${NC}"

    echo

    return 0
}

# =========================================================
# REINSTALAR NEXTCLOUD DESDE INTERNET
# REPARA INSTALACION DAÑADA
# CONSERVA DB + DATA + CONFIG
# =========================================================

nextcloud_restore(){

    clear

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}   REINSTALAR NEXTCLOUD DESDE INTERNET${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    # =========================================================
    # VALIDAR NEXTCLOUD
    # =========================================================

    if [ ! -f "$NEXTCLOUD_DIR/version.php" ]; then

        echo -e "${RED}❌ No se encontró Nextcloud${RESET}"

        read -rp "ENTER para continuar..."
        return 1
    fi

    # =========================================================
    # DETECTAR VERSION
    # =========================================================

    echo -e "${CYAN}➜ Detectando versión instalada...${RESET}"

    VERSION_ACTUAL=$(
        grep "\$OC_VersionString" \
        "$NEXTCLOUD_DIR/version.php" \
        | cut -d"'" -f2
    )

    if [ -z "$VERSION_ACTUAL" ]; then

        VERSION_ACTUAL=$(
            sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
            status --output=json 2>/dev/null \
            | grep -oP '"version"\s*:\s*"\K[^"]+'
        )
    fi

    if [ -z "$VERSION_ACTUAL" ]; then

        echo -e "${RED}❌ No se pudo detectar la versión${RESET}"

        read -rp "ENTER para continuar..."
        return 1
    fi

    echo -e "${GREEN}✔ Versión detectada:${RESET} $VERSION_ACTUAL"
    echo

    confirmar "¿Reinstalar Nextcloud $VERSION_ACTUAL?" || return

    # =========================================================
    # OBTENER CONFIG
    # =========================================================

    DATA_DIR=$(
        sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
        config:system:get datadirectory 2>/dev/null
    )

    [ -z "$DATA_DIR" ] && DATA_DIR="/var/www/nextcloud-data"

    echo -e "${CYAN}Data directory:${RESET} $DATA_DIR"
    echo

    # =========================================================
    # MODO MANTENIMIENTO
    # =========================================================

    echo -e "${YELLOW}➜ Activando modo mantenimiento...${RESET}"

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
    maintenance:mode --on || true

    echo

    # =========================================================
    # DETENER SERVICIOS
    # =========================================================

    detener_servicios_nextcloud

    # =========================================================
    # TEMPORAL
    # =========================================================

    TMP_DIR="/tmp/nextcloud_reinstall"

    rm -rf "$TMP_DIR"

    mkdir -p "$TMP_DIR"

    cd "$TMP_DIR" || return 1

    # =========================================================
    # URLS DESCARGA
    # =========================================================

    BASE_URL="https://download.nextcloud.com/server/releases"

    ZIP_URL="$BASE_URL/nextcloud-$VERSION_ACTUAL.zip"

    TAR_URL="$BASE_URL/nextcloud-$VERSION_ACTUAL.tar.bz2"

    # =========================================================
    # DESCARGA
    # =========================================================

    echo -e "${CYAN}➜ Descargando Nextcloud $VERSION_ACTUAL...${RESET}"
    echo

    FORMATO=""

    if wget -q --spider "$ZIP_URL"; then

        echo -e "${GREEN}✔ ZIP encontrado${RESET}"

        wget -O nextcloud.zip "$ZIP_URL"

        ARCHIVO="nextcloud.zip"

        FORMATO="zip"

    else

        echo -e "${YELLOW}⚠ ZIP no disponible${RESET}"
        echo -e "${CYAN}Intentando TAR.BZ2...${RESET}"

        if wget -q --spider "$TAR_URL"; then

            echo -e "${GREEN}✔ TAR.BZ2 encontrado${RESET}"

            wget -O nextcloud.tar.bz2 "$TAR_URL"

            ARCHIVO="nextcloud.tar.bz2"

            FORMATO="tar"

        else

            echo -e "${RED}❌ No existe la versión:${RESET} $VERSION_ACTUAL"

            iniciar_servicios_nextcloud

            read -rp "ENTER para continuar..."
            return 1
        fi
    fi

    echo
    echo -e "${GREEN}✔ Descarga completada${RESET}"
    echo

    # =========================================================
    # EXTRAER
    # =========================================================

    echo -e "${CYAN}➜ Extrayendo archivos...${RESET}"

    if [ "$FORMATO" = "zip" ]; then

        unzip -q "$ARCHIVO"

    else

        tar -xjf "$ARCHIVO"

    fi

    if [ ! -d "$TMP_DIR/nextcloud" ]; then

        echo -e "${RED}❌ Error extrayendo Nextcloud${RESET}"

        iniciar_servicios_nextcloud
        return 1
    fi

    echo -e "${GREEN}✔ Archivos extraídos${RESET}"
    echo

    # =========================================================
    # BACKUP CONFIG
    # =========================================================

    echo -e "${CYAN}➜ Resguardando config.php...${RESET}"

    mkdir -p /tmp/nc_restore_backup

    cp "$NEXTCLOUD_DIR/config/config.php" \
       /tmp/nc_restore_backup/config.php.bak

    # =========================================================
    # ELIMINAR INSTALACION DAÑADA
    # =========================================================

    echo -e "${CYAN}➜ Eliminando instalación dañada...${RESET}"

    find "$NEXTCLOUD_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        ! -name "data" \
        -exec rm -rf {} +

    echo

    # =========================================================
    # COPIAR NUEVA INSTALACION
    # =========================================================

    echo -e "${CYAN}➜ Instalando nueva copia...${RESET}"

    rsync -Aax --info=progress2 \
        "$TMP_DIR/nextcloud"/ \
        "$NEXTCLOUD_DIR"/

    if [ $? != 0 ]; then

        echo -e "${RED}❌ Error copiando archivos${RESET}"

        iniciar_servicios_nextcloud
        return 1
    fi

    echo
    echo -e "${GREEN}✔ Archivos instalados${RESET}"
    echo

    # =========================================================
    # RESTAURAR CONFIG
    # =========================================================

    mkdir -p "$NEXTCLOUD_DIR/config"

    cp /tmp/nc_restore_backup/config.php.bak \
       "$NEXTCLOUD_DIR/config/config.php"

    echo -e "${GREEN}✔ Config restaurado${RESET}"
    echo

    # =========================================================
    # DATA DIRECTORY
    # =========================================================

    mkdir -p "$DATA_DIR"

    touch "$DATA_DIR/.ocdata"

    # =========================================================
    # PERMISOS
    # =========================================================

    echo -e "${CYAN}➜ Corrigiendo permisos...${RESET}"

    chown -R "$USER_WEB:$USER_WEB" "$NEXTCLOUD_DIR"

    find "$NEXTCLOUD_DIR" -type d -exec chmod 750 {} \;

    find "$NEXTCLOUD_DIR" -type f -exec chmod 640 {} \;

    chmod +x "$NEXTCLOUD_DIR/occ"

    echo

    # =========================================================
    # INICIAR SERVICIOS
    # =========================================================

    iniciar_servicios_nextcloud
# =========================================================
# UPGRADE NEXTCLOUD
# =========================================================

echo
echo -e "${YELLOW}➜ Ejecutando upgrade...${RESET}"
echo

sudo -u "$USER_WEB" php \
-d memory_limit=1G \
"$NEXTCLOUD_DIR/occ" upgrade

UPGRADE_STATUS=$?

echo

if [ "$UPGRADE_STATUS" != "0" ]; then

    echo -e "${RED}❌ Upgrade terminó con errores${RESET}"
    echo

    sudo -u "$USER_WEB" php \
    "$NEXTCLOUD_DIR/occ" maintenance:mode --off || true

    iniciar_servicios_nextcloud

    read -rp "ENTER para continuar..."
    return 1
fi

echo -e "${GREEN}✔ Upgrade completado${RESET}"
echo

    # =========================================================
    # REPARACION
    # =========================================================

    echo -e "${CYAN}➜ Reparando instalación...${RESET}"

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" maintenance:repair || true

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" db:add-missing-indices || true

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" db:add-missing-columns || true

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" db:add-missing-primary-keys || true

    echo

    # =========================================================
    # MAINTENANCE OFF
    # =========================================================

    echo -e "${CYAN}➜ Desactivando mantenimiento...${RESET}"

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
    maintenance:mode --off || true

    echo

    # =========================================================
    # LIMPIEZA
    # =========================================================

    rm -rf "$TMP_DIR"

    # =========================================================
    # VERSION FINAL
    # =========================================================

    VERSION_FINAL=$(
        sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
        status --output=json 2>/dev/null \
        | grep -oP '"version"\s*:\s*"\K[^"]+'
    )

    # =========================================================
    # FINAL
    # =========================================================

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${GREEN}✔ NEXTCLOUD REINSTALADO${RESET}"
    echo -e "${GREEN}Versión:${RESET} $VERSION_FINAL"
    echo -e "${CYAN}========================================${RESET}"

    echo

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" check || true

    echo
    read -rp "ENTER para continuar..."
}

# =========================================================
# FIN REINSTALAR NEXTCLOUD
# =========================================================

# ========= RESTORE COPIA DE SEGURIDAD FORZADO =========

restaurar_backup_forzado(){
echo -e "${YELLOW}📂 Buscando backups disponibles...${NC}"
  listar_backups_nextcloud || return

  read -rp "Selecciona la copia a restaurar (0=cancelar): " n
  [[ "$n" == "0" ]] && warn "Cancelado." && return
  [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#BACKUPS[@]} )) || { err "Número inválido."; return; }

  SELECTED_BACKUP="${BACKUPS[$((n-1))]}"
echo
echo -e "${CYAN}📦 Backup seleccionado:${NC} ${WHITE}$SELECTED_BACKUP${NC}"
  confirmar "¿Restaurar desde $SELECTED_BACKUP?" || return

echo
echo -e "${YELLOW}🔍 Verificando dependencia pv...${NC}"

  # ===== Verificar pv (sin cortar ejecución) =====
USE_PV=true

if ! command -v pv >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠ pv no está instalado. Intentando instalar...${NC}"
  
  if apt update -qq && apt install -y -qq pv; then
    echo -e "${GREEN}✔ pv instalado correctamente${NC}"
  else
    echo -e "${RED}❌ No se pudo instalar pv, continuando sin barra de progreso...${NC}"
    USE_PV=false
  fi
fi

echo -e "${YELLOW}⛔ Deteniendo servicios Nextcloud...${NC}"
  detener_servicios_nextcloud

  echo
  echo -e "${CYAN}🧹 Eliminando instalación actual...${NC}"

  # BORRADO TOTAL (fuerza bruta)
  rm -rf "$NEXTCLOUD_DIR"/*
  echo -e "${GREEN}✔ Instalación anterior eliminada${NC}"

  echo
  echo -e "${CYAN}📥 Restaurando archivos desde backup...${NC}"
  
  # ===== RESTORE CON PROGRESO (MISMA LÓGICA CP) =====
TOTAL_FILES=$(find "$SELECTED_BACKUP" -type f | wc -l)
  echo -e "${WHITE}📄 Total de archivos a restaurar:${NC} $TOTAL_FILES"
cd "$SELECTED_BACKUP" || return

find . -type f -print0 | pv -0 -l -s "$TOTAL_FILES" -w 80 \
-F "Progreso: [%b] %p%% (%c/$TOTAL_FILES archivos) ETA %t" \
| while IFS= read -r -d '' file; do
  mkdir -p "$NEXTCLOUD_DIR/$(dirname "$file")"
  cp -a "$file" "$NEXTCLOUD_DIR/$file"
done

echo

  echo
  echo -e "${YELLOW}🔐 Aplicando permisos seguros...${NC}"
  # PERMISOS

# PROPIETARIO
chown -R $USER_WEB:$USER_WEB "$NEXTCLOUD_DIR"
echo -e "${YELLOW}🔐 Aplicado Permisos Propietario...${NC}"

# PERMISOS SEGUROS
find "$NEXTCLOUD_DIR" -type d -exec chmod 750 {} \;
find "$NEXTCLOUD_DIR" -type f -exec chmod 640 {} \;
echo -e "${YELLOW}🔐 Aplicado Permisos Nextcloud chmod 750/640...${NC}"

# OCC EJECUTABLE
chmod +x "$NEXTCLOUD_DIR/occ"
echo -e "${YELLOW}🔐 Aplicado Permiso Ejecutable OCC...${NC}"

# CARPETAS QUE NEXTCLOUD NECESITA ESCRIBIR

chmod -R 770 "$NEXTCLOUD_DIR/config"
chmod -R 770 "$NEXTCLOUD_DIR/apps"
chmod -R 770 "$NEXTCLOUD_DIR/custom_apps"
chmod -R 770 "$NEXTCLOUD_DIR/updater"
echo -e "${YELLOW}🔐 Aplicado Permiso Carpetas que necesta Escribir...${NC}"
# DATA
chown -R $USER_WEB:$USER_WEB "$DATA_DIR"
find "$DATA_DIR" -type d -exec chmod 750 {} \;
find "$DATA_DIR" -type f -exec chmod 640 {} \; 
echo -e "${YELLOW}🔐 Aplicado Permisos nextcloud-data 750/640...${NC}"
echo
echo
echo -e "${GREEN}✔ Permisos aplicados${NC}"  
  
  echo
  echo -e "${YELLOW}▶ Iniciando servicios Nextcloud...${NC}"
  iniciar_servicios_nextcloud
  
  echo -e "${YELLOW}Intentando upgrade...${NC}"
  sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" upgrade 2>/dev/null
  
  echo -e "${YELLOW} Deshabilitando modo mantenimiento ${NC}"
  sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off
  
  # REPARACION BASICA
  echo -e "${YELLOW}Ejecutando reparación básica...${NC}"
  sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:repair 2>/dev/null
  
printf "\n"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}   ✔ Restauración completada correctamente  ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo
echo -e "${CYAN}📌 Presiona Enter para volver al menú...${NC}"
read

}

# ========= FIN RESTORE COPIA DE SEGURIDAD FORZADO =========

# INICIAR SERVICIOS DE Nextcloud

iniciar_servicios_nextcloud() {
    echo -e "${CYAN}Iniciando servicios de Nextcloud...${NC}"

    systemctl start apache2 2>/dev/null
    systemctl start nginx 2>/dev/null

    systemctl start php8.3-fpm 2>/dev/null
    systemctl start php8.2-fpm 2>/dev/null
    systemctl start php8.1-fpm 2>/dev/null

    echo -e "${GREEN}✔ Servicios iniciados${NC}"
}

# FIN INICIAR SERVICIOS DE Nextcloud

# DETENER SERVICIOS DE Nextcloud
detener_servicios_nextcloud() {
    echo -e "${CYAN}Deteniendo servicios de Nextcloud...${NC}"

    # Apache
    systemctl stop apache2 2>/dev/null

    # Nginx
    systemctl stop nginx 2>/dev/null

    # PHP-FPM (varias versiones posibles)
    systemctl stop php8.3-fpm 2>/dev/null
    systemctl stop php8.2-fpm 2>/dev/null
    systemctl stop php8.1-fpm 2>/dev/null

    # Cron de Nextcloud (www-data normalmente)
    crontab -u www-data -l 2>/dev/null | grep -v "cron.php" | crontab -u www-data -

    echo -e "${GREEN}✔ Servicios detenidos${NC}"
}
# FIN DETENER SERVICIOS DE Nextcloud
# =========================================================
# NEXTCLOUD USER MANAGER (STANDALONE)
# =========================================================

# ========= COLORES =========

RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'

# ========= CONFIG =========

NC_PATH="/var/www/nextcloud"
NC_USER="www-data"

# Detectar DATA_DIR automáticamente
DATA_DIR=$(sudo -u "$NC_USER" php "$NC_PATH/occ" config:system:get datadirectory 2>/dev/null)

# Usuario web
WEB_USER="www-data"

# ========= FUNCIONES BASE =========

pausa(){
    echo
    read -rp "Presiona ENTER para continuar..."
}

ok(){
    echo -e "${GREEN}✔ $1${RESET}"
}

warn(){
    echo -e "${YELLOW}⚠ $1${RESET}"
}

err(){
    echo -e "${RED}✘ $1${RESET}"
}

# =========================================================
# VALIDAR NEXTCLOUD
# =========================================================

validar_nextcloud(){

    if [ ! -f "$NC_PATH/occ" ]; then

        err "No se encontró Nextcloud en:"
        echo "$NC_PATH"
        exit 1

    fi

    if [ -z "$DATA_DIR" ]; then

        err "No se pudo detectar DATA_DIR"
        exit 1

    fi

}

# =========================================================
# MENU PRINCIPAL
# =========================================================

menu_usuarios_nextcloud(){

  while true; do

    clear

    echo -e "${CYAN}${BOLD}=========================================${RESET}"
    echo -e "${CYAN}${BOLD}      NEXTCLOUD USER MANAGER            ${RESET}"
    echo -e "${CYAN}${BOLD}=========================================${RESET}"

    echo
    echo -e "${CYAN}Nextcloud:${RESET} $NC_PATH"
    echo -e "${CYAN}DATA:${RESET} $DATA_DIR"

    echo
    echo -e " ${YELLOW}1)${RESET} Listar usuarios"
    echo -e " ${YELLOW}2)${RESET} Crear usuario"
    echo -e " ${YELLOW}3)${RESET} Eliminar usuario"
    echo -e " ${YELLOW}4)${RESET} Resetear contraseña"
    echo -e " ${YELLOW}5)${RESET} Cambiar contraseña automático"
    echo -e " ${YELLOW}6)${RESET} Hacer administrador"
    echo -e " ${YELLOW}7)${RESET} Información usuario"
    echo -e " ${YELLOW}0)${RESET} Volver"

    echo
    read -rp "> " op

    case "$op" in

      1) nc_listar_usuarios ;;
      2) nc_crear_usuario ;;
      3) nc_eliminar_usuario ;;
      4) nc_resetear_password ;;
      5) nc_cambiar_password ;;
      6) nc_hacer_admin ;;
      7) nc_info_usuario ;;
      0) return ;;

      *) warn "Opción inválida"; pausa ;;

    esac

  done
}

# =========================================================
# LISTAR USUARIOS
# =========================================================

nc_listar_usuarios(){

    clear

    echo
    echo -e "${YELLOW}==================================================${RESET}"
    echo -e "${YELLOW}           USUARIOS NEXTCLOUD                     ${RESET}"
    echo -e "${YELLOW}==================================================${RESET}"
    echo

    USERS=$(sudo -u "$NC_USER" php "$NC_PATH/occ" user:list \
        | cut -d: -f2 \
        | sed 's/^ //')

    if [ -z "$USERS" ]; then

        err "No hay usuarios registrados"
        pausa
        return

    fi

    COUNT=1

    for USER in $USERS; do

        IS_ADMIN=$(sudo -u "$NC_USER" php "$NC_PATH/occ" group:list "$USER" 2>/dev/null | grep -w admin)

        QUOTA=$(sudo -u "$NC_USER" php "$NC_PATH/occ" user:info "$USER" 2>/dev/null \
            | grep "quota:" \
            | awk -F': ' '{print $2}')

        [ -z "$QUOTA" ] && QUOTA="Default"

        if [ -n "$IS_ADMIN" ]; then

            echo -e "${CYAN}[$COUNT]${RESET} ${GREEN}$USER${RESET} ${YELLOW}(ADMIN)${RESET}"

        else

            echo -e "${CYAN}[$COUNT]${RESET} ${GREEN}$USER${RESET}"

        fi

        echo -e "    ${CYAN}Cuota:${RESET} $QUOTA"

        if [ -d "$DATA_DIR/$USER" ]; then

            SIZE=$(du -sh "$DATA_DIR/$USER" 2>/dev/null | awk '{print $1}')

            echo -e "    ${CYAN}DATA:${RESET} ${GREEN}Existe${RESET} (${SIZE})"

        else

            echo -e "    ${CYAN}DATA:${RESET} ${RED}No encontrada${RESET}"

        fi

        echo

        COUNT=$((COUNT+1))

    done

    pausa
}

# =========================================================
# CREAR USUARIO
# =========================================================

nc_crear_usuario(){

    clear

    echo
    echo -e "${YELLOW}==================================================${RESET}"
    echo -e "${YELLOW}        CREAR USUARIO NEXTCLOUD                   ${RESET}"
    echo -e "${YELLOW}==================================================${RESET}"
    echo

    read -rp "Nuevo usuario: " USERNAME

    if [ -z "$USERNAME" ]; then

        err "Usuario vacío"
        pausa
        return

    fi

    USER_DIR="$DATA_DIR/$USERNAME"

    TEMP_BACKUP="${DATA_DIR}/.${USERNAME}_backup_$(date +%s)"

    RESTORE_USER=0

    if sudo -u "$NC_USER" php "$NC_PATH/occ" user:info "$USERNAME" >/dev/null 2>&1; then

        err "El usuario ya existe"
        pausa
        return

    fi

    if [ -d "$USER_DIR" ]; then

        echo
        warn "Carpeta existente detectada"
        echo -e "${CYAN}Ruta:${RESET} $USER_DIR"
        echo

        read -rp "¿Reutilizar DATA existente? (s/n): " REUSE_DATA

        if [[ "$REUSE_DATA" =~ ^[sS]$ ]]; then

            echo
            echo -e "${CYAN}Limpiando residuos...${RESET}"

            rm -rf "$USER_DIR/files_trashbin" 2>/dev/null
            rm -rf "$USER_DIR/files_versions" 2>/dev/null
            rm -rf "$USER_DIR/uploads" 2>/dev/null
            rm -rf "$USER_DIR/cache" 2>/dev/null

            find "$USER_DIR" -type d -name "appdata_*" -exec rm -rf {} + 2>/dev/null
            find "$USER_DIR" -type d -name "updater-*" -exec rm -rf {} + 2>/dev/null
            find "$USER_DIR" -type f -name "*.log" -delete 2>/dev/null

            mv "$USER_DIR" "$TEMP_BACKUP"

            if [ $? -ne 0 ]; then

                err "No se pudo mover DATA"
                pausa
                return

            fi

            RESTORE_USER=1

        else

            warn "Operación cancelada"
            pausa
            return

        fi

    fi

    echo
    echo -e "${CYAN}Creando usuario...${RESET}"

    sudo -u "$NC_USER" php "$NC_PATH/occ" user:add "$USERNAME"

    if [ $? -ne 0 ]; then

        err "Error creando usuario"

        if [ "$RESTORE_USER" = "1" ] && [ -d "$TEMP_BACKUP" ]; then
            mv "$TEMP_BACKUP" "$USER_DIR"
        fi

        pausa
        return

    fi

    if [ "$RESTORE_USER" = "1" ]; then

        echo
        echo -e "${CYAN}Restaurando DATA...${RESET}"

        rm -rf "$USER_DIR"
        mv "$TEMP_BACKUP" "$USER_DIR"

        chown -R "$WEB_USER:$WEB_USER" "$USER_DIR"

        find "$USER_DIR" -type d -exec chmod 750 {} \;
        find "$USER_DIR" -type f -exec chmod 640 {} \;

        echo
        echo -e "${CYAN}Escaneando archivos...${RESET}"

        sudo -u "$NC_USER" php "$NC_PATH/occ" files:scan --path="$USERNAME/files"

    fi

    ok "Usuario creado correctamente"

    pausa
}

# =========================================================
# ELIMINAR USUARIO NEXTCLOUD (SEGURO)
# CONSERVA DATA RENOMBRANDO ANTES
# =========================================================

nc_eliminar_usuario(){

    clear

    echo
    echo -e "${YELLOW}==================================================${RESET}"
    echo -e "${YELLOW}         ELIMINAR USUARIO NEXTCLOUD               ${RESET}"
    echo -e "${YELLOW}==================================================${RESET}"

    seleccionar_usuario_nc || return

    USER_DIR="$DATA_DIR/$SELECTED_USER"

    echo
    echo -e "${CYAN}Usuario:${RESET} ${GREEN}$SELECTED_USER${RESET}"
    echo

    read -rp "¿Eliminar también DATA del usuario? (s/n): " DEL_DATA

    # =====================================================
    # SI SE CONSERVA DATA
    # =====================================================

    if [[ ! "$DEL_DATA" =~ ^[sS]$ ]] && [ -d "$USER_DIR" ]; then

        echo
        echo -e "${CYAN}Protegiendo DATA usuario...${RESET}"

        # =================================================
        # RENOMBRAR DATA ANTES DE ELIMINAR
        # =================================================

        TEMP_BACKUP="${DATA_DIR}/.${SELECTED_USER}_backup_$(date +%s)"

        mv "$USER_DIR" "$TEMP_BACKUP"

        if [ $? -ne 0 ]; then

            err "No se pudo proteger DATA"

            pausa
            return

        fi

        ok "DATA protegida temporalmente"

    fi

    # =====================================================
    # ELIMINAR USUARIO NEXTCLOUD
    # =====================================================

    echo
    echo -e "${CYAN}Eliminando usuario Nextcloud...${RESET}"

    sudo -u "$NC_USER" php "$NC_PATH/occ" user:delete "$SELECTED_USER"

    if [ $? -ne 0 ]; then

        err "Error eliminando usuario"

        # =================================================
        # RESTAURAR DATA SI FALLA
        # =================================================

        if [ -d "$TEMP_BACKUP" ]; then

            mv "$TEMP_BACKUP" "$USER_DIR"

            ok "DATA restaurada"

        fi

        pausa
        return

    fi

    ok "Usuario eliminado"

    # =====================================================
    # ELIMINAR DATA DEFINITIVAMENTE
    # =====================================================

    if [[ "$DEL_DATA" =~ ^[sS]$ ]]; then

        echo
        echo -e "${CYAN}Eliminando DATA usuario...${RESET}"

        rm -rf "$USER_DIR"

        if [ $? -eq 0 ]; then

            ok "DATA eliminada"
        else
            err "No se pudo eliminar DATA"
        fi

    else

        # =================================================
        # RESTAURAR NOMBRE ORIGINAL
        # =================================================

        echo
        echo -e "${CYAN}Restaurando DATA usuario...${RESET}"

        mv "$TEMP_BACKUP" "$USER_DIR"

        if [ $? -ne 0 ]; then

            err "No se pudo restaurar DATA"

            pausa
            return

        fi

        # =================================================
        # REPARAR PERMISOS
        # =================================================

        chown -R "$WEB_USER:$WEB_USER" "$USER_DIR"

        find "$USER_DIR" -type d -exec chmod 750 {} \;
        find "$USER_DIR" -type f -exec chmod 640 {} \;

        ok "DATA restaurada correctamente"

        echo
        echo -e "${GREEN}✔ DATA conservada:${RESET}"
        echo "$USER_DIR"

    fi

    pausa
}

# =========================================================
# SELECCIONAR USUARIO
# =========================================================

seleccionar_usuario_nc(){

    USERS=$(sudo -u "$NC_USER" php "$NC_PATH/occ" user:list \
        | cut -d: -f2 \
        | sed 's/^ //')

    if [ -z "$USERS" ]; then

        err "No hay usuarios"
        return 1

    fi

    echo

    USER_ARRAY=()

    COUNT=1

    for USER in $USERS; do

        USER_ARRAY+=("$USER")

        echo -e "${CYAN}[$COUNT]${RESET} ${GREEN}$USER${RESET}"

        COUNT=$((COUNT+1))

    done

    echo -e "${CYAN}[$COUNT]${RESET} ${RED}Volver${RESET}"
    echo

    while true; do

        read -rp "Selecciona usuario: " OPTION

        if ! [[ "$OPTION" =~ ^[0-9]+$ ]]; then

            warn "Ingresa un número válido"
            continue

        fi

        if [ "$OPTION" -eq "$COUNT" ]; then
            return 1
        fi

        INDEX=$((OPTION-1))

        if [ -n "${USER_ARRAY[$INDEX]}" ]; then

            SELECTED_USER="${USER_ARRAY[$INDEX]}"
            return 0

        fi

        warn "Selección inválida"

    done
}

# =========================================================
# RESET PASSWORD
# =========================================================

nc_resetear_password(){

    clear

    seleccionar_usuario_nc || return

    echo
    echo -e "${CYAN}Usuario:${RESET} ${GREEN}$SELECTED_USER${RESET}"
    echo

    sudo -u "$NC_USER" php "$NC_PATH/occ" user:resetpassword "$SELECTED_USER"

    pausa
}

# =========================================================
# PASSWORD AUTOMATICO
# =========================================================

nc_cambiar_password(){

    clear

    seleccionar_usuario_nc || return

    echo
    echo -e "${CYAN}Usuario:${RESET} ${GREEN}$SELECTED_USER${RESET}"
    echo

    read -rsp "Nueva contraseña: " pass
    echo

    if [ -z "$pass" ]; then

        warn "Contraseña vacía"
        pausa
        return

    fi

    sudo -u "$NC_USER" OC_PASS="$pass" php "$NC_PATH/occ" \
        user:resetpassword --password-from-env "$SELECTED_USER"

    if [ $? -eq 0 ]; then
        ok "Contraseña actualizada"
    else
        err "Error cambiando contraseña"
    fi

    pausa
}

# =========================================================
# HACER ADMIN
# =========================================================

nc_hacer_admin(){

    clear

    seleccionar_usuario_nc || return

    echo
    echo -e "${CYAN}Usuario:${RESET} ${GREEN}$SELECTED_USER${RESET}"
    echo

    sudo -u "$NC_USER" php "$NC_PATH/occ" group:add admin >/dev/null 2>&1

    sudo -u "$NC_USER" php "$NC_PATH/occ" \
        group:adduser admin "$SELECTED_USER"

    if [ $? -eq 0 ]; then
        ok "Usuario ahora es ADMIN"
    else
        err "Error asignando permisos"
    fi

    pausa
}

# =========================================================
# INFO USUARIO
# =========================================================

nc_info_usuario(){

    clear

    seleccionar_usuario_nc || return

    echo
    echo -e "${CYAN}Usuario:${RESET} ${GREEN}$SELECTED_USER${RESET}"
    echo

    sudo -u "$NC_USER" php "$NC_PATH/occ" user:info "$SELECTED_USER"

    pausa
}
# =========================================================
# DESCARGAR SCRIPTS DESDE GITHUB
# DESCARGA + EJECUTA
# SOBRESCRIBE SI EXISTE
# =========================================================

download_script(){

    echo
    echo -e "${CYAN}Buscando scripts disponibles...${RESET}"

    # =====================================================
    # CONFIG GITHUB
    # =====================================================

    GITHUB_USER="llancor"
    GITHUB_REPO="script-llancor"
    GITHUB_BRANCH="main"
    GITHUB_PATH="Script_Unificados_3.0"

    API_URL="https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO/contents/$GITHUB_PATH"

    # =====================================================
    # VERIFICAR DEPENDENCIAS
    # =====================================================

    for cmd in curl jq wget; do

        if ! command -v "$cmd" >/dev/null 2>&1; then

            echo
            echo -e "${YELLOW}Instalando dependencia:${RESET} $cmd"

            apt update -y

            case $cmd in

                jq)
                    apt install -y jq
                ;;

                *)
                    apt install -y curl wget
                ;;

            esac
        fi
    done

    # =====================================================
    # VALIDAR INTERNET
    # =====================================================

    if ! ping -c 1 github.com >/dev/null 2>&1; then

        echo
        echo -e "${RED}Sin conexión a internet.${RESET}"

        return
    fi

    # =====================================================
    # OBTENER ARCHIVOS DESDE GITHUB
    # =====================================================

    HTTP_CODE=$(curl -s -o /tmp/github_scripts.json -w "%{http_code}" "$API_URL")

    if [ "$HTTP_CODE" != "200" ]; then

        echo
        echo -e "${RED}Error accediendo al repositorio GitHub.${RESET}"

        return
    fi

    # =====================================================
    # LISTAR ARCHIVOS .SH
    # =====================================================

    mapfile -t FILES < <(
        jq -r '.[] | select(.name | endswith(".sh")) | .name' /tmp/github_scripts.json
    )

    # =====================================================
    # VALIDAR ARCHIVOS
    # =====================================================

    if [ ${#FILES[@]} -eq 0 ]; then

        echo
        echo -e "${RED}No se encontraron scripts .sh${RESET}"

        return
    fi

    # =====================================================
    # MENU
    # =====================================================

    while true; do

        clear

        echo -e "${YELLOW}========================================${RESET}"
        echo -e "${YELLOW}      SCRIPTS DISPONIBLES GITHUB        ${RESET}"
        echo -e "${YELLOW}========================================${RESET}"
        echo

        for i in "${!FILES[@]}"; do

            echo -e "${CYAN}[$((i+1))]${RESET} ${GREEN}${FILES[$i]}${RESET}"

        done

        echo
        echo -e "${RED}[0]${RESET} Volver"
        echo

        read -rp "Seleccione script: " opt

        if [[ "$opt" == "0" ]]; then
            return
        fi

        if ! [[ "$opt" =~ ^[0-9]+$ ]]; then

            echo
            echo -e "${RED}Opción inválida.${RESET}"

            sleep 2
            continue
        fi

        if (( opt < 1 || opt > ${#FILES[@]} )); then

            echo
            echo -e "${RED}Número fuera de rango.${RESET}"

            sleep 2
            continue
        fi

        FILE="${FILES[$((opt-1))]}"

        echo
        echo -e "${GREEN}✔ Script seleccionado:${RESET} ${YELLOW}$FILE${RESET}"

        break

    done

    # =====================================================
    # URL RAW GITHUB
    # =====================================================

    RAW_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH/$GITHUB_PATH/$FILE"

    # =====================================================
    # RUTA DESTINO
    # =====================================================

    CURRENT_DIR="$(pwd)"

    DEST_FILE="$CURRENT_DIR/$FILE"

    TMP_FILE="/tmp/$FILE"

    echo
    echo -e "${CYAN}Descargando script...${RESET}"

    # =====================================================
    # DESCARGAR SCRIPT
    # =====================================================

    if ! wget -q -O "$TMP_FILE" "$RAW_URL"; then

        echo
        echo -e "${RED}Error descargando script.${RESET}"

        return
    fi

    # =====================================================
    # VALIDAR SCRIPT
    # =====================================================

    if ! grep -q "#!/bin/bash" "$TMP_FILE"; then

        echo
        echo -e "${RED}Archivo descargado inválido.${RESET}"

        rm -f "$TMP_FILE"

        return
    fi

    # =====================================================
    # SOBRESCRIBIR SI EXISTE
    # =====================================================

    if [ -f "$DEST_FILE" ]; then

        echo
        echo -e "${YELLOW}El archivo ya existe y será sobrescrito:${RESET}"
        echo -e "${CYAN}$DEST_FILE${RESET}"

    fi

    # =====================================================
    # MOVER SCRIPT
    # =====================================================

    mv -f "$TMP_FILE" "$DEST_FILE"

    chmod +x "$DEST_FILE"

    echo
    echo -e "${GREEN}✔ Script descargado correctamente${RESET}"

    echo
    echo -e "${CYAN}Ruta:${RESET}"
    echo -e "${GREEN}$DEST_FILE${RESET}"

    sleep 2

    # =====================================================
    # EJECUTAR SCRIPT
    # =====================================================

    echo
    echo -e "${YELLOW}Ejecutando script...${RESET}"

    sleep 1

    exec bash "$DEST_FILE"
}
# =========================================================
# MENU
# =========================================================
while true; do

clear

echo
echo -e "${CYAN}====================================================${RESET}"
echo -e "${CYAN}       NEXTCLOUD PRO v8.2 PRO VIP GitHub V1.4.6   ${RESET}"
echo -e "${CYAN}====================================================${RESET}"
echo

echo -e "${YELLOW}1)${RESET}  ${CYAN}Instalar Nextcloud Full Verciones / Restaura Archidos de (nextcloud-data)"
echo -e "${YELLOW}2)${RESET}  ${WHITE}Instalar Dependencias ${CYAN}(Apache/MySQL/PHP/wget/Cron)${RESET}"
echo -e "${YELLOW}3)${RESET}  ${WHITE}Actualizar Nextcloud ${CYAN}(updater.phar)${RESET}"
echo -e "${YELLOW}4)${RESET}  ${YELLOW}Menu Gestion Nextcloud ${CYAN}(Respaldo/Servicios/Update/DNS/)${RESET}"
echo -e "${YELLOW}5)${RESET}  ${WHITE}Crear Base de Datos Atomatica${YELLOW}(/root/nextcloud_db.conf)${RESET}"
echo -e "${YELLOW}6)${RESET}  ${CYAN}Desinstalar${RESET} ${WHITE}Nextcloud Completamente${RESET}"
echo -e "${YELLOW}7)${RESET}  ${CYAN}Estado Servicios Nextcloud${RESET}"
echo -e "${YELLOW}8)${RESET}  ${GREEN}Descargar Scripts desde GITHUB${RESET}"
echo
echo -e "${CYAN}0)${RESET}  ${CYAN}SALIR${RESET}"
echo

echo

read -p "Opción: " op

case $op in

1) install_nextcloud ;;
2) install_dependencies ;;
3) update_nextcloud ;;
4) menu_nextcloud_occ_pro ;;
5) menu_mysql_backup ;;
6) uninstall_nextcloud ;;
7) status_services ;;
8) download_script ;;
0) exit ;;

*)
echo "Inválido"
sleep 1
;;

esac

done