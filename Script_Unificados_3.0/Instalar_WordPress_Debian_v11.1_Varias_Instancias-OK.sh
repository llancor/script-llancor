#!/bin/bash

# =========================================
# INSTALADOR WORDPRESS AUTOMÁTICO
# Apache + MariaDB + PHP + SSL
# =========================================

# ========= Variables =========
NEXTCLOUD_DIR="/var/www/nextcloud"
NEXTCLOUD_DATA="/var/www/nextcloud-data"
APACHE_SITES="/etc/apache2/sites-available"
USER_WEB="www-data"
EDITOR_BIN="nano"
WWW_DIR="/var/www"
APACHE_SITES="/etc/apache2/sites-available"
USER_WEB="www-data"

# ========= Utilidades =========
log(){ echo "$(date '+%F %T') | $1" >> "$LOG_FILE"; }
pausa(){ read -rp "Presiona ENTER para continuar..."; }
ok(){ echo -e "${GREEN}✅ $1${NC}"; }
warn(){ echo -e "${YELLOW}⚠️  $1${NC}"; }
err(){ echo -e "${RED}❌ $1${NC}"; }
# ===== COLORES =====

GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
NC='\033[0m'
BLUE='\033[1;34m'
BOLD='\033[1m'

# =========================================
# DEPENDENCIAS WORDPRESS
# =========================================

DEPENDENCIAS=(
    sudo
    apache2
    mariadb-server
    php
    php-cli
    php-common
    php-mysql
    php-xml
    php-curl
    php-gd
    php-mbstring
    php-zip
    php-intl
    php-imagick
    unzip
    wget
    curl
)

# =========================================
# VERIFICAR DEPENDENCIAS
# =========================================

verificar_dependencias_wordpress() {

    clear

    echo -e "${CYAN}=========================================${NC}"
    echo -e "${WHITE} VERIFICANDO DEPENDENCIAS WORDPRESS${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo

    INSTALADAS=()
    FALTANTES=()

    for paquete in "${DEPENDENCIAS[@]}"; do

        if dpkg -s "$paquete" &>/dev/null; then
            echo -e "${GREEN}[INSTALADO]${NC} $paquete"
            INSTALADAS+=("$paquete")
        else
            echo -e "${RED}[FALTANTE]${NC} $paquete"
            FALTANTES+=("$paquete")
        fi

    done

    echo
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${WHITE} RESUMEN${NC}"
    echo -e "${CYAN}=========================================${NC}"

    echo -e "${GREEN}Instaladas:${NC} ${#INSTALADAS[@]}"
    echo -e "${RED}Faltantes:${NC} ${#FALTANTES[@]}"
    echo

    if [ ${#FALTANTES[@]} -eq 0 ]; then
        echo -e "${GREEN}✔ Todas las dependencias están instaladas.${NC}"
        return
    fi

    echo -e "${YELLOW}Paquetes faltantes:${NC}"
    printf ' - %s\n' "${FALTANTES[@]}"
    echo

    read -rp "¿Deseas instalar las dependencias faltantes? (s/n): " resp

    if [[ "$resp" =~ ^[Ss]$ ]]; then

        echo
        echo -e "${CYAN}Actualizando repositorios...${NC}"
        apt update

        echo
        echo -e "${CYAN}Instalando dependencias faltantes...${NC}"

        apt install -y "${FALTANTES[@]}"

        echo
        echo -e "${GREEN}✔ Dependencias instaladas correctamente.${NC}"

    else

        echo
        echo -e "${YELLOW}Instalación cancelada.${NC}"

    fi
}

# =========================================
# CREAR BASE DE DATOS
# =========================================

create_db() {

    echo -e "${YELLOW}Configuración de base de datos${RESET}"

    read -rp "Nombre DB [wordpress]: " DBNAME
    DBNAME=${DBNAME:-wordpress}

    read -rp "Usuario DB [wordpress]: " DBUSER
    DBUSER=${DBUSER:-wordpress}

    read -rp "Contraseña DB [wordpress]: " DBPASS
    DBPASS=${DBPASS:-wordpress}

    echo
    echo -e "${CYAN}Se solicitará la contraseña ROOT de MariaDB/MySQL${RESET}"
    echo

    mysql -u root -p <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS \`$DBNAME\`
CHARACTER SET utf8mb4
COLLATE utf8mb4_general_ci;

CREATE USER IF NOT EXISTS '$DBUSER'@'localhost'
IDENTIFIED BY '$DBPASS';

GRANT ALL PRIVILEGES ON \`$DBNAME\`.* TO '$DBUSER'@'localhost';

FLUSH PRIVILEGES;
MYSQL_SCRIPT

    if [ $? -eq 0 ]; then

        echo -e "${GREEN}✔ Base de datos creada correctamente${RESET}"

    else

        echo -e "${RED}✘ Error al crear la base de datos${RESET}"
        return 1

    fi

    WP_DBNAME=$DBNAME
    WP_DBUSER=$DBUSER
    WP_DBPASS=$DBPASS
}

# =========================================
# CREAR VIRTUALHOST
# =========================================

create_vhost() {

    read -rp "Nombre del VirtualHost [wordpress.conf]: " vhost
    vhost=${vhost:-wordpress.conf}

    [[ "$vhost" != *.conf ]] && vhost="${vhost}.conf"

    read -rp "Dominio o ServerName [wordpress.local]: " dominio
    dominio=${dominio:-wordpress.local}

    read -rp "Ruta DocumentRoot [/var/www/wordpress]: " docroot
    docroot=${docroot:-/var/www/wordpress}

    sudo mkdir -p "$docroot"
    sudo chown -R $USER_WEB:$USER_WEB "$docroot"

    echo
    echo "Tipo de SSL:"
    echo "1) Sin SSL"
    echo "2) Certificado Snakeoil TurnKey"
    echo "3) Certificados cert.pem/cert.key de TurnKey"
    echo "4) Let's Encrypt"

    read -rp "Opción [1]: " sslopt
    sslopt=${sslopt:-1}

    SSL_ENABLE=false
    SSL_INFO="Sin SSL"

    case $sslopt in

        1)

            SSL_INFO="Sin SSL"

        ;;

        2)

            echo -e "${GREEN}Usando certificado Snakeoil${RESET}"

            sudo apt install ssl-cert -y

            CERT_FILE="/etc/ssl/certs/ssl-cert-snakeoil.pem"
            KEY_FILE="/etc/ssl/private/ssl-cert-snakeoil.key"

            SSL_ENABLE=true
            SSL_INFO="Snakeoil"

        ;;

        3)

            echo -e "${GREEN}Usando certificados cert.pem/cert.key de TurnKey${RESET}"

            CERT_FILE="/etc/ssl/private/cert.pem"
            KEY_FILE="/etc/ssl/private/cert.key"

            if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then

                echo -e "${RED}No existen los certificados:${RESET}"
                echo "$CERT_FILE"
                echo "$KEY_FILE"

                return 1

            fi

            SSL_ENABLE=true
            SSL_INFO="Certificados personalizados TurnKey"

        ;;

        4)

            echo -e "${CYAN}Configurando Let's Encrypt${RESET}"

            sudo apt install certbot python3-certbot-apache -y

            SSL_ENABLE="LETSENCRYPT"
            SSL_INFO="Let's Encrypt"

        ;;

        *)

            echo -e "${RED}Opción inválida${RESET}"
            return 1

        ;;

    esac

    # ===== HTTP =====

    cat <<EOF | sudo tee "$APACHE_SITES/$vhost" > /dev/null
<VirtualHost *:80>

    ServerName $dominio
    DocumentRoot $docroot

    <Directory $docroot>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
EOF

    if [[ "$SSL_ENABLE" != false ]]; then

cat <<EOF | sudo tee -a "$APACHE_SITES/$vhost" > /dev/null

    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
EOF

    fi

cat <<EOF | sudo tee -a "$APACHE_SITES/$vhost" > /dev/null
</VirtualHost>
EOF

    # ===== HTTPS =====

    if [[ "$SSL_ENABLE" == true ]]; then

cat <<EOF | sudo tee -a "$APACHE_SITES/$vhost" > /dev/null

<VirtualHost *:443>

    ServerName $dominio
    DocumentRoot $docroot

    <Directory $docroot>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    SSLEngine on
    SSLCertificateFile $CERT_FILE
    SSLCertificateKeyFile $KEY_FILE

</VirtualHost>

EOF

    fi

    sudo a2enmod rewrite ssl
    sudo a2ensite "$vhost"

    sudo apache2ctl configtest || {

        echo -e "${RED}Error en configuración Apache${RESET}"
        return 1

    }

    sudo systemctl reload apache2

    # ===== LETS ENCRYPT =====

    if [[ "$SSL_ENABLE" == "LETSENCRYPT" ]]; then

        sudo certbot --apache -d "$dominio"

    fi

    WP_VHOST=$vhost
    WP_DOMAIN=$dominio
    WP_PATH=$docroot

    echo
    echo -e "${GREEN}✔ VirtualHost creado correctamente${RESET}"
}

# =========================================
# GENERAR INFORME
# =========================================

generar_informe_instalacion() {

    INFORME_DIR="/root/instalaciones-wordpress"

    sudo mkdir -p "$INFORME_DIR"

    FECHA=$(date +"%Y-%m-%d_%H-%M-%S")

    INFORME="$INFORME_DIR/${WP_DOMAIN}_${FECHA}.txt"

    SERVER_IP=$(hostname -I | awk '{print $1}')
    PHP_VERSION=$(php -v | head -n 1)

    cat <<EOF | sudo tee "$INFORME" > /dev/null
========================================
      INFORME INSTALACIÓN WORDPRESS
========================================

Fecha:
$(date)

Servidor:
$SERVER_IP

Dominio:
$WP_DOMAIN

Ruta instalación:
$WP_PATH

VirtualHost:
$WP_VHOST

Base de datos:
$WP_DBNAME

Usuario DB:
$WP_DBUSER

Contraseña DB:
$WP_DBPASS

PHP:
$PHP_VERSION

Apache:
$(apache2 -v | head -n 1)

MariaDB:
$(mysql --version)

SSL:
$SSL_INFO

Acceso:
https://$WP_DOMAIN

========================================
EOF

    echo
    echo -e "${GREEN}✔ Informe generado:${RESET}"
    echo "$INFORME"
}

# =========================================
# AÑADIR ALIAS
# =========================================

add_alias_to_vhost_file() {

    echo -e "${YELLOW}Selecciona el VirtualHost:${RESET}"

    FILES=$(ls $APACHE_SITES/*.conf 2>/dev/null)

    select f in $FILES; do

        if [ -n "$f" ]; then

            echo -e "${GREEN}Seleccionado:${RESET} $f"

            read -rp "Alias (ej: /mi_wp): " alias_path

            guessed_docroot=$(grep -m1 -oP '(?<=DocumentRoot )[^\r\n]+' "$f" || true)
            guessed_docroot=${guessed_docroot:-/var/www/wordpress}

            backup="${f}.bak-$(date +%Y%m%d-%H%M%S)"

            sudo cp "$f" "$backup"

            echo -e "${GREEN}Backup:${RESET} $backup"

            tmp=$(mktemp)

            awk -v ap="$alias_path" -v dr="$guessed_docroot" '
            {
                if ($0 ~ /<\/VirtualHost>/) {
                    print "    Alias " ap " " dr
                    print "    <Directory " dr ">"
                    print "        Options Indexes FollowSymLinks"
                    print "        AllowOverride All"
                    print "        Require all granted"
                    print "    </Directory>"
                }
                print $0
            }' "$f" > "$tmp" && sudo mv "$tmp" "$f"

            sudo systemctl reload apache2

            echo -e "${GREEN}Alias añadido:${RESET} $alias_path -> $guessed_docroot"

            break

        else

            echo -e "${RED}Selección inválida.${RESET}"

        fi

    done
}

# =========================================
# INSTALAR WORDPRESS
# =========================================

install_wordpress() {

    verificar_dependencias_wordpress

    read -rp "Ruta instalación [/var/www/wordpress]: " wp_path
    wp_path=${wp_path:-/var/www/wordpress}

    wget -O /tmp/wp_latest.zip https://wordpress.org/latest.zip

    unzip -qo /tmp/wp_latest.zip -d /tmp

    sudo mv /tmp/wordpress "$wp_path"

    sudo chown -R $USER_WEB:$USER_WEB "$wp_path"

    sudo chmod -R 755 "$wp_path"

    create_db
    create_vhost

    echo -e "${GREEN}==============================${RESET}"
    echo -e "${GREEN} WordPress Instalado${RESET}"
    echo "Ruta: $WP_PATH"
    echo "Dominio: $WP_DOMAIN"
    echo "VirtualHost: $WP_VHOST"
    echo "Base de datos: $WP_DBNAME"
    echo "Usuario DB: $WP_DBUSER"
    echo "Contraseña DB: $WP_DBPASS"
    echo "SSL: $SSL_INFO"
    echo "Acceso: https://$WP_DOMAIN"
    echo -e "${GREEN}==============================${RESET}"

    generar_informe_instalacion
}

# =========================================
# DESINSTALAR WORDPRESS
# =========================================

uninstall_wordpress() {

    # =====================================
    # ELIMINAR DIRECTORIO
    # =====================================

    echo -e "${YELLOW}Selecciona instalación:${RESET}"

    DIRS=$(ls -d $WWW_DIR/*/ 2>/dev/null)

    OPTIONS=("No eliminar directorio")

    for d in $DIRS; do
        OPTIONS+=("$d")
    done

    select d in "${OPTIONS[@]}"; do

        if [[ "$REPLY" == "1" ]]; then

            echo -e "${CYAN}Omitiendo eliminación de directorio${RESET}"
            break

        elif [ -n "$d" ]; then

            read -rp "¿Eliminar directorio seleccionado? (s/n): " confirm

            if [[ "$confirm" =~ ^[Ss]$ ]]; then

                sudo rm -rf "$d"

                echo -e "${GREEN}✔ Directorio eliminado${RESET}"

            else

                echo -e "${YELLOW}Cancelado${RESET}"

            fi

            break

        else

            echo -e "${RED}Selección inválida${RESET}"

        fi

    done

    echo

    # =====================================
    # ELIMINAR VHOST
    # =====================================

    echo -e "${YELLOW}Selecciona VirtualHost:${RESET}"

    FILES=$(ls $APACHE_SITES/*.conf 2>/dev/null)

    OPTIONS=("No eliminar VirtualHost")

    for f in $FILES; do
        OPTIONS+=("$f")
    done

    select f in "${OPTIONS[@]}"; do

        if [[ "$REPLY" == "1" ]]; then

            echo -e "${CYAN}Omitiendo eliminación de VirtualHost${RESET}"
            break

        elif [ -n "$f" ]; then

            read -rp "¿Eliminar VirtualHost seleccionado? (s/n): " confirm

            if [[ "$confirm" =~ ^[Ss]$ ]]; then

                sudo a2dissite "$(basename "$f")"

                sudo rm -f "$f"

                sudo systemctl reload apache2

                echo -e "${GREEN}✔ VirtualHost eliminado${RESET}"

            else

                echo -e "${YELLOW}Cancelado${RESET}"

            fi

            break

        else

            echo -e "${RED}Selección inválida${RESET}"

        fi

    done

    echo

    # =========================================
# ELIMINAR BASE DE DATOS
# =====================================

read -rp "¿Eliminar base de datos y usuario? (s/n): " confirm

if [[ "$confirm" =~ ^[Ss]$ ]]; then

    echo
    echo -e "${CYAN}Se solicitará contraseña ROOT MariaDB/MySQL UNA SOLA VEZ${RESET}"
    echo

    # ===== PEDIR PASSWORD UNA VEZ =====

    read -rsp "Contraseña ROOT MariaDB/MySQL: " MYSQL_ROOT_PASS
    echo

    # ===== LISTAR DB + USUARIOS =====

    DBS_INFO=$(mysql -u root -p"$MYSQL_ROOT_PASS" -Nse "
    SELECT
        SCHEMA_NAME,
        GROUP_CONCAT(DISTINCT GRANTEE SEPARATOR ', ')
    FROM information_schema.SCHEMATA s
    LEFT JOIN information_schema.SCHEMA_PRIVILEGES p
        ON s.SCHEMA_NAME = p.TABLE_SCHEMA
    WHERE SCHEMA_NAME NOT IN (
        'information_schema',
        'performance_schema',
        'mysql',
        'sys'
    )
    GROUP BY SCHEMA_NAME;
    ")

    if [ -z "$DBS_INFO" ]; then

        echo -e "${RED}No se encontraron bases de datos${RESET}"
        return

    fi

    declare -a DBS_ARRAY
    declare -a USERS_ARRAY

    echo
    echo -e "${YELLOW}Bases de datos disponibles:${RESET}"
    echo

    i=1

    while IFS=$'\t' read -r db users; do

        clean_users=$(echo "$users" | sed "s/'//g")

        echo "$i) DB: $db"
        echo "   Usuarios: ${clean_users:-Sin usuarios}"
        echo

        DBS_ARRAY+=("$db")
        USERS_ARRAY+=("$clean_users")

        ((i++))

    done <<< "$DBS_INFO"

    echo "0) No eliminar base de datos"
    echo

    read -rp "Selecciona opción: " opt

    if [[ "$opt" == "0" ]]; then

        echo -e "${CYAN}Omitiendo eliminación de base de datos${RESET}"

    elif [[ "$opt" =~ ^[0-9]+$ ]] && (( opt >= 1 && opt < i )); then

        INDEX=$((opt-1))

        DBNAME="${DBS_ARRAY[$INDEX]}"
        DBUSER_RAW="${USERS_ARRAY[$INDEX]}"

        # Extraer primer usuario válido
        DBUSER=$(echo "$DBUSER_RAW" | cut -d',' -f1 | cut -d'@' -f1)

        echo
        echo -e "${YELLOW}Base de datos:${RESET} $DBNAME"
        echo -e "${YELLOW}Usuario:${RESET} $DBUSER"

        read -rp "¿Eliminar esta base de datos y usuario? (s/n): " confirmdb

        if [[ "$confirmdb" =~ ^[Ss]$ ]]; then

            mysql -u root -p"$MYSQL_ROOT_PASS" <<MYSQL_SCRIPT
DROP DATABASE IF EXISTS \`$DBNAME\`;
DROP USER IF EXISTS '$DBUSER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

            if [ $? -eq 0 ]; then

                echo -e "${GREEN}✔ Base de datos eliminada${RESET}"

            else

                echo -e "${RED}✘ Error eliminando base de datos${RESET}"

            fi

        else

            echo -e "${YELLOW}Cancelado${RESET}"

        fi

    else

        echo -e "${RED}Opción inválida${RESET}"

    fi

else

    echo -e "${CYAN}Omitiendo eliminación de base de datos${RESET}"

fi

}

# ========= Configuración Apache / Vhost =========
menu_config_nextcloud(){
  while true; do
    clear
    echo -e "${CYAN}${BOLD}=== CONFIGURACIÓN VHOST / APACHE ===${NC}"
    echo -e " ${YELLOW}1)${NC} Editar VirtualHost Apache"
    echo -e " ${YELLOW}2)${NC} Verificar configuración de Apache"
    echo -e " ${YELLOW}3)${NC} Habilitar VirtualHost"
    echo -e " ${YELLOW}4)${NC} Deshabilitar VirtualHost"
    echo -e " ${YELLOW}5)${NC} Editar puertos Apache (ports.conf)"
    echo -e " ${YELLOW}6)${NC} Crear VirtualHost Generico/Reverse Proxy"
    echo -e " ${YELLOW}7)${NC} Eliminar VirtualHost"
    echo -e " ${CYAN}0) Volver${NC}"


    read -rp "> " op
    case "$op" in
     1)
    echo "=== Editar VirtualHost Apache ==="
    echo

    mapfile -t FILES < <(ls "$APACHE_SITES"/*.conf 2>/dev/null)

    if [ ${#FILES[@]} -eq 0 ]; then
        warn "No se encontraron archivos .conf en $APACHE_SITES"
        pausa
        break
    fi

    select f in "${FILES[@]}" "Cancelar"; do
        if [[ "$REPLY" -gt 0 && "$REPLY" -le ${#FILES[@]} ]]; then
            echo "Editando: $f"
            sudo "$EDITOR_BIN" "$f"

            echo
            echo "🔧 Validando configuración Apache..."
            if apachectl configtest; then
                echo "🔄 Recargando Apache..."
                systemctl reload apache2
                echo "✔ Apache recargado correctamente"
            else
                echo "❌ Error en la configuración, NO se recargó Apache"
            fi

            break
        elif [[ "$f" == "Cancelar" ]]; then
            break
        else
            warn "Selección inválida"
        fi
    done

    pausa
    ;;
      2) sudo apache2ctl -t; pausa ;;
      3)
         FILES=$(ls $APACHE_SITES/*.conf 2>/dev/null | xargs -n1 basename)
         select sitio in $FILES; do
           [ -n "$sitio" ] || { warn "Selección inválida"; break; }
           sudo a2ensite "$sitio" && sudo systemctl reload apache2
           ok "Sitio $sitio habilitado."
           break
         done
         pausa
         ;;
      4)
         FILES=$(ls $APACHE_SITES/*.conf 2>/dev/null | xargs -n1 basename)
         select sitio in $FILES; do
           [ -n "$sitio" ] || { warn "Selección inválida"; break; }
           sudo a2dissite "$sitio" && sudo systemctl reload apache2
           ok "Sitio $sitio deshabilitado."
           break
         done
         pausa
         ;;
      5) sudo $EDITOR_BIN /etc/apache2/ports.conf; pausa ;;
6)
read -rp "Nombre del VirtualHost (ej: ejemplo.conf): " vhost
read -rp "Dominio o ServerName (ej: ejemplo.com): " dominio
read -rp "Ruta DocumentRoot (ej: /var/www/html/ejemplo): " docroot

echo
echo "Tipo de configuración:"
echo "1) Sitio web normal (WordPress, HTML, etc)"
echo "2) Reverse Proxy (Odoo, apps en puerto)"
echo "3) Alias (ej: /zabbix)"
read -rp "Selecciona opción [1-3]: " tipo

echo
echo "Tipo de certificado SSL:"
echo "1) Let's Encrypt (Certbot)"
echo "2) Certificado autofirmado (TurnKey)"
read -rp "Selecciona opción [1-2]: " ssl_tipo

# Validación básica
if [ "$ssl_tipo" != "1" ] && [ "$ssl_tipo" != "2" ]; then
    echo "Opción inválida, usando certificado TurnKey por defecto"
    ssl_tipo="2"
fi

# Variables SSL dinámicas
if [ "$ssl_tipo" == "1" ]; then
    SSL_CERT="/etc/letsencrypt/live/$dominio/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$dominio/privkey.pem"
else
    SSL_CERT="/etc/ssl/private/cert.pem"
    SSL_KEY="/etc/ssl/private/cert.key"
fi

sudo mkdir -p "$docroot"
sudo chown -R $USER_WEB:$USER_WEB "$docroot"

CONFIG=""

# ===============================
# SITIO NORMAL
# ===============================
if [ "$tipo" == "1" ]; then

CONFIG=$(cat <<EOF
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

    ErrorLog \${APACHE_LOG_DIR}/$dominio-error.log
    CustomLog \${APACHE_LOG_DIR}/$dominio-access.log combined
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
    SSLCertificateFile $SSL_CERT
    SSLCertificateKeyFile $SSL_KEY

    ErrorLog \${APACHE_LOG_DIR}/$dominio-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/$dominio-ssl-access.log combined
</VirtualHost>
EOF
)

# ===============================
# REVERSE PROXY
# ===============================
elif [ "$tipo" == "2" ]; then

read -rp "Puerto backend (ej: 8069): " puerto

CONFIG=$(cat <<EOF
<VirtualHost *:80>
    ServerName $dominio

    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:$puerto/
    ProxyPassReverse / http://127.0.0.1:$puerto/

    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

    ErrorLog \${APACHE_LOG_DIR}/$dominio-error.log
    CustomLog \${APACHE_LOG_DIR}/$dominio-access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName $dominio

    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:$puerto/
    ProxyPassReverse / http://127.0.0.1:$puerto/

    SSLEngine on
    SSLCertificateFile $SSL_CERT
    SSLCertificateKeyFile $SSL_KEY

    ErrorLog \${APACHE_LOG_DIR}/$dominio-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/$dominio-ssl-access.log combined
</VirtualHost>
EOF
)

# ===============================
# ALIAS
# ===============================
elif [ "$tipo" == "3" ]; then

read -rp "Alias (ej: /zabbix): " alias

CONFIG=$(cat <<EOF
<VirtualHost *:80>
    ServerName $dominio

    Alias $alias $docroot

    <Directory $docroot>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

    ErrorLog \${APACHE_LOG_DIR}/$dominio-error.log
    CustomLog \${APACHE_LOG_DIR}/$dominio-access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName $dominio

    Alias $alias $docroot

    <Directory $docroot>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    SSLEngine on
    SSLCertificateFile $SSL_CERT
    SSLCertificateKeyFile $SSL_KEY

    ErrorLog \${APACHE_LOG_DIR}/$dominio-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/$dominio-ssl-access.log combined
</VirtualHost>
EOF
)

fi

# ===============================
# GUARDAR CONFIG
# ===============================
echo "$CONFIG" | sudo tee "$APACHE_SITES/$vhost" > /dev/null

# ===============================
# ACTIVAR MÓDULOS
# ===============================
sudo a2enmod ssl rewrite

if [ "$tipo" == "2" ]; then
    sudo a2enmod proxy proxy_http
fi

# ===============================
# ACTIVAR SITIO
# ===============================
sudo a2ensite "$vhost"

# ===============================
# LETSENCRYPT
# ===============================
if [ "$ssl_tipo" == "1" ]; then
    echo "Generando certificado Let's Encrypt..."
    sudo apt update
    sudo apt install -y certbot python3-certbot-apache
    sudo certbot --apache -d "$dominio" --non-interactive --agree-tos -m admin@$dominio
fi

# ===============================
# RELOAD APACHE
# ===============================
sudo systemctl reload apache2

ok "VirtualHost $vhost creado correctamente con SSL 🚀"
pausa
;;

      7)
         FILES=$(ls $APACHE_SITES/*.conf 2>/dev/null | xargs -n1 basename)
         select vhost in $FILES; do
           [ -n "$vhost" ] || { warn "Selección inválida"; break; }
           sudo a2dissite "$vhost"
           sudo rm "$APACHE_SITES/$vhost"
           sudo systemctl reload apache2
           ok "VirtualHost $vhost eliminado."
           break
         done
         pausa
         ;;
      0) return ;;
      *) warn "Opción inválida"; pausa ;;
    esac
  done
}


# =========================================
# MENÚ
# =========================================

while true; do

    clear

    echo -e "${WHITE}===============================================${RESET}"
    echo -e "${CYAN} Instalador WordPress Automático v11.1 ${RESET}"
    echo -e "${WHITE}===============================================${RESET}"

    echo -e "${YELLOW}1)${RESET} Instalar WordPress Varias Instancias"
    echo -e "${YELLOW}2)${RESET} Verificar dependencias"
    echo -e "${YELLOW}3)${RESET} Crear VirtualHost"
    echo -e "${YELLOW}4)${RESET} ${CYAN}Menu VirtualHost editar/crear/borrar"
    echo -e "${YELLOW}5)${RESET} Desinstalar WordPress"
    echo -e "${YELLOW}0)${RESET} Salir"

    echo -e "${WHITE}===============================================${RESET}"

    read -rp "Opción: " opt

    case $opt in

        1)
            install_wordpress
            read -rp "ENTER para continuar..."
        ;;

        2)
            verificar_dependencias_wordpress
            read -rp "ENTER para continuar..."
        ;;

        3)
            create_vhost
            read -rp "ENTER para continuar..."
        ;;

        4)
            menu_config_nextcloud
            read -rp "ENTER para continuar..."
        ;;

        5)
            uninstall_wordpress
            read -rp "ENTER para continuar..."
        ;;

        0)
            echo "Saliendo..."
            exit 0
        ;;

        *)
            echo "Opción inválida"
            read -rp "ENTER para continuar..."
        ;;

    esac

done