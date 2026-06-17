#!/bin/bash
set -e

# =========================================================
# BASE
# =========================================================

BASE_DIR="/opt/wordpress"
SITES_DIR="$BASE_DIR/sites"
BACKUP_DIR="$BASE_DIR/backups"
PHP_DIR="$BASE_DIR/php"
DATA_DIR="$BASE_DIR/data"
CONFIG_DIR="$BASE_DIR/config"

mkdir -p "$SITES_DIR" "$BACKUP_DIR" "$PHP_DIR" "$DATA_DIR" "$CONFIG_DIR"

# =========================================================
# COLORES
# =========================================================
CYAN='\033[1;36m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
ORANGE='\033[38;5;208m'
RED='\033[1;31m'
RESET='\033[0m'

# =========================================================
# DOCKER COMPOSE COMPATIBLE (FIX CLAVE)
# =========================================================

if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE=""
fi

# =========================================================
# UI
# =========================================================

header() {
clear
echo -e "${CYAN}"
echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN}     WORDPRESS MANAGER DOCKER v4.1     ${RESET}"
echo -e "${CYAN}========================================${RESET}"
echo -e "${RESET}"
}

pause() {
read -rp "Presione ENTER para continuar..."
}

# =========================================================
# DEPENDENCIAS
# =========================================================

instalar_dependencias() {

    echo "Verificando dependencias..."

    if ! command -v docker >/dev/null 2>&1; then

        echo "Instalando Docker..."

        apt update
        apt install -y curl wget nano unzip tar openssl ca-certificates

        curl -fsSL https://get.docker.com | sh

        systemctl enable docker
        systemctl start docker
    else
        echo "Docker ya está instalado."
    fi

    # Docker Compose v2 plugin (CORREGIDO)
    if docker compose version >/dev/null 2>&1; then
        echo "Docker Compose v2 OK"
    else
        echo "Instalando Docker Compose plugin..."

        mkdir -p /usr/local/lib/docker/cli-plugins

        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f4)

        curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" \
            -o /usr/local/lib/docker/cli-plugins/docker-compose

        chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    fi

    chmod 700 "$CONFIG_DIR" "$BACKUP_DIR"
    touch "$CONFIG_DIR/sites.db"
}

# =========================================================
# PHP CONFIG
# =========================================================

crear_php_ini() {

mkdir -p "$PHP_DIR"

cat > "$PHP_DIR/uploads.ini" <<EOF
upload_max_filesize = 2048M
post_max_size = 2048M
max_file_uploads = 200

memory_limit = 1024M
max_execution_time = 600
max_input_time = 600
max_input_vars = 10000

opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=20000

realpath_cache_size=4096K
realpath_cache_ttl=600

expose_php=Off
cgi.fix_pathinfo=0

date.timezone=America/Santiago
EOF

chmod 644 "$PHP_DIR/uploads.ini"
}

# =========================================================
# MARIADB STACK (FIX HEALTHCHECK + COMPOSE)
# =========================================================

crear_stack_mariadb() {

    mkdir -p "$DATA_DIR"

    if docker ps --format '{{.Names}}' | grep -q '^wordpress-db$'; then
        echo "MariaDB ya está funcionando."
        return
    fi

    if docker ps -a --format '{{.Names}}' | grep -q '^wordpress-db$'; then
        echo "Iniciando MariaDB existente..."
        docker start wordpress-db
        return
    fi

    echo "Creando MariaDB..."

    DB_ROOT_PASS=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24)
    echo "$DB_ROOT_PASS" > "$CONFIG_DIR/mysql_root_password"
    chmod 600 "$CONFIG_DIR/mysql_root_password"

cat > "$BASE_DIR/docker-compose.yml" <<EOF
services:

  mariadb:
    image: mariadb:11
    container_name: wordpress-db
    restart: unless-stopped

    command:
      - --max_allowed_packet=1024M
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci

    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASS}
      TZ: America/Santiago

    volumes:
      - ${DATA_DIR}:/var/lib/mysql

    healthcheck:
      test: ["CMD", "mariadb-admin", "ping", "-uroot", "-p${DB_ROOT_PASS}"]
      interval: 10s
      timeout: 5s
      retries: 10

    networks:
      - wordpress

networks:
  wordpress:
    name: wordpress
EOF

    cd "$BASE_DIR"
    $DOCKER_COMPOSE up -d

    echo "Esperando MariaDB..."

    until docker exec wordpress-db mariadb-admin ping -uroot -p"$DB_ROOT_PASS" >/dev/null 2>&1; do
        sleep 2
    done

    echo "MariaDB lista."
}

# =========================================================
# INSTALACIÓN INICIAL
# =========================================================

instalacion_inicial() {

    header

    echo "INSTALACIÓN INICIAL WORDPRESS MANAGER"

    instalar_dependencias
    crear_php_ini
    crear_stack_mariadb

    echo "Instalación completada."
    pause
}
# =========================================================
# MYSQL ROOT PASSWORD
# =========================================================

obtener_mysql_root() {

    local PASS_FILE="$CONFIG_DIR/mysql_root_password"

    if [ ! -f "$PASS_FILE" ]; then
        echo "ERROR: No existe password MySQL" >&2
        return 1
    fi

    tr -d '\r\n' < "$PASS_FILE"
}

# =========================================================
# PUERTO SEGURO
# =========================================================

puerto_libre() {

    local PUERTO=8081

    while ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$PUERTO$"; do
        PUERTO=$((PUERTO + 1))
    done

    echo "$PUERTO"
}

# =========================================================
# SIGUIENTE WP INDEX
# =========================================================

obtener_siguiente_wp() {

    if [ ! -f "$CONFIG_DIR/sites.db" ]; then
        echo 1
        return
    fi

    awk -F'|' '$1 ~ /^wordpress[0-9]+$/ {
        gsub("wordpress","",$1)
        print $1
    }' "$CONFIG_DIR/sites.db" | sort -n | tail -1 | awk '{print $1+1}'
}

# =========================================================
# CREAR WORDPRESS (FIX COMPLETO)
# =========================================================

crear_wordpress() {

    header

    NUMERO=$(wc -l < "$CONFIG_DIR/sites.db" 2>/dev/null || echo 0)
    NUMERO=$((NUMERO + 1))

    SITIO="wordpress${NUMERO}"
    PUERTO=$(puerto_libre)

    DB_NAME="wp${NUMERO}"
    DB_USER="wp${NUMERO}"
    DB_PASS=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)

    ROOT_PASS=$(obtener_mysql_root)

    mkdir -p "$SITES_DIR/$SITIO/html"

    SQL="
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
"

    docker exec -i wordpress-db mariadb -uroot -p"$ROOT_PASS" <<< "$SQL"

cat > "$SITES_DIR/$SITIO/docker-compose.yml" <<EOF
services:
  ${SITIO}:
    image: wordpress:php8.3-apache
    container_name: ${SITIO}
    restart: unless-stopped
    environment:
      WORDPRESS_DB_HOST: wordpress-db:3306
      WORDPRESS_DB_NAME: ${DB_NAME}
      WORDPRESS_DB_USER: ${DB_USER}
      WORDPRESS_DB_PASSWORD: ${DB_PASS}
    volumes:
      - ./html:/var/www/html
      - ${PHP_DIR}/uploads.ini:/usr/local/etc/php/conf.d/uploads.ini:ro
    ports:
      - "${PUERTO}:80"
    networks:
      - wordpress

networks:
  wordpress:
    external: true
EOF

    cd "$SITES_DIR/$SITIO"
    $DOCKER_COMPOSE up -d || {
        echo "Error levantando WordPress"
        pause
        return
    }

    echo "${SITIO}|${PUERTO}|${DB_NAME}|${DB_USER}|${DB_PASS}" >> "$CONFIG_DIR/sites.db"
    chmod 600 "$CONFIG_DIR/sites.db"

    IP_LOCAL=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo
    echo "==========================================="
    echo " WORDPRESS CREADO"
    echo "==========================================="
    echo "Sitio  : $SITIO"
    echo "Puerto : $PUERTO"
    echo "URL    : http://${IP_LOCAL}:${PUERTO}"
    echo

    pause
}
# =========================================================
# LISTAR WORDPRESS (ROBUSTO)
# =========================================================
listar_wordpress() {

    clear

    echo
    echo -e "${CYAN}====================================${NC}"
    echo -e "${CYAN}      INSTANCIAS WORDPRESS         ${NC}"
    echo -e "${CYAN}====================================${NC}"
    echo

    mapfile -t WORDPRESS < <(
        docker ps -a --format "{{.Names}}" | while read -r c; do
            docker exec "$c" test -f /var/www/html/wp-config.php 2>/dev/null && echo "$c"
        done
    )

    if [ ${#WORDPRESS[@]} -eq 0 ]; then
        echo -e "${RED}❌ No se encontraron instancias WordPress${NC}"
        echo
        read -rp "ENTER para continuar..."
        return
    fi

    printf "%-25s %-10s %-25s %-15s\n" \
        "CONTENEDOR" \
        "ESTADO" \
        "DNS" \
        "PUERTO"

    echo "-------------------------------------------------------------------------------------------"

    for CONT in "${WORDPRESS[@]}"; do

        ESTADO=$(docker inspect \
            --format='{{.State.Status}}' \
            "$CONT" 2>/dev/null)

        case "$ESTADO" in
            running)
                ESTADO="${GREEN}🟢 Activo${NC}"
                ;;
            exited)
                ESTADO="${RED}🔴 Detenido${NC}"
                ;;
            restarting)
                ESTADO="${YELLOW}🟡 Reiniciando${NC}"
                ;;
            *)
                ESTADO="${YELLOW}⚪ Desconocido${NC}"
                ;;
        esac

        DNS=$(docker exec "$CONT" sh -c \
            "grep WP_HOME /var/www/html/wp-config.php 2>/dev/null" | \
            sed -n "s/.*https:\/\/\([^']*\).*/\1/p")

        [ -z "$DNS" ] && DNS="No configurado"

        PUERTO=$(docker port "$CONT" 2>/dev/null | head -n1 | awk -F: '{print $2}')

        [ -z "$PUERTO" ] && PUERTO="-"

        printf "%-25s %-20b %-25s %-15s\n" \
            "$CONT" \
            "$ESTADO" \
            "$DNS" \
            "$PUERTO"

    done

    echo
    echo -e "${CYAN}Detalle:${NC}"
    echo

    for CONT in "${WORDPRESS[@]}"; do

        DNS=$(docker exec "$CONT" sh -c \
            "grep WP_HOME /var/www/html/wp-config.php 2>/dev/null" | \
            sed -n "s/.*https:\/\/\([^']*\).*/\1/p")

        if [ -n "$DNS" ]; then

            if getent hosts "$DNS" >/dev/null 2>&1; then
                DNS_ESTADO="${GREEN}🟢 DNS OK${NC}"
            else
                DNS_ESTADO="${RED}🔴 DNS NO RESUELVE${NC}"
            fi

            echo -e "${WHITE}$CONT${NC}"
            echo -e "  URL : https://$DNS"
            echo -e "  DNS : $DNS_ESTADO"
            echo

        else

            PUERTO=$(docker port "$CONT" 2>/dev/null | head -n1 | awk -F: '{print $2}')

            echo -e "${WHITE}$CONT${NC}"
            echo -e "  URL : http://IP_SERVIDOR:$PUERTO"
            echo -e "  DNS : ${YELLOW}No configurado${NC}"
            echo

        fi

    done

    read -rp "ENTER para continuar..."
}
# =========================================================
# LISTAR WORDPRESS (ROBUSTO)
# =========================================================

listar_wordpress_url() {

    header

    if [ ! -s "$CONFIG_DIR/sites.db" ]; then
        echo "No existen sitios registrados."
        pause
        return
    fi

    IP_LOCAL=$(hostname -I 2>/dev/null | awk '{print $1}')

    echo "=========================================================="
    echo "INSTANCIAS WORDPRESS"
    echo "=========================================================="
    printf "%-15s %-8s %-12s %-12s %-10s\n" "SITIO" "PUERTO" "BD" "USUARIO" "ESTADO"
    echo "----------------------------------------------------------"

    while IFS='|' read -r SITIO PUERTO DB USER PASS; do

        [ -z "$SITIO" ] && continue

        if docker ps --format '{{.Names}}' | grep -qx "$SITIO"; then
            ESTADO="ACTIVO"
        else
            ESTADO="DETENIDO"
        fi

        printf "%-15s %-8s %-12s %-12s %-10s\n" \
            "$SITIO" "$PUERTO" "$DB" "$USER" "$ESTADO"

    done < "$CONFIG_DIR/sites.db"

    echo
    echo "URLs:"
    echo

    while IFS='|' read -r SITIO PUERTO DB USER PASS; do
        [ -z "$SITIO" ] && continue
        echo "• $SITIO → http://${IP_LOCAL}:${PUERTO}"
    done < "$CONFIG_DIR/sites.db"

    pause
}
# =========================================================
# GESTIONAR CONTENEDORES
# =========================================================

gestionar_contenedores_docker() {

    while true; do

        clear

        echo
        echo -e "${CYAN}====================================${NC}"
        echo -e "${CYAN}    GESTOR DE CONTENEDORES         ${NC}"
        echo -e "${CYAN}====================================${NC}"
        echo

        mapfile -t CONTENEDORES < <(
            docker ps -a --format "{{.Names}}"
        )

        if [ ${#CONTENEDORES[@]} -eq 0 ]; then
            echo -e "${RED}❌ No existen contenedores Docker${NC}"
            echo
            read -rp "ENTER para continuar..."
            return
        fi

        for i in "${!CONTENEDORES[@]}"; do

            NOMBRE="${CONTENEDORES[$i]}"

            ESTADO=$(docker inspect \
                --format='{{.State.Status}}' \
                "$NOMBRE" 2>/dev/null)

            IMAGEN=$(docker inspect \
                --format='{{.Config.Image}}' \
                "$NOMBRE" 2>/dev/null)

            HEALTH=$(docker inspect \
                --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}sin-healthcheck{{end}}' \
                "$NOMBRE" 2>/dev/null)

            case "$ESTADO" in
                running)
                    ICONO="${GREEN}🟢${NC}"
                    ;;
                exited)
                    ICONO="${RED}🔴${NC}"
                    ;;
                restarting)
                    ICONO="${YELLOW}🟡${NC}"
                    ;;
                *)
                    ICONO="${YELLOW}⚪${NC}"
                    ;;
            esac

            printf "%b %2s) %-25s %-15s [%s]\n" \
                "$ICONO" \
                "$((i+1))" \
                "$NOMBRE" \
                "$ESTADO" \
                "$HEALTH"

        done

        echo
        echo "1) Reiniciar un contenedor"
        echo "2) Iniciar un contenedor"
        echo "3) Detener un contenedor"
        echo "4) Reiniciar todos"
        echo "5) Iniciar todos los detenidos"
        echo "6) Ver detalles de un contenedor"
        echo "0) Volver"
        echo

        read -rp "Seleccione una opción: " OPCION

        case "$OPCION" in

            1)

                echo
                read -rp "Número del contenedor: " NUM

                CONT="${CONTENEDORES[$((NUM-1))]}"

                [ -z "$CONT" ] && continue

                echo
                echo -ne "Escriba ${YELLOW}REINICIAR${NC} para continuar: "
                read -r CONFIRMAR

                [ "$CONFIRMAR" != "REINICIAR" ] && continue

                docker restart "$CONT"

                echo
                echo -e "${GREEN}✅ Contenedor reiniciado${NC}"
                read -rp "ENTER para continuar..."
                ;;

            2)

                echo
                read -rp "Número del contenedor: " NUM

                CONT="${CONTENEDORES[$((NUM-1))]}"

                [ -z "$CONT" ] && continue

                docker start "$CONT"

                echo
                echo -e "${GREEN}✅ Contenedor iniciado${NC}"
                read -rp "ENTER para continuar..."
                ;;

            3)

                echo
                read -rp "Número del contenedor: " NUM

                CONT="${CONTENEDORES[$((NUM-1))]}"

                [ -z "$CONT" ] && continue

                echo
                echo -ne "Escriba ${YELLOW}DETENER${NC} para continuar: "
                read -r CONFIRMAR

                [ "$CONFIRMAR" != "DETENER" ] && continue

                docker stop "$CONT"

                echo
                echo -e "${GREEN}✅ Contenedor detenido${NC}"
                read -rp "ENTER para continuar..."
                ;;

            4)

                echo
                echo -ne "Escriba ${YELLOW}REINICIAR-TODOS${NC} para continuar: "
                read -r CONFIRMAR

                [ "$CONFIRMAR" != "REINICIAR-TODOS" ] && continue

                docker restart $(docker ps -q)

                echo
                echo -e "${GREEN}✅ Todos los contenedores fueron reiniciados${NC}"
                read -rp "ENTER para continuar..."
                ;;

            5)

                docker ps -a \
                    --filter "status=exited" \
                    --format "{{.Names}}" | while read -r c; do
                        docker start "$c"
                    done

                echo
                echo -e "${GREEN}✅ Contenedores detenidos iniciados${NC}"
                read -rp "ENTER para continuar..."
                ;;

            6)

                echo
                read -rp "Número del contenedor: " NUM

                CONT="${CONTENEDORES[$((NUM-1))]}"

                [ -z "$CONT" ] && continue

                clear

                echo
                echo -e "${CYAN}Detalles de:${NC} $CONT"
                echo

                docker inspect "$CONT" | less

                ;;

            0)
                return
                ;;

        esac

    done
}

# =========================================================
# VER CREDENCIALES (MEJORADO)
# =========================================================

ver_credenciales() {

    header

    if [ ! -s "$CONFIG_DIR/sites.db" ]; then
        echo "No existen sitios registrados."
        pause
        return
    fi

    echo "================= CREDENCIALES WORDPRESS ================="
    echo

    while IFS='|' read -r SITIO PUERTO DB USER PASS; do

        [ -z "$SITIO" ] && continue

        echo "--------------------------------------------------"
        echo "Sitio      : $SITIO"
        echo "Puerto     : $PUERTO"
        echo "DB         : $DB"
        echo "Usuario    : $USER"
        echo "Password   : $PASS"

        if docker ps --format '{{.Names}}' | grep -qx "$SITIO"; then
            echo "Estado     : ACTIVO"
        else
            echo "Estado     : DETENIDO"
        fi

    done < "$CONFIG_DIR/sites.db"

    echo
    echo "================= MYSQL ROOT ================="
    echo

    cat "$CONFIG_DIR/mysql_root_password" 2>/dev/null || echo "No disponible"

    pause
}

# =========================================================
# ELIMINAR WORDPRESS (SEGURO)
# =========================================================
eliminar_wordpress() {

    header

    if [ ! -s "$CONFIG_DIR/sites.db" ]; then
        echo "No hay sitios registrados."
        pause
        return
    fi

    echo "Sitios disponibles:"
    echo

    awk -F'|' '{print NR") "$1" (Puerto "$2")"}' "$CONFIG_DIR/sites.db"

    echo
    read -rp "Número a eliminar (ENTER cancela): " N

    if [ -z "$N" ]; then
        echo "Cancelado."
        pause
        return
    fi

    if ! [[ "$N" =~ ^[0-9]+$ ]]; then
        echo "Opción inválida."
        pause
        return
    fi

    LINEA=$(sed -n "${N}p" "$CONFIG_DIR/sites.db")

    if [ -z "$LINEA" ]; then
        echo "No existe ese número."
        pause
        return
    fi

    SITIO=$(echo "$LINEA" | cut -d'|' -f1)
    DB=$(echo "$LINEA" | cut -d'|' -f3)
    USER=$(echo "$LINEA" | cut -d'|' -f4)

    echo
    echo "Eliminando: $SITIO ($DB)"
    echo

    # Eliminar contenedor WordPress
    if docker ps -a --format "{{.Names}}" | grep -qx "$SITIO"; then
        docker rm -f "$SITIO"
    fi

    # Eliminar BD y usuario si MariaDB existe
    if docker ps -a --format "{{.Names}}" | grep -qx "wordpress-db"; then

        ROOT_PASS=$(obtener_mysql_root)

        docker exec wordpress-db mariadb -uroot -p"$ROOT_PASS" <<EOF
DROP DATABASE IF EXISTS \`$DB\`;
DROP USER IF EXISTS '$USER'@'%';
FLUSH PRIVILEGES;
EOF

    else
        echo "MariaDB no existe. Omitiendo eliminación de BD."
    fi

    # Eliminar archivos del sitio
    rm -rf "$SITES_DIR/$SITIO"

    # Eliminar SOLO la línea seleccionada
    TMP=$(mktemp)
    sed "${N}d" "$CONFIG_DIR/sites.db" > "$TMP"
    mv "$TMP" "$CONFIG_DIR/sites.db"

    chmod 600 "$CONFIG_DIR/sites.db"

    echo
    echo "Sitio eliminado correctamente."
    pause
}

# =========================================================
# BACKUP COMPLETO (SEGURO)
# =========================================================

backup_bd() {

    header

    if [ ! -s "$CONFIG_DIR/sites.db" ]; then
        echo "No existen sitios registrados."
        pause
        return
    fi

    FECHA=$(date +%Y%m%d_%H%M%S)
    DESTINO="$BACKUP_DIR/$FECHA"

    mkdir -p "$DESTINO"

    ROOT_PASS=$(obtener_mysql_root) || {
        echo "No se pudo obtener root MySQL"
        pause
        return
    }

    echo "Iniciando backup..."

    while IFS='|' read -r SITIO PUERTO DB USER PASS; do

        [ -z "$SITIO" ] && continue

        echo "→ DB: $DB"

        if ! docker exec wordpress-db mysqldump \
            -uroot -p"$ROOT_PASS" \
            --single-transaction \
            --quick \
            --skip-lock-tables \
            "$DB" > "$DESTINO/${DB}.sql"; then

            echo "ERROR backup DB: $DB"
            continue
        fi

        if [ -d "$SITES_DIR/$SITIO/html" ]; then

            echo "→ Files: $SITIO"

            tar -czf "$DESTINO/${SITIO}_files.tar.gz" \
                -C "$SITES_DIR/$SITIO" html

        fi

    done < "$CONFIG_DIR/sites.db"

    cp "$CONFIG_DIR/sites.db" "$DESTINO/"
    cp "$CONFIG_DIR/mysql_root_password" "$DESTINO/" 2>/dev/null || true

    chmod 600 "$DESTINO/mysql_root_password" 2>/dev/null || true

    echo "Empaquetando backup..."

    tar -czf "$BACKUP_DIR/wordpress_backup_${FECHA}.tar.gz" \
        -C "$BACKUP_DIR" "$FECHA"

    rm -rf "$DESTINO"

    echo
    echo "BACKUP COMPLETADO:"
    echo "$BACKUP_DIR/wordpress_backup_${FECHA}.tar.gz"
    echo

    ls -lh "$BACKUP_DIR/wordpress_backup_${FECHA}.tar.gz"

    pause
}

# =========================================================
# ACTUALIZAR CONTENEDORES (SEGURO)
# =========================================================

actualizar_contenedores() {

    header

    echo "Actualizando imágenes base..."

    docker pull mariadb:11
    docker pull wordpress:php8.3-apache

    echo
    echo "Recreando MariaDB..."
    cd "$BASE_DIR"
    $DOCKER_COMPOSE up -d mariadb

    if [ -s "$CONFIG_DIR/sites.db" ]; then

        while IFS='|' read -r SITIO PUERTO DB USER PASS; do

            [ -z "$SITIO" ] && continue

            if [ -d "$SITES_DIR/$SITIO" ]; then

                echo "Actualizando $SITIO..."

                cd "$SITES_DIR/$SITIO"
                $DOCKER_COMPOSE up -d --force-recreate

            fi

        done < "$CONFIG_DIR/sites.db"
    fi

    echo
    echo "Limpieza segura (SIN borrar todo)..."

    docker container prune -f
    docker network prune -f

    echo
    echo "Estado actual:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    pause
}

# =========================================================
# REPARAR PERMISOS (OPTIMIZADO WORDPRESS)
# =========================================================

reparar_permisos() {

    header

    echo "Aplicando permisos optimizados..."

    if [ ! -d "$BASE_DIR" ]; then
        echo "No existe base"
        pause
        return
    fi

    # Base segura
    find "$BASE_DIR" -type d -exec chmod 755 {} \;
    find "$BASE_DIR" -type f -exec chmod 644 {} \;

    # Seguridad crítica
    chmod 600 "$CONFIG_DIR/mysql_root_password" 2>/dev/null || true
    chmod 600 "$CONFIG_DIR/sites.db" 2>/dev/null || true

    chmod 700 "$CONFIG_DIR"
    chmod 700 "$BACKUP_DIR"

    # WordPress específico (mejor práctica)
    if [ -d "$SITES_DIR" ]; then

        find "$SITES_DIR" -type d -exec chmod 755 {} \;
        find "$SITES_DIR" -type f -exec chmod 644 {} \;

        # wp-config seguridad
        find "$SITES_DIR" -name "wp-config.php" -exec chmod 600 {} \;
    fi

    echo
    echo "Permisos reparados correctamente."
    pause
}
reparar_mariadb() {

    header

    echo "======================================"
    echo " REPARACIÓN COMPLETA DE MARIADB"
    echo "======================================"
    echo
    echo "ATENCIÓN:"
    echo "- Se eliminarán TODAS las bases de datos."
    echo "- Se generará una nueva contraseña root."
    echo

    read -rp "¿Continuar? (s/N): " RESP

    [[ ! "$RESP" =~ ^[sS]$ ]] && {
        echo "Cancelado."
        pause
        return
    }

    echo
    echo "Deteniendo MariaDB..."

    docker stop wordpress-db 2>/dev/null || true
    docker rm wordpress-db 2>/dev/null || true

    echo "Eliminando datos..."

    rm -rf "$DATA_DIR"/*
    rm -f "$CONFIG_DIR/mysql_root_password"

    echo "Recreando MariaDB..."

    crear_stack_mariadb

    echo
    echo "======================================"
    echo " MARIADB REPARADA"
    echo "======================================"
    echo

    echo "Nueva contraseña root:"
    cat "$CONFIG_DIR/mysql_root_password"

    echo
    pause
}
verificar_docker() {

    echo "Verificando Docker..."

    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: Docker no está instalado."
        exit 1
    fi

    if ! systemctl is-active --quiet docker; then
        echo "Docker está detenido. Iniciando..."
        systemctl start docker
        systemctl enable docker >/dev/null 2>&1
        sleep 3
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "ERROR: No se pudo conectar con Docker."
        echo "Revisar con: journalctl -u docker -n 50 --no-pager"
        exit 1
    fi

    echo "Docker operativo."
}
configurar_dns_wordpress() {

    while true; do

        clear

        echo
        echo -e "${CYAN}====================================${NC}"
        echo -e "${CYAN}       DNS WORDPRESS               ${NC}"
        echo -e "${CYAN}====================================${NC}"
        echo

        mapfile -t WORDPRESS < <(
            docker ps --format "{{.Names}}" | while read -r c; do
                docker exec "$c" test -f /var/www/html/wp-config.php 2>/dev/null && echo "$c"
            done
        )

        if [ ${#WORDPRESS[@]} -eq 0 ]; then
            echo -e "${RED}❌ No se encontraron instancias WordPress${NC}"
            echo
            read -rp "ENTER para continuar..."
            return
        fi

echo -e "${WHITE}Instancias detectadas:${NC}"
echo

for i in "${!WORDPRESS[@]}"; do

    DNS_ACTUAL=$(docker exec "${WORDPRESS[$i]}" sh -c \
    "grep 'WP_HOME' /var/www/html/wp-config.php 2>/dev/null || true" | \
    sed -E "s/.*https?:\/\/([^'\"]+).*/\1/")

    if [ -z "$DNS_ACTUAL" ]; then
        ESTADO="${YELLOW}SIN DNS${NC}"
        DNS_ACTUAL="No configurado"
    else
        if getent hosts "$DNS_ACTUAL" >/dev/null 2>&1; then
            ESTADO="${GREEN}DNS OK${NC}"
        else
            ESTADO="${RED}DNS NO RESUELVE${NC}"
        fi
    fi

    printf "%b %s) %-20s DNS: %s\n" \
        "$ESTADO" \
        "$((i+1))" \
        "${WORDPRESS[$i]}" \
        "$DNS_ACTUAL"

done

        echo
        echo "0) Volver"
        echo
        read -rp "Seleccione una instancia: " OPCION

        if [ "$OPCION" = "0" ]; then
            return
        fi

        if ! [[ "$OPCION" =~ ^[0-9]+$ ]]; then
            continue
        fi

CONTENEDOR="${WORDPRESS[$((OPCION-1))]}"

if [ -z "$CONTENEDOR" ]; then
    continue
fi

while true; do

    clear

    DNS_ACTUAL=$(docker exec "$CONTENEDOR" sh -c \
    "grep 'WP_HOME' /var/www/html/wp-config.php 2>/dev/null || true" | \
    sed -E "s/.*https?:\/\/([^'\"]+).*/\1/")

    echo
    echo -e "${CYAN}Instancia:${NC} $CONTENEDOR"

    if [ -n "$DNS_ACTUAL" ]; then
        echo -e "${GREEN}DNS actual:${NC} $DNS_ACTUAL"
    else
        echo -e "${YELLOW}DNS actual:${NC} No configurado"
    fi

            echo
            echo "1) Configurar DNS"
            echo "2) Cambiar DNS"
            echo "3) Eliminar DNS"
            echo "4) Ver configuración actual"
            echo "5) Restaurar último respaldo"
            echo "0) Volver"
            echo

            read -rp "Seleccione una opción: " ACCION

            case "$ACCION" in

                1|2)

                    echo
                    read -rp "Ingrese el dominio (ej: casa.llancor.com): " DOMINIO

                    [ -z "$DOMINIO" ] && continue

                    echo
                    echo -ne "Escriba ${YELLOW}CONFIRMAR${NC} para continuar: "
                    read -r CONFIRMAR

                    [ "$CONFIRMAR" != "CONFIRMAR" ] && continue

                    FECHA=$(date +%Y%m%d-%H%M%S)

                    echo
                    echo "Configurando $CONTENEDOR..."
                    echo

                    docker exec "$CONTENEDOR" sh -c "
                    cp /var/www/html/wp-config.php /var/www/html/wp-config.php.bak-${FECHA}

                    sed -i '/WP_HOME/d' /var/www/html/wp-config.php
                    sed -i '/WP_SITEURL/d' /var/www/html/wp-config.php

                    sed -i \"/That's all, stop editing/i define('WP_HOME', 'https://${DOMINIO}');\" /var/www/html/wp-config.php
                    sed -i \"/That's all, stop editing/i define('WP_SITEURL', 'https://${DOMINIO}');\" /var/www/html/wp-config.php
                    "

                    echo
                    echo -e "${CYAN}Verificando...${NC}"
                    echo

                    docker exec "$CONTENEDOR" grep -nE "WP_HOME|WP_SITEURL" /var/www/html/wp-config.php

                    echo

                    docker restart "$CONTENEDOR" >/dev/null 2>&1

                    echo
                    echo -e "${GREEN}✅ DNS configurado correctamente${NC}"
                    echo -e "${WHITE}Dominio:${NC} https://${DOMINIO}"
                    echo

                    read -rp "ENTER para continuar..."
                    ;;

                3)

                    echo
                    echo -e "${RED}⚠️  ATENCIÓN${NC}"
                    echo
                    echo "Se eliminarán WP_HOME y WP_SITEURL"
                    echo

                    echo -ne "Escriba ${YELLOW}ELIMINAR${NC} para continuar: "
                    read -r CONFIRMAR

                    [ "$CONFIRMAR" != "ELIMINAR" ] && continue

                    FECHA=$(date +%Y%m%d-%H%M%S)

                    docker exec "$CONTENEDOR" sh -c "
                        cp /var/www/html/wp-config.php /var/www/html/wp-config.php.bak-${FECHA}

                        sed -i '/WP_HOME/d' /var/www/html/wp-config.php
                        sed -i '/WP_SITEURL/d' /var/www/html/wp-config.php
                    "

                    docker restart "$CONTENEDOR" >/dev/null 2>&1

                    echo
                    echo -e "${GREEN}✅ DNS eliminado correctamente${NC}"
                    echo
                    read -rp "ENTER para continuar..."
                    ;;

                4)

                    clear

                    echo
                    echo -e "${CYAN}====================================${NC}"
                    echo -e "${CYAN}    CONFIGURACIÓN ACTUAL           ${NC}"
                    echo -e "${CYAN}====================================${NC}"
                    echo

                    CONFIG=$(docker exec "$CONTENEDOR" sh -c \
                        "grep -E 'WP_HOME|WP_SITEURL' /var/www/html/wp-config.php 2>/dev/null || true")

                    if [ -z "$CONFIG" ]; then
                        echo -e "${YELLOW}No hay DNS configurado${NC}"
                    else
                        echo "$CONFIG"
                    fi

                    echo
                    read -rp "ENTER para continuar..."

                    continue
                    ;;

                5)

                    BACKUP=$(docker exec "$CONTENEDOR" sh -c \
                        "ls -1t /var/www/html/wp-config.php.bak-* 2>/dev/null | head -n1")

                    if [ -z "$BACKUP" ]; then
                        echo
                        echo -e "${RED}❌ No existen respaldos${NC}"
                        echo
                        read -rp "ENTER para continuar..."
                        continue
                    fi

                    echo
                    echo -e "${YELLOW}Respaldo encontrado:${NC}"
                    echo "$BACKUP"
                    echo

                    echo -ne "Escriba ${YELLOW}RESTAURAR${NC} para continuar: "
                    read -r CONFIRMAR

                    [ "$CONFIRMAR" != "RESTAURAR" ] && continue

                    docker exec "$CONTENEDOR" sh -c "
                        cp '$BACKUP' /var/www/html/wp-config.php
                    "

                    docker restart "$CONTENEDOR" >/dev/null 2>&1

                    echo
                    echo -e "${GREEN}✅ Respaldo restaurado correctamente${NC}"
                    echo
                    read -rp "ENTER para continuar..."
                    ;;

                0)
                    break
                    ;;

            esac

        done

    done
}
# =========================================================
# MENU PRINCIPAL (ROBUSTO)
# =========================================================

menu() {

while true; do

header


echo -e "${GREEN}*"
echo -e "${GREEN} 1) Instalación Inicial${RESET}"
echo -e "${GREEN} 2) Crear WordPress${RESET}"
echo -e "${GREEN}*"
echo -e "${BLUE} 3) Listar WordPress${RESET}"
echo -e "${BLUE} 4) Ver Credenciales${RESET}"
echo -e "${GREEN}*"
echo -e "${RED} 5) Eliminar WordPress${RESET}"
echo -e "${GREEN}*"
echo -e "${ORANGE} 6) Backup Completo${RESET}"
echo -e "${YELLOW} 7) Actualizar Contenedores${RESET}"
echo -e "${GREEN}*"
echo -e "${ORANGE} 8) Reparar Permisos${RESET}"
echo -e "${GREEN}*"
echo -e "${BLUE} 9) Mostrar URLs${RESET}"
echo -e "${GREEN}*"
echo -e "${YELLOW}10) Gestionar Contenedores Docker / Reiniciar / Estado${RESET}"
echo -e "${GREEN}*"
echo -e "${ORANGE}11) Reparar MariaDB${RESET}"
echo -e "${GREEN}*"
echo -e "${YELLOW}12) Agregar DNS a Instancia WordPress${RESET}"
echo -e "${GREEN}*"
echo -e "${RED} 0) Salir${RESET}"

read -rp "Seleccione opción: " OPCION

case "$OPCION" in
    1) instalacion_inicial ;;
    2) crear_wordpress ;;
    3) listar_wordpress_url ;;
    4) ver_credenciales ;;
    5) eliminar_wordpress ;;
    6) backup_bd ;;
    7) actualizar_contenedores ;;
    8) reparar_permisos ;;
    9) listar_wordpress ;;
	10) gestionar_contenedores_docker ;;
	11) reparar_mariadb ;;
	12) configurar_dns_wordpress ;;
    0) exit 0 ;;
    *) echo "Opción inválida" ; pause ;;
esac

done

}
menu