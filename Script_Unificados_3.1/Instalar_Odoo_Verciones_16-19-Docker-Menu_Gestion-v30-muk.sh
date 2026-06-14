#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

# ===== COLORES =====
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'
WHITE='\033[1;37m'

BASE_DIR="/opt"

# Activar/Desactivar DB Manager
toggle_db_manager() {
    echo -e "${CYAN}Selecciona versión:${RESET}"
    select VERSION in 16 17 18 19; do break; done

    FILE="/opt/odoo$VERSION/config/odoo.conf"

    echo "1) Activar (mostrar bases de datos)"
    echo "2) Desactivar (ocultar bases de datos)"
    read -p "Opción: " OP

    if [ "$OP" == "1" ]; then
        sed -i "s/^list_db.*/list_db = True/" $FILE
        echo -e "${GREEN}DB Manager activado ✔${RESET}"
    else
        sed -i "s/^list_db.*/list_db = False/" $FILE
        echo -e "${RED}DB Manager oculto ✔${RESET}"
    fi

    docker restart odoo$VERSION
}
# CAMBIAR MASTER PASWORDS
change_master_password() {
    echo -e "${CYAN}Selecciona versión:${RESET}"
    select VERSION in 16 17 18 19; do break; done

    FILE="/opt/odoo$VERSION/config/odoo.conf"

    read -p "Nueva master password: " PASS

    sed -i "s/^admin_passwd.*/admin_passwd = $PASS/" $FILE

    docker restart odoo$VERSION

    echo -e "${GREEN}Password cambiada ✔${RESET}"
}
# EDITAR ODOO.CONF
edit_odoo_conf() {
    clear
    echo -e "${CYAN}=== EDITAR CONFIGURACIÓN ODOO ===${RESET}"

    select VERSION in 16 17 18 19; do break; done

    FILE="/opt/odoo$VERSION/config/odoo.conf"

    if [ ! -f "$FILE" ]; then
        echo -e "${RED}No existe el archivo de configuración${RESET}"
        read -p "ENTER para volver..."
        return
    fi

    echo -e "${YELLOW}Abriendo nano... (CTRL+X para salir)${RESET}"
    sleep 1

    nano "$FILE"

    echo -e "${YELLOW}Reiniciando Odoo $VERSION...${RESET}"
    docker restart odoo$VERSION >/dev/null 2>&1

    echo -e "${GREEN}✔ Configuración aplicada${RESET}"
    echo ""
    read -p "Presiona ENTER para volver al menú..." pausa
}
# REINICIAR SERVICIOS
restart_services() {
    echo -e "${CYAN}1) Reiniciar Odoo${RESET}"
    echo -e "${CYAN}2) Reiniciar Docker${RESET}"
    read -p "Opción: " OP

    if [ "$OP" == "1" ]; then
        select VERSION in 16 17 18 19; do break; done
        docker restart odoo$VERSION
        echo -e "${GREEN}Odoo $VERSION reiniciado ✔${RESET}"
    else
        systemctl restart docker
        echo -e "${GREEN}Docker reiniciado ✔${RESET}"
    fi
}
# ESTATUS ODOO
status_odoo() {
    echo -e "${CYAN}=== ESTADO DE ODOO ===${RESET}"
    echo ""

    for V in 16 17 18 19; do
        PORT=$((8068 + V))

        if docker ps --format '{{.Names}}' | grep -q "^odoo$V$"; then
            echo -e "${GREEN}Odoo $V activo ✔ (Puerto $PORT)${RESET}"
        else
            echo -e "${RED}Odoo $V detenido ✘${RESET}"
        fi
    done

    echo ""
    read -p "Presiona ENTER para continuar..." pausa
}

# MENU GESTION ODOO
manage_odoo() {
while true; do
    clear
    echo -e "${CYAN}====== GESTIÓN ODOO ======${RESET}"
    echo -e "${WHITE}1) Ver estado${RESET}"
    echo -e "${WHITE}2) Reiniciar servicios${RESET}"
    echo -e "${WHITE}3) Editar odoo.conf${RESET}"
    echo -e "${WHITE}4) Cambiar master password${RESET}"
    echo -e "${WHITE}5) Activar/Desactivar DB Manager${RESET}"
    echo -e "${RED}0) Volver${RESET}"

    read -p "Opción: " OP

    case $OP in
        1) status_odoo ;;
        2) restart_services ;;
        3) edit_odoo_conf ;;
        4) change_master_password ;;
        5) toggle_db_manager ;;
        0) break ;;
        *) echo "Opción inválida"; sleep 2 ;;
    esac
done
}

# ===== AUTO DETECCIÓN OS =====
detect_os() {
    if [ -f /etc/turnkey_version ]; then
        OS="turnkey"
    else
        OS="debian"
    fi
}

# ===== FIX SOURCES AUTO =====
fix_sources_auto() {
    echo -e "${YELLOW}Configurando repositorios...${RESET}"

    detect_os

    if [ "$OS" == "turnkey" ]; then
        FILE="/etc/apt/sources.list.d/sources.list"
    else
        FILE="/etc/apt/sources.list"
    fi

    cat > $FILE <<EOF
deb http://mirror.ufro.cl/debian bookworm main contrib non-free non-free-firmware
deb http://mirror.ufro.cl/debian bookworm-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

    echo -e "${GREEN}Repositorios OK ✔${RESET}"
}

# ===== FIX APT AUTO =====
fix_apt_auto() {
    echo -e "${YELLOW}Reparando APT...${RESET}"

    fix_sources_auto

    systemctl stop docker 2>/dev/null

    rm -rf /var/lib/apt/lists/*
    rm -rf /var/cache/apt/archives/*
    rm -rf /var/cache/apt/*.bin

    echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
    echo 'Acquire::http::No-Cache "true";' > /etc/apt/apt.conf.d/99no-cache
    echo 'Acquire::BrokenProxy "true";' > /etc/apt/apt.conf.d/99broken-proxy

    apt clean

    if ! apt update --fix-missing; then
        echo -e "${RED}Reintentando APT...${RESET}"
        sleep 3
        apt update --fix-missing
    fi

    apt install -f -y

    echo -e "${GREEN}APT OK ✔${RESET}"
}

# ===== FIX APPARMOR =====
fix_apparmor() {
    echo -e "${YELLOW}Configurando AppArmor...${RESET}"
    apt install -y apparmor apparmor-utils
    systemctl enable apparmor
    systemctl start apparmor
}

# ===== INSTALAR DOCKER AUTO =====
install_docker_auto() {
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}Docker ya instalado ✔${RESET}"
        return
    fi

    fix_apt_auto
    fix_apparmor
	

    echo -e "${YELLOW}Instalando Docker...${RESET}"

    if ! apt install -y docker.io docker-compose; then
        echo -e "${RED}Reintentando instalación...${RESET}"
        fix_apt_auto
        apt install -y docker.io docker-compose || {
            echo -e "${RED}Error crítico instalando Docker ❌${RESET}"
            exit 1
        }
    fi

    systemctl daemon-reexec
    systemctl enable docker
    systemctl restart docker

    sleep 2

    if ! systemctl is-active --quiet docker; then
        echo -e "${RED}Docker no inició ❌${RESET}"
        systemctl status docker --no-pager
        exit 1
    fi

    if docker run hello-world &> /dev/null; then
        echo -e "${GREEN}Docker funcionando ✔${RESET}"
    else
        echo -e "${RED}Docker falla ❌${RESET}"
        exit 1
    fi
}

# ===== ESTADO ODOO =====
status_odoo() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker no instalado${RESET}"
        return
    fi

    echo -e "${CYAN}=== ESTADO ODOO ===${RESET}"

    for V in 16 17 18 19; do
        PORT=$((8068 + V))
        if docker ps --format '{{.Names}}' | grep -q "^odoo$V$"; then
            echo -e "${GREEN}Odoo $V activo ✔ (Puerto $PORT)${RESET}"
        else
            echo -e "${RED}Odoo $V detenido ✘${RESET}"
        fi
    done

    read -p "ENTER..." pausa
}

# ===== INSTALAR ODOO ANTIGUO Y MODERNO =====
install_odoo_automatico() {
    install_docker_auto

    echo -e "${CYAN}Selecciona versión:${RESET}"
    select VERSION in 16 17 18 19 "Volver"; do
        case $VERSION in
            16|17|18|19) break ;;
            "Volver") return ;;
            *) echo -e "${RED}Opción inválida${RESET}" ;;
        esac
    done

    PORT=$((8068 + VERSION))
    DIR="$BASE_DIR/odoo$VERSION"

    if [ -d "$DIR" ]; then
        echo -e "${RED}Ya existe Odoo $VERSION${RESET}"
        return
    fi

    mkdir -p $DIR && cd $DIR

    echo -e "${YELLOW}Instalando Odoo $VERSION...${RESET}"

    cat > docker-compose.yml <<EOF
version: '3.1'
services:
  db:
    image: postgres:15
    container_name: odoo${VERSION}_db
    restart: always
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
    volumes:
      - odoo${VERSION}_db_data:/var/lib/postgresql/data

  odoo:
    image: odoo:${VERSION}
    container_name: odoo${VERSION}
    restart: always
    depends_on:
      - db
    ports:
      - "$PORT:8069"
    volumes:
      - ./config:/etc/odoo
      - ./addons:/mnt/extra-addons
      - ./muk-addons:/mnt/muk-addons   # 👈 AGREGADO

volumes:
  odoo${VERSION}_db_data:
EOF

    mkdir -p config addons muk-addons   # 👈 AGREGADO

    cat > config/odoo.conf <<EOF
[options]
admin_passwd = admin123
db_host = db
db_port = 5432
db_user = odoo
db_password = odoo
list_db = True
proxy_mode = True

addons_path = /usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons,/mnt/muk-addons
EOF

    # Levantar contenedores (compatibilidad)
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d
    else
        docker compose up -d
    fi

    echo -e "${YELLOW}Esperando inicio de Odoo...${RESET}"
    sleep 5

    # ===== VERIFICACIÓN =====
    if docker ps --format '{{.Names}}' | grep -q "^odoo$VERSION$"; then
        STATUS="${GREEN}ACTIVO ✔${RESET}"
    else
        STATUS="${RED}ERROR ❌${RESET}"
    fi

    IP=$(hostname -I | awk '{print $1}')

    # ===== INFORME =====
    echo ""
    echo -e "${CYAN}========= INFORME ODOO =========${RESET}"
    echo -e "${WHITE}Versión:${RESET} Odoo $VERSION"
    echo -e "${WHITE}Estado:${RESET} $STATUS"
    echo -e "${WHITE}Puerto:${RESET} $PORT"
    echo -e "${WHITE}URL local:${RESET} http://localhost:$PORT"
    echo -e "${WHITE}URL red:${RESET} http://$IP:$PORT"
    echo -e "${WHITE}Ruta:${RESET} $DIR"
    echo -e "${WHITE}Config:${RESET} $DIR/config/odoo.conf"
    echo -e "${WHITE}Usuario DB:${RESET} odoo"
    echo -e "${WHITE}Password DB:${RESET} odoo"
    echo ""
    echo -e "${YELLOW}👉 Puedes crear dominio con la opción VHost${RESET}"
    echo ""

    read -p "Presiona ENTER para continuar..." pausa
}


# ===== INSTALAR ODOO ULTRA INTELIGENTE =====
install_odoo_new() {
    install_docker_auto

    echo -e "${CYAN}Selecciona versión:${RESET}"
    select VERSION in 16 17 18 19 "Volver"; do
        case $VERSION in
            16|17|18|19) break ;;
            "Volver") return ;;
            *) echo -e "${RED}Opción inválida${RESET}" ;;
        esac
    done

    PORT=$((8068 + VERSION))
    DIR="$BASE_DIR/odoo$VERSION"

    if [ -d "$DIR" ]; then
        echo -e "${RED}Ya existe Odoo $VERSION${RESET}"
        return
    fi

    echo -e "${YELLOW}Detectando imagen disponible...${RESET}"

    # ===== DETECCIÓN INTELIGENTE =====
    if docker manifest inspect odoo:$VERSION >/dev/null 2>&1; then
        ODOO_IMAGE="odoo:$VERSION"
        echo -e "${GREEN}✔ Imagen encontrada: $ODOO_IMAGE${RESET}"
    else
        ODOO_IMAGE="odoo:latest"
        echo -e "${YELLOW}⚠ odoo:$VERSION no existe, usando latest${RESET}"
    fi

    mkdir -p "$DIR"
    cd "$DIR" || return

    echo -e "${CYAN}Instalando con:${RESET} $ODOO_IMAGE"

    mkdir -p config addons muk-addons

    cat > docker-compose.yml <<EOF
version: '3.1'
services:
  db:
    image: postgres:15
    container_name: odoo${VERSION}_db
    restart: always
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
    volumes:
      - odoo${VERSION}_db_data:/var/lib/postgresql/data

  odoo:
    image: $ODOO_IMAGE
    container_name: odoo${VERSION}
    restart: always
    depends_on:
      - db
    ports:
      - "$PORT:8069"
    volumes:
      - ./config:/etc/odoo
      - ./addons:/mnt/extra-addons
      - ./muk-addons:/mnt/muk-addons

volumes:
  odoo${VERSION}_db_data:
EOF

    cat > config/odoo.conf <<EOF
[options]
admin_passwd = admin123
db_host = db
db_port = 5432
db_user = odoo
db_password = odoo
list_db = True
proxy_mode = True

addons_path = /usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons,/mnt/muk-addons
EOF

    # ===== LEVANTAR =====
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d
    else
        docker compose up -d
    fi

    echo -e "${YELLOW}Esperando inicio...${RESET}"
    sleep 6

    # ===== AUTOARRANQUE =====
    docker update --restart=always odoo$VERSION >/dev/null 2>&1
    docker update --restart=always odoo${VERSION}_db >/dev/null 2>&1

    # ===== ESTADO =====
    if docker ps --format '{{.Names}}' | grep -q "^odoo$VERSION$"; then
        STATUS="${GREEN}ACTIVO ✔${RESET}"
    else
        STATUS="${RED}ERROR ❌${RESET}"
    fi

    IP=$(hostname -I | awk '{print $1}')

    # ===== DETECTAR VERSION REAL =====
    REAL_VERSION=$(docker exec odoo$VERSION odoo --version 2>/dev/null)

    # ===== INFORME FINAL =====
    echo ""
    echo -e "${CYAN}========= INFORME ULTRA =========${RESET}"
    echo -e "${WHITE}Versión seleccionada:${RESET} Odoo $VERSION"
    echo -e "${WHITE}Imagen usada:${RESET} $ODOO_IMAGE"
    echo -e "${WHITE}Versión real:${RESET} $REAL_VERSION"
    echo -e "${WHITE}Estado:${RESET} $STATUS"
    echo -e "${WHITE}Puerto:${RESET} $PORT"
    echo -e "${WHITE}URL local:${RESET} http://localhost:$PORT"
    echo -e "${WHITE}URL red:${RESET} http://$IP:$PORT"
    echo -e "${WHITE}Ruta:${RESET} $DIR"
    echo -e "${WHITE}Autoarranque:${RESET} Activado ✔"
    echo -e "${WHITE}Config:${RESET} $DIR/config/odoo.conf"
    echo -e "${WHITE}Addons core:${RESET} /mnt/extra-addons"
    echo -e "${WHITE}Addons MUK:${RESET} /mnt/muk-addons"
    echo ""
    echo -e "${GREEN}🔥 Instalación inteligente completada${RESET}"
    echo ""

    read -p "Presiona ENTER para continuar..." pausa
}

# ===== INSTALAR ODOO ULTRA INTELIGENTE =====
install_odoo_new() {
    install_docker_auto

    echo -e "${CYAN}Selecciona versión:${RESET}"
    select VERSION in 16 17 18 19 "Volver"; do
        case $VERSION in
            16|17|18|19) break ;;
            "Volver") return ;;
            *) echo -e "${RED}Opción inválida${RESET}" ;;
        esac
    done

    PORT=$((8068 + VERSION))
    DIR="$BASE_DIR/odoo$VERSION"

    if [ -d "$DIR" ]; then
        echo -e "${RED}Ya existe Odoo $VERSION${RESET}"
        return
    fi

    echo -e "${YELLOW}Detectando imagen disponible...${RESET}"

    # ===== DETECCIÓN INTELIGENTE =====
    if docker manifest inspect odoo:$VERSION >/dev/null 2>&1; then
        ODOO_IMAGE="odoo:$VERSION"
        echo -e "${GREEN}✔ Imagen encontrada: $ODOO_IMAGE${RESET}"
    else
        ODOO_IMAGE="odoo:latest"
        echo -e "${YELLOW}⚠ odoo:$VERSION no existe, usando latest${RESET}"
    fi

    mkdir -p $DIR && cd $DIR

    echo -e "${CYAN}Instalando con:${RESET} $ODOO_IMAGE"

    cat > docker-compose.yml <<EOF
version: '3.1'
services:
  db:
    image: postgres:15
    container_name: odoo${VERSION}_db
    restart: always
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
    volumes:
      - odoo${VERSION}_db_data:/var/lib/postgresql/data

  odoo:
    image: $ODOO_IMAGE
    container_name: odoo${VERSION}
    restart: always
    depends_on:
      - db
    ports:
      - "$PORT:8069"
    volumes:
      - ./config:/etc/odoo
      - ./addons:/mnt/extra-addons

volumes:
  odoo${VERSION}_db_data:
EOF

    mkdir -p config addons

    cat > config/odoo.conf <<EOF
[options]
admin_passwd = admin123
db_host = db
db_port = 5432
db_user = odoo
db_password = odoo
list_db = True
proxy_mode = True
EOF

    # ===== LEVANTAR =====
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d
    else
        docker compose up -d
    fi

    echo -e "${YELLOW}Esperando inicio...${RESET}"
    sleep 6

    # ===== AUTOARRANQUE =====
    docker update --restart=always odoo$VERSION >/dev/null 2>&1
    docker update --restart=always odoo${VERSION}_db >/dev/null 2>&1

    # ===== ESTADO =====
    if docker ps --format '{{.Names}}' | grep -q "^odoo$VERSION$"; then
        STATUS="${GREEN}ACTIVO ✔${RESET}"
    else
        STATUS="${RED}ERROR ❌${RESET}"
    fi

    IP=$(hostname -I | awk '{print $1}')

    # ===== DETECTAR VERSION REAL =====
    REAL_VERSION=$(docker exec odoo$VERSION odoo --version 2>/dev/null)

    # ===== INFORME FINAL =====
    echo ""
    echo -e "${CYAN}========= INFORME ULTRA =========${RESET}"
    echo -e "${WHITE}Versión seleccionada:${RESET} Odoo $VERSION"
    echo -e "${WHITE}Imagen usada:${RESET} $ODOO_IMAGE"
    echo -e "${WHITE}Versión real:${RESET} $REAL_VERSION"
    echo -e "${WHITE}Estado:${RESET} $STATUS"
    echo -e "${WHITE}Puerto:${RESET} $PORT"
    echo -e "${WHITE}URL local:${RESET} http://localhost:$PORT"
    echo -e "${WHITE}URL red:${RESET} http://$IP:$PORT"
    echo -e "${WHITE}Ruta:${RESET} $DIR"
    echo -e "${WHITE}Autoarranque:${RESET} Activado ✔"
    echo -e "${WHITE}Config:${RESET} $DIR/config/odoo.conf"
    echo ""
    echo -e "${GREEN}🔥 Instalación inteligente completada${RESET}"
    echo ""

    read -p "Presiona ENTER para continuar..." pausa
}

# ===== DESINSTALAR ODOO COMPLETO (SAFE NEXTCLOUD) =====
uninstall_odoo() {
    echo -e "${RED}Selecciona versión:${RESET}"
    select VERSION in 16 17 18 19 "Volver"; do
        case $VERSION in
            16|17|18|19) break ;;
            "Volver") return ;;
            *) echo -e "${RED}Opción inválida${RESET}" ;;
        esac
    done

    DIR="$BASE_DIR/odoo$VERSION"
    VHOST="/etc/apache2/sites-available/odoo$VERSION.conf"

    echo -e "${YELLOW}Desinstalando Odoo $VERSION...${RESET}"

    # ===== DOCKER =====
    if command -v docker &> /dev/null; then
        if docker ps -a --format '{{.Names}}' | grep -q "^odoo$VERSION$"; then

            echo -e "${YELLOW}Detectando imágenes asociadas...${RESET}"

            IMG_ODOO=$(docker inspect odoo$VERSION --format '{{.Config.Image}}' 2>/dev/null)
            IMG_DB=$(docker inspect odoo${VERSION}_db --format '{{.Config.Image}}' 2>/dev/null)

            echo -e "${CYAN}Imagen Odoo:${RESET} $IMG_ODOO"
            echo -e "${CYAN}Imagen DB:${RESET} $IMG_DB"

            echo -e "${YELLOW}Deteniendo y eliminando contenedores...${RESET}"

            docker update --restart=no odoo$VERSION >/dev/null 2>&1
            docker update --restart=no odoo${VERSION}_db >/dev/null 2>&1

            cd "$DIR" 2>/dev/null

            if command -v docker-compose &> /dev/null; then
                docker-compose down -v
            else
                docker compose down -v
            fi

            echo -e "${GREEN}✔ Contenedores eliminados${RESET}"

            # ===== LIMPIEZA INTELIGENTE =====
            echo ""
            read -p "¿Eliminar también imágenes asociadas? (s/n): " CLEAN

            if [[ "$CLEAN" =~ ^[Ss]$ ]]; then
                echo -e "${YELLOW}Limpiando imágenes...${RESET}"

                remove_image_if_unused() {
                    IMAGE=$1

                    if [ -z "$IMAGE" ]; then
                        return
                    fi

                    if docker ps -a --format '{{.Image}}' | grep -q "^$IMAGE$"; then
                        echo -e "${CYAN}En uso, se mantiene:${RESET} $IMAGE"
                    else
                        docker rmi "$IMAGE" >/dev/null 2>&1 && \
                        echo -e "${GREEN}✔ Eliminada:${RESET} $IMAGE"
                    fi
                }

                remove_image_if_unused "$IMG_ODOO"
                remove_image_if_unused "$IMG_DB"

                echo -e "${GREEN}✔ Limpieza inteligente completada${RESET}"
            else
                echo -e "${CYAN}Se mantienen las imágenes${RESET}"
            fi

        else
            echo -e "${YELLOW}No hay contenedores${RESET}"
        fi
    fi

    # ===== VHOST =====
    if [ -f "$VHOST" ]; then
        echo -e "${YELLOW}Eliminando VHost...${RESET}"

        a2dissite odoo$VERSION >/dev/null 2>&1
        rm -f "$VHOST"

        systemctl reload apache2

        echo -e "${GREEN}✔ VHost eliminado (Nextcloud intacto)${RESET}"
    else
        echo -e "${YELLOW}No existe VHost${RESET}"
    fi

    # ===== ARCHIVOS =====
    if [ -d "$DIR" ]; then
        rm -rf "$DIR"
        echo -e "${GREEN}✔ Archivos eliminados${RESET}"
    fi

    echo ""
    echo -e "${GREEN}🔥 Odoo $VERSION eliminado completamente ✔${RESET}"
    echo ""

    read -p "ENTER para continuar..." pausa
}

# ===== CREAR VHOST (CON INFORME) =====
create_vhost() {
    echo -e "${CYAN}Selecciona versión:${RESET}"

    select VERSION in 16 17 18 19 "Volver"; do
        case $VERSION in
            16|17|18|19) break ;;
            "Volver") return ;;
            *) echo -e "${RED}Opción inválida${RESET}" ;;
        esac
    done

    PORT=$((8068 + VERSION))

    read -p "Dominio (ej: odoo.midominio.com): " DOMAIN

    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}Dominio inválido${RESET}"
        return
    fi

    FILE="/etc/apache2/sites-available/odoo$VERSION.conf"

    echo -e "${YELLOW}Creando VHost...${RESET}"

    cat > $FILE <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    Redirect permanent / https://$DOMAIN/
</VirtualHost>

<VirtualHost *:443>
    ServerName $DOMAIN

    SSLEngine on
    SSLCertificateFile /etc/ssl/private/cert.pem
    SSLCertificateKeyFile /etc/ssl/private/cert.key

    ProxyPreserveHost On
    ProxyRequests Off

    ProxyPass / http://127.0.0.1:$PORT/
    ProxyPassReverse / http://127.0.0.1:$PORT/

    ErrorLog \${APACHE_LOG_DIR}/odoo$VERSION-error.log
    CustomLog \${APACHE_LOG_DIR}/odoo$VERSION-access.log combined
</VirtualHost>
EOF

    a2enmod proxy proxy_http ssl headers >/dev/null 2>&1
    a2ensite odoo$VERSION >/dev/null 2>&1

    systemctl reload apache2

    # ===== VERIFICACIÓN =====
    if [ -f "$FILE" ]; then
        STATUS="${GREEN}ACTIVO ✔${RESET}"
    else
        STATUS="${RED}ERROR ❌${RESET}"
    fi

    # ===== INFORME =====
    echo ""
    echo -e "${CYAN}========= INFORME VHOST =========${RESET}"
    echo -e "${WHITE}Versión:${RESET} Odoo $VERSION"
    echo -e "${WHITE}Dominio:${RESET} $DOMAIN"
    echo -e "${WHITE}Puerto interno:${RESET} $PORT"
    echo -e "${WHITE}Estado:${RESET} $STATUS"
    echo -e "${WHITE}Ruta config:${RESET} $FILE"
    echo ""
    echo -e "${GREEN}🌐 Acceso:${RESET} https://$DOMAIN"
    echo ""

    read -p "Presiona ENTER para continuar..." pausa
}
# ===== ACTIVAR AUTOARRANQUE =====
enable_autostart_odoo() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker no está instalado${RESET}"
        return
    fi

    echo -e "${CYAN}Activando autoarranque...${RESET}"

    for V in 16 17 18 19; do
        if docker ps -a --format '{{.Names}}' | grep -q "^odoo$V$"; then
            docker update --restart=always odoo$V >/dev/null 2>&1
            docker update --restart=always odoo${V}_db >/dev/null 2>&1
            echo -e "${GREEN}✔ Odoo $V autoarranque ACTIVADO${RESET}"
        else
            echo -e "${YELLOW}⚠ Odoo $V no existe${RESET}"
        fi
    done

    echo ""
    read -p "ENTER para continuar..." pausa
}

# ===== DESACTIVAR AUTOARRANQUE =====
disable_autostart_odoo() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker no está instalado${RESET}"
        return
    fi

    echo -e "${CYAN}Desactivando autoarranque...${RESET}"

    for V in 16 17 18 19; do
        if docker ps -a --format '{{.Names}}' | grep -q "^odoo$V$"; then
            docker update --restart=no odoo$V >/dev/null 2>&1
            docker update --restart=no odoo${V}_db >/dev/null 2>&1
            echo -e "${RED}✘ Odoo $V autoarranque DESACTIVADO${RESET}"
        else
            echo -e "${YELLOW}⚠ Odoo $V no existe${RESET}"
        fi
    done

    echo ""
    read -p "ENTER para continuar..." pausa
}

# ===== MENU =====
menu() {
while true; do
    clear
    echo -e "${CYAN}========= ODOO PRO AUTO =========${RESET}"
    echo -e "${CYAN}1)${WHITE} Instalar Odoo Docker Moderno${RESET}"
	echo -e "${CYAN}2)${WHITE} Instalar Odoo Docker Automatico old/new${RESET}"
	echo -e "${CYAN}3)${WHITE} Activar autoarranque Odoo (16-19)${RESET}"
    echo -e "${CYAN}4)${WHITE} Desactivar autoarranque Odoo (16-19)${RESET}"
    echo -e "${CYAN}5)${WHITE} Desinstalar Odoo${RESET}"
    echo -e "${CYAN}6)${WHITE} Estado Odoo${RESET}"
    echo -e "${CYAN}7)${WHITE} Reparar APT Solucion Dependencias Docker${RESET}"
    echo -e "${CYAN}8)${WHITE} Crear VHost (SSL TurnKey)${RESET}"
	echo -e "${CYAN}9)${WHITE} Gestión de Odoo (odoo.conf-MasterPasswords)${RESET}"
    echo -e "${CYAN}0) Salir${RESET}"

    read -p "Opción: " OP

    case $OP in
        1) install_odoo_automatico ;;
		2) install_odoo_new ;;
		3) enable_autostart_odoo ;;
        4) disable_autostart_odoo ;;
        5) uninstall_odoo ;;
        6) status_odoo ;;
        7) fix_apt_auto ;;
		8) create_vhost ;;
		9) manage_odoo ;;
        0) exit ;;
        *) echo "Opción inválida"; sleep 2 ;;
    esac
done
}

menu