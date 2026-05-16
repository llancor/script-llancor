#!/bin/bash
# =========================================================
# ODOO MASTER MANAGER MULTI-VERSION (16 / 17 / 18 / 19)
# Instalador + Desinstalador + Ajustes + Addons + VHost
# Debian / TurnKey / Nextcloud 
# =========================================================

set -e

# ===== COLORES =====
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

# ===== VARIABLES =====
APACHE_SITES="/etc/apache2/sites-available"

VERSION=""
CONFIG=""
SERVICE=""
ODOO_DIR=""
ODOO_USER=""
BACKUP_DIR=""
ADDONS_DIR=""
PORT=""
CERT=""
KEY=""

# =========================================================
# BASE
# =========================================================

pause() {
    read -p "ENTER para continuar..."
}

select_odoo_version() {
    while true; do
        clear
        echo -e "${CYAN}=========== SELECCIONAR VERSION ODOO ===========${RESET}"
        echo "1) Odoo 16"
        echo "2) Odoo 17"
        echo "3) Odoo 18"
        echo "4) Odoo 19"
        read -p "Opción: " ver

        case $ver in
            1) VERSION="16"; PORT="8069"; break ;;
            2) VERSION="17"; PORT="8070"; break ;;
            3) VERSION="18"; PORT="8071"; break ;;
            4) VERSION="19"; PORT="8072"; break ;;
            *) echo -e "${RED}Versión inválida${RESET}"; pause ;;
        esac
    done

    CONFIG="/etc/odoo${VERSION}.conf"
    SERVICE="odoo${VERSION}"
    ODOO_DIR="/opt/odoo${VERSION}"
    ODOO_USER="odoo${VERSION}"
    BACKUP_DIR="${ODOO_DIR}/backups"
    ADDONS_DIR="${ODOO_DIR}/custom-addons"

    mkdir -p "$BACKUP_DIR" "$ADDONS_DIR"
}

check_config() {
    if [ ! -f "$CONFIG" ]; then
        echo -e "${RED}No existe $CONFIG${RESET}"
        echo -e "${YELLOW}Primero debes instalar Odoo $VERSION${RESET}"
        return 1
    fi
    return 0
}

backup_config() {
    if ! check_config; then
        pause
        return
    fi

    mkdir -p "$BACKUP_DIR"

    cp "$CONFIG" "$BACKUP_DIR/odoo${VERSION}.conf.$(date +%F-%H%M%S)" \
        && echo -e "${GREEN}Backup creado${RESET}" \
        || echo -e "${RED}Error al crear backup${RESET}"
}

restart_services() {
    echo -e "${BLUE}Reiniciando PostgreSQL...${RESET}"
    systemctl restart postgresql

    echo -e "${BLUE}Reiniciando $SERVICE...${RESET}"
    systemctl restart "$SERVICE"

    echo -e "${GREEN}Servicios reiniciados correctamente${RESET}"
}

ask_restart() {
    while true; do
        read -p "¿Reiniciar Odoo ahora? (s/n): " r
        case $r in
            [sS])
                restart_services
                break
                ;;
            [nN])
                echo -e "${YELLOW}No se reinició. Continuando...${RESET}"
                break
                ;;
            *)
                echo -e "${RED}Respuesta inválida${RESET}"
                ;;
        esac
    done
}

# =========================================================
# SSL
# =========================================================

get_ssl_cert() {
    if [ -f /etc/ssl/certs/cert.pem ] && [ -f /etc/ssl/private/cert.key ]; then
        CERT="/etc/ssl/certs/cert.pem"
        KEY="/etc/ssl/private/cert.key"
    else
        CERT="/etc/ssl/certs/ssl-cert-snakeoil.pem"
        KEY="/etc/ssl/private/ssl-cert-snakeoil.key"
    fi
}
# =========================================================
# INSTALAR DEPENDENCIAS PARA ODOO
# =========================================================
install_dependencies() {
    echo -e "${BLUE}Verificando dependencias...${RESET}"

    DEPS=(
        sudo git python3-pip build-essential python3-dev python3-venv
        libxslt1-dev libzip-dev libldap2-dev libsasl2-dev libjpeg-dev libpq-dev
        libssl-dev wkhtmltopdf postgresql apache2 unzip
    )

    TO_INSTALL=()
    INSTALLED=()

    for pkg in "${DEPS[@]}"; do
        if dpkg -s "$pkg" &>/dev/null; then
            INSTALLED+=("$pkg")
        else
            TO_INSTALL+=("$pkg")
        fi
    done

    echo ""
    echo -e "${CYAN}Ya instalados:${RESET}"
    for p in "${INSTALLED[@]}"; do
        echo -e "  ${GREEN}✔ $p${RESET}"
    done

    echo ""
    if [ ${#TO_INSTALL[@]} -eq 0 ]; then
        echo -e "${GREEN}Todas las dependencias ya están instaladas${RESET}"
        return
    fi

    echo -e "${YELLOW}Faltan por instalar:${RESET}"
    for p in "${TO_INSTALL[@]}"; do
        echo -e "  ${RED}✘ $p${RESET}"
    done

    echo ""
    read -p "¿Instalar dependencias faltantes? (s/n): " r
    [[ ! $r =~ [sS] ]] && return

    echo -e "${BLUE}Instalando...${RESET}"
    apt update -y
    apt install -y "${TO_INSTALL[@]}"

    echo ""
    echo -e "${GREEN}===== RESULTADO FINAL =====${RESET}"

    for pkg in "${TO_INSTALL[@]}"; do
        if dpkg -s "$pkg" &>/dev/null; then
            echo -e "${GREEN}✔ Instalado: $pkg${RESET}"
        else
            echo -e "${RED}✘ Falló: $pkg${RESET}"
        fi
    done
}
# =========================================================
# INSTALAR ODOO
# =========================================================
# =========================================================
# CORRECCION INSTALL_ODOO()
# SOLO SE MODIFICARON:
# - setuptools compatible
# - http_port
# - proxy_mode
# - logfile
# =========================================================

install_odoo() {

    select_odoo_version

    echo -e "${GREEN}>>> Instalando Odoo $VERSION...${RESET}"

    install_dependencies

    # =========================================================
    # CREAR USUARIO
    # =========================================================

    if ! id -u "$ODOO_USER" &>/dev/null; then
        useradd -m -d "$ODOO_DIR" -U -r -s /bin/bash "$ODOO_USER"
    fi

    mkdir -p "$ODOO_DIR"
    chown -R "$ODOO_USER":"$ODOO_USER" "$ODOO_DIR"

    # =========================================================
    # CREAR VENV
    # =========================================================

    if [ ! -d "$ODOO_DIR/venv" ]; then
        sudo -u "$ODOO_USER" python3 -m venv "$ODOO_DIR/venv"
    fi

    # =========================================================
    # PYTHON / PIP / SETUPTOOLS
    # =========================================================

    echo -e "${BLUE}Configurando entorno Python...${RESET}"

    # pip + wheel
    sudo -u "$ODOO_USER" "$ODOO_DIR/venv/bin/pip" install --upgrade pip wheel

    # =========================================================
    # SETUPTOOLS COMPATIBLE
    # =========================================================

    case $VERSION in

        16)

            echo -e "${YELLOW}Usando setuptools compatible para Odoo 16...${RESET}"

            sudo -u "$ODOO_USER" "$ODOO_DIR/venv/bin/pip" uninstall -y setuptools || true

            sudo -u "$ODOO_USER" "$ODOO_DIR/venv/bin/pip" install \
                setuptools==68.2.2

        ;;

        17)

            echo -e "${YELLOW}Usando setuptools compatible para Odoo 17...${RESET}"

            sudo -u "$ODOO_USER" "$ODOO_DIR/venv/bin/pip" install \
                "setuptools<81"

        ;;

        18|19)

            echo -e "${YELLOW}Usando setuptools moderno...${RESET}"

            sudo -u "$ODOO_USER" "$ODOO_DIR/venv/bin/pip" install \
                --upgrade setuptools

        ;;

    esac

    # =========================================================
    # VERIFICAR pkg_resources
    # =========================================================

    echo -e "${BLUE}Verificando pkg_resources...${RESET}"

    if ! sudo -u "$ODOO_USER" "$ODOO_DIR/venv/bin/python" \
        -c "import pkg_resources" &>/dev/null; then

        echo -e "${RED}ERROR: pkg_resources no funciona${RESET}"

        if [ "$VERSION" = "16" ]; then

            echo -e "${YELLOW}Reinstalando setuptools compatible...${RESET}"

            sudo -u "$ODOO_USER" "$ODOO_DIR/venv/bin/pip" uninstall -y setuptools

            sudo -u "$ODOO_USER" "$ODOO_DIR/venv/bin/pip" install \
                setuptools==68.2.2
        fi
    fi

    cd "$ODOO_DIR"

    # =========================================================
    # CLONAR ODOO
    # =========================================================

    if [ ! -d "$ODOO_DIR/odoo$VERSION" ]; then

        echo -e "${BLUE}Verificando si existe la versión $VERSION en GitHub...${RESET}"

        if ! git ls-remote --heads https://github.com/odoo/odoo.git \
            | grep -q "refs/heads/$VERSION.0"; then

            echo -e "${RED}ERROR: La versión $VERSION.0 no existe${RESET}"
            return
        fi

        sudo -u "$ODOO_USER" -H git clone \
            https://github.com/odoo/odoo.git \
            --branch "$VERSION.0" \
            --single-branch \
            "odoo$VERSION"
    fi

    # =========================================================
    # REQUIREMENTS
    # =========================================================

    echo -e "${BLUE}Instalando requirements...${RESET}"

    sudo -u "$ODOO_USER" "$ODOO_DIR/venv/bin/pip" install \
        -r "$ODOO_DIR/odoo$VERSION/requirements.txt"

    # =========================================================
    # POSTGRESQL
    # =========================================================

    systemctl enable --now postgresql

    sudo -u postgres createuser -s "$ODOO_USER" || true

    # =========================================================
    # ADDONS
    # =========================================================

    mkdir -p "$ADDONS_DIR"

    chown -R "$ODOO_USER":"$ODOO_USER" "$ADDONS_DIR"

    chmod -R 755 "$ADDONS_DIR"

    # =========================================================
    # LOGS
    # =========================================================

    touch "/var/log/odoo${VERSION}.log"

    chown "$ODOO_USER":"$ODOO_USER" "/var/log/odoo${VERSION}.log"

    chmod 640 "/var/log/odoo${VERSION}.log"

    # =========================================================
    # CONFIG ODOO
    # =========================================================

cat > "$CONFIG" <<EOF
[options]

admin_passwd = admin

db_user = $ODOO_USER

addons_path = $ODOO_DIR/odoo$VERSION/addons,$ADDONS_DIR

proxy_mode = True

http_port = $PORT

logfile = /var/log/odoo${VERSION}.log

limit_time_cpu = 600
limit_time_real = 1200

workers = 2
gevent_port = 8072

list_db = True

EOF

    # =========================================================
    # SYSTEMD
    # =========================================================

cat > "/etc/systemd/system/$SERVICE.service" <<EOF
[Unit]
Description=Odoo $VERSION
After=network.target postgresql.service

[Service]

Type=simple

User=$ODOO_USER
Group=$ODOO_USER

SyslogIdentifier=$SERVICE

PermissionsStartOnly=true

ExecStart=$ODOO_DIR/venv/bin/python \
    $ODOO_DIR/odoo$VERSION/odoo-bin \
    -c $CONFIG

StandardOutput=journal+console

Restart=always
RestartSec=5

LimitNOFILE=65535

PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    # =========================================================
    # INICIAR SERVICIO
    # =========================================================

    systemctl daemon-reload

    systemctl enable --now "$SERVICE"

    sleep 5

    # =========================================================
    # VERIFICAR SERVICIO
    # =========================================================

    if systemctl is-active "$SERVICE" >/dev/null; then

        echo
        echo -e "${GREEN}=========================================${RESET}"
        echo -e "${GREEN} ODOO $VERSION INSTALADO CORRECTAMENTE ${RESET}"
        echo -e "${GREEN}=========================================${RESET}"
        echo

        IP=$(hostname -I | awk '{print $1}')

        echo -e "URL: ${CYAN}http://$IP:$PORT${RESET}"
        echo

    else

        echo
        echo -e "${RED}=========================================${RESET}"
        echo -e "${RED} ERROR AL INICIAR ODOO $VERSION ${RESET}"
        echo -e "${RED}=========================================${RESET}"
        echo

        journalctl -u "$SERVICE" -n 50 --no-pager
    fi

    # =========================================================
    # VHOST
    # =========================================================

    read -p "¿Crear VirtualHost ahora? (s/n): " vh

    [[ $vh =~ [sS] ]] && create_vhost
}

# =========================================================
# DESINSTALAR
# =========================================================

remove_odoo() {
    delete_vhost
    select_odoo_version

    echo -e "${RED}Esto eliminará Odoo $VERSION completamente${RESET}"
    read -p "¿Continuar? (s/n): " r
    [[ ! $r =~ [sS] ]] && return

    systemctl stop "$SERVICE" || true
    systemctl disable "$SERVICE" || true

    rm -f "/etc/systemd/system/$SERVICE.service"
    systemctl daemon-reload

    rm -rf "$ODOO_DIR"
    rm -f "$CONFIG"

    sudo -u postgres dropuser "$ODOO_USER" || true

    echo -e "${GREEN}Odoo $VERSION eliminado${RESET}"
}

# =========================================================
# CONFIGURACIONES
# =========================================================

edit_config() {
    if ! check_config; then
        pause
        return
    fi

    nano "$CONFIG"
    ask_restart
}

fix_db() {
    if ! check_config; then
        pause
        return
    fi

    backup_config
    sed -i "/^db_host/d" "$CONFIG"
    sed -i "/^db_port/d" "$CONFIG"
    sed -i "/^db_password/d" "$CONFIG"
    sed -i "/^db_name/d" "$CONFIG"

    echo -e "${GREEN}DB corregida${RESET}"
    ask_restart
}

master_pass() {
    if ! check_config; then
        pause
        return
    fi

    backup_config
    read -p "Nueva master password: " p
    sed -i "s|^admin_passwd.*|admin_passwd = $p|" "$CONFIG"

    echo -e "${GREEN}Password actualizada${RESET}"
    ask_restart
}

toggle_db() {
    if ! check_config; then
        pause
        return
    fi
    backup_config

    # Si existe y está en True -> cambiar a False
    if grep -qE "^[[:space:]]*list_db[[:space:]]*=[[:space:]]*True" "$CONFIG"; then
        sed -i -E "s|^[[:space:]]*list_db[[:space:]]*=.*|list_db = False|" "$CONFIG"
        echo -e "${YELLOW}Gestor de bases de datos WEB DESACTIVADO${RESET}"

    # Si existe y está en False -> cambiar a True
    elif grep -qE "^[[:space:]]*list_db[[:space:]]*=[[:space:]]*False" "$CONFIG"; then
        sed -i -E "s|^[[:space:]]*list_db[[:space:]]*=.*|list_db = True|" "$CONFIG"
        echo -e "${GREEN}Gestor de bases de datos WEB ACTIVADO${RESET}"

    # Si no existe la línea -> agregarla como True
    else
        echo "list_db = True" >> "$CONFIG"
        echo -e "${GREEN}list_db no existía. Se agregó y quedó ACTIVADO${RESET}"
    fi

    # Verificación final
    echo -e "${CYAN}Estado actual:${RESET} $(grep -E '^[[:space:]]*list_db' "$CONFIG" | tail -1)"

    ask_restart
}


# =========================================================
# ADDONS
# =========================================================

config_addons() {

    if ! check_config; then
        pause
        return
    fi

    DEFAULT="$ODOO_DIR/odoo$VERSION/addons"

    mkdir -p "$ADDONS_DIR"
    chown -R "$ODOO_USER":"$ODOO_USER" "$ADDONS_DIR"
    chmod -R 755 "$ADDONS_DIR"

    sed -i "s|^addons_path.*|addons_path = $DEFAULT,$ADDONS_DIR|" "$CONFIG"

    echo -e "${GREEN}addons_path corregido:${RESET}"
    echo "$DEFAULT,$ADDONS_DIR"

    ask_restart
}

fix_permissions_addons() {
    mkdir -p "$ADDONS_DIR"
    chown -R "$ODOO_USER":"$ODOO_USER" "$ADDONS_DIR"
    chmod -R 755 "$ADDONS_DIR"

    echo -e "${GREEN}Permisos corregidos${RESET}"
}

install_addon() {
    read -p "Ruta del addon (.zip o carpeta): " path

    if [ ! -e "$path" ]; then
        echo -e "${RED}Ruta inválida${RESET}"
        return
    fi

    if [[ "$path" == *.zip ]]; then
        unzip "$path" -d "$ADDONS_DIR"
    else
        cp -r "$path" "$ADDONS_DIR"
    fi

    chown -R "$ODOO_USER":"$ODOO_USER" "$ADDONS_DIR"

    echo -e "${GREEN}Addon instalado${RESET}"
    ask_restart
}

list_addons() {
    echo -e "${CYAN}Addons en $ADDONS_DIR:${RESET}"
    ls -lah "$ADDONS_DIR"
}

# =========================================================
# BASE DE DATOS
# =========================================================

backup_db() {
    read -p "Nombre de la DB: " db
    sudo -u postgres pg_dump "$db" > "$BACKUP_DIR/$db.sql"
    echo -e "${GREEN}Backup creado: $BACKUP_DIR/$db.sql${RESET}"
}

restore_db() {
    read -p "Archivo .sql: " file
    read -p "Nueva DB: " db

    sudo -u postgres createdb "$db"
    sudo -u postgres psql "$db" < "$file"

    echo -e "${GREEN}DB restaurada${RESET}"
}

list_db() {
    sudo -u postgres psql -l
}

# =========================================================
# LOGS / STATUS
# =========================================================

status_services() {

    IP=$(hostname -I | awk '{print $1}')

    echo -e "${BLUE}Estado servicios:${RESET}"
    echo

    # =========================================================
    # DETECTAR PUERTO REAL
    # =========================================================

    if [ -f "$CONFIG" ]; then

        REAL_PORT=$(grep -E "xmlrpc_port|http_port" "$CONFIG" \
            | awk '{print $3}' \
            | head -n1)

    else

        REAL_PORT="$PORT"

    fi

    # =========================================================
    # VALIDAR SERVICIO ODOO
    # =========================================================

    if [ -z "$SERVICE" ]; then

        echo -e "Odoo $VERSION: ${RED}SERVICIO NO DEFINIDO${RESET}"

    elif systemctl list-unit-files | grep -q "^${SERVICE}.service"; then

        if systemctl is-active --quiet "$SERVICE"; then

            echo -e "Odoo $VERSION: ${GREEN}ACTIVO${RESET}"

        else

            echo -e "Odoo $VERSION: ${RED}DETENIDO${RESET}"

        fi

        echo -e "Servicio : ${CYAN}$SERVICE${RESET}"

        if [ -n "$REAL_PORT" ]; then

            echo -e "Puerto   : ${GREEN}$REAL_PORT${RESET}"
            echo -e "URL      : ${CYAN}http://$IP:$REAL_PORT${RESET}"

        else

            echo -e "Puerto   : ${YELLOW}No detectado${RESET}"

        fi

    else

        echo -e "Odoo $VERSION: ${RED}NO INSTALADO${RESET}"

    fi

    echo

    # =========================================================
    # POSTGRESQL
    # =========================================================

    if systemctl is-active --quiet postgresql; then

        echo -e "PostgreSQL: ${GREEN}ACTIVO${RESET}"

    else

        echo -e "PostgreSQL: ${RED}DETENIDO${RESET}"

    fi

    echo
}

logs() {
    journalctl -u "$SERVICE" -n 50 --no-pager
}

show_url() {
    IP=$(hostname -I | awk '{print $1}')
    echo -e "${CYAN}http://$IP:$PORT${RESET}"
}

# =========================================================
# CREAR VHOST APACHE PARA ODOO
# =========================================================
# =========================================================
# DETECTAR INSTANCIAS ODOO INSTALADAS
# =========================================================

detect_odoo_instances() {

    ODOO_LIST=()

    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}      DETECTANDO INSTANCIAS ODOO         ${RESET}"
    echo -e "${CYAN}=========================================${RESET}"

    # Buscar configs Odoo
    for CONF in /etc/odoo*.conf; do

        [ ! -f "$CONF" ] && continue

        NAME=$(basename "$CONF")

        # Detectar versión
        VERSION=$(grep -i "server_wide_modules" "$CONF" | grep -oE '[0-9]+' | head -n1)

        # Si no encuentra versión, intentar desde path
        if [ -z "$VERSION" ]; then
            VERSION=$(echo "$NAME" | grep -oE '[0-9]+')
        fi

        [ -z "$VERSION" ] && VERSION="Desconocida"

        # Puerto principal
        PORT=$(grep -E "xmlrpc_port|http_port" "$CONF" | awk '{print $3}' | head -n1)

        # Puerto longpolling
        LONGPOLL=$(grep -E "longpolling_port|gevent_port" "$CONF" | awk '{print $3}' | head -n1)

        # Valores por defecto
        [ -z "$PORT" ] && PORT="8069"
        [ -z "$LONGPOLL" ] && LONGPOLL="8072"

        # Servicio
        SERVICE=$(systemctl list-units --type=service --all | grep -i "$NAME" | awk '{print $1}' | head -n1)

        [ -z "$SERVICE" ] && SERVICE="No detectado"

        STATUS=$(systemctl is-active "$SERVICE" 2>/dev/null)

        [ -z "$STATUS" ] && STATUS="unknown"

        # Guardar instancia
        ODOO_LIST+=("$VERSION|$PORT|$LONGPOLL|$CONF|$SERVICE|$STATUS")

    done

    # Mostrar resultados
    if [ ${#ODOO_LIST[@]} -eq 0 ]; then
        echo -e "${RED}No se detectaron instancias Odoo${RESET}"
        return 1
    fi

    echo
    echo -e "${GREEN}Instancias detectadas:${RESET}"
    echo

    INDEX=1

    for ITEM in "${ODOO_LIST[@]}"; do

        VERSION=$(echo "$ITEM" | cut -d'|' -f1)
        PORT=$(echo "$ITEM" | cut -d'|' -f2)
        LONGPOLL=$(echo "$ITEM" | cut -d'|' -f3)
        CONF=$(echo "$ITEM" | cut -d'|' -f4)
        SERVICE=$(echo "$ITEM" | cut -d'|' -f5)
        STATUS=$(echo "$ITEM" | cut -d'|' -f6)

        echo -e "${YELLOW}[$INDEX]${RESET} Odoo ${CYAN}$VERSION${RESET}"
        echo -e "     Puerto      : $PORT"
        echo -e "     Longpolling : $LONGPOLL"
        echo -e "     Config      : $CONF"
        echo -e "     Servicio    : $SERVICE"
        echo -e "     Estado      : $STATUS"
        echo

        INDEX=$((INDEX+1))

    done

    return 0
}

# =========================================================
# SELECCIONAR INSTANCIA ODOO
# =========================================================

select_odoo_instance() {

    detect_odoo_instances || return 1

    read -p "Seleccionar instancia: " OPTION

    INDEX=1

    for ITEM in "${ODOO_LIST[@]}"; do

        if [ "$INDEX" = "$OPTION" ]; then

            ODOO_VERSION=$(echo "$ITEM" | cut -d'|' -f1)
            PORT=$(echo "$ITEM" | cut -d'|' -f2)
            LONGPOLL=$(echo "$ITEM" | cut -d'|' -f3)
            ODOO_CONF=$(echo "$ITEM" | cut -d'|' -f4)
            ODOO_SERVICE=$(echo "$ITEM" | cut -d'|' -f5)

            return 0
        fi

        INDEX=$((INDEX+1))

    done

    echo -e "${RED}Opción inválida${RESET}"
    return 1
}

# =========================================================
# CREAR VHOST AUTOMÁTICO
# =========================================================

create_vhost() {

    select_odoo_instance || return

    echo
    echo -e "${GREEN}Instancia seleccionada:${RESET}"
    echo -e "Odoo Version : ${CYAN}$ODOO_VERSION${RESET}"
    echo -e "Puerto       : ${CYAN}$PORT${RESET}"
    echo -e "Longpolling  : ${CYAN}$LONGPOLL${RESET}"
    echo

    read -p "Dominio (ej: erp.midominio.com): " DOMINIO

    [ -z "$DOMINIO" ] && return

    get_ssl_cert

    FILE="$APACHE_SITES/$DOMINIO.conf"

cat > "$FILE" <<EOF
<VirtualHost *:80>

    ServerName $DOMINIO

    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)\$ https://%{HTTP_HOST}\$1 [R=301,L]

</VirtualHost>

<VirtualHost *:443>

    ServerName $DOMINIO

    SSLEngine on
    SSLCertificateFile $CERT
    SSLCertificateKeyFile $KEY

    ProxyPreserveHost On
    ProxyRequests Off

    AllowEncodedSlashes NoDecode

    ProxyPass / http://127.0.0.1:$PORT/
    ProxyPassReverse / http://127.0.0.1:$PORT/

    ProxyPass /longpolling http://127.0.0.1:$LONGPOLL/longpolling
    ProxyPassReverse /longpolling http://127.0.0.1:$LONGPOLL/longpolling

    RequestHeader set X-Forwarded-Proto "https"

    ErrorLog \${APACHE_LOG_DIR}/${DOMINIO}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMINIO}_access.log combined

</VirtualHost>
EOF

    # Activar módulos
    a2enmod proxy >/dev/null 2>&1
    a2enmod proxy_http >/dev/null 2>&1
    a2enmod headers >/dev/null 2>&1
    a2enmod rewrite >/dev/null 2>&1
    a2enmod ssl >/dev/null 2>&1

    # Activar sitio
    a2ensite "$DOMINIO.conf" >/dev/null 2>&1

    # Verificar apache
    apache2ctl configtest

    if [ $? -eq 0 ]; then

        systemctl reload apache2
        systemctl restart apache2

        echo
        echo -e "${GREEN}=========================================${RESET}"
        echo -e "${GREEN} VHOST CREADO CORRECTAMENTE ${RESET}"
        echo -e "${GREEN}=========================================${RESET}"
        echo
        echo -e "Dominio : ${CYAN}$DOMINIO${RESET}"
        echo -e "Odoo    : ${CYAN}$ODOO_VERSION${RESET}"
        echo -e "Puerto  : ${CYAN}$PORT${RESET}"
        echo

    else

        echo -e "${RED}Error en Apache${RESET}"

    fi

    pause
}

# =========================================================
# ELIMINAR VHOST
# =========================================================

delete_vhost() {

    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}        ELIMINAR VHOST                   ${RESET}"
    echo -e "${CYAN}=========================================${RESET}"

    ls $APACHE_SITES | grep ".conf"

    echo
    read -p "Nombre del dominio: " DOMINIO

    FILE="$APACHE_SITES/$DOMINIO.conf"

    if [ ! -f "$FILE" ]; then
        echo -e "${RED}No existe el VHost${RESET}"
        pause
        return
    fi

    a2dissite "$DOMINIO.conf"
    rm -f "$FILE"

    systemctl reload apache2

    echo -e "${GREEN}VHost eliminado correctamente${RESET}"

    pause
}

# =========================================================
# LISTAR VHOSTS
# =========================================================

list_vhosts() {

    echo -e "${CYAN}=========================================${RESET}"
    echo -e "${CYAN}         VHOSTS ACTIVOS                  ${RESET}"
    echo -e "${CYAN}=========================================${RESET}"

    apache2ctl -S

    pause
}

# =========================================================
# AJUSTES ODOO
# =========================================================

ajustes_odoo() {

    # 🔴 BLOQUEO GLOBAL (CLAVE)
    if [ ! -f "$CONFIG" ]; then
        echo -e "${RED}Odoo $VERSION no está instalado${RESET}"
        echo -e "${YELLOW}Primero debes instalar esta versión${RESET}"
        pause
        return
    fi

    while true; do
        clear
        echo -e "${BLUE}=========== AJUSTES ODOO $VERSION ===========${RESET}"
        echo ""
        status_services
        echo ""

        echo -e "${YELLOW}1)${RESET} Arreglar DB config"
        echo -e "${YELLOW}2)${RESET} Cambiar Master Password"
        echo -e "${YELLOW}3)${RESET} Mostrar/Ocultar DB web"
        echo -e "${YELLOW}4)${RESET} Reiniciar Servicios Odoo/PostgreSQL"
        echo -e "${YELLOW}5)${RESET} Instalar Addon/Temas Muk"
        echo -e "${YELLOW}6)${RESET} Listar addons"
        echo -e "${YELLOW}7)${RESET} Backup DB PostgreSQL"
        echo -e "${YELLOW}8)${RESET} Restaurar DB PostgreSQL"
        echo -e "${YELLOW}9)${RESET} Listar bases de Datos PostgreSQL"
        echo -e "${YELLOW}10)${RESET} Ver logs"
        echo -e "${YELLOW}11)${RESET} Mostrar URL Odoo/Port"
        echo -e "${YELLOW}12)${RESET} Editar odoo.conf"
        echo -e "${YELLOW}13)${RESET} Configurar addons_path"
        echo -e "${YELLOW}14)${RESET} Corregir permisos addons"
        echo -e "${YELLOW}15)${RESET} Crear VirtualHost"
		echo -e "${YELLOW}16)${RESET} Eliminar VirtualHost"
		echo -e "${YELLOW}17)${RESET} Listar VirtualHost"
        echo -e "${YELLOW}0)${RESET} Volver"

        echo ""
        read -p "Opción: " op

        case $op in
            1) fix_db ;;
            2) master_pass ;;
            3) toggle_db ;;
            4) restart_services ;;
            5) install_addon ;;
            6) list_addons ;;
            7) backup_db ;;
            8) restore_db ;;
            9) list_db ;;
            10) logs ;;
            11) show_url ;;
            12) edit_config ;;
            13) config_addons ;;
            14) fix_permissions_addons ;;
            15) create_vhost ;;
			16) delete_vhost ;;
			17) list_vhosts ;;
            0) break ;;
            *) echo -e "${RED}Opción inválida${RESET}" ;;
        esac

        pause
    done
}

# =========================================================
# INICIO
# =========================================================

select_odoo_version

# =========================================================
# MENU PRINCIPAL
# =========================================================

while true; do
    clear

    echo -e "${CYAN}=========== INSTALAR ODOO MASTER MANAGER v4.0 ===========${RESET}"
    echo -e "${WHITE}Versión activa: Odoo $VERSION | Puerto: $PORT${RESET}"
    echo ""

    status_services
    echo ""

    echo -e "${YELLOW}1)${RESET} Instalar Odoo Verciones"
    echo -e "${YELLOW}2)${RESET} Desinstalar Odoo Verciones"
    echo -e "${YELLOW}3)${RESET} Ajustes Odoo Verciones"
    echo -e "${YELLOW}4)${RESET} Cambiar Versión Odoo"
	echo -e "${YELLOW}5)${RESET} Instalar / Verificar dependencias"
    echo -e "${YELLOW}0)${RESET} Salir"

    echo ""
    read -p "Opción: " op

    case $op in
        1) install_odoo ;;
        2) remove_odoo ;;
        3) ajustes_odoo ;;
        4) select_odoo_version ;;
		5) install_dependencies ;;
        0) exit ;;
        *) echo -e "${RED}Opción inválida${RESET}" ;;
    esac

    pause
done