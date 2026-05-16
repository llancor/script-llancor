#!/bin/bash

# =========================================
# PANEL UPTIME KUMA DOCKER + APACHE HTTPS
# =========================================

KUMA_DIR="/opt/uptime-kuma"
COMPOSE_FILE="$KUMA_DIR/docker-compose.yml"
SERVICE_NAME="uptime-kuma"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pause(){
    read -p "Presiona ENTER para continuar..."
}

instalar_kuma(){

set -e

echo -e "${CYAN}===== INSTALADOR UPTIME KUMA =====${NC}"
echo
echo -e "${YELLOW}1)${NC} Versión estable (1.x) ✅"
echo -e "${YELLOW}2)${NC} Versión nueva (2.x beta) ⚠️"
echo

read -p "Seleccione versión: " VERSION_OP

case $VERSION_OP in
    1) KUMA_TAG="1" ;;
    2) KUMA_TAG="2" ;;
    *) echo -e "${RED}Opción inválida${NC}"; return ;;
esac

echo
read -rp "Server Name (dominio o IP): " SERVER_NAME
[ -z "$SERVER_NAME" ] && echo "Vacío" && return

KUMA_PORT=3001
KUMA_CONTAINER="uptime-kuma"
KUMA_VOLUME="uptime-kuma"

echo -e "${CYAN}Usando imagen: louislam/uptime-kuma:${KUMA_TAG}${NC}"

# ---------- Docker ----------
if ! command -v docker &>/dev/null; then
    echo -e "${YELLOW}Instalando Docker...${NC}"
    apt-get update -qq
    apt-get install -y docker.io
    systemctl enable --now docker
fi

# ---------- Contenedor ----------
if docker ps -a --format '{{.Names}}' | grep -q "^${KUMA_CONTAINER}$"; then
    echo -e "${YELLOW}Contenedor ya existe, recreando...${NC}"
    docker stop $KUMA_CONTAINER
    docker rm $KUMA_CONTAINER
fi

docker pull louislam/uptime-kuma:${KUMA_TAG}

docker run -d \
    --name "$KUMA_CONTAINER" \
    --restart=always \
    -p 127.0.0.1:${KUMA_PORT}:3001 \
    -v ${KUMA_VOLUME}:/app/data \
    louislam/uptime-kuma:${KUMA_TAG}

echo -e "${GREEN}✔ Contenedor levantado${NC}"

# ---------- Apache ----------
if ! command -v apache2 &>/dev/null; then
    apt-get install -y apache2
    systemctl enable --now apache2
fi

a2enmod proxy proxy_http proxy_wstunnel ssl rewrite headers

SSL_CERT="/etc/ssl/private/cert.pem"
SSL_KEY="/etc/ssl/private/cert.pem"

VHOST="/etc/apache2/sites-available/uptime-kuma.conf"

cat > "$VHOST" <<EOF
<VirtualHost *:80>
    ServerName $SERVER_NAME
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName $SERVER_NAME

    SSLEngine on
    SSLCertificateFile    $SSL_CERT
    SSLCertificateKeyFile $SSL_KEY

    ProxyPreserveHost On

    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteRule /(.*) ws://127.0.0.1:${KUMA_PORT}/\$1 [P,L]
    RewriteCond %{HTTP:Upgrade} !=websocket [NC]
    RewriteRule /(.*) http://127.0.0.1:${KUMA_PORT}/\$1 [P,L]

    ProxyPass / http://127.0.0.1:${KUMA_PORT}/
    ProxyPassReverse / http://127.0.0.1:${KUMA_PORT}/
</VirtualHost>
EOF

a2ensite uptime-kuma.conf
systemctl restart apache2

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}✔ Instalación completada${NC}"
echo -e "${CYAN}https://${SERVER_NAME}${NC}"
echo -e "${GREEN}======================================${NC}"
}

desinstalar_todo(){

    #!/bin/bash
# ============================================================
#  Desinstalador de Uptime Kuma + vhost Apache
#  TurnKey Linux
# ============================================================

set -e

# ---------- Colores ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------- Banner ----------
echo -e "${RED}"
cat << 'EOF'
  ____          _           _        _
 |  _ \  ___  (_) _ __    | |  __ _| |
 | | | |/ _ \ | || '_ \   | | / _` | |
 | |_| |  __/ | || | | |  | || (_| | |
 |____/  \___| |_||_| |_|  |_| \__,_|_|

  Desinstalador Uptime Kuma — TurnKey Linux
EOF
echo -e "${NC}"

# ---------- Verificar root ----------
[[ $EUID -ne 0 ]] && error "Este script debe ejecutarse como root. Usá: sudo $0"

# ---------- Confirmación ----------
echo -e "${RED}ADVERTENCIA: Esto eliminará:${NC}"
echo "  • Contenedor Docker: uptime-kuma"
echo "  • Volumen Docker:    uptime-kuma  (todos los datos e historial)"
echo "  • Imagen Docker:     louislam/uptime-kuma"
echo "  • VirtualHost:       /etc/apache2/sites-available/uptime-kuma.conf"
echo ""
read -rp "$(echo -e ${YELLOW}"¿Estás seguro? Escribí 'si' para continuar: "${NC})" CONFIRM
[[ "$CONFIRM" != "si" ]] && echo "Cancelado." && exit 0

echo ""

# ---------- 1. Detener y eliminar contenedor ----------
info "Buscando contenedor 'uptime-kuma'..."
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^uptime-kuma$"; then
    info "Deteniendo contenedor..."
    docker stop uptime-kuma
    info "Eliminando contenedor..."
    docker rm uptime-kuma
    success "Contenedor eliminado."
else
    warn "Contenedor 'uptime-kuma' no encontrado. Saltando."
fi

# ---------- 2. Eliminar volumen ----------
info "Buscando volumen 'uptime-kuma'..."
if docker volume ls --format '{{.Name}}' 2>/dev/null | grep -q "^uptime-kuma$"; then
    docker volume rm uptime-kuma
    success "Volumen eliminado."
else
    warn "Volumen 'uptime-kuma' no encontrado. Saltando."
fi

# ---------- 3. Eliminar imagen ----------
info "Buscando imagen 'louislam/uptime-kuma'..."
if docker images --format '{{.Repository}}' 2>/dev/null | grep -q "louislam/uptime-kuma"; then
    docker rmi louislam/uptime-kuma
    success "Imagen eliminada."
else
    warn "Imagen 'louislam/uptime-kuma' no encontrada. Saltando."
fi

# ---------- 4. Eliminar vhost Apache ----------
info "Eliminando VirtualHost Apache..."
if [[ -f /etc/apache2/sites-enabled/uptime-kuma.conf ]]; then
    a2dissite uptime-kuma.conf
    success "Sitio deshabilitado."
fi
if [[ -f /etc/apache2/sites-available/uptime-kuma.conf ]]; then
    rm -f /etc/apache2/sites-available/uptime-kuma.conf
    success "Archivo de VirtualHost eliminado."
else
    warn "VirtualHost no encontrado. Saltando."
fi

# ---------- 5. Reiniciar Apache ----------
info "Reiniciando Apache..."
if systemctl is-active --quiet apache2; then
    apache2ctl configtest && systemctl restart apache2
    success "Apache reiniciado."
else
    warn "Apache no está corriendo. Saltando reinicio."
fi

# ---------- 6. Limpiar logs ----------
info "Eliminando logs de Uptime Kuma..."
rm -f /var/log/apache2/uptime-kuma-error.log
rm -f /var/log/apache2/uptime-kuma-access.log
success "Logs eliminados."

# ---------- Resumen ----------
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  ✅  Desinstalación completada${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}  Docker y Apache siguen instalados en el sistema.${NC}"
echo -e "${YELLOW}  Si querés desinstalarlos también:${NC}"
echo -e "  ${CYAN}apt-get remove --purge docker-ce docker-ce-cli containerd.io${NC}"
echo -e "  ${CYAN}apt-get remove --purge apache2${NC}"
echo ""
}

menu(){
while true; do
clear
echo -e "${YELLOW}==== PANEL UPTIME KUMA DOCKER ==== ${NC}"
echo -e "${YELLOW}1)${CYAN} Instalar Uptime Kuma"
echo -e "${YELLOW}2)${CYAN} Crear VHost HTTPS"
echo -e "${YELLOW}3)${CYAN} Iniciar servicio"
echo -e "${YELLOW}4)${CYAN} Reiniciar servicio"
echo -e "${YELLOW}5)${CYAN} Detener servicio"
echo -e "${YELLOW}6)${CYAN} Ver estado"
echo -e "${YELLOW}7)${CYAN} Desinstalar TODO"
echo -e "${YELLOW}0)${YELLOW} Salir${NC}"

read -p "Seleccione: " op

case $op in
1) instalar_kuma ;;
2) crear_vhost ;;
3) start_kuma ;;
4) restart_kuma ;;
5) stop_kuma ;;
6) estado_kuma ;;
7) desinstalar_todo ;;
0) exit ;;
*) echo "Opción inválida" ;;
esac

pause
done
}

menu
