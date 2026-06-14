#!/bin/bash

############################################################
# Jellyfin Tools
############################################################

SCRIPT_URL="https://repo.jellyfin.org/install-debuntu.sh"

# ===== Colores =====
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# ===== Dependencias =====
DEPENDENCIAS=(
    curl
    apache2
    openssl
)

MODULOS_APACHE=(
    ssl
    proxy
    proxy_http
    proxy_wstunnel
    headers
    rewrite
)

# =========================================================
# VERIFICAR DEPENDENCIAS
# =========================================================
verificar_dependencias() {

    SILENT="$1"

    echo
    echo -e "${CYAN}===============================================${NC}"
    echo -e "${CYAN}Verificando dependencias de Jellyfin...${NC}"
    echo -e "${CYAN}===============================================${NC}"
    echo

    INSTALADAS=()
    FALTANTES=()

    DEPENDENCIAS=(
        curl
		sudo
        ca-certificates
        gnupg
        apt-transport-https
        apache2
        openssl
    )

    MODULOS_APACHE=(
        ssl
        proxy
        proxy_http
        proxy_wstunnel
        headers
        rewrite
    )

    #
    # Revisar paquetes
    #
    for pkg in "${DEPENDENCIAS[@]}"; do

        if dpkg -s "$pkg" >/dev/null 2>&1; then
            echo -e "${GREEN}✔ Instalado:${NC} $pkg"
            INSTALADAS+=("$pkg")
        else
            echo -e "${YELLOW}➜ Falta instalar:${NC} $pkg"
            FALTANTES+=("$pkg")
        fi

    done

    #
    # Instalar faltantes
    #
    if [ ${#FALTANTES[@]} -gt 0 ]; then

        echo
        echo -e "${CYAN}Instalando dependencias faltantes...${NC}"
        echo

        apt update
        apt install -y "${FALTANTES[@]}"

    else
        echo
        echo -e "${GREEN}Todas las dependencias ya están instaladas.${NC}"
    fi

    #
    # Verificar Apache
    #
    if command -v apache2ctl >/dev/null 2>&1; then

        echo
        echo -e "${CYAN}Verificando módulos Apache...${NC}"
        echo

        for mod in "${MODULOS_APACHE[@]}"; do

            if apache2ctl -M 2>/dev/null | grep -q "${mod}_module"; then
                echo -e "${GREEN}✔ Módulo activo:${NC} $mod"
            else
                echo -e "${YELLOW}➜ Activando módulo:${NC} $mod"
                a2enmod "$mod" >/dev/null 2>&1
            fi

        done

        a2dissite 000-default.conf >/dev/null 2>&1 || true

        apache2ctl configtest >/dev/null 2>&1

        if [ $? -eq 0 ]; then
            systemctl reload apache2
        fi
    fi

    #
    # Resumen final
    #
    echo
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${GREEN} RESUMEN${NC}"
    echo -e "${GREEN}===============================================${NC}"
    echo

    if [ ${#INSTALADAS[@]} -gt 0 ]; then
        echo "Ya instaladas:"
        printf ' - %s\n' "${INSTALADAS[@]}"
        echo
    fi

    if [ ${#FALTANTES[@]} -gt 0 ]; then
        echo "Instaladas ahora:"
        printf ' - %s\n' "${FALTANTES[@]}"
        echo
    fi

    echo -e "${GREEN}✅ Verificación finalizada.${NC}"

    if [[ "$SILENT" != "--silent" ]]; then
        echo
        read -p "Presiona ENTER para continuar..."
    fi
}
# =========================================================
# CREAR VHOST
# =========================================================

create_vhost() {

    verificar_dependencias --silent

    echo
    echo -e "${CYAN}=== Crear VirtualHost Jellyfin SSL ===${NC}"
    echo

    read -p "Dominio (ej: jellyfin.midominio.com): " SERVERNAME
    SERVERNAME=${SERVERNAME:-jellyfin-server.com}

    read -p "IP interna [127.0.0.1]: " IP
    IP=${IP:-127.0.0.1}

    read -p "Puerto interno [8096]: " PORT
    PORT=${PORT:-8096}

    CERT="/etc/ssl/private/cert.pem"
    KEY="/etc/ssl/private/cert.key"
    CONF_PATH="/etc/apache2/sites-available/${SERVERNAME}.conf"

    if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
        echo
        echo -e "${RED}❌ Certificado SSL no encontrado:${NC}"
        echo "$CERT"
        echo "$KEY"
        read -p "Presiona ENTER para continuar..."
        return
    fi

sudo tee "$CONF_PATH" > /dev/null <<EOF
<VirtualHost *:443>
    ServerName ${SERVERNAME}

    SSLEngine on
    SSLCertificateFile ${CERT}
    SSLCertificateKeyFile ${KEY}

    ProxyPreserveHost On
    ProxyRequests Off
    Timeout 600
    ProxyTimeout 600

    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule /(.*) ws://${IP}:${PORT}/\$1 [P,L]

    ProxyPass / http://${IP}:${PORT}/
    ProxyPassReverse / http://${IP}:${PORT}/

    Header always unset X-Frame-Options
    Header always set X-Forwarded-Proto "https"
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"

    ErrorLog \${APACHE_LOG_DIR}/${SERVERNAME}_error.log
    CustomLog \${APACHE_LOG_DIR}/${SERVERNAME}_access.log combined
</VirtualHost>

<VirtualHost *:80>
    ServerName ${SERVERNAME}
    Redirect permanent / https://${SERVERNAME}/
</VirtualHost>
EOF

    sudo a2ensite "${SERVERNAME}.conf" >/dev/null 2>&1
    sudo systemctl reload apache2

    echo
    echo -e "${GREEN}✅ VirtualHost creado:${NC}"
    echo "https://${SERVERNAME}"

    echo
    read -p "Presiona ENTER para continuar..."
}

# =========================================================
# INSTALAR JELLYFIN
# =========================================================

install_jellyfin() {

    verificar_dependencias --silent

    echo
    echo -e "${CYAN}=== Instalando Jellyfin ===${NC}"
    echo

    curl -fsSL "$SCRIPT_URL" | sudo bash

    sudo usermod -aG www-data jellyfin
    sudo systemctl enable jellyfin
    sudo systemctl restart jellyfin

    echo
    echo -e "${GREEN}✅ Jellyfin instalado correctamente.${NC}"
    echo
    echo "URL local:"
    echo "http://127.0.0.1:8096"
    echo

    read -p "¿Crear VirtualHost SSL ahora? (s/n): " CREAR_VHOST

    if [[ "$CREAR_VHOST" =~ ^[sS]$ ]]; then

        read -p "Dominio (ej: jellyfin.midominio.com): " SERVERNAME
        SERVERNAME=${SERVERNAME:-jellyfin-server.com}

        IP="127.0.0.1"
        PORT="8096"

        CERT="/etc/ssl/private/cert.pem"
        KEY="/etc/ssl/private/cert.key"
        CONF_PATH="/etc/apache2/sites-available/${SERVERNAME}.conf"

        if [ -f "$CERT" ] && [ -f "$KEY" ]; then

sudo tee "$CONF_PATH" > /dev/null <<EOF
<VirtualHost *:443>
    ServerName ${SERVERNAME}

    SSLEngine on
    SSLCertificateFile ${CERT}
    SSLCertificateKeyFile ${KEY}

    ProxyPreserveHost On
    ProxyRequests Off
    Timeout 600
    ProxyTimeout 600

    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule /(.*) ws://${IP}:${PORT}/\$1 [P,L]

    ProxyPass / http://${IP}:${PORT}/
    ProxyPassReverse / http://${IP}:${PORT}/

    Header always set X-Forwarded-Proto "https"
</VirtualHost>

<VirtualHost *:80>
    ServerName ${SERVERNAME}
    Redirect permanent / https://${SERVERNAME}/
</VirtualHost>
EOF

            sudo a2ensite "${SERVERNAME}.conf" >/dev/null 2>&1
            sudo systemctl reload apache2

            echo
            echo -e "${GREEN}✅ VirtualHost habilitado:${NC}"
            echo "https://${SERVERNAME}"

        else
            echo
            echo -e "${RED}⚠ No se encontró certificado SSL.${NC}"
        fi
    fi

    echo
    read -p "Presiona ENTER para continuar..."
}

# =========================================================
# DESINSTALAR
# =========================================================

uninstall_jellyfin() {

    echo
    echo -e "${RED}=== Desinstalar Jellyfin ===${NC}"
    echo

    read -p "¿Confirmas eliminar Jellyfin? (s/n): " CONFIRM

    [[ "$CONFIRM" =~ ^[sS]$ ]] || return

    sudo systemctl stop jellyfin 2>/dev/null

    sudo apt remove --purge -y \
        jellyfin \
        jellyfin-server \
        jellyfin-web \
        jellyfin-ffmpeg

    sudo rm -rf /var/lib/jellyfin
    sudo rm -rf /etc/jellyfin
    sudo rm -rf /var/log/jellyfin

    sudo rm -f /etc/apt/sources.list.d/jellyfin.sources
    sudo rm -f /etc/apt/keyrings/jellyfin.gpg

    sudo apt autoremove -y
    sudo apt update

    echo
    echo -e "${GREEN}✅ Jellyfin eliminado correctamente.${NC}"

    echo
    read -p "Presiona ENTER para continuar..."
}

# =========================================================
# MENU
# =========================================================

menu() {

    while true; do

        clear

        echo -e "${WHITE}===============================================${NC}"
        echo -e "${CYAN}Jellyfin Tools${NC}"
        echo -e "${WHITE}===============================================${NC}"
        echo
        echo -e "${YELLOW}1)${NC} Instalar Jellyfin"
        echo -e "${YELLOW}2)${NC} Desinstalar Jellyfin"
        echo -e "${YELLOW}3)${NC} Crear VirtualHost SSL"
        echo -e "${YELLOW}4)${NC} Verificar dependencias"
        echo -e "${YELLOW}0)${NC} Salir"
        echo
        echo -e "${WHITE}===============================================${NC}"

        read -p "Elige una opción: " OPT

        case "$OPT" in
            1) install_jellyfin ;;
            2) uninstall_jellyfin ;;
            3) create_vhost ;;
            4) verificar_dependencias ;;
            0) exit 0 ;;
            *)
                echo
                echo -e "${RED}Opción inválida${NC}"
                sleep 2
                ;;
        esac

    done
}

menu