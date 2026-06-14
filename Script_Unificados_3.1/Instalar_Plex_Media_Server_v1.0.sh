#!/usr/bin/env bash
set -e

# ===============================
# MEDIA MANAGER v2 - TURNKEY LINUX
# Jellyfin + Apache Reverse Proxy
# Redirección global a HTTPS
# ===============================

SSL_CERT="/etc/ssl/private/cert.pem"
SSL_KEY="/etc/ssl/private/cert.key"

if [[ $EUID -ne 0 ]]; then
  echo "❌ Ejecuta como root o con sudo"
  exit 1
fi

# ===============================
# FUNCIONES
# ===============================

forzar_https_global() {

CONF="/etc/apache2/sites-available/000-force-https.conf"

cat > "$CONF" <<EOF
<VirtualHost *:80>
    ServerName _
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
</VirtualHost>
EOF

    a2enmod rewrite >/dev/null
    a2ensite 000-force-https.conf >/dev/null
    systemctl reload apache2

    echo "✅ Redirección global HTTP → HTTPS activada"
}

crear_vhost() {

    echo ""
    read -p "ServerName (ej: media.tudominio.com): " SERVERNAME
    read -p "IP interna [127.0.0.1]: " IP
    IP=${IP:-127.0.0.1}
    read -p "Puerto interno [8096]: " PORT
    PORT=${PORT:-8096}

    CONF="/etc/apache2/sites-available/${SERVERNAME}.conf"

cat > "$CONF" <<EOF
<VirtualHost *:443>
    ServerName ${SERVERNAME}

    SSLEngine on
    SSLCertificateFile ${SSL_CERT}
    SSLCertificateKeyFile ${SSL_KEY}

    ProxyPreserveHost On
    ProxyRequests Off
    ProxyTimeout 600

    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule /(.*) ws://${IP}:${PORT}/\$1 [P,L]

    ProxyPass / http://${IP}:${PORT}/
    ProxyPassReverse / http://${IP}:${PORT}/

    Header always set X-Forwarded-Proto "https"

    ErrorLog \${APACHE_LOG_DIR}/${SERVERNAME}_error.log
    CustomLog \${APACHE_LOG_DIR}/${SERVERNAME}_access.log combined
</VirtualHost>
EOF

    a2enmod ssl proxy proxy_http proxy_wstunnel headers rewrite >/dev/null
    a2ensite "${SERVERNAME}.conf" >/dev/null
    systemctl reload apache2

    echo "✅ VHost creado y habilitado:"
    echo "👉 https://${SERVERNAME}"
}

instalar_jellyfin() {
    echo "📦 Instalando Jellyfin..."
    curl -fsSL https://repo.jellyfin.org/install-debuntu.sh | bash
    usermod -aG www-data jellyfin
    systemctl restart jellyfin
    echo "✅ Jellyfin instalado"
}

reiniciar_jellyfin() {
    echo "🔄 Reiniciando Jellyfin..."
    systemctl restart jellyfin
    systemctl status jellyfin --no-pager
}

desinstalar_jellyfin() {

    echo "⚠ DESINSTALACIÓN TOTAL DE JELLYFIN"
    echo ""
    read -p "¿Seguro que deseas continuar? (s/n): " CONFIRM
    [[ "$CONFIRM" != "s" ]] && echo "❌ Cancelado" && return

    read -p "ServerName usado en Apache (ej: media.tudominio.com): " SERVERNAME

    systemctl stop jellyfin || true
    systemctl disable jellyfin || true

    apt purge -y jellyfin jellyfin-server jellyfin-web jellyfin-ffmpeg || true
    apt autoremove -y

    rm -f /etc/apt/sources.list.d/jellyfin.*
    rm -f /etc/apt/keyrings/jellyfin.gpg

    userdel jellyfin 2>/dev/null || true

    rm -rf /etc/jellyfin
    rm -rf /var/lib/jellyfin
    rm -rf /var/cache/jellyfin
    rm -rf /usr/share/jellyfin

    a2dissite "${SERVERNAME}.conf" 2>/dev/null || true
    rm -f /etc/apache2/sites-available/${SERVERNAME}.conf

    systemctl reload apache2

    echo "✅ Jellyfin eliminado completamente"
}

estado() {
    echo "---- ESTADO ----"
    systemctl status jellyfin --no-pager || true
    systemctl status apache2 --no-pager
    ss -tulnp | grep -E ':(80|443|8096)' || true
}

# ===============================
# MENU PRINCIPAL
# ===============================
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
while true; do
    clear
echo -e "${WHITE}==================================${RESET}"
echo -e "${CYAN}     MEDIA MANAGER v2 - TURNKEY${RESET}"
echo -e "${WHITE}==================================${RESET}"

echo -e "${YELLOW}1)${RESET} ${WHITE}Instalar Jellyfin${RESET}"
echo -e "${YELLOW}2)${RESET} ${WHITE}Crear VirtualHost SSL (443)${RESET}"
echo -e "${YELLOW}3)${RESET} ${WHITE}Forzar redirección global HTTP → HTTPS${RESET}"
echo -e "${YELLOW}4)${RESET} ${WHITE}Reiniciar Jellyfin${RESET}"
echo -e "${YELLOW}5)${RESET} ${WHITE}Desinstalar Jellyfin (TOTAL)${RESET}"
echo -e "${YELLOW}6)${RESET} ${WHITE}Ver estado del sistema${RESET}"
echo -e "${YELLOW}7)${RESET} ${CYAN}Salir${RESET}"

echo ""
echo -e "${WHITE}==================================${RESET}"

read -p "Opción: " opt

    case $opt in
        1) instalar_jellyfin ;;
        2) crear_vhost ;;
        3) forzar_https_global ;;
        4) reiniciar_jellyfin ;;
        5) desinstalar_jellyfin ;;
        6) estado ;;
        7) exit 0 ;;
        *) echo "Opción inválida"; sleep 2 ;;
    esac

    read -p "Presiona ENTER para continuar..."
done
