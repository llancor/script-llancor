#!/bin/bash
# ============================================
# Instalador y gestor interactivo de OpenEMR 7.0.3
# Compatible con Debian 12 / TurnKey Linux
# Autor: Cesar
# ============================================

set -e

# ===== Colores =====
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
RESET='\033[0m'

# ===== Variables =====
APP="openemr"
WWW_DIR="/var/www"
APACHE_SITES="/etc/apache2/sites-available"
USER_WEB="www-data"
OPENEMR_VERSION="7.0.3"

# ===== Verificar / Instalar dependencias =====
# ===== Instalar dependencias =====
# ===== Instalar dependencias =====
install_dependencies() {

    clear

    echo -e "${CYAN}===========================================${RESET}"
    echo -e "${CYAN}     INSTALADOR DE DEPENDENCIAS OPENEMR    ${RESET}"
    echo -e "${CYAN}===========================================${RESET}"

    echo
    echo -e "${YELLOW}Verificando dependencias del sistema...${RESET}"
    echo

    DEPENDENCIAS=(

        apache2
        mariadb-server
        mariadb-client

        php
        php-cli
        php-common
        php-mysql
        php-curl
        php-gd
        php-mbstring
        php-xml
        php-zip
        php-soap
        php-intl
        php-bcmath
        php-imap
        php-apcu

        libapache2-mod-php

        unzip
        curl
        wget
        git
        sudo
        nano

        composer
        npm
        nodejs

        certbot
        python3-certbot-apache

    )

    INSTALADOS=()
    YA_INSTALADOS=()
    FALLIDOS=()

    echo -e "${YELLOW}Actualizando repositorios...${RESET}"

    apt update

    echo

    # ===== VERIFICAR / INSTALAR =====

    for pkg in "${DEPENDENCIAS[@]}"; do

        if dpkg -s "$pkg" &>/dev/null; then

            echo -e "${GREEN}✔ YA INSTALADO:${RESET} $pkg"

            YA_INSTALADOS+=("$pkg")

        else

            echo -e "${YELLOW}➜ INSTALANDO:${RESET} $pkg"

            if apt install -y "$pkg"; then

                echo -e "${GREEN}✔ INSTALADO:${RESET} $pkg"

                INSTALADOS+=("$pkg")

            else

                echo -e "${RED}✘ ERROR:${RESET} $pkg"

                FALLIDOS+=("$pkg")

            fi
        fi
    done

    echo
    echo -e "${YELLOW}Configurando servicios...${RESET}"

    systemctl enable apache2 >/dev/null 2>&1
    systemctl restart apache2

    systemctl enable mariadb >/dev/null 2>&1
    systemctl restart mariadb

    echo
    echo -e "${YELLOW}Activando módulos Apache...${RESET}"

    a2enmod rewrite ssl headers expires >/dev/null 2>&1

    systemctl reload apache2

    echo
    echo -e "${YELLOW}Validando Apache...${RESET}"

    apachectl configtest

    # ===== RESUMEN =====

    echo
    echo -e "${CYAN}===========================================${RESET}"
    echo -e "${CYAN}      RESUMEN DEPENDENCIAS OPENEMR         ${RESET}"
    echo -e "${CYAN}===========================================${RESET}"

    echo
    echo -e "${GREEN}Paquetes instalados:${RESET}"

    if [ ${#INSTALADOS[@]} -eq 0 ]; then

        echo "Ninguno"

    else

        for i in "${INSTALADOS[@]}"; do
            echo "✔ $i"
        done

    fi

    echo
    echo -e "${BLUE}Paquetes ya instalados:${RESET}"

    if [ ${#YA_INSTALADOS[@]} -eq 0 ]; then

        echo "Ninguno"

    else

        for i in "${YA_INSTALADOS[@]}"; do
            echo "✔ $i"
        done

    fi

    echo
    echo -e "${RED}Paquetes con error:${RESET}"

    if [ ${#FALLIDOS[@]} -eq 0 ]; then

        echo "Ninguno"

    else

        for i in "${FALLIDOS[@]}"; do
            echo "✘ $i"
        done

    fi

    # ===== INFORMACION SISTEMA =====

    echo
    echo -e "${YELLOW}Servicios:${RESET}"

    echo "Apache:  $(systemctl is-active apache2)"
    echo "MariaDB: $(systemctl is-active mariadb)"

    echo
    echo -e "${YELLOW}PHP:${RESET}"

    php -v | head -n 1

    # ===== GUARDAR REPORTE =====

    REPORT_FILE="/root/openemr_dependencias.txt"

    {

        echo "===== INFORME DEPENDENCIAS OPENEMR ====="
        echo
        echo "Fecha: $(date)"
        echo

        echo "===== INSTALADOS ====="
        printf '%s\n' "${INSTALADOS[@]}"

        echo
        echo "===== YA INSTALADOS ====="
        printf '%s\n' "${YA_INSTALADOS[@]}"

        echo
        echo "===== FALLIDOS ====="
        printf '%s\n' "${FALLIDOS[@]}"

        echo
        echo "Apache: $(systemctl is-active apache2)"
        echo "MariaDB: $(systemctl is-active mariadb)"

        echo
        php -v | head -n 1

    } > "$REPORT_FILE"

    echo
    echo -e "${GREEN}Reporte guardado:${RESET} $REPORT_FILE"

    echo
    echo -e "${YELLOW}Mostrando resultados por 2 segundos...${RESET}"

    sleep 2

}

# ===== Crear base de datos =====
create_db() {

    echo -e "${YELLOW}Configuración de base de datos${RESET}"

    read -rp "Nombre DB [openemr]: " DBNAME
    DBNAME=${DBNAME:-openemr}

    read -rp "Usuario DB [openemr]: " DBUSER
    DBUSER=${DBUSER:-openemr}

    echo
    echo "1) Ingresar contraseña manual"
    echo "2) Generar contraseña segura automáticamente"
    echo

    read -rp "Opción [1/2]: " PASSOPT

    case $PASSOPT in

        1)

            read -rsp "Contraseña personalizada: " DBPASS
            echo

            if [ -z "$DBPASS" ]; then
                echo -e "${RED}La contraseña no puede estar vacía${RESET}"
                return 1
            fi

        ;;

        2)

            DBPASS=$(openssl rand -base64 16)

            echo
            echo -e "${GREEN}Contraseña generada:${RESET}"
            echo "$DBPASS"

        ;;

        *)

            echo -e "${RED}Opción inválida${RESET}"
            return 1

        ;;

    esac

    mysql <<MYSQL_SCRIPT

DROP DATABASE IF EXISTS \`${DBNAME}\`;

CREATE DATABASE \`${DBNAME}\`
CHARACTER SET utf8mb4
COLLATE utf8mb4_general_ci;

DROP USER IF EXISTS '${DBUSER}'@'localhost';

CREATE USER '${DBUSER}'@'localhost'
IDENTIFIED BY '${DBPASS}';

GRANT ALL PRIVILEGES ON \`${DBNAME}\`.* TO '${DBUSER}'@'localhost';

FLUSH PRIVILEGES;

MYSQL_SCRIPT

    OPENEMR_DBNAME=$DBNAME
    OPENEMR_DBUSER=$DBUSER
    OPENEMR_DBPASS=$DBPASS

    echo
    echo -e "${GREEN}Base de datos creada correctamente${RESET}"
}

# ===== Crear VirtualHost =====
# ===== Crear VirtualHost =====
create_vhost() {

    echo
    echo -e "${YELLOW}Configuración VirtualHost${RESET}"

    read -rp "Dominio [openemr.local]: " dominio
    dominio=${dominio:-openemr.local}

    read -rp "Ruta instalación [/var/www/openemr]: " docroot
    docroot=${docroot:-/var/www/openemr}

    mkdir -p "$docroot"

    chown -R www-data:www-data "$docroot"

    OPENEMR_DOMAIN=$dominio
    OPENEMR_PATH=$docroot

    HTTP_CONF="${APACHE_SITES}/${dominio}.conf"

    # ===== VHOST HTTP =====

    cat > "$HTTP_CONF" <<EOF
<VirtualHost *:80>

    ServerName $dominio

    DocumentRoot $docroot

    <Directory $docroot>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${dominio}_error.log
    CustomLog \${APACHE_LOG_DIR}/${dominio}_access.log combined

</VirtualHost>
EOF

    a2ensite "$(basename "$HTTP_CONF")" >/dev/null 2>&1

    # ===== MODULOS APACHE =====

    a2enmod rewrite ssl headers expires >/dev/null 2>&1

    # ===== MENU SSL =====

    echo
    echo -e "${YELLOW}Configuración SSL${RESET}"
    echo

    echo "1) SSL TurnKey (cert.pem)"
    echo "2) SSL Debian SnakeOil"
    echo "3) Let's Encrypt"
    echo "4) Sin SSL"
    echo

    read -rp "Selecciona opción [1-4]: " SSL_OPTION

    SSL_MODE="Sin SSL"

    case $SSL_OPTION in

        # ===== TURNKEY SSL =====

        1)

            if [ -f "/etc/ssl/private/cert.pem" ] && \
               [ -f "/etc/ssl/private/cert.key" ]; then

                SSL_CERT="/etc/ssl/private/cert.pem"
                SSL_KEY="/etc/ssl/private/cert.key"

                SSL_MODE="TurnKey SSL"

            else

                echo -e "${RED}No existe cert.pem${RESET}"
                return 1

            fi

        ;;

        # ===== SNAKEOIL =====

        2)

            if [ -f "/etc/ssl/certs/ssl-cert-snakeoil.pem" ] && \
               [ -f "/etc/ssl/private/ssl-cert-snakeoil.key" ]; then

                SSL_CERT="/etc/ssl/certs/ssl-cert-snakeoil.pem"
                SSL_KEY="/etc/ssl/private/ssl-cert-snakeoil.key"

                SSL_MODE="SnakeOil SSL"

            else

                echo -e "${RED}No existe SSL SnakeOil${RESET}"
                return 1

            fi

        ;;

        # ===== LETS ENCRYPT =====

        3)

            echo
            echo -e "${YELLOW}Instalando Certbot...${RESET}"

            apt install -y certbot python3-certbot-apache

            systemctl reload apache2

            echo
            echo -e "${YELLOW}Generando certificado Let's Encrypt...${RESET}"

            certbot --apache -d "$dominio"

            SSL_MODE="Let's Encrypt"

        ;;

        # ===== SIN SSL =====

        4)

            SSL_MODE="Sin SSL"

        ;;

        *)

            echo -e "${RED}Opción inválida${RESET}"
            return 1

        ;;

    esac

    # ===== CREAR SSL VHOST =====

    if [[ "$SSL_MODE" != "Sin SSL" && \
          "$SSL_MODE" != "Let's Encrypt" ]]; then

        SSL_CONF="${APACHE_SITES}/${dominio}-ssl.conf"

        cat > "$SSL_CONF" <<EOF
<VirtualHost *:443>

    ServerName $dominio

    DocumentRoot $docroot

    <Directory $docroot>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${dominio}_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/${dominio}_ssl_access.log combined

    SSLEngine on

    SSLCertificateFile $SSL_CERT
    SSLCertificateKeyFile $SSL_KEY

</VirtualHost>
EOF

        a2ensite "$(basename "$SSL_CONF")" >/dev/null 2>&1

        # ===== REDIRECCION HTTPS =====

        sed -i '/CustomLog/a \
    RewriteEngine On\n\
    RewriteCond %{HTTPS} off\n\
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]' "$HTTP_CONF"

    fi

    # ===== VALIDAR APACHE =====

    echo
    echo -e "${YELLOW}Verificando configuración Apache...${RESET}"

    if apachectl configtest; then

        systemctl reload apache2

        echo
        echo -e "${GREEN}VirtualHost configurado correctamente${RESET}"

        echo
        echo "Dominio: $dominio"
        echo "Ruta: $docroot"
        echo "SSL: $SSL_MODE"

    else

        echo
        echo -e "${RED}Error en configuración Apache${RESET}"

        return 1

    fi
}

# ===== Instalar OpenEMR =====
# ===== Instalar OpenEMR =====
install_openemr() {

    clear

    echo -e "${CYAN}===========================================${RESET}"
    echo -e "${CYAN}         INSTALADOR OPENEMR ${OPENEMR_VERSION}        ${RESET}"
    echo -e "${CYAN}===========================================${RESET}"

    echo
    echo -e "${YELLOW}Verificando dependencias...${RESET}"

    REQUIRED_CMDS=(

        apache2
        mysql
        php
        composer
        npm
        git

    )

    FALTANTES=()

    for cmd in "${REQUIRED_CMDS[@]}"; do

        if ! command -v "$cmd" &>/dev/null; then

            FALTANTES+=("$cmd")

        fi

    done

    # ===== SI FALTAN DEPENDENCIAS =====

    if [ ${#FALTANTES[@]} -gt 0 ]; then

        echo
        echo -e "${RED}Faltan dependencias:${RESET}"

        for f in "${FALTANTES[@]}"; do
            echo " - $f"
        done

        echo
        read -rp "¿Deseas instalar dependencias ahora? [s/n]: " resp

        if [[ "$resp" =~ ^[Ss]$ ]]; then

            install_dependencies

        else

            echo
            echo -e "${RED}No es posible continuar.${RESET}"

            return

        fi
    fi

    echo
    echo -e "${GREEN}Dependencias verificadas correctamente.${RESET}"

    # ===== BASE DE DATOS =====

    create_db

    # ===== VHOST =====

    create_vhost

    # ===== DESCARGAR OPENEMR =====

    echo
    echo -e "${YELLOW}Descargando OpenEMR ${OPENEMR_VERSION}...${RESET}"

    cd /tmp || return

    rm -rf openemr

    git clone --depth 1 \
    --branch rel-703 \
    https://github.com/openemr/openemr.git

    cd openemr || return

    # ===== COMPOSER =====

    echo
    echo -e "${YELLOW}Instalando dependencias Composer...${RESET}"

    composer install --no-dev

    # ===== NPM =====

    echo
    echo -e "${YELLOW}Instalando paquetes NPM...${RESET}"

    npm install --unsafe-perm

    # ===== BUILD =====

    echo
    echo -e "${YELLOW}Compilando frontend...${RESET}"

    npm run build

    # ===== COPIAR ARCHIVOS =====

    echo
    echo -e "${YELLOW}Copiando archivos...${RESET}"

    rm -rf "$OPENEMR_PATH"

    cp -a . "$OPENEMR_PATH"

    # ===== PERMISOS =====

    echo
    echo -e "${YELLOW}Configurando permisos...${RESET}"

    chown -R www-data:www-data "$OPENEMR_PATH"

    find "$OPENEMR_PATH" -type d -exec chmod 755 {} \;

    find "$OPENEMR_PATH" -type f -exec chmod 644 {} \;

    mkdir -p "$OPENEMR_PATH/sites/default/documents"

    chmod -R 775 "$OPENEMR_PATH/sites/default/documents"

    chown -R www-data:www-data \
    "$OPENEMR_PATH/sites/default/documents"

    touch "$OPENEMR_PATH/sites/default/sqlconf.php"

    chmod 640 \
    "$OPENEMR_PATH/sites/default/sqlconf.php"

    chown www-data:www-data \
    "$OPENEMR_PATH/sites/default/sqlconf.php"

    # ===== APACHE =====

    echo
    echo -e "${YELLOW}Reiniciando Apache...${RESET}"

    systemctl restart apache2

    # ===== INFORMACION =====

    IP_ADDR=$(hostname -I | awk '{print $1}')

    REPORT="/root/openemr_install.txt"

    # ===== REPORTE =====

    {

        echo "===== INSTALACION OPENEMR ====="
        echo

        echo "Fecha: $(date)"
        echo

        echo "Version: $OPENEMR_VERSION"

        echo
        echo "===== INSTANCIA ====="

        echo "Dominio: $OPENEMR_DOMAIN"
        echo "Ruta: $OPENEMR_PATH"

        echo
        echo "===== BASE DE DATOS ====="

        echo "DB: $OPENEMR_DBNAME"
        echo "Usuario: $OPENEMR_DBUSER"
        echo "Password: $OPENEMR_DBPASS"

        echo
        echo "===== SSL ====="

        echo "$SSL_MODE"

        echo
        echo "===== SERVICIOS ====="

        echo "Apache: $(systemctl is-active apache2)"
        echo "MariaDB: $(systemctl is-active mariadb)"

        echo
        echo "===== ACCESO ====="

        echo "https://$OPENEMR_DOMAIN"

        echo
        echo "IP servidor: $IP_ADDR"

    } > "$REPORT"

    # ===== RESUMEN FINAL =====

    clear

    echo -e "${GREEN}===========================================${RESET}"
    echo -e "${GREEN}      OPENEMR INSTALADO CORRECTAMENTE      ${RESET}"
    echo -e "${GREEN}===========================================${RESET}"

    echo
    echo -e "${YELLOW}INSTANCIA:${RESET}"

    echo "Dominio:      $OPENEMR_DOMAIN"
    echo "Ruta:         $OPENEMR_PATH"
    echo "Versión:      $OPENEMR_VERSION"

    echo
    echo -e "${YELLOW}BASE DE DATOS:${RESET}"

    echo "DB:            $OPENEMR_DBNAME"
    echo "Usuario DB:    $OPENEMR_DBUSER"
    echo "Contraseña DB: $OPENEMR_DBPASS"

    echo
    echo -e "${YELLOW}SSL:${RESET}"

    echo "$SSL_MODE"

    echo
    echo -e "${YELLOW}SERVICIOS:${RESET}"

    echo "Apache:  $(systemctl is-active apache2)"
    echo "MariaDB: $(systemctl is-active mariadb)"

    echo
    echo -e "${YELLOW}ACCESO:${RESET}"

    echo "https://$OPENEMR_DOMAIN"

    echo
    echo -e "${YELLOW}SERVIDOR:${RESET}"

    echo "IP: $IP_ADDR"

    echo
    echo -e "${YELLOW}REPORTE:${RESET}"

    echo "$REPORT"

    echo
    read -rp "Presiona ENTER para continuar..."

}

# ===== Desinstalar OpenEMR =====
uninstall_openemr() {

    echo -e "${YELLOW}Buscando VirtualHosts de OpenEMR...${RESET}"

    # ===== DETECCIÓN INTELIGENTE =====
    VHOSTS=$(grep -l -i "DocumentRoot.*openemr" $APACHE_SITES/*.conf 2>/dev/null)

    # ===== SI NO ENCUENTRA, CONTINÚA =====
    if [ -z "$VHOSTS" ]; then
        echo -e "${RED}No se detectaron VirtualHosts de OpenEMR.${RESET}"
        echo -e "${BLUE}Continuando en modo manual...${RESET}"

        # ===== MODO MANUAL =====
        read -rp "Dominio (opcional): " dominio
        read -rp "Ruta a eliminar: " docroot

        if [[ -z "$docroot" || "$docroot" == "/" ]]; then
            echo -e "${RED}Ruta inválida. Cancelado.${RESET}"
            return
        fi

        read -rp "Base de datos [openemr]: " DBNAME
        DBNAME=${DBNAME:-openemr}

        read -rp "Usuario DB [openemr]: " DBUSER
        DBUSER=${DBUSER:-openemr}

        read -rp "Escribe 'ELIMINAR' para confirmar: " confirm
        [[ "$confirm" != "ELIMINAR" ]] && echo "Cancelado" && return

        # ===== BORRADO =====
        [ -d "$docroot" ] && rm -rf "$docroot"

        if [ -n "$dominio" ]; then
            a2dissite "$dominio.conf" "$dominio-ssl.conf" >/dev/null 2>&1 || true
            rm -f "$APACHE_SITES/$dominio.conf" "$APACHE_SITES/$dominio-ssl.conf"
            systemctl reload apache2
        fi

        mysql -u root -p <<MYSQL_SCRIPT
DROP DATABASE IF EXISTS $DBNAME;
DROP USER IF EXISTS '$DBUSER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

        echo -e "${GREEN}✔ Eliminación manual completada${RESET}"
        return
    fi

    # ===== MODO NORMAL (SI ENCUENTRA VHOST) =====
    echo -e "${YELLOW}Selecciona el VirtualHost:${RESET}"

    select vh in $VHOSTS; do
        if [ -n "$vh" ]; then

            dominio=$(basename "$vh" .conf)
            docroot_detectado=$(grep -m1 "DocumentRoot" "$vh" | awk '{print $2}')

            echo -e "${BLUE}Ruta detectada:${RESET} $docroot_detectado"
            read -rp "Ruta a eliminar [Enter=usar detectada]: " docroot
            docroot=${docroot:-$docroot_detectado}

            if [[ -z "$docroot" || "$docroot" == "/" ]]; then
                echo -e "${RED}Ruta inválida.${RESET}"
                return
            fi

            read -rp "Base de datos [openemr]: " DBNAME
            DBNAME=${DBNAME:-openemr}

            read -rp "Usuario DB [openemr]: " DBUSER
            DBUSER=${DBUSER:-openemr}

            read -rp "Escribe 'ELIMINAR' para confirmar: " confirm
            [[ "$confirm" != "ELIMINAR" ]] && echo "Cancelado" && return

            [ -d "$docroot" ] && rm -rf "$docroot"

            a2dissite "$dominio.conf" "$dominio-ssl.conf" >/dev/null 2>&1 || true
            rm -f "$APACHE_SITES/$dominio.conf" "$APACHE_SITES/$dominio-ssl.conf"
            systemctl reload apache2

            mysql -u root -p <<MYSQL_SCRIPT
DROP DATABASE IF EXISTS $DBNAME;
DROP USER IF EXISTS '$DBUSER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

            echo -e "${GREEN}✔ OpenEMR eliminado correctamente${RESET}"
            break
        else
            echo -e "${RED}Selección inválida.${RESET}"
        fi
    done
}
# ===== Status OpenEMR =====
status_openemr() {

clear

IP=$(hostname -I | awk '{print $1}')

PHPV=$(php -v 2>/dev/null | head -n 1)

APACHE=$(systemctl is-active apache2)
MARIADB=$(systemctl is-active mariadb)


echo -e "${CYAN}===========================================${RESET}"
echo -e "${CYAN}        ESTADO DEL SISTEMA OPENEMR         ${RESET}"
echo -e "${CYAN}===========================================${RESET}"

echo

echo -e "Apache:  ${GREEN}$APACHE${RESET}"
echo -e "MariaDB: ${GREEN}$MARIADB${RESET}"
echo -e "PHP: $PHPV"
echo -e "IP: $IP"

echo

echo -e "${YELLOW}VirtualHosts activos:${RESET}"

grep -R "DocumentRoot" /etc/apache2/sites-enabled/*.conf 2>/dev/null

echo
}
# ===== Ver ajustes instalación =====
view_install_report() {

    clear

    REPORT="/root/openemr_install.txt"

    echo -e "${CYAN}===========================================${RESET}"
    echo -e "${CYAN}       AJUSTES INSTALACION OPENEMR         ${RESET}"
    echo -e "${CYAN}===========================================${RESET}"

    echo

    if [ -f "$REPORT" ]; then

        cat "$REPORT"

    else

        echo -e "${RED}No existe reporte de instalación.${RESET}"

    fi

    echo
    read -rp "Presiona ENTER para continuar..."

}
# ===== Menú principal =====
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

while true; do
    clear
clear
echo -e "${WHITE}===============================================${RESET}"
echo -e "${CYAN}   Instalador y Gestor de OpenEMR v10.3${RESET}"
echo -e "${WHITE}===============================================${RESET}"

echo -e "${YELLOW}1)${RESET} ${WHITE}Instalar dependencias${RESET}"
echo -e "${YELLOW}2)${RESET} ${WHITE}Instalar OpenEMR${RESET}"
echo -e "${YELLOW}3)${RESET} ${WHITE}Desinstalar OpenEMR${RESET}"
echo -e "${YELLOW}4)${RESET} ${WHITE}Estado del sistema${RESET}"
echo -e "${YELLOW}5)${RESET} ${WHITE}Crear Host SSL / SnakeOil / cert.pem / Let's Encrypt${RESET}"
echo -e "${YELLOW}6)${RESET} ${WHITE}Ver ajustes de instalación / Base de Datos${RESET}"
echo -e "${YELLOW}0)${RESET} ${CYAN}Salir${RESET}"

echo -e "${WHITE}===============================================${RESET}"

read -rp "Opción: " opt

    case $opt in
    1) install_dependencies; read -rp "Presiona ENTER para volver al menú..." ;;
    2) install_openemr; read -rp "Presiona ENTER para volver al menú..." ;;
    3) uninstall_openemr; read -rp "Presiona ENTER para volver al menú..." ;;
	4) status_openemr; read -rp "Presiona ENTER para volver al menú..." ;;
	5) create_vhost; read -rp "Presiona ENTER para volver al menú..." ;;
	6) view_install_report; read -rp "Presiona ENTER para volver al menú..." ;;
    0) echo "Saliendo..."; exit 0 ;;
    *) echo "Opción inválida"; read -rp "Presiona ENTER para volver al menú..." ;;
    esac
done
