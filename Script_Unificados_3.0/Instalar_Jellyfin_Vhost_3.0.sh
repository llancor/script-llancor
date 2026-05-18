#!/bin/bash

############################################################
#  Menu de herramientas para Jellyfin
############################################################

SCRIPT_URL="https://repo.jellyfin.org/install-debuntu.sh"

# ===== Colores =====
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# =========================================================
# VERIFICAR DEPENDENCIAS
# =========================================================

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

verificar_dependencias() {

    echo
    echo -e "${CYAN}===============================================${NC}"
    echo -e "${CYAN}       Verificando dependencias...${NC}"
    echo -e "${CYAN}===============================================${NC}"
    echo

    FALTANTES=()

    # Verificar paquetes
    for pkg in "${DEPENDENCIAS[@]}"; do

        if dpkg -s "$pkg" &>/dev/null; then
            echo -e "${GREEN}✔${NC} Paquete instalado: ${pkg}"
        else
            echo -e "${RED}✘${NC} Falta paquete: ${pkg}"
            FALTANTES+=("$pkg")
        fi

    done

    echo

    # Verificar módulos apache
    for mod in "${MODULOS_APACHE[@]}"; do

        if apache2ctl -M 2>/dev/null | grep -q "${mod}_module"; then
            echo -e "${GREEN}✔${NC} Módulo Apache activo: ${mod}"
        else
            echo -e "${RED}✘${NC} Módulo Apache faltante: ${mod}"
        fi

    done

    echo

    # Si faltan paquetes
    if [ ${#FALTANTES[@]} -gt 0 ]; then

        echo -e "${YELLOW}Faltan dependencias:${NC}"
        printf ' - %s\n' "${FALTANTES[@]}"
        echo

        read -p "¿Deseas instalarlas ahora? (s/n): " INSTALAR_DEP

        if [[ "$INSTALAR_DEP" =~ ^[sS]$ ]]; then

            echo
            echo -e "${CYAN}Instalando dependencias...${NC}"
            sudo apt update
            sudo apt install -y "${FALTANTES[@]}"

            echo
            echo -e "${CYAN}Habilitando módulos Apache...${NC}"

            for mod in "${MODULOS_APACHE[@]}"; do
                sudo a2enmod "$mod" >/dev/null 2>&1
            done

            sudo systemctl restart apache2

            echo
            echo -e "${GREEN}✅ Dependencias instaladas correctamente.${NC}"

        else

            echo
            echo -e "${RED}⚠ Algunas funciones podrían no funcionar.${NC}"

        fi

    else

        echo -e "${GREEN}✅ Todas las dependencias están instaladas.${NC}"

    fi

    echo
    read -p "Presiona ENTER para continuar..."
}

# =========================================================
# CREAR VHOST
# =========================================================

create_vhost() {

    verificar_dependencias

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

    echo
    echo -e "${GREEN}✅ Archivo creado:${NC} ${CONF_PATH}"

    read -p "¿Habilitar sitio y recargar Apache? (s/n): " ENABLE

    if [[ "$ENABLE" =~ ^[sS]$ ]]; then

        sudo a2ensite "${SERVERNAME}.conf"
        sudo systemctl reload apache2

        echo
        echo -e "${GREEN}✅ Sitio habilitado.${NC}"

    else

        echo
        echo -e "${YELLOW}ℹ Puedes habilitarlo luego con:${NC}"
        echo "sudo a2ensite ${SERVERNAME}.conf && sudo systemctl reload apache2"

    fi

    echo
    read -p "Presiona ENTER para continuar..."
}

# =========================================================
# INSTALAR JELLYFIN
# =========================================================

install_jellyfin() {

    verificar_dependencias

    echo
    echo -e "${CYAN}=== Instalando Jellyfin ===${NC}"
    echo

    curl -fsSL "$SCRIPT_URL" | sudo bash

    sudo usermod -aG www-data jellyfin
    sudo systemctl restart jellyfin

    echo
    echo -e "${GREEN}✅ Jellyfin instalado correctamente.${NC}"

    echo
    read -p "Presiona ENTER para continuar..."
}

# =========================================================
# DESINSTALAR JELLYFIN
# =========================================================

uninstall_jellyfin() {

    echo "=== Desinstalación segura de Jellyfin ==="
    echo "Esto NO toca Nextcloud ni otras aplicaciones."

    read -p "¿Confirmas eliminar Jellyfin? (s/n): " CONFIRM

    [[ "$CONFIRM" =~ ^[sS]$ ]] || {
        echo "Cancelado."
        return
    }

    echo
    echo "➤ Deteniendo servicio..."
    sudo systemctl stop jellyfin 2>/dev/null

    echo "➤ Eliminando paquetes..."
    sudo apt remove --purge -y jellyfin jellyfin-server jellyfin-web jellyfin-ffmpeg 2>/dev/null

    echo "➤ Eliminando carpetas..."
    sudo rm -rf /var/lib/jellyfin
    sudo rm -rf /etc/jellyfin
    sudo rm -f /etc/apt/sources.list.d/jellyfin.sources
    sudo rm -f /etc/apt/keyrings/jellyfin.gpg

    echo "➤ Actualizando repos..."
    sudo apt update

    echo
    echo -e "${GREEN}✅ Jellyfin desinstalado correctamente.${NC}"

    echo
    read -p "Presiona ENTER para continuar..."
}

# =========================================================
# MENU PRINCIPAL
# =========================================================

menu() {

    while true; do

        clear

        echo -e "${WHITE}===============================================${NC}"
        echo -e "${CYAN}         Jellyfin Tools - Cesar${NC}"
        echo -e "${WHITE}===============================================${NC}"

        echo -e "${YELLOW}1)${NC} ${WHITE}Instalar Jellyfin${NC}"
        echo -e "${YELLOW}2)${NC} ${WHITE}Desinstalar Jellyfin${NC}"
        echo -e "${YELLOW}3)${NC} ${WHITE}Crear VirtualHost SSL${NC}"
        echo -e "${YELLOW}4)${NC} ${WHITE}Verificar dependencias${NC}"
        echo -e "${YELLOW}0)${NC} ${CYAN}Salir${NC}"

        echo -e "${WHITE}===============================================${NC}"

        read -p "Elige una opción: " OPT

        case "$OPT" in

            1)
                install_jellyfin
            ;;

            2)
                uninstall_jellyfin
            ;;

            3)
                create_vhost
            ;;

            4)
                verificar_dependencias
            ;;

            0)
                exit 0
            ;;

            *)
                echo
                echo -e "${RED}Opción inválida${NC}"
                sleep 2
            ;;

        esac

    done
}

menu