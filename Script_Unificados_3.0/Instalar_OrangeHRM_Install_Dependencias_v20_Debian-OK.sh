#!/bin/bash

# ===== Colores =====
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
RESET='\033[0m'

# ===== Variables =====
WWW_DIR="/var/www"
APACHE_SITES="/etc/apache2/sites-available"
USER_WEB="www-data"

# ===== Dependencias =====
install_dependencies() {

    clear

    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW}   VERIFICANDO DEPENDENCIAS ORANGEHRM   ${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo

    PACKAGES=(
        apache2
        mariadb-server
        mariadb-client
        php
        php-mysql
        php-cli
        php-curl
        php-gd
        php-xml
        php-mbstring
        php-zip
        unzip
        wget
        curl
        zip
    )

    INSTALLED=()
    MISSING=()

    # =====================================================
    # VERIFICAR PAQUETES
    # =====================================================

    for pkg in "${PACKAGES[@]}"; do

        if dpkg -s "$pkg" &>/dev/null; then

            echo -e "${GREEN}[INSTALADO]${RESET} $pkg"

            INSTALLED+=("$pkg")

        else

            echo -e "${RED}[FALTA]${RESET} $pkg"

            MISSING+=("$pkg")

        fi

    done

    echo
    echo -e "${YELLOW}========================================${RESET}"

    # =====================================================
    # TODO INSTALADO
    # =====================================================

    if [ ${#MISSING[@]} -eq 0 ]; then

        echo
        echo -e "${GREEN}✔ Todas las dependencias ya están instaladas.${RESET}"

    else

        echo
        echo -e "${YELLOW}Dependencias faltantes:${RESET}"

        for pkg in "${MISSING[@]}"; do
            echo -e " - ${CYAN}$pkg${RESET}"
        done

        echo

        read -rp "¿Deseas instalar las dependencias faltantes? (s/n): " confirm

        if [[ ! "$confirm" =~ ^[sS]$ ]]; then

            echo
            echo -e "${RED}Instalación cancelada.${RESET}"

            return 1

        fi

        echo
        echo -e "${YELLOW}Actualizando repositorios...${RESET}"

        apt-get update

        echo
        echo -e "${YELLOW}Instalando dependencias faltantes...${RESET}"

        apt-get install -y "${MISSING[@]}"

    fi

    # =====================================================
    # ACTIVAR MODULOS APACHE
    # =====================================================

    echo
    echo -e "${YELLOW}Configurando Apache...${RESET}"

    a2enmod rewrite ssl >/dev/null 2>&1

    systemctl enable apache2 >/dev/null 2>&1

    systemctl restart apache2

    echo
    echo -e "${GREEN}✔ Dependencias listas.${RESET}"

    echo
    read -rp "Presiona ENTER para continuar con la instalación de OrangeHRM..."

}

# ===== Crear DB =====
create_db() {
    echo -e "${YELLOW}Configuración de base de datos para esta instalación${RESET}"
    read -rp "Nombre de la base de datos [orangehrm]: " DBNAME
    DBNAME=${DBNAME:-orangehrm}
    read -rp "Usuario de la base de datos [orangehrm]: " DBUSER
    DBUSER=${DBUSER:-orangehrm}
    read -rp "Contraseña del usuario [orangehrm]: " DBPASS
    DBPASS=${DBPASS:-orangehrm}

    mysql -u root -p <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS $DBNAME CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$DBUSER'@'localhost' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON $DBNAME.* TO '$DBUSER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

    ORG_DBNAME=$DBNAME
    ORG_DBUSER=$DBUSER
    ORG_DBPASS=$DBPASS
}

# ===== Crear VirtualHost =====
create_vhost() {
    read -rp "Nombre del VirtualHost [orangehrm.conf]: " vhost
    vhost=${vhost:-orangehrm.conf}
    [[ "$vhost" != *.conf ]] && vhost="${vhost}.conf"

    read -rp "Dominio o ServerName [orangehrm.local]: " dominio
    dominio=${dominio:-orangehrm.local}

    read -rp "Ruta DocumentRoot [/var/www/orangehrm]: " docroot
    docroot=${docroot:-/var/www/orangehrm}

    sudo mkdir -p "$docroot"
    sudo chown -R $USER_WEB:$USER_WEB "$docroot"

    cat <<EOF | sudo tee "$APACHE_SITES/$vhost"
<VirtualHost *:80>
    ServerName $dominio
    DocumentRoot $docroot
    <Directory $docroot>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
</VirtualHost>

<VirtualHost *:443>
    ServerName $dominio
    DocumentRoot $docroot
    <Directory $docroot>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    SSLEngine on
    SSLCertificateFile /etc/ssl/private/cert.pem
    SSLCertificateKeyFile /etc/ssl/private/cert.key
</VirtualHost>
EOF

    sudo a2ensite "$vhost"
    sudo systemctl reload apache2

    ORG_VHOST=$vhost
    ORG_DOMAIN=$dominio
    ORG_PATH=$docroot
}

# ===== Descargar OrangeHRM =====
download_orangehrm() {
    echo -e "${YELLOW}Descargando OrangeHRM v5.7...${RESET}"
    cd /tmp || exit
    wget -O orangehrm.zip "https://sourceforge.net/projects/orangehrm/files/stable/5.7/orangehrm-5.7.zip/download"
    unzip -o orangehrm.zip
    VERSION="5.7"
    ORG_SRC_DIR=$(find /tmp -maxdepth 1 -type d -name "orangehrm-*")
}

# ===== Instalar OrangeHRM =====
install_orangehrm() {
    install_dependencies
    download_orangehrm

    read -rp "Ruta donde instalar OrangeHRM [/var/www/orangehrm]: " org_path
    org_path=${org_path:-/var/www/orangehrm}

    sudo mkdir -p "$org_path"
    sudo mv "$ORG_SRC_DIR"/* "$org_path"
    sudo chown -R $USER_WEB:$USER_WEB "$org_path"
    sudo chmod -R 755 "$org_path"

    create_db
    create_vhost

    echo -e "${GREEN}==============================${RESET}"
    echo -e "${GREEN} OrangeHRM Instalado${RESET}"
    echo "Ruta de instalación: $ORG_PATH"
    echo "Dominio: $ORG_DOMAIN"
    echo "VirtualHost: $ORG_VHOST"
    echo "Base de datos: $ORG_DBNAME"
    echo "Usuario: $ORG_DBUSER"
    echo "Contraseña: $ORG_DBPASS"
    echo "IP local: $(hostname -I | awk '{print $1}')"
    echo "IP pública: $(curl -s ifconfig.me || echo 'No detectada')"
    echo -e "${GREEN}==============================${RESET}"
}

# ===== Desinstalar OrangeHRM =====
uninstall_orangehrm() {
    echo -e "${YELLOW}Selecciona la ruta de OrangeHRM a eliminar:${RESET}"
    DIRS=$(ls -d $WWW_DIR/*/ 2>/dev/null)
    select d in $DIRS; do
        if [ -n "$d" ]; then
            echo -e "${GREEN}Has seleccionado:${RESET} $d"
            read -rp "¿Quieres eliminar este directorio? (s/n): " confirm
            if [[ "$confirm" == "s" ]]; then
                sudo rm -rf "$d"
                echo -e "${GREEN}Directorio eliminado.${RESET}"
            fi
            break
        else
            echo -e "${RED}Selección inválida.${RESET}"
        fi
    done

    echo -e "${YELLOW}Selecciona el VirtualHost a eliminar:${RESET}"
    FILES=$(ls $APACHE_SITES/*.conf 2>/dev/null)
    select f in $FILES; do
        if [ -n "$f" ]; then
            echo -e "${GREEN}Has seleccionado:${RESET} $f"
            read -rp "¿Quieres deshabilitar y borrar este vhost? (s/n): " confirm
            if [[ "$confirm" == "s" ]]; then
                sudo a2dissite "$(basename "$f")"
                sudo rm -f "$f"
                sudo systemctl reload apache2
                echo -e "${GREEN}VirtualHost eliminado.${RESET}"
            fi
            break
        else
            echo -e "${RED}Selección inválida.${RESET}"
        fi
    done

    read -rp "¿Quieres eliminar la base de datos y usuario de OrangeHRM? (s/n): " confirm
    if [[ "$confirm" == "s" ]]; then
        read -rp "Nombre de la base de datos: " DBNAME
        read -rp "Usuario de la base de datos: " DBUSER
        mysql -u root -p <<MYSQL_SCRIPT
DROP DATABASE IF EXISTS $DBNAME;
DROP USER IF EXISTS '$DBUSER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
        echo -e "${GREEN}Base de datos y usuario eliminados.${RESET}"
    fi
}

# ===== Menú principal =====
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
while true; do
    clear
echo -e "${WHITE}===============================================${RESET}"
echo -e "${CYAN}        Instalador OrangeHRM v5.7${RESET}"
echo -e "${WHITE}===============================================${RESET}"

echo -e "${YELLOW}1)${RESET} ${WHITE}Instalar nueva instancia de OrangeHRM${RESET}"
echo -e "${YELLOW}2)${RESET} ${WHITE}Listar VirtualHosts${RESET}"
echo -e "${YELLOW}3)${RESET} ${WHITE}Desinstalar OrangeHRM${RESET}"
echo -e "${YELLOW}4)${RESET} ${WHITE}Instalar Dependencias OrangeHRM${RESET}"
echo -e "${YELLOW}0)${RESET} ${CYAN}Salir${RESET}"

echo -e "${WHITE}===============================================${RESET}"

read -rp "Opción: " opt

    case $opt in
        1) install_orangehrm; read -rp "Presiona ENTER para volver al menú..." ;;
        2) ls -1 $APACHE_SITES/*.conf 2>/dev/null || echo "No hay VirtualHosts"
           read -rp "Presiona ENTER para volver al menú..." ;;
        3) uninstall_orangehrm; read -rp "Presiona ENTER para volver al menú..." ;;
		4) install_dependencies; read -rp "Presiona ENTER para volver al menú..." ;;
        0) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción inválida"; read -rp "Presiona ENTER para volver al menú..." ;;
    esac
done
