#!/bin/bash

# ===== COLORES =====
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

NC_PATH="/var/www/nextcloud"
CONTAINER_NAME="talk-hpb"
DEFAULT_PORT=8081

# ===== ROOT =====
[ "$EUID" -ne 0 ] && echo -e "${RED}Ejecuta como root${RESET}" && exit

# ===== DOCKER =====
install_docker() {
  if ! command -v docker &>/dev/null; then
    echo -e "${YELLOW}Instalando Docker...${RESET}"
    apt update && apt install -y docker.io
    systemctl enable docker
    systemctl start docker
  else
    echo -e "${GREEN}Docker OK${RESET}"
  fi
}

# ===== INSTALAR APPARMOR =====
instalar_apparmor() {

  if ! command -v apparmor_parser &>/dev/null; then
    echo -e "${YELLOW}Instalando AppArmor...${RESET}"
    apt install -y apparmor apparmor-utils
    systemctl enable apparmor
    systemctl start apparmor
  fi

  systemctl enable docker
  systemctl start docker
}

# ===== VHOST =====
create_vhost() {
  echo -e "${CYAN}=== Crear VirtualHost Talk ===${RESET}"

  read -p "ServerName (ej: talk.midominio.com): " DOMAIN
  read -p "Puerto backend [${DEFAULT_PORT}]: " PORT
  PORT=${PORT:-$DEFAULT_PORT}

  VHOST="/etc/apache2/sites-available/${DOMAIN}.conf"

  cat > $VHOST <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    Redirect / https://$DOMAIN/
</VirtualHost>

<VirtualHost *:443>
    ServerName $DOMAIN

    SSLEngine on
    SSLCertificateFile /etc/ssl/private/cert.pem
    SSLCertificateKeyFile /etc/ssl/private/cert.key

    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:$PORT/
    ProxyPassReverse / http://127.0.0.1:$PORT/

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
</VirtualHost>
EOF

  a2enmod proxy proxy_http ssl headers
  a2ensite ${DOMAIN}.conf
  systemctl reload apache2

  echo -e "${GREEN}VHost creado: https://$DOMAIN${RESET}"
}

# ===== TURN =====
install_turn() {
  echo -e "${CYAN}Configurando coturn...${RESET}"
  apt install -y coturn

  read -p "Dominio TURN: " DOMAIN
  read -p "Clave TURN: " SECRET

  cat > /etc/turnserver.conf <<EOF
listening-port=3478
fingerprint
use-auth-secret
static-auth-secret=$SECRET
realm=$DOMAIN
total-quota=100
bps-capacity=0
EOF

  systemctl enable coturn
  systemctl restart coturn

  echo -e "${GREEN}coturn listo${RESET}"
}
# ===== INSTALAR TALK =====
instalar_talk_nextcloud() {
    echo -e "${YELLOW}Instalando Nextcloud Talk (spreed)...${RESET}"

    # Detectar usuario web si no está definido
    USER_WEB=${USER_WEB:-www-data}
    NEXTCLOUD_DIR=${NEXTCLOUD_DIR:-/var/www/nextcloud}

    # Verificar que existe occ
    if [[ ! -f "$NEXTCLOUD_DIR/occ" ]]; then
        echo -e "${RED}No se encontró occ en $NEXTCLOUD_DIR${RESET}"
        return 1
    fi

    # Verificar si ya está instalada
    if sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" app:list | grep -q "spreed:"; then
        echo -e "${GREEN}Talk ya está instalado, intentando activar...${RESET}"
        sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" app:enable spreed
    else
        echo -e "${CYAN}Instalando app spreed...${RESET}"
        sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" app:install spreed

        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Error al instalar Talk${RESET}"
            return 1
        fi
    fi

    # Asegurar activación
    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" app:enable spreed

    # Verificación final
    if sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" app:list | grep -q "spreed: enabled"; then
        echo -e "${GREEN}Nextcloud Talk instalado y activo correctamente${RESET}"
    else
        echo -e "${RED}Talk no se pudo activar correctamente${RESET}"
        return 1
    fi
}

# ===== HPB =====
install_hpb() {
  install_docker

  read -p "Dominio Talk (ej: talk.midominio.com): " DOMAIN
  read -p "Puerto backend [${DEFAULT_PORT}]: " PORT
  PORT=${PORT:-$DEFAULT_PORT}
  read -p "Clave HPB: " SECRET

  docker run -d \
    --name $CONTAINER_NAME \
    -p $PORT:8081 \
    -e NC_DOMAIN=$DOMAIN \
    -e NC_SECRET=$SECRET \
    --restart unless-stopped \
    strukturag/nextcloud-spreed-signaling

  echo -e "${GREEN}HPB instalado${RESET}"

  sudo -u www-data php $NC_PATH/occ config:app:set spreed signaling_servers \
    --value="[{\"url\":\"https://$DOMAIN\",\"secret\":\"$SECRET\"}]"
}

# ===== TURN EN NC =====
configure_turn_nc() {
  read -p "Dominio TURN: " DOMAIN
  read -p "Clave TURN: " SECRET

  sudo -u www-data php $NC_PATH/occ config:app:set spreed turn_servers \
    --value="[{\"server\":\"$DOMAIN:3478\",\"secret\":\"$SECRET\",\"protocols\":\"udp,tcp\"}]"

  echo -e "${GREEN}TURN en Nextcloud OK${RESET}"
}

# ===== ESTADO =====
status_services() {
  echo -e "${CYAN}=== ESTADO ===${RESET}"

  docker ps | grep $CONTAINER_NAME \
    && echo -e "${GREEN}HPB activo${RESET}" \
    || echo -e "${RED}HPB detenido${RESET}"

  systemctl is-active coturn &>/dev/null \
    && echo -e "${GREEN}coturn activo${RESET}" \
    || echo -e "${RED}coturn inactivo${RESET}"
}

# ===== REINICIAR =====
restart_services() {
  docker restart $CONTAINER_NAME 2>/dev/null
  systemctl restart coturn
  systemctl reload apache2
  echo -e "${GREEN}Servicios reiniciados${RESET}"
}

# ===== DESINSTALAR =====
uninstall_all() {
  echo -e "${RED}Eliminando Talk...${RESET}"

  docker stop $CONTAINER_NAME 2>/dev/null
  docker rm $CONTAINER_NAME 2>/dev/null

  apt remove --purge -y coturn
  apt autoremove -y

  sudo -u www-data php $NC_PATH/occ config:app:delete spreed signaling_servers
  sudo -u www-data php $NC_PATH/occ config:app:delete spreed turn_servers

  echo -e "${GREEN}Eliminado completamente${RESET}"
}
# ===== INSTALA TODO DE UNA VEZ =====
install_all() {
  echo -e "${CYAN}=== INSTALACIÓN AUTOMÁTICA NEXTCLOUD TALK ===${RESET}"

  # ===== DATOS =====
  read -p "Dominio Talk (ej: talk.midominio.com): " DOMAIN
  read -p "Puerto backend [8081]: " PORT
  PORT=${PORT:-8081}

  read -p "Clave HPB (enter = auto): " HPB_SECRET
  HPB_SECRET=${HPB_SECRET:-$(openssl rand -hex 16)}

  read -p "Clave TURN (enter = auto): " TURN_SECRET
  TURN_SECRET=${TURN_SECRET:-$(openssl rand -hex 16)}

  echo -e "${YELLOW}Configuración:${RESET}"
  echo "Dominio: $DOMAIN"
  echo "Puerto: $PORT"
  echo "HPB: $HPB_SECRET"
  echo "TURN: $TURN_SECRET"

  read -p "¿Continuar? (s/n): " CONFIRM
  [[ "$CONFIRM" != "s" ]] && return

  # ===== DEPENDENCIAS =====
  apt update
  apt install -y docker.io curl

  # ===== APPARMOR FIX =====
  if ! command -v apparmor_parser &>/dev/null; then
    echo -e "${YELLOW}Instalando AppArmor...${RESET}"
    apt install -y apparmor apparmor-utils
    systemctl enable apparmor
    systemctl start apparmor
  fi

  systemctl enable docker
  systemctl start docker

  # ===== LIMPIAR =====
  docker rm -f talk-hpb 2>/dev/null

  # ===== INSTALAR HPB =====
  echo -e "${CYAN}Instalando HPB...${RESET}"

  docker run -d \
    --name talk-hpb \
    -p $PORT:8081 \
    -e NC_DOMAIN=$DOMAIN \
    -e NC_SECRET=$HPB_SECRET \
    --restart unless-stopped \
    strukturag/nextcloud-spreed-signaling

  sleep 5

  # ===== VERIFICAR HPB =====
  if ! docker ps | grep -q talk-hpb; then
    echo -e "${RED}HPB falló, intentando sin AppArmor...${RESET}"

    docker rm -f talk-hpb

    docker run -d \
      --name talk-hpb \
      --security-opt apparmor=unconfined \
      -p $PORT:8081 \
      -e NC_DOMAIN=$DOMAIN \
      -e NC_SECRET=$HPB_SECRET \
      --restart unless-stopped \
      strukturag/nextcloud-spreed-signaling

    sleep 5
  fi

  if ! docker ps | grep -q talk-hpb; then
    echo -e "${RED}ERROR: HPB no pudo iniciar${RESET}"
    docker logs talk-hpb
    return
  fi

  echo -e "${GREEN}HPB funcionando ✔${RESET}"

  # ===== TURN =====
  echo -e "${CYAN}Instalando coturn...${RESET}"
  apt install -y coturn

  cat > /etc/turnserver.conf <<EOF
listening-port=3478
fingerprint
use-auth-secret
static-auth-secret=$TURN_SECRET
realm=$DOMAIN
total-quota=100
bps-capacity=0
EOF

  systemctl enable coturn
  systemctl restart coturn

  echo -e "${GREEN}TURN listo ✔${RESET}"

  # ===== VHOST =====
  echo -e "${CYAN}Configurando Apache...${RESET}"

  VHOST="/etc/apache2/sites-available/${DOMAIN}.conf"

  cat > $VHOST <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    Redirect / https://$DOMAIN/
</VirtualHost>

<VirtualHost *:443>
    ServerName $DOMAIN

    SSLEngine on
    SSLCertificateFile /etc/ssl/private/cert.pem
    SSLCertificateKeyFile /etc/ssl/private/cert.key

    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:$PORT/
    ProxyPassReverse / http://127.0.0.1:$PORT/
</VirtualHost>
EOF

  a2enmod proxy proxy_http ssl headers >/dev/null
  a2ensite ${DOMAIN}.conf >/dev/null
  systemctl reload apache2

  echo -e "${GREEN}VHost listo ✔${RESET}"

  # ===== TALK APP =====
  echo -e "${CYAN}Instalando Talk...${RESET}"
  sudo -u www-data php /var/www/nextcloud/occ app:install spreed
  sudo -u www-data php /var/www/nextcloud/occ app:enable spreed

  # ===== CONFIG NC =====
  sudo -u www-data php /var/www/nextcloud/occ config:app:set spreed signaling_servers \
    --value="[{\"url\":\"https://$DOMAIN\",\"secret\":\"$HPB_SECRET\"}]"

  sudo -u www-data php /var/www/nextcloud/occ config:app:set spreed turn_servers \
    --value="[{\"server\":\"$DOMAIN:3478\",\"secret\":\"$TURN_SECRET\",\"protocols\":\"udp,tcp\"}]"

  echo -e "${GREEN}Nextcloud configurado ✔${RESET}"

  # ===== FINAL =====
  echo -e "${GREEN}"
  echo "======================================"
  echo " INSTALACIÓN COMPLETA ✔"
  echo "======================================"
  echo -e "${RESET}"

  echo "URL: https://$DOMAIN"
  echo "HPB: OK"
  echo "TURN: OK"
}

# ===== COLORES =====
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
RESET='\033[0m'


# ===== MENU =====
while true; do
  clear
  echo -e "${CYAN}${BOLD}"
  echo "╔══════════════════════════════════════╗"
  echo "║        NEXTCLOUD TALK PRO           ║"
  echo "╚══════════════════════════════════════╝"
  echo -e "${RESET}"

  echo -e "${YELLOW} 1)${WHITE} Instalar Talk"
  echo -e "${YELLOW} 2)${WHITE} Instalar High Performance Backend"
  echo -e "${YELLOW} 3)${WHITE} Crear VirtualHost (Apache)"
  echo -e "${YELLOW} 4)${WHITE} Instalar Servidor TURN"
  echo -e "${YELLOW} 5)${WHITE} Configurar TURN en Nextcloud"
  echo -e "${YELLOW} 6)${WHITE} Ver estado de los Servicios HPB/TURN"
  echo -e "${YELLOW} 7)${WHITE} Reiniciar servicios"
  echo -e "${YELLOW} 8)${WHITE} Instalar AppArmor"
  echo -e "${YELLOW} 9)${GREEN} Instalación COMPLETA automática"
  echo -e "${YELLOW} 10)${CYAN} Desinstalar TODO"
  echo -e "${YELLOW} 0)${YELLOW} Salir"

  echo
  read -rp "Selecciona una opción: " OP

  case $OP in
    1) instalar_talk_nextcloud ;;
    2) install_hpb ;;
    3) create_vhost ;;
    4) install_turn ;;
    5) configure_turn_nc ;;
    6) status_services ;;
    7) restart_services ;;
	8) instalar_apparmor ;;
	9) install_all ;;
   10) uninstall_all ;;
    0) exit ;;
    *) echo -e "${CYAN}Opción inválida${RESET}" ;;
  esac

  echo
  read -p "Presiona ENTER para continuar..."
done
