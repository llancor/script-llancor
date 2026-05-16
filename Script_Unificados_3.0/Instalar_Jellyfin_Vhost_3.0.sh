#!/bin/bash

############################################################
#  Menu de herramientas para Jellyfin
############################################################

SCRIPT_URL="https://repo.jellyfin.org/install-debuntu.sh"

create_vhost() {
    echo "=== Crear nuevo VirtualHost SSL para Jellyfin ==="

    read -p "ServerName (ej: jellyfin-server.com): " SERVERNAME
    SERVERNAME=${SERVERNAME:-jellyfin-server.com}

    read -p "IP interna del servicio [127.0.0.1]: " IP
    IP=${IP:-127.0.0.1}

    read -p "Puerto interno [8096]: " PORT
    PORT=${PORT:-8096}

    CERT="/etc/ssl/private/cert.pem"
    KEY="/etc/ssl/private/cert.key"
    CONF_PATH="/etc/apache2/sites-available/${SERVERNAME}.conf"

    echo ""
    echo "Creando configuración en ${CONF_PATH}..."
    echo "----------------------------------------"

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

    echo "✅ Archivo creado: ${CONF_PATH}"

    read -p "¿Habilitar sitio y recargar Apache? (s/n): " ENABLE
    if [[ "$ENABLE" =~ ^[sS]$ ]]; then
        sudo a2enmod ssl proxy proxy_http proxy_wstunnel headers rewrite
        sudo a2ensite "${SERVERNAME}.conf"
        sudo systemctl reload apache2
        echo "✅ Sitio habilitado."
    else
        echo "ℹ️ Puedes habilitarlo luego con:"
        echo "   sudo a2ensite ${SERVERNAME}.conf && sudo systemctl reload apache2"
    fi
}

install_jellyfin() {
    echo "=== Instalando Jellyfin ==="
    curl -fsSL "$SCRIPT_URL" | sudo bash
    sudo usermod -aG www-data jellyfin
    sudo systemctl restart jellyfin
}

uninstall_jellyfin() {
    echo "=== Desinstalación segura de Jellyfin ==="
    echo "Esto NO toca Nextcloud ni otras aplicaciones."

    read -p "¿Confirmas eliminar Jellyfin? (s/n): " CONFIRM
    [[ "$CONFIRM" =~ ^[sS]$ ]] || { echo "Cancelado."; return; }

    echo "➤ Deteniendo servicio..."
    sudo systemctl stop jellyfin 2>/dev/null

    echo "➤ Eliminando paquetes..."
    sudo apt remove --purge -y jellyfin jellyfin-server jellyfin-web jellyfin-ffmpeg 2>/dev/null

    echo "➤ Eliminando carpetas (sin tocar Nextcloud)..."
    sudo rm -rf /var/lib/jellyfin
    sudo rm -rf /etc/jellyfin
    sudo rm -f /etc/apt/sources.list.d/jellyfin.sources
    sudo rm -f /etc/apt/keyrings/jellyfin.gpg

    echo "➤ Actualizando repos..."
    sudo apt update

    echo "✅ Jellyfin desinstalado correctamente."
}
# ===== Jellyfin Tools =====
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
menu() {
    while true; do
        clear
        echo -e "${WHITE}===============================================${NC}"
echo -e "${CYAN}            Jellyfin Tools - Cesar${NC}"
echo -e "${WHITE}===============================================${NC}"

echo -e "${YELLOW}1)${NC} ${WHITE}Instalar Jellyfin${NC}"
echo -e "${YELLOW}2)${NC} ${WHITE}Desinstalar Jellyfin (seguro, no toca Nextcloud)${NC}"
echo -e "${YELLOW}3)${NC} ${WHITE}Crear VirtualHost SSL para Jellyfin${NC}"
echo -e "${YELLOW}0)${NC} ${CYAN}Salir${NC}"

echo -e "${WHITE}===============================================${NC}"

read -p "Elige una opción: " OPT

        case "$OPT" in
            1) install_jellyfin ;;
            2) uninstall_jellyfin ;;
            3) create_vhost ;;
            4) exit 0 ;;
            *) echo "Opción inválida"; sleep 2 ;;
        esac
    done
}

menu
