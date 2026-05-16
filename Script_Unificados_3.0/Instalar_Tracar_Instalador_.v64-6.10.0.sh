#!/bin/bash
# Instalador interactivo de Traccar para TurnKey Linux
# Autor: Cesar + ChatGPT
# Versión: 5.0

set -e

# ===== Colores =====
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# ===== Variable global para MySQL =====
MYSQL_PASS=""

# ===== Funciones =====

check_install() {
    if ! dpkg -s "$1" &>/dev/null; then
        echo -e "${YELLOW}Instalando $1...${NC}"
        sudo apt install -y "$1"
    else
        echo -e "${GREEN}$1 ya está instalado.${NC}"
    fi
}

ask_mysql_password() {
    if [ -z "$MYSQL_PASS" ]; then
        read -sp "Ingrese la contraseña de root de MySQL: " MYSQL_PASS
        echo
    fi
}

instalar_dependencias() {
    echo -e "${CYAN}==============================================${NC}"
    echo -e "${BLUE}        Verificando dependencias...${NC}"
    echo -e "${CYAN}==============================================${NC}"
    check_install openjdk-17-jre-headless
    check_install unzip
    check_install wget
    check_install apache2
    check_install mysql-server
    check_install certbot
    check_install python3-certbot-apache
    echo -e "${GREEN}✅ Todas las dependencias están instaladas.${NC}"
}

instalar_traccar() {
    echo -e "${CYAN}==============================================${NC}"
    echo -e "${BLUE}        Descargando Traccar v6.10.0...${NC}"
    echo -e "${CYAN}==============================================${NC}"
    wget https://sourceforge.net/projects/traccar.mirror/files/v6.10.0/traccar-linux-64-6.10.0.zip -O /tmp/traccar.zip

    echo -e "${BLUE}Descomprimiendo el ZIP y sobrescribiendo contenido...${NC}"
    unzip -o /tmp/traccar.zip -d /tmp/traccar

    cd /tmp/traccar

    echo -e "${BLUE}Dando permisos de ejecución al instalador...${NC}"
    chmod +x traccar.run

    echo -e "${BLUE}Ejecutando instalador de Traccar...${NC}"
    sudo ./traccar.run

    echo -e "${BLUE}Activando y reiniciando servicios...${NC}"
    sudo systemctl start traccar
    sudo systemctl enable traccar
    sudo systemctl restart apache2

    crear_vhost
    verificar_servicios
}

verificar_servicios() {
    echo -e "${CYAN}==============================================${NC}"
    echo -e "${BLUE}        Estado de los servicios...${NC}"
    echo -e "${CYAN}==============================================${NC}"
    sudo systemctl status traccar --no-pager
    sudo systemctl status apache2 --no-pager
}

crear_vhost() {
    read -p "Ingrese el ServerName (dominio o IP pública): " SERVERNAME

    echo -e "${MAGENTA}Seleccione el tipo de certificado SSL:${NC}"
    echo -e "${CYAN}1) Certificados de TurnKey Linux"
    echo "2) Certificados Let's Encrypt${NC}"
    read -p "Opción [1/2]: " SSL_OPTION

    VHOST_CONF="/etc/apache2/sites-available/traccar.conf"

    if [ "$SSL_OPTION" == "1" ]; then
        CERT_FILE="/etc/ssl/private/cert.pem"
        KEY_FILE="/etc/ssl/private/cert.key"
    elif [ "$SSL_OPTION" == "2" ]; then
        sudo certbot --apache -d "$SERVERNAME" --non-interactive --agree-tos -m admin@$SERVERNAME
        CERT_FILE="/etc/letsencrypt/live/$SERVERNAME/fullchain.pem"
        KEY_FILE="/etc/letsencrypt/live/$SERVERNAME/privkey.pem"
    else
        CERT_FILE="/etc/ssl/private/cert.pem"
        KEY_FILE="/etc/ssl/private/cert.key"
    fi

    echo -e "${BLUE}Creando VirtualHost con redirección HTTP → HTTPS...${NC}"
    sudo bash -c "cat > $VHOST_CONF" <<EOL
<VirtualHost *:80>
    ServerName $SERVERNAME
    Redirect permanent / https://$SERVERNAME/
</VirtualHost>

<VirtualHost *:443>
    ServerName $SERVERNAME

    DocumentRoot /opt/traccar/web

    SSLEngine on
    SSLCertificateFile $CERT_FILE
    SSLCertificateKeyFile $KEY_FILE

    <Directory /opt/traccar/web>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ProxyPass / http://localhost:8082/
    ProxyPassReverse / http://localhost:8082/
</VirtualHost>
EOL

    sudo a2enmod proxy proxy_http ssl rewrite
    sudo a2ensite traccar
    sudo systemctl reload apache2

    echo -e "${GREEN}✅ VirtualHost configurado correctamente.${NC}"
}

editar_vhost() {
    VHOST_CONF="/etc/apache2/sites-available/traccar.conf"
    if [ ! -f "$VHOST_CONF" ]; then
        echo -e "${RED}No se encontró VirtualHost de Traccar.${NC}"
        return
    fi

    echo -e "${BLUE}Abriendo VirtualHost de Traccar para editar...${NC}"
    sudo nano "$VHOST_CONF"

    echo -e "${BLUE}Recargando Apache para aplicar cambios...${NC}"
    sudo systemctl reload apache2
    echo -e "${GREEN}✅ Cambios aplicados correctamente.${NC}"
}

eliminar_vhost() {
    VHOST_CONF="/etc/apache2/sites-available/traccar.conf"
    if [ ! -f "$VHOST_CONF" ]; then
        echo -e "${RED}No se encontró VirtualHost de Traccar.${NC}"
        return
    fi

    read -p "¿Seguro que desea eliminar el VirtualHost de Traccar? (s/n): " CONFIRM
    if [[ "$CONFIRM" =~ ^[sS]$ ]]; then
        sudo a2dissite traccar.conf &>/dev/null || true
        sudo rm -f /etc/apache2/sites-available/traccar.conf
        sudo rm -f /etc/apache2/sites-enabled/traccar.conf
        sudo systemctl reload apache2
        echo -e "${GREEN}✅ VirtualHost de Traccar eliminado correctamente.${NC}"
    else
        echo "Operación cancelada."
    fi
}

configurar_mysql() {
    ask_mysql_password

    echo -e "${BLUE}Configurando Traccar para usar MySQL...${NC}"

    read -p "Nombre de la base de datos [traccardb]: " DB_NAME
    DB_NAME=${DB_NAME:-traccardb}

    read -p "Usuario de la base de datos [traccaruser]: " DB_USER
    DB_USER=${DB_USER:-traccaruser}

    mysql -u root -p"$MYSQL_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -u root -p"$MYSQL_PASS" -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASS';"
    mysql -u root -p"$MYSQL_PASS" -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"

    echo -e "${BLUE}Instalando conector MySQL para Java...${NC}"
    wget -O /tmp/mysql-connector.zip https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-j-8.0.33.zip
    unzip -j /tmp/mysql-connector.zip "*.jar" -d /opt/traccar/lib/

    CONF_FILE="/opt/traccar/conf/traccar.xml"
    sudo cp $CONF_FILE $CONF_FILE.bak

    sudo sed -i "s|<entry key='database.driver'>.*</entry>|<entry key='database.driver'>com.mysql.cj.jdbc.Driver</entry>|" $CONF_FILE
    sudo sed -i "s|<entry key='database.url'>.*</entry>|<entry key='database.url'>jdbc:mysql://localhost:3306/$DB_NAME?serverTimezone=UTC</entry>|" $CONF_FILE
    sudo sed -i "s|<entry key='database.user'>.*</entry>|<entry key='database.user'>$DB_USER</entry>|" $CONF_FILE
    sudo sed -i "s|<entry key='database.password'>.*</entry>|<entry key='database.password'>$MYSQL_PASS</entry>|" $CONF_FILE

    sudo systemctl restart traccar
    echo -e "${GREEN}✅ Traccar ahora está configurado para usar MySQL.${NC}"
}

desinstalar_traccar() {
    ask_mysql_password

    echo -e "${RED}ADVERTENCIA: Esto eliminará completamente Traccar, su configuración y base de datos.${NC}"
    read -p "¿Seguro que desea continuar? (s/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
        echo "Operación cancelada."
        return
    fi

    echo -e "${BLUE}Deteniendo servicio Traccar...${NC}"
    sudo systemctl stop traccar || true
    sudo systemctl disable traccar || true

    if [ -f /etc/apache2/sites-available/traccar.conf ]; then
        SERVERNAME=$(grep -m1 "ServerName" /etc/apache2/sites-available/traccar.conf | awk '{print $2}')
    fi

    echo -e "${BLUE}Deshabilitando y eliminando VirtualHost de Apache...${NC}"
    sudo a2dissite traccar.conf &>/dev/null || true
    sudo rm -f /etc/apache2/sites-available/traccar.conf
    sudo rm -f /etc/apache2/sites-enabled/traccar.conf
    sudo systemctl reload apache2

    echo -e "${BLUE}Eliminando archivos de Traccar...${NC}"
    sudo rm -rf /opt/traccar /etc/systemd/system/traccar.service

    read -p "¿Desea eliminar también la base de datos MySQL de Traccar? (s/n): " DBDEL
    if [[ "$DBDEL" =~ ^[sS]$ ]]; then
        mysql -u root -p"$MYSQL_PASS" -e "DROP DATABASE IF EXISTS traccardb;"
        mysql -u root -p"$MYSQL_PASS" -e "DROP USER IF EXISTS 'traccaruser'@'localhost';"
    fi

    if [ -n "$SERVERNAME" ] && [ -d "/etc/letsencrypt/live/$SERVERNAME" ]; then
        echo -e "${YELLOW}Se detectó un certificado Let's Encrypt para $SERVERNAME.${NC}"
        read -p "¿Desea eliminar este certificado (solo afectará a Traccar)? (s/n): " DELCERT
        if [[ "$DELCERT" =~ ^[sS]$ ]]; then
            sudo certbot delete --cert-name "$SERVERNAME"
        fi
    fi

    sudo systemctl reload apache2
    echo -e "${GREEN}✅ Traccar eliminado completamente sin afectar Nextcloud ni otros sitios.${NC}"
}

desinstalar_letsencrypt() {
    read -p "Ingrese el dominio del certificado Let's Encrypt que desea eliminar: " DEL_DOMAIN
    if [ -z "$DEL_DOMAIN" ]; then
        echo "Dominio vacío. Operación cancelada."
        return
    fi

    if [ -d "/etc/letsencrypt/live/$DEL_DOMAIN" ]; then
        echo -e "${YELLOW}Se detectó certificado Let's Encrypt para $DEL_DOMAIN.${NC}"
        read -p "¿Desea eliminar este certificado? (s/n): " CONFIRM
        if [[ "$CONFIRM" =~ ^[sS]$ ]]; then
            sudo certbot delete --cert-name "$DEL_DOMAIN"
            echo -e "${GREEN}✅ Certificado eliminado correctamente.${NC}"
        else
            echo "Operación cancelada."
        fi
    else
        echo -e "${RED}No se encontró certificado Let's Encrypt para $DEL_DOMAIN.${NC}"
    fi
}

# ===== Menú =====
while true; do
    echo -e "${MAGENTA}==============================================${NC}"
    echo -e "${YELLOW}           MENÚ INTERACTIVO TRACCAR${NC}"
    echo -e "${MAGENTA}==============================================${NC}"
    echo -e "${CYAN}1) Instalar dependencias"
    echo "2) Instalar Traccar"
    echo "3) Crear VirtualHost Apache"
    echo "4) Desinstalar Traccar"
    echo "5) Configurar base de datos MySQL"
    echo "6) Salir"
    echo "7) Desinstalar certificado Let's Encrypt"
    echo "8) Editar VirtualHost de Traccar"
    echo "9) Eliminar VirtualHost de Traccar${NC}"
    read -p "Seleccione una opción: " opt

    case $opt in
        1) instalar_dependencias ;;
        2) instalar_traccar ;;
        3) crear_vhost ;;
        4) desinstalar_traccar ;;
        5) configurar_mysql ;;
        6) exit 0 ;;
        7) desinstalar_letsencrypt ;;
        8) editar_vhost ;;
        9) eliminar_vhost ;;
        *) echo -e "${RED}Opción inválida${NC}" ;;
    esac
done
