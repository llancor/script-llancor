#!/bin/bash

# ==========================================================
#   GESTOR NGINX UI + NGINX PROXY MANAGER
# ==========================================================

RESET='\033[0m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
WHITE='\033[1;37m'

NPM_DIR="/opt/nginx-proxy-manager"

pause() {
  echo
  read -p "Presiona ENTER para continuar..."
}

header() {
  clear
  echo
  echo -e "${CYAN}═══════════════════════════════════════════════${RESET}"
  echo -e "${CYAN}$1${RESET}"
  echo -e "${CYAN}═══════════════════════════════════════════════${RESET}"
  echo
}
# ==========================================================
# buscar puertos
# ==========================================================
buscar_puerto_libre() {
    local puerto=$1

    while ss -ltn "( sport = :$puerto )" | grep -q ":$puerto"; do
        puerto=$((puerto + 1))
    done

    echo "$puerto"
}

# ==========================================================
# DEPENDENCIAS
# ==========================================================
verificar_dependencias() {

header "VERIFICANDO DEPENDENCIAS"

DEPENDENCIAS=(
  sudo
  curl
  wget
  docker.io
  ca-certificates
  gnupg
  lsb-release
  apparmor
  apparmor-utils
  openssl
)

OK=()
NEW=()
FAIL=()

echo
echo -e "${CYAN}Actualizando repositorios...${RESET}"
apt update

echo

for pkg in "${DEPENDENCIAS[@]}"; do

    echo -e "${WHITE}Revisando:${RESET} ${YELLOW}$pkg${RESET}"

    if dpkg -s "$pkg" >/dev/null 2>&1; then
        OK+=("$pkg")
        echo -e "${GREEN}✔ Ya está instalado${RESET}"
    else
        echo -e "${YELLOW}→ Instalando $pkg...${RESET}"

        if apt install -y "$pkg"; then
            NEW+=("$pkg")
            echo -e "${GREEN}✔ Instalado correctamente${RESET}"
        else
            FAIL+=("$pkg")
            echo -e "${RED}✘ No se pudo instalar${RESET}"
        fi
    fi

    echo
done

# ==========================================================
# VERIFICAR DOCKER COMPOSE
# ==========================================================

echo -e "${WHITE}Revisando:${RESET} ${YELLOW}docker compose${RESET}"

if docker compose version >/dev/null 2>&1; then

    OK+=("docker compose plugin")
    echo -e "${GREEN}✔ Docker Compose Plugin instalado${RESET}"

elif command -v docker-compose >/dev/null 2>&1; then

    OK+=("docker-compose")
    echo -e "${GREEN}✔ docker-compose instalado${RESET}"

else

    echo -e "${YELLOW}→ Instalando docker-compose...${RESET}"

    if apt install -y docker-compose; then
        NEW+=("docker-compose")
        echo -e "${GREEN}✔ docker-compose instalado correctamente${RESET}"
    else
        FAIL+=("docker-compose")
        echo -e "${RED}✘ No se pudo instalar docker-compose${RESET}"
    fi
fi

echo
echo -e "${CYAN}Reiniciando Docker...${RESET}"
systemctl enable docker >/dev/null 2>&1
systemctl restart docker >/dev/null 2>&1

echo
echo -e "${CYAN}════════════════════════════════════${RESET}"
echo -e "${CYAN}RESUMEN FINAL${RESET}"
echo -e "${CYAN}════════════════════════════════════${RESET}"

echo
echo -e "${GREEN}Ya instaladas:${RESET}"
for i in "${OK[@]}"; do
  echo "  ✔ $i"
done

echo
echo -e "${GREEN}Instaladas por el script:${RESET}"
for i in "${NEW[@]}"; do
  echo "  ✔ $i"
done

if [ ${#FAIL[@]} -gt 0 ]; then
  echo
  echo -e "${RED}No se pudieron instalar:${RESET}"
  for i in "${FAIL[@]}"; do
    echo "  ✘ $i"
  done
fi

pause
}

# ==========================================================
# CORREGIR sites-enabled NGINX
# ==========================================================
corregir_sites_enabled() {

    header "CORRIGIENDO SITES-ENABLED"

    CONTAINER=$(docker ps --format "{{.Names}}" | grep nginx-ui | head -n1)

    if [ -z "$CONTAINER" ]; then
        echo -e "${RED}✘ No se encontró contenedor nginx-ui activo${RESET}"
        pause
        return
    fi

    echo -e "${CYAN}Contenedor detectado:${RESET} $CONTAINER"
    echo

    docker exec "$CONTAINER" sh -c '
        mkdir -p /etc/nginx/sites-available
        mkdir -p /etc/nginx/sites-enabled

        if [ -f /etc/nginx/nginx.conf ]; then

            grep -q "include /etc/nginx/sites-enabled/\*;" /etc/nginx/nginx.conf || \
            sed -i "/http {/a\\    include /etc/nginx/sites-enabled/*;" /etc/nginx/nginx.conf

            nginx -t && nginx -s reload
        fi
    '

    echo
    echo -e "${GREEN}✔ Corrección aplicada dentro del contenedor${RESET}"

    pause
}
# ==========================================================
# Installation Secret (Nginx UI)
# ==========================================================

generar_installation_secret() {

    header "INSTALLATION SECRET NGINX UI"

    if ! docker ps -a --format '{{.Names}}' | grep -q '^nginx-ui$'; then
        echo -e "${RED}nginx-ui no está instalado.${RESET}"
        pause
        return
    fi

    SECRET=$(docker exec nginx-ui cat /etc/nginx-ui/.install_secret 2>/dev/null)

    if [ -z "$SECRET" ]; then
        echo -e "${RED}No se pudo obtener el Installation Secret.${RESET}"
        echo
        echo -e "${YELLOW}Verifica que el contenedor nginx-ui esté iniciado.${RESET}"
    else
        echo
        echo -e "${GREEN}Installation Secret:${RESET}"
        echo
        echo -e "${YELLOW}${SECRET}${RESET}"
        echo
        echo -e "${WHITE}Cópialo y pégalo en la pantalla inicial de Nginx UI.${RESET}"
    fi

    pause
}
# ==========================================================
# PUERTOS
# ==========================================================

definir_puertos() {

    HTTP_PORT=$(buscar_puerto_libre 80)
    PANEL_PORT=$(buscar_puerto_libre 81)
    HTTPS_PORT=$(buscar_puerto_libre 443)

    echo
    echo -e "${CYAN}Puertos seleccionados:${RESET}"
    echo "HTTP : ${HTTP_PORT}"
    echo "Panel: ${PANEL_PORT}"
    echo "HTTPS: ${HTTPS_PORT}"
    echo
}
# ==========================================================
# NGINX PROXY MANAGER
# ==========================================================
instalar_npm() {

    verificar_dependencias

    header "INSTALANDO NGINX PROXY MANAGER"

    if command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    elif docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        echo -e "${RED}Docker Compose no está instalado${RESET}"
        pause
        return
    fi

    HTTP_PORT=$(buscar_puerto_libre 80)
    PANEL_PORT=$(buscar_puerto_libre 81)
    HTTPS_PORT=$(buscar_puerto_libre 443)

    mkdir -p "$NPM_DIR"
    cd "$NPM_DIR" || return

    mkdir -p data
    mkdir -p letsencrypt

    $COMPOSE_CMD down 2>/dev/null || true
    docker rm -f nginx-proxy-manager 2>/dev/null || true

cat > docker-compose.yml <<EOF
version: '3'

services:
  app:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped

    ports:
      - "${HTTP_PORT}:80"
      - "${PANEL_PORT}:81"
      - "${HTTPS_PORT}:443"

    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF

    echo
    echo -e "${CYAN}Descargando imagen...${RESET}"
    $COMPOSE_CMD pull

    echo
    echo -e "${CYAN}Levantando contenedor...${RESET}"
    $COMPOSE_CMD up -d

    sleep 10

    if docker ps --format '{{.Names}}' | grep -q '^nginx-proxy-manager$'; then

        IP=$(hostname -I | awk '{print $1}')

        echo
        echo -e "${GREEN}✔ Nginx Proxy Manager instalado correctamente${RESET}"
        echo
        echo -e "${YELLOW}Panel:${RESET}"
        echo "http://${IP}:${PANEL_PORT}"
        echo
        echo "Usuario: admin@example.com"
        echo "Clave: changeme"
        echo
        echo "HTTP : ${HTTP_PORT}"
        echo "HTTPS: ${HTTPS_PORT}"

    else

        echo
        echo -e "${RED}✘ No pudo iniciarse Nginx Proxy Manager${RESET}"
        echo
        $COMPOSE_CMD logs --tail 50

    fi

    pause
}

desinstalar_npm() {
 docker rm -f nginx-proxy-manager 2>/dev/null
 rm -rf "$NPM_DIR"
 pause
}

estado_npm() {
 docker ps | grep nginx-proxy-manager
 pause
}

reiniciar_npm() {
 docker restart nginx-proxy-manager
 pause
}
reparar_nginx_ui_conf() {

    header "REPARANDO NGINX.CONF"

    mkdir -p /etc/nginx/conf.d
    mkdir -p /etc/nginx/sites-enabled
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/streams-enabled
    mkdir -p /etc/nginx/streams-available

cat >/etc/nginx/nginx.conf <<'EOF'
user root;
worker_processes auto;

events {
    worker_connections 1024;
}

http {

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    sendfile on;
    keepalive_timeout 65;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}

stream {
    include /etc/nginx/streams-enabled/*;
}
EOF

    echo
    echo -e "${GREEN}✔ nginx.conf recreado${RESET}"

    docker restart nginx-ui 2>/dev/null || true

    echo
    echo -e "${GREEN}✔ nginx-ui reiniciado${RESET}"

    pause
}

generar_password_segura() {
    openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 16
}

reparar_socket_nginx_ui() {

    header "REPARANDO SOCKET DOCKER NGINX UI"

    docker rm -f nginx-ui 2>/dev/null || true

    mkdir -p /etc/nginx
    mkdir -p /var/www

    if [ -S /var/run/docker.sock ]; then
        SOCKET="/var/run/docker.sock"
    elif [ -S /run/docker.sock ]; then
        SOCKET="/run/docker.sock"
    else
        echo -e "${RED}✘ No se encontró docker.sock en el host${RESET}"
        pause
        return
    fi

    echo -e "${CYAN}Socket detectado:${RESET} $SOCKET"

    docker run -d \
      --name nginx-ui \
      --restart unless-stopped \
      -p ${NGINX_UI_PORT:-9000}:9000 \
      -v /etc/nginx:/etc/nginx \
      -v /var/www:/var/www \
      -v ${SOCKET}:/var/run/docker.sock \
      --privileged \
      -e TZ=America/Santiago \
      -e NGINX_UI_IGNORE_DOCKER_SOCKET=false \
      uozi/nginx-ui:latest

    echo
    echo -e "${GREEN}✔ nginx-ui recreado${RESET}"
    echo

    docker exec nginx-ui ls -lah /var/run/docker.sock

    pause
	
}
# ==========================================================
# NGINX UI
# ==========================================================
instalar_nginx_ui() {

    verificar_dependencias

    header "INSTALANDO NGINX UI"

    docker rm -f nginx-ui 2>/dev/null || true

    mkdir -p /etc/nginx
    mkdir -p /etc/nginx/conf.d
    mkdir -p /etc/nginx/sites-enabled
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/streams-enabled
    mkdir -p /etc/nginx/streams-available
    mkdir -p /var/www

    echo
    echo -e "${CYAN}Preparando configuración de Nginx...${RESET}"

cat >/etc/nginx/mime.types <<'EOF'
types {
    text/html                             html htm shtml;
    text/css                              css;
    application/javascript                js;
    application/json                      json;
    text/xml                              xml;
    image/gif                             gif;
    image/jpeg                            jpeg jpg;
    image/png                             png;
    image/svg+xml                         svg;
    image/x-icon                          ico;
    application/octet-stream              bin exe dll;
}
EOF

cat >/etc/nginx/nginx.conf <<'EOF'
user root;
worker_processes auto;

events {
    worker_connections 1024;
}

http {

    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}

stream {
    include /etc/nginx/streams-enabled/*;
}
EOF

cat >/etc/nginx/conf.d/status.conf <<'EOF'
server {
    listen 127.0.0.1:8080;
    server_name localhost;

    location /nginx_status {
        stub_status;
        access_log off;

        allow 127.0.0.1;
        allow ::1;
        deny all;
    }
}
EOF

    docker run -d \
        --name nginx-ui \
        --restart unless-stopped \
        -p ${NGINX_UI_PORT:-9000}:9000 \
        -v /etc/nginx:/etc/nginx \
        -v /var/www:/var/www \
        -v /var/run/docker.sock:/var/run/docker.sock \
        --privileged \
        -e TZ=America/Santiago \
        uozi/nginx-ui:latest

    echo
    echo -e "${CYAN}Esperando inicio del contenedor...${RESET}"
    sleep 8

    echo
    echo -e "${CYAN}Validando nginx...${RESET}"

    if docker exec nginx-ui nginx -t; then

        docker exec nginx-ui nginx -s reload >/dev/null 2>&1 || \
        docker exec nginx-ui nginx >/dev/null 2>&1

        echo -e "${GREEN}✔ nginx iniciado correctamente${RESET}"

        echo
        echo -e "${CYAN}Verificando stub_status...${RESET}"

        docker exec nginx-ui curl -s http://127.0.0.1:8080/nginx_status || true

    else

        echo -e "${RED}✘ error validando nginx${RESET}"
        docker logs nginx-ui --tail 50

    fi

    echo
    echo -e "${GREEN}✔ Nginx UI instalado correctamente${RESET}"
    echo -e "${YELLOW}URL:${RESET} http://IP_DEL_SERVIDOR:${NGINX_UI_PORT:-9000}"
    echo

    pause
    generar_installation_secret
}


mostrar_password_segura() {

header "GENERADOR DE CONTRASEÑA SEGURA"

PASS=$(generar_password_segura)

echo
echo -e "${GREEN}Contraseña generada:${RESET}"
echo
echo -e "${YELLOW}${PASS}${RESET}"
echo

pause
}

desinstalar_nginx_ui() {
 docker rm -f nginx-ui 2>/dev/null
 docker volume rm nginx-ui-data 2>/dev/null
 pause
}

estado_nginx_ui() {
 docker ps | grep nginx-ui
 pause
}

reiniciar_nginx_ui() {
 docker restart nginx-ui
 pause
}

# ==========================================================
# MENUS
# ==========================================================

menu_nginx_ui() {

while true; do

header "GESTIÓN NGINX UI"

echo -e "${YELLOW}1)${RESET} Instalar"
echo -e "${YELLOW}2)${RESET} Desinstalar"
echo -e "${YELLOW}3)${RESET} Ver estado"
echo -e "${YELLOW}4)${RESET} Reiniciar"
echo -e "${YELLOW}5)${RESET} Generar contraseña Installation Secret (Nginx UI)"
echo -e "${YELLOW}6)${RESET} Corregir sites-enabled"
echo -e "${YELLOW}0)${RESET} Volver"

echo
read -p "Selecciona una opción: " op

case $op in
1) instalar_nginx_ui ;;
2) desinstalar_nginx_ui ;;
3) estado_nginx_ui ;;
4) reiniciar_nginx_ui ;;
5) generar_installation_secret ;;
6) corregir_sites_enabled ;;
0) break ;;
esac

done
}

menu_npm() {

while true; do

header "GESTIÓN NGINX PROXY MANAGER"

echo -e "${YELLOW}1)${RESET} Instalar"
echo -e "${YELLOW}2)${RESET} Desinstalar"
echo -e "${YELLOW}3)${RESET} Ver estado"
echo -e "${YELLOW}4)${RESET} Reiniciar"
echo -e "${YELLOW}0)${RESET} Volver"

echo
read -p "Selecciona una opción: " op

case $op in
1) instalar_npm ;;
2) desinstalar_npm ;;
3) estado_npm ;;
4) reiniciar_npm ;;
0) break ;;
esac

done
}

# ==========================================================
# MENU PRINCIPAL
# ==========================================================

while true; do

header "MENU GESTOR NGINX v2.3"

echo -e "${YELLOW}1)${RESET} Verificar dependencias"
echo -e "${YELLOW}2)${RESET} Gestión Nginx UI"
echo -e "${YELLOW}3)${RESET} Gestión Nginx Proxy Manager"
echo -e "${YELLOW}0)${RESET} Salir"

echo
read -p "Selecciona una opción: " opcion

case $opcion in
1) verificar_dependencias ;;
2) menu_nginx_ui ;;
3) menu_npm ;;
0) exit ;;
esac

done
