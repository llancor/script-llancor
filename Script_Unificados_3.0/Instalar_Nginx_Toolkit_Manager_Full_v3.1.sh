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
    shift
    local reservados=("$@")

    while true; do

        # evitar repetir puertos ya elegidos
        for r in "${reservados[@]}"; do
            if [ "$puerto" = "$r" ]; then
                puerto=$((puerto + 1))
                continue 2
            fi
        done

        # comprobar si está ocupado por sistema
        if lsof -iTCP:"$puerto" -sTCP:LISTEN -P -n >/dev/null 2>&1; then
            puerto=$((puerto + 1))
            continue
        fi

        # respaldo con ss
        if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${puerto}$"; then
            puerto=$((puerto + 1))
            continue
        fi

        # comprobar docker publicado
        if docker ps --format '{{.Ports}}' | grep -q ":${puerto}->"; then
            puerto=$((puerto + 1))
            continue
        fi

        echo "$puerto"
        return
    done
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

    IP=$(hostname -I | awk '{print $1}')
    NGINX_PORT=${NGINX_UI_PORT:-9000}

    SECRET=$(docker exec nginx-ui cat /etc/nginx-ui/.install_secret 2>/dev/null)

    echo
    echo -e "${GREEN}✔ Nginx UI instalado correctamente${RESET}"
    echo
    echo -e "${CYAN}IP del servidor:${RESET} ${YELLOW}${IP}${RESET}"
    echo -e "${CYAN}Puerto:${RESET} ${YELLOW}${NGINX_PORT}${RESET}"
    echo -e "${CYAN}Acceso web:${RESET} ${YELLOW}http://${IP}:${NGINX_PORT}${RESET}"

    if [ -z "$SECRET" ]; then
        echo
        echo -e "${RED}No se pudo obtener el Installation Secret.${RESET}"
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
PANEL_PORT=$(buscar_puerto_libre 81 "$HTTP_PORT")
HTTPS_PORT=$(buscar_puerto_libre 443 "$HTTP_PORT" "$PANEL_PORT")
	
    echo
    echo -e "${CYAN}Puertos detectados automáticamente:${RESET}"
    echo -e "HTTP  → ${YELLOW}${HTTP_PORT}${RESET}"
    echo -e "Panel → ${YELLOW}${PANEL_PORT}${RESET}"
    echo -e "HTTPS → ${YELLOW}${HTTPS_PORT}${RESET}"
    echo
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

# ==========================================================
# DESISNTALAR nginx-proxy-manager
# ==========================================================
desinstalar_npm() {
 docker rm -f nginx-proxy-manager 2>/dev/null
 rm -rf "$NPM_DIR"
 pause
}

# ==========================================================
# ESTADO nginx-proxy-manager
# ==========================================================

estado_npm() {
 docker ps | grep nginx-proxy-manager
 pause
}

# ==========================================================
# REINICIAR nginx-proxy-manager
# ==========================================================

reiniciar_npm() {
 docker restart nginx-proxy-manager
 pause
}

# ==========================================================
# REPARAR nginx-proxy-manager
# ==========================================================

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

# ==========================================================
# GENERAR PASWORDS
# ==========================================================

generar_password_segura() {
    openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 16
}

# ==========================================================
# REPARANDO SOCKET DOCKER NGINX UI
# ==========================================================

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

generar_installation_secret
}

# ==========================================================
# GENERADOR DE CONTRASEÑA SEGURA
# ==========================================================

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

# ==========================================================
# DESISNTALAR NGINX UI
# ==========================================================

desinstalar_nginx_ui() {
 docker rm -f nginx-ui 2>/dev/null
 docker volume rm nginx-ui-data 2>/dev/null
 pause
}

# ==========================================================
# ESTADO NGINX UI
# ==========================================================

estado_nginx_ui() {
 docker ps | grep nginx-ui
 pause
}

# ==========================================================
# REINICIAR NGINX UI
# ==========================================================

reiniciar_nginx_ui() {
 docker restart nginx-ui
 pause
}
# ==========================================================
# BLOQUEAR PUERTO 80
# ==========================================================
bloquear_http() {

    header "BLOQUEAR PUERTO 80"

    if iptables -C DOCKER-USER -p tcp --dport 80 -j DROP 2>/dev/null; then
        echo -e "${YELLOW}El puerto 80 ya está bloqueado${RESET}"
        pause
        return
    fi

    iptables -I DOCKER-USER -p tcp --dport 80 -j DROP

    echo
    echo -e "${GREEN}✔ Puerto 80 bloqueado correctamente${RESET}"
    echo

    pause
}

# ==========================================================
# DESBLOQUEAR PUERTO 80
# ==========================================================
desbloquear_http() {

    header "DESBLOQUEAR PUERTO 80"

    if ! iptables -C DOCKER-USER -p tcp --dport 80 -j DROP 2>/dev/null; then
        echo -e "${YELLOW}El puerto 80 ya está desbloqueado${RESET}"
        pause
        return
    fi

    iptables -D DOCKER-USER -p tcp --dport 80 -j DROP

    echo
    echo -e "${GREEN}✔ Puerto 80 desbloqueado correctamente${RESET}"
    echo

    pause
}
# ==========================================================
# ESTADO PUERTO 80
# ==========================================================
estado_http() {

    header "ESTADO PUERTO 80"

    if iptables -C DOCKER-USER -p tcp --dport 80 -j DROP 2>/dev/null; then
        echo -e "${RED}BLOQUEADO${RESET}"
    else
        echo -e "${GREEN}ABIERTO${RESET}"
    fi

    echo
    iptables -L DOCKER-USER -n --line-numbers | grep 80

    pause
}
# ==========================================================
# EXPORTAR DOCKER MIGRADO NPM 
# ==========================================================
backup_npm() {

    STACK_DIR="/opt/nginx-proxy-manager"

    if [ ! -d "$STACK_DIR" ]; then
        echo "❌ No existe $STACK_DIR"
        read -rp "Presiona ENTER para continuar..."
        return 1
    fi

    mkdir -p /root/backup_nginx_docker

    BACKUP_FILE="/root/backup_nginx_docker/nginx-proxy-manager_$(date +%F_%H%M).tar.gz"

    echo
    echo "📦 Creando backup de Nginx Proxy Manager..."
    echo

    tar -czpf "$BACKUP_FILE" \
        -C /opt \
        nginx-proxy-manager

    if [ $? -ne 0 ]; then
        echo
        echo "❌ Error al crear el backup"
        read -rp "Presiona ENTER para continuar..."
        return 1
    fi

    BACKUP_SIZE=$(du -h "$BACKUP_FILE" 2>/dev/null | awk '{print $1}')
    BACKUP_FILES=$(tar -tzf "$BACKUP_FILE" 2>/dev/null | wc -l)
    BACKUP_DATE=$(date '+%Y-%m-%d %H:%M:%S')

    DB_FILE="/opt/nginx-proxy-manager/data/database.sqlite"

    HOSTS="N/D"
    USERS="N/D"
    CERTS="N/D"

    if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB_FILE" ]; then

        HOSTS=$(sqlite3 "$DB_FILE" "select count(*) from proxy_host;" 2>/dev/null)
        USERS=$(sqlite3 "$DB_FILE" "select count(*) from user;" 2>/dev/null)
        CERTS=$(sqlite3 "$DB_FILE" "select count(*) from certificate;" 2>/dev/null)

    fi

    echo
    echo "=================================================="
    echo "✅ BACKUP COMPLETADO"
    echo "=================================================="
    echo "📦 Archivo        : $(basename "$BACKUP_FILE")"
    echo "📂 Ruta           : $BACKUP_FILE"
    echo "💾 Tamaño         : $BACKUP_SIZE"
    echo "📄 Archivos       : $BACKUP_FILES"
    echo "🕒 Fecha          : $BACKUP_DATE"
    echo "--------------------------------------------------"
    echo "👤 Usuarios       : $USERS"
    echo "🌐 Proxy Hosts    : $HOSTS"
    echo "🔐 Certificados   : $CERTS"
    echo "=================================================="
    echo
    echo "📁 Los backups se almacenan en:"
    echo "   /root/backup_nginx_docker"
    echo

    read -rp "Presiona ENTER para continuar..."
}
# ==========================================================
# IMPORTAR DOCKER MIGRADO NPM 
# ==========================================================
restore_npm() {

    echo
    echo "🔎 Backups disponibles"
    echo "================================"

    BACKUPS=()
    i=1

    while IFS= read -r file; do
        BACKUPS+=("$file")
        echo "[$i] $(basename "$file")"
        ((i++))
    done < <(find /root/backup_nginx_docker -type f -name "nginx-proxy-manager*.tar.gz" 2>/dev/null)

    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo "❌ No se encontraron backups en /root/backup_nginx_docker"
        read -rp "ENTER para continuar..."
        return 1
    fi

    echo
    read -rp "Selecciona backup: " opcion

    BACKUP_FILE="${BACKUPS[$((opcion-1))]}"

    if [ ! -f "$BACKUP_FILE" ]; then
        echo "❌ Opción inválida"
        read -rp "ENTER para continuar..."
        return 1
    fi

    echo
    echo "📦 Backup seleccionado:"
    echo "$BACKUP_FILE"
    echo

    read -rp "⚠️ Se eliminará la instalación actual de NPM. ¿Continuar? (s/N): " CONFIRM

    case "$CONFIRM" in
        s|S|si|SI|Si) ;;
        *)
            echo "❌ Operación cancelada"
            read -rp "ENTER para continuar..."
            return 0
            ;;
    esac

    echo
    echo "🛑 Deteniendo instalación actual..."

    if [ -f /opt/nginx-proxy-manager/docker-compose.yml ]; then

        if docker compose version >/dev/null 2>&1; then
            docker compose -f /opt/nginx-proxy-manager/docker-compose.yml down
        elif command -v docker-compose >/dev/null 2>&1; then
            docker-compose -f /opt/nginx-proxy-manager/docker-compose.yml down
        fi

    fi

    echo "🗑️ Eliminando instalación actual..."
    rm -rf /opt/nginx-proxy-manager

    echo
    echo "📥 Restaurando backup..."

    tar -xzpf "$BACKUP_FILE" -C /opt

    if [ ! -f /opt/nginx-proxy-manager/docker-compose.yml ]; then
        echo "❌ Error: docker-compose.yml no encontrado"
        read -rp "ENTER para continuar..."
        return 1
    fi

    echo
    echo "🚀 Iniciando Nginx Proxy Manager..."

    if docker compose version >/dev/null 2>&1; then
        docker compose -f /opt/nginx-proxy-manager/docker-compose.yml up -d
    else
        docker-compose -f /opt/nginx-proxy-manager/docker-compose.yml up -d
    fi

    echo
    echo "⏳ Esperando inicio de servicios..."
    sleep 10

    DB_FILE="/opt/nginx-proxy-manager/data/database.sqlite"

    HOSTS="N/D"
    USERS="N/D"
    CERTS="N/D"

    if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB_FILE" ]; then

        HOSTS=$(sqlite3 "$DB_FILE" "select count(*) from proxy_host;" 2>/dev/null)
        USERS=$(sqlite3 "$DB_FILE" "select count(*) from user;" 2>/dev/null)
        CERTS=$(sqlite3 "$DB_FILE" "select count(*) from certificate;" 2>/dev/null)

    fi

    CONTAINER_STATUS=$(docker ps \
        --filter "name=nginx-proxy-manager" \
        --format "{{.Status}}" | head -n1)

    [ -z "$CONTAINER_STATUS" ] && CONTAINER_STATUS="No encontrado"

    SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" 2>/dev/null | awk '{print $1}')
    RESTORE_DATE=$(date '+%Y-%m-%d %H:%M:%S')

    echo
    echo "=================================================="
    echo "✅ RESTAURACIÓN COMPLETADA"
    echo "=================================================="
    echo "📦 Backup restaurado : $(basename "$BACKUP_FILE")"
    echo "📂 Ruta backup      : $BACKUP_FILE"
    echo "📂 Ruta restaurada  : /opt/nginx-proxy-manager"
    echo "💾 Tamaño backup    : $BACKUP_SIZE"
    echo "🐳 Estado Docker    : $CONTAINER_STATUS"
    echo "🕒 Fecha            : $RESTORE_DATE"
    echo "--------------------------------------------------"
    echo "👤 Usuarios         : $USERS"
    echo "🌐 Proxy Hosts      : $HOSTS"
    echo "🔐 Certificados     : $CERTS"
    echo "--------------------------------------------------"
    echo "🌍 Panel NPM:"
    echo "http://${SERVER_IP}:81"
    echo "=================================================="
    echo
    echo "⚠️ IMPORTANTE:"
    echo "   Después de restaurar:"
    echo "   1. Cierra sesión en NPM"
    echo "   2. Vuelve a iniciar sesión"
    echo "   3. Si sigue igual, usa modo incógnito"
    echo

    read -rp "Presiona ENTER para continuar..."
}
# BACKUP RESTORE AJUSTES DE NPM DOCKER Y DOCKER COMPOSE # 
backup_restore_all() {

    BACKUP_DIR="/root/backup_ajustes_nginx"
    mkdir -p "$BACKUP_DIR"

    detect_container() {
        CONTAINER=$(docker ps -a --format "{{.Names}}" | grep -Ei "npm|proxy|nginx" | head -n 1)

        if [ -z "$CONTAINER" ]; then
            echo "❌ No se encontró Nginx Proxy Manager en este servidor"
            docker ps -a
            return 1
        fi

        echo "✅ Usando contenedor: $CONTAINER"
    }

    get_volumes() {
        docker inspect "$CONTAINER" 2>/dev/null \
            | grep -A 20 Mounts \
            | grep Source \
            | awk -F '"' '{print $4}'
    }

    while true; do
        clear

        echo -e "${CYAN}==============================${RESET}"
        echo -e "${CYAN}   NGINX PROXY MANAGER AUTO${RESET}"
        echo -e "${CYAN}==============================${RESET}"
        echo -e "${YELLOW}1)${RESET} 📦 Backup"
        echo -e "${YELLOW}2)${RESET} 📥 Restore"
        echo -e "${YELLOW}3)${RESET} 🔄 Update"
        echo -e "${YELLOW}4)${RESET} 📊 Status"
        echo -e "${YELLOW}0)${RESET} ⬅ Salir"
        echo -e "${CYAN}==============================${RESET}"

        read -rp "Opción: " opt

        case $opt in

            1)
                clear
                echo "📦 BACKUP NPM"

                detect_container || continue

                DATE=$(date +%Y-%m-%d_%H-%M)
                TMP="/tmp/npm_backup_$DATE"
                FILE="$BACKUP_DIR/npm_backup_$DATE.tar.gz"

                mkdir -p "$TMP"

                echo "⏸ Deteniendo $CONTAINER..."
                docker stop "$CONTAINER"

                echo "📁 Copiando volúmenes..."

                for V in $(get_volumes); do
                    NAME=$(basename "$V")
                    mkdir -p "$TMP/$NAME"
                    cp -a "$V/." "$TMP/$NAME/" 2>/dev/null || true
                done

                echo "▶️ Iniciando $CONTAINER..."
                docker start "$CONTAINER"

                tar -czf "$FILE" -C "$TMP" .
                rm -rf "$TMP"

                echo "✅ Backup creado:"
                echo "$FILE"
                read -rp "ENTER..."
                ;;

            2)
                clear
                echo "📥 RESTORE"

                detect_container || continue

                echo
                echo "📁 Backups disponibles:"
                echo

                mapfile -t BACKUPS < <(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null)

                if [ ${#BACKUPS[@]} -eq 0 ]; then
                    echo "❌ No hay backups"
                    read -rp "ENTER..."
                    continue
                fi

                i=1
                for b in "${BACKUPS[@]}"; do
                    echo "$i) $(basename "$b")"
                    ((i++))
                done

                echo
                read -rp "Selecciona backup: " sel

                FILE="${BACKUPS[$((sel-1))]}"

                if [ ! -f "$FILE" ]; then
                    echo "❌ Backup inválido"
                    read -rp "ENTER..."
                    continue
                fi

                TMP="/tmp/npm_restore"
                mkdir -p "$TMP"

                tar -xzf "$FILE" -C "$TMP"

                echo "⏸ Deteniendo $CONTAINER..."
                docker stop "$CONTAINER"

                for V in $(get_volumes); do
                    NAME=$(basename "$V")
                    echo " - restaurando $NAME"
                    rm -rf "$V"/*
                    cp -a "$TMP/$NAME/." "$V/" 2>/dev/null || true
                done

                docker start "$CONTAINER"

                rm -rf "$TMP"

                echo "✅ Restore completado"
                read -rp "ENTER..."
                ;;

            3)
                clear
                echo "🔄 UPDATE NPM"

                detect_container || continue

                echo "📦 Backup antes de update..."
                $FUNCNAME 1 2>/dev/null

                echo "📥 Pull imagen..."
                docker pull jc21/nginx-proxy-manager:latest

                echo "🔄 Reiniciando..."
                docker restart "$CONTAINER"

                echo "✅ Update completado"
                read -rp "ENTER..."
                ;;

            4)
                clear
                echo "📊 STATUS"

                detect_container || continue

                docker ps -a | grep "$CONTAINER"

                read -rp "ENTER..."
                ;;

            0)
                break
                ;;

            *)
                echo "❌ Opción inválida"
                sleep 1
                ;;
        esac
    done
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

echo -e "${YELLOW}1)${CYAN} Instalar"
echo -e "${YELLOW}2)${RED} Desinstalar"
echo -e "${YELLOW}3)${RESET} Ver estado"
echo -e "${YELLOW}4)${RESET} Reiniciar"
echo -e "${YELLOW}5)${RESET} Bloquear puerto 80"
echo -e "${YELLOW}6)${RESET} Desbloquear puerto 80"
echo -e "${YELLOW}7)${RESET} Estado puerto 80"
echo -e "${YELLOW}8)${CYAN} Respadar/Restaurar Ajustes Nginx"
echo -e "${YELLOW}9)${GREEN} 📤 Exportar migración Docker NPM"
echo -e "${YELLOW}10)${RED} 📥 Importar migración Docker NPM"
echo -e "${YELLOW}0)${RESET} Volver"

echo
read -p "Selecciona una opción: " op

case $op in
1) instalar_npm ;;
2) desinstalar_npm ;;
3) estado_npm ;;
4) reiniciar_npm ;;
5) bloquear_http ;;
6) desbloquear_http ;;
7) estado_http ;;
8) backup_restore_all ;;
9) backup_npm ;;
10) restore_npm ;;
0) break ;;
esac

done
}

# ==========================================================
# MENU PRINCIPAL
# ==========================================================

while true; do

header "* INSTALADOR Y GESTOR NGINX v3.1 / SISTEMA DE RESPALDO *"

echo -e "${YELLOW}1)${CYAN} Gestión Nginx Proxy Manager"
echo -e "${YELLOW}2)${CYAN} Gestión Nginx UI"
echo -e "${YELLOW}3)${GREEN} Verificar dependencias"
echo -e "${YELLOW}0)${CYAN} Salir"

echo
read -p "Selecciona una opción: " opcion

case $opcion in
1) menu_npm ;;
2) menu_nginx_ui ;;
3) verificar_dependencias ;;
0) exit ;;
esac

done