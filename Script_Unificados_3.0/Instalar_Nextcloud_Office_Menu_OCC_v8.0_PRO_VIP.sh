#!/bin/bash

# =========================================================
# NEXTCLOUD PRO v5.1 FIXED
# Debian / Ubuntu / TurnKey Linux
# =========================================================

set -uo pipefail

trap 'echo -e "\n\033[1;31m[ERROR] Línea $LINENO\033[0m"' ERR

clear

# =========================================================
# CONFIG
# =========================================================

NC_DIR="/var/www/nextcloud"
DATA_DIR="/var/www/nextcloud-data"
WEB_USER="www-data"
DB_FILE="/root/nextcloud_db.conf"

# ========= Variables =========
SUDO="sudo -u $WEB_USER"
USER_WEB="www-data"
APACHE_SITES="/etc/apache2/sites-available"
ROOT_PASS=""
BACKUP_DIR_DEFAULT="$HOME/backups-mysql"
EDITOR_BIN="nano"
NEXTCLOUD_DIR="/var/www/nextcloud"
NEXTCLOUD_DATA="/var/www/nextcloud-data"
# =========================================================
# COLORES
# =========================================================

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
NC='\033[0m'
BOLD="\e[1m"

# ========= Utilidades =========
log(){ echo "$(date '+%F %T') | $1" >> "$LOG_FILE"; }
pausa(){ read -rp "Presiona ENTER para continuar..."; }
ok(){ echo -e "${GREEN}✅ $1${NC}"; }
warn(){ echo -e "${YELLOW}⚠️  $1${NC}"; }
err(){ echo -e "${RED}❌ $1${NC}"; }
require_cmd(){ command -v "$1" >/dev/null 2>&1 || { err "Falta el comando '$1'."; return 1; }; }

pedir_root_pass(){
  if [ -z "$ROOT_PASS" ]; then
    echo -e "${CYAN}🔐 Introduce la contraseña de root de MySQL:${NC}"
    read -rs -p "Contraseña: " ROOT_PASS; echo
  fi
}

confirmar(){ read -rp "⚠️  $1 (s/N): " _c; [[ "$_c" =~ ^[sS]$ ]]; }
# =========================================================
# ROOT
# =========================================================

[ "$EUID" -ne 0 ] && echo "Ejecuta como root" && exit 1

pause(){
read -p "ENTER para continuar..."
}

# =========================================================
# PHP
# =========================================================

detect_php(){

PHPV=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)

if [ -z "${PHPV:-}" ]; then
    PHPV="8.2"
fi

PHPINI="/etc/php/$PHPV/apache2/php.ini"

}

# =========================================================
# INTERNET
# =========================================================

check_internet(){

ping -c 1 8.8.8.8 &>/dev/null || {

    echo -e "${RED}Sin internet${RESET}"
    pause
    return 1
}

}
# =========================================================
# DEPENDENCIAS
# =========================================================
install_dependencies(){

echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN}     INSTALADOR DEPENDENCIAS${RESET}"
echo -e "${CYAN}========================================${RESET}"

check_internet

PACKAGES=(
sudo
apache2
mariadb-server
mariadb-client
libapache2-mod-php
php
php-cli
php-common
php-gd
php-curl
php-zip
php-xml
php-mbstring
php-intl
php-bcmath
php-gmp
php-bz2
php-imagick
php-mysql
php-apcu
php-redis
redis-server
curl
wget
unzip
ffmpeg
imagemagick
cron
certbot
python3-certbot-apache
dnsutils
)

INSTALLED=()
MISSING=()
FAILED=()

echo
echo -e "${YELLOW}Verificando paquetes...${RESET}"
echo

# =========================================================
# VERIFICAR
# =========================================================

for pkg in "${PACKAGES[@]}"; do

    if dpkg -s "$pkg" &>/dev/null; then

        INSTALLED+=("$pkg")

    else

        MISSING+=("$pkg")

    fi

done

# =========================================================
# MOSTRAR INSTALADOS
# =========================================================

echo -e "${GREEN}Paquetes ya instalados:${RESET}"
echo

if [ ${#INSTALLED[@]} -eq 0 ]; then

    echo "Ninguno"

else

    for pkg in "${INSTALLED[@]}"; do
        echo -e "${GREEN}✔${RESET} $pkg"
    done

fi

echo

# =========================================================
# INSTALAR FALTANTES
# =========================================================


if [ ${#MISSING[@]} -gt 0 ]; then

    echo -e "${YELLOW}Paquetes faltantes:${RESET}"
    echo

    for pkg in "${MISSING[@]}"; do
        echo -e "${YELLOW}➜${RESET} $pkg"
    done

    echo
    read -rp "¿Deseas instalar los paquetes faltantes? [s/N]: " RESP

    case "$RESP" in
        s|S|si|SI|y|Y)

            echo
            echo -e "${CYAN}Actualizando repositorios...${RESET}"
            echo

            apt update

            echo
            echo -e "${CYAN}Instalando paquetes faltantes...${RESET}"
            echo

            for pkg in "${MISSING[@]}"; do

                echo -e "${BLUE}Instalando:${RESET} $pkg"

                if apt install -y "$pkg"; then

                    echo -e "${GREEN}✔ Instalado:${RESET} $pkg"

                else

                    echo -e "${RED}✘ Error:${RESET} $pkg"

                    FAILED+=("$pkg")

                fi

                echo

            done
            ;;

        *)

            echo
            echo -e "${RED}Instalación cancelada${RESET}"
            pause
            return 1
            ;;

    esac

else

    echo -e "${GREEN}✔ Todas las dependencias ya están instaladas${RESET}"

fi

echo

# =========================================================
# DETECTAR PHP
# =========================================================

detect_php

if [ ! -f "$PHPINI" ]; then

    echo -e "${RED}No existe:${RESET} $PHPINI"
    pause
    return

fi

# =========================================================
# APACHE
# =========================================================

echo -e "${CYAN}Configurando Apache...${RESET}"

a2enmod rewrite headers env dir mime ssl >/dev/null 2>&1

a2enmod http2 >/dev/null 2>&1 || true

systemctl enable apache2 mariadb redis-server cron >/dev/null 2>&1

systemctl restart apache2
systemctl restart mariadb
systemctl restart redis-server

# =========================================================
# PHP
# =========================================================

echo -e "${CYAN}Optimizando PHP...${RESET}"

sed -i 's/^memory_limit.*/memory_limit = 1024M/' $PHPINI
sed -i 's/^upload_max_filesize.*/upload_max_filesize = 10G/' $PHPINI
sed -i 's/^post_max_size.*/post_max_size = 10G/' $PHPINI
sed -i 's/^max_execution_time.*/max_execution_time = 360/' $PHPINI
sed -i 's/^max_input_time.*/max_input_time = 360/' $PHPINI

grep -q "date.timezone" $PHPINI \
&& sed -i 's|^;*date.timezone.*|date.timezone = America/Santiago|' $PHPINI \
|| echo "date.timezone = America/Santiago" >> $PHPINI

grep -q "opcache.enable=1" $PHPINI \
|| echo "opcache.enable=1" >> $PHPINI

grep -q "opcache.memory_consumption" $PHPINI \
|| echo "opcache.memory_consumption=256" >> $PHPINI

systemctl restart apache2

echo

# =========================================================
# RESUMEN FINAL
# =========================================================

echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN}            RESUMEN FINAL${RESET}"
echo -e "${CYAN}========================================${RESET}"

echo

echo -e "${GREEN}Instalados correctamente:${RESET}"

for pkg in "${PACKAGES[@]}"; do

    if dpkg -s "$pkg" &>/dev/null; then
        echo -e "${GREEN}✔${RESET} $pkg"
    fi

done

echo

echo -e "${RED}No instalados / errores:${RESET}"

if [ ${#FAILED[@]} -eq 0 ]; then

    echo -e "${GREEN}Ninguno${RESET}"

else

    for pkg in "${FAILED[@]}"; do
        echo -e "${RED}✘${RESET} $pkg"
    done

fi

echo
echo -e "${GREEN}✔ Proceso finalizado${RESET}"

pause
}
# =========================================================
# CREAR BASE DE DATOS INSTALACION (CONFIG.PHP)
# =========================================================

setup_database(){

echo
echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN}     CONFIGURACIÓN BASE DE DATOS (config.php)${RESET}"
echo -e "${CYAN}========================================${RESET}"
echo

DEFAULT_DB_NAME="nextcloud"
DEFAULT_DB_USER="usernc"
DEFAULT_DB_PASS=$(openssl rand -base64 12)

echo -e "${YELLOW}1)${RESET} ${GREEN}Crear Base de Datos Automática${RESET}"
echo -e "${YELLOW}2)${RESET} ${CYAN}Configuración Personalizada${RESET}"
echo

read -rp "Selecciona una opción: " DB_OPTION

echo

case "$DB_OPTION" in

1)

    DB_NAME="$DEFAULT_DB_NAME"
    DB_USER="$DEFAULT_DB_USER"
    DB_PASS="$DEFAULT_DB_PASS"

    echo -e "${GREEN}Usando configuración automática:${RESET}"
    echo
    echo -e "${CYAN}DB:${RESET} $DB_NAME"
    echo -e "${CYAN}Usuario:${RESET} $DB_USER"
    echo -e "${CYAN}Password:${RESET} $DB_PASS"
    ;;

2)

    echo -e "${CYAN}Configuración personalizada:${RESET}"
    echo

    read -rp "DB [$DEFAULT_DB_NAME]: " DB_NAME
    DB_NAME=${DB_NAME:-$DEFAULT_DB_NAME}

    read -rp "Usuario [$DEFAULT_DB_USER]: " DB_USER
    DB_USER=${DB_USER:-$DEFAULT_DB_USER}

    read -rp "Password [$DEFAULT_DB_PASS]: " DB_PASS
    DB_PASS=${DB_PASS:-$DEFAULT_DB_PASS}
    ;;

*)

    echo -e "${RED}✘ Opción inválida${RESET}"
    pause
    return
    ;;

esac

DB_HOST="localhost"

# =========================================================
# OPTIMIZAR MARIADB
# =========================================================

echo
echo -e "${CYAN}Configurando MariaDB para Nextcloud...${RESET}"

CONF="/etc/mysql/mariadb.conf.d/50-server.cnf"

grep -q "nextcloud-opt" "$CONF" || cat >> "$CONF" <<EOF

# nextcloud-opt
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
transaction_isolation = READ-COMMITTED
binlog_format = ROW
innodb_file_per_table = 1
innodb_buffer_pool_size = 512M
EOF

systemctl restart mariadb

# =========================================================
# CREAR DB
# =========================================================

echo
echo -e "${CYAN}Creando base de datos...${RESET}"

mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"

# =========================================================
# CREAR USUARIO
# =========================================================

echo
echo -e "${CYAN}Creando usuario MariaDB...${RESET}"

mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"

# =========================================================
# PERMISOS
# =========================================================

echo
echo -e "${CYAN}Asignando permisos...${RESET}"

mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"

mysql -e "FLUSH PRIVILEGES;"

# =========================================================
# Crear copia de seguridad nextcloud_db.conf
# =========================================================
echo -e "${YELLOW} Renombrando nextcloud_db.conf...${RESET}"
[ -f /root/nextcloud_db.conf ] && \
mv /root/nextcloud_db.conf "/root/nextcloud_db_$(date +%F_%H-%M-%S).conf"
echo -e "${GREEN}✔ Archivo Renombrado ${RESET}"
echo

if [ -f "$DB_FILE" ]; then
    echo -e "${YELLOW}Eliminando configuración anterior si existe...${RESET}"
    rm -f "$DB_FILE"
    echo -e "${GREEN}✔ Archivo eliminado${RESET}"
else
    echo -e "${CYAN}No existe configuración anterior${RESET}"
fi
# =========================================================
# GUARDAR CONFIG
# =========================================================

cat > "$DB_FILE" <<EOF
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASS="${DB_PASS}"
DB_HOST="${DB_HOST}"
EOF

chmod 600 "$DB_FILE"

# =========================================================
# FINAL
# =========================================================

echo
echo -e "${GREEN}========================================${RESET}"
echo -e "${GREEN}     BASE DE DATOS CONFIGURADA${RESET}"
echo -e "${GREEN}========================================${RESET}"

echo
echo -e "${CYAN}DB:${RESET} $DB_NAME"
echo -e "${CYAN}Usuario:${RESET} $DB_USER"
echo -e "${CYAN}Host:${RESET} $DB_HOST"

echo
echo -e "${GREEN}✔ Base de datos creada correctamente${RESET}"
echo

pause

}

# ========= RESPALDO / RESTAURACIÓN MYSQL 2.0 =========

BACKUP_DIR="/root/BackupDB"

menu_mysql_backup(){

  pedir_root_pass
  mkdir -p "$BACKUP_DIR"

  while true; do
    clear

    echo -e "${CYAN}${BOLD}=== RESPALDO / RESTAURACIÓN MYSQL ===${NC}"
    echo -e " ${YELLOW}1)${NC} Respaldar BD MYSQL + Info"
    echo -e " ${YELLOW}2)${NC} Restaurar BD MYSQL Listado"
    echo -e " ${YELLOW}3)${NC} Listar respaldos MYSQL + Info"
	echo -e " ${YELLOW}4)${NC} Restaurar BD MYSQL Listado + Info"
	echo -e " ${YELLOW}5)${NC} Crear BD + Usuario MYSQL"
    echo -e " ${YELLOW}6)${NC} Eliminar BD + Usuario MYSQL"
	echo -e " ${YELLOW}7)${NC} Reiniciar servicio MySQL"
    echo -e " ${CYAN}0) Volver${NC}"

    read -rp "> " op

    case "$op" in

      1)

    echo -e "${YELLOW}Bases de datos disponibles:${NC}"

    DBS=$(mysql -uroot -p"$ROOT_PASS" -e "SHOW DATABASES;" \
      | grep -Ev "Database|information_schema|mysql|performance_schema|sys")

    echo -e "${CYAN}0) Cancelar${NC}"

    select db in $DBS; do

      [[ "$REPLY" == "0" ]] && {
        warn "Cancelado."
        break
      }

      [ -n "$db" ] || {
        warn "Selección inválida"
        break
      }

      FECHA=$(date +%F_%H-%M)

      # =========================================================
      # VERSION NEXTCLOUD
      # =========================================================

      if [ -f "$NC_DIR/occ" ]; then

        NC_VERSION=$(
          sudo -u "$WEB_USER" php "$NC_DIR/occ" status --output=json 2>/dev/null \
          | grep -oP '"version"\s*:\s*"\K[^"]+'
        )

      fi

      [ -z "$NC_VERSION" ] && NC_VERSION="unknown"

      # limpiar caracteres raros
      NC_VERSION_CLEAN=$(echo "$NC_VERSION" | tr '.' '_')

      # =========================================================
      # ARCHIVO BACKUP
      # =========================================================

      DB_BACKUP="$BACKUP_DIR/${db}_v${NC_VERSION_CLEAN}_${FECHA}.sql.gz"

      echo -e "${CYAN}========================================${RESET}"
      echo -e "${WHITE}      BACKUP DATABASE MYSQL${RESET}"
      echo -e "${CYAN}========================================${RESET}"
      echo

      echo -e "${GREEN}Base de datos:${RESET} $db"
      echo -e "${GREEN}Versión Nextcloud:${RESET} $NC_VERSION"
      echo -e "${GREEN}Destino:${RESET} $DB_BACKUP"
      echo

      mysqldump -uroot -p"$ROOT_PASS" "$db" | gzip > "$DB_BACKUP"

      if [ $? -eq 0 ]; then
        ok "Respaldo creado correctamente."
      else
        err "Error al crear respaldo."
      fi

      break

    done

    pausa
;;

     2)

   echo -e "${YELLOW}Respaldos disponibles:${NC}"

    FILES=$(ls "$BACKUP_DIR"/*.sql.gz 2>/dev/null)

    [ -z "$FILES" ] && {
      warn "No hay respaldos disponibles."
      pausa
      continue
    }

    echo -e "${CYAN}0) Cancelar${NC}"

    select file in $FILES; do

      [[ "$REPLY" == "0" ]] && {
        warn "Cancelado."
        break
      }

      [ -n "$file" ] || {
        warn "Selección inválida"
        break
      }

      echo
      echo -e "${YELLOW}Bases de datos disponibles:${NC}"

      DBS=$(mysql -uroot -p"$ROOT_PASS" -e "SHOW DATABASES;" \
        | grep -Ev "Database|information_schema|mysql|performance_schema|sys")

      echo -e "${CYAN}0) Cancelar${NC}"

      select db in $DBS; do
10
        [[ "$REPLY" == "0" ]] && {
          warn "Cancelado."
          break
        }

        [ -n "$db" ] || {
          warn "Selección inválida"
          break
        }

        echo
        echo -e "${YELLOW}Restaurando respaldo en:${NC} $db"

        gunzip < "$file" | mysql -uroot -p"$ROOT_PASS" "$db"

        if [ $? -eq 0 ]; then
          ok "BD restaurada correctamente en $db"
        else
          err "Error al restaurar BD"
        fi

        break

      done

      break

    done

    pausa
;;

3)

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}      RESPALDOS DISPONIBLES MYSQL DETALLE 2.0${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    if ls "$BACKUP_DIR"/*.sql.gz >/dev/null 2>&1; then

        for file in "$BACKUP_DIR"/*.sql.gz; do

            SIZE=$(du -h "$file" | awk '{print $1}')
            FECHA_MOD=$(date -r "$file" "+%Y-%m-%d %H:%M")
            NOMBRE=$(basename "$file")

            # =====================================================
            # EXTRAER DATOS DEL NOMBRE
            # FORMATO:
            # nextcloud_v29_0_4_1_2026-05-14_02-05.sql.gz
            # =====================================================

            DB_NAME=$(echo "$NOMBRE" | sed -E 's/_v[0-9_]+_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}\.sql\.gz//')

            VERSION=$(echo "$NOMBRE" \
              | sed -E 's/.*_v([0-9_]+)_[0-9]{4}-.*/\1/' \
              | tr '_' '.')

            echo -e "${GREEN}Archivo:${RESET} $NOMBRE"
            echo -e "${GREEN}Base de datos:${RESET} ${DB_NAME:-unknown}"
            echo -e "${GREEN}Versión Nextcloud:${RESET} ${VERSION:-unknown}"
            echo -e "${GREEN}Tamaño:${RESET} $SIZE"
            echo -e "${GREEN}Fecha:${RESET} $FECHA_MOD"

            echo -e "${CYAN}----------------------------------------${RESET}"

        done

    else

        warn "No hay respaldos disponibles en $BACKUP_DIR"

    fi

    pausa
;;

4)
    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}      RESTAURAR BACKUP MYSQL${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    mapfile -t FILES < <(find "$BACKUP_DIR" -maxdepth 1 -name "*.sql.gz" | sort)

    [ ${#FILES[@]} -eq 0 ] && {
        warn "No hay respaldos disponibles."
        pausa
        continue
    }

    # =====================================================
    # LISTAR RESPALDOS
    # =====================================================

    for i in "${!FILES[@]}"; do

        file="${FILES[$i]}"

        SIZE=$(du -h "$file" | awk '{print $1}')
        FECHA_MOD=$(date -r "$file" "+%Y-%m-%d %H:%M")
        NOMBRE=$(basename "$file")

        DB_NAME=$(echo "$NOMBRE" \
          | sed -E 's/_v[0-9_]+_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}\.sql\.gz//')

        VERSION=$(echo "$NOMBRE" \
          | sed -E 's/.*_v([0-9_]+)_[0-9]{4}-.*/\1/' \
          | tr '_' '.')

        echo -e "${YELLOW}$((i+1)))${NC} $NOMBRE"
        echo -e "   ${GREEN}Backup BD:${NC} ${DB_NAME:-unknown}"
        echo -e "   ${GREEN}Versión:${NC} ${VERSION:-unknown}"
        echo -e "   ${GREEN}Tamaño:${NC} $SIZE"
        echo -e "   ${GREEN}Fecha:${NC} $FECHA_MOD"
        echo

    done

    echo -e "${CYAN}0) Cancelar${NC}"
    echo

    read -rp "Selecciona respaldo: " opt

    [[ "$opt" == "0" ]] && continue

    [[ "$opt" =~ ^[0-9]+$ ]] || {
        warn "Opción inválida"
        pausa
        continue
    }

    (( opt >= 1 && opt <= ${#FILES[@]} )) || {
        warn "Número fuera de rango"
        pausa
        continue
    }

    file="${FILES[$((opt-1))]}"

    # =====================================================
    # LISTAR BASES DE DATOS DISPONIBLES
    # =====================================================

    echo
    echo -e "${YELLOW}Bases de datos disponibles:${NC}"
    echo

    DBS=$(mysql -uroot -p"$ROOT_PASS" -e "SHOW DATABASES;" \
      | grep -Ev "Database|information_schema|mysql|performance_schema|sys")

    select db in $DBS; do

        [ -n "$db" ] || {
            warn "Selección inválida"
            break
        }

        echo
        echo -e "${YELLOW}Restaurando respaldo en:${NC} $db"
        echo

        gunzip < "$file" | mysql -uroot -p"$ROOT_PASS" "$db"

        if [ $? -eq 0 ]; then
            ok "BD restaurada correctamente en $db"
        else
            err "Error al restaurar BD"
        fi

        break

    done

    pausa
;;

5)

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}      CREAR BASE DE DATOS MYSQL${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    read -rp "Nombre base de datos (0 cancelar): " NEW_DB

    [[ "$NEW_DB" == "0" ]] && {
        warn "Cancelado"
        pausa
        continue
    }

    read -rp "Usuario MYSQL (0 cancelar): " NEW_USER

    [[ "$NEW_USER" == "0" ]] && {
        warn "Cancelado"
        pausa
        continue
    }

    read -rsp "Contraseña MYSQL (0 cancelar): " NEW_PASS
    echo

    [[ "$NEW_PASS" == "0" ]] && {
        warn "Cancelado"
        pausa
        continue
    }

    # validar vacío
    [ -z "$NEW_DB" ] && {
        err "Nombre BD vacío"
        pausa
        continue
    }

    [ -z "$NEW_USER" ] && {
        err "Usuario vacío"
        pausa
        continue
    }

    mysql -uroot -p"$ROOT_PASS" -e "
    CREATE DATABASE \`$NEW_DB\`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;
    "

    if [ $? -ne 0 ]; then
        err "No se pudo crear la base de datos"
        pausa
        continue
    fi

    mysql -uroot -p"$ROOT_PASS" -e "
    CREATE USER '$NEW_USER'@'localhost' IDENTIFIED BY '$NEW_PASS';
    GRANT ALL PRIVILEGES ON \`$NEW_DB\`.* TO '$NEW_USER'@'localhost';
    FLUSH PRIVILEGES;
    "

    if [ $? -eq 0 ]; then

        echo
        ok "Base de datos creada correctamente"
        echo

        echo -e "${GREEN}Base de datos:${RESET} $NEW_DB"
        echo -e "${GREEN}Usuario:${RESET} $NEW_USER"
        echo -e "${GREEN}Contraseña:${RESET} $NEW_PASS"

    else

        err "Error al crear usuario MYSQL"

    fi

    pausa
;;

6)

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}      ELIMINAR BD + USUARIO MYSQL${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    DBS=$(mysql -uroot -p"$ROOT_PASS" -e "SHOW DATABASES;" \
      | grep -Ev "Database|information_schema|mysql|performance_schema|sys")

    echo -e "${YELLOW}Selecciona base de datos:${NC}"
    echo -e "${CYAN}0) Cancelar${NC}"

    select DEL_DB in $DBS; do

        [[ "$REPLY" == "0" ]] && {
            warn "Cancelado"
            break
        }

        [ -n "$DEL_DB" ] || {
            warn "Selección inválida"
            break
        }

        echo
        echo -e "${YELLOW}Usuarios MYSQL:${NC}"

        USERS=$(mysql -uroot -p"$ROOT_PASS" -N -e "
        SELECT User FROM mysql.user
        WHERE User NOT IN ('root','mysql','mariadb.sys');
        ")

        echo -e "${CYAN}0) Cancelar${NC}"

        select DEL_USER in $USERS; do

            [[ "$REPLY" == "0" ]] && {
                warn "Cancelado"
                break
            }

            [ -n "$DEL_USER" ] || {
                warn "Selección inválida"
                break
            }

            echo
            read -rp "Confirmar eliminación de BD '$DEL_DB' y usuario '$DEL_USER' ? (s/n): " CONFIRM

            [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]] && {
                warn "Cancelado"
                break
            }

            mysql -uroot -p"$ROOT_PASS" -e "
            DROP DATABASE \`$DEL_DB\`;
            DROP USER '$DEL_USER'@'localhost';
            FLUSH PRIVILEGES;
            "

            if [ $? -eq 0 ]; then
                ok "BD y usuario eliminados correctamente"
            else
                err "Error al eliminar BD o usuario"
            fi

            break

        done

        break

    done

    pausa
;;
      7) sudo systemctl restart mysql && ok "MySQL reiniciado." || err "Error reiniciando MySQL."; pausa ;;
      0)
        return
      ;;

      *)
        warn "Opción inválida"
        pausa
      ;;

    esac
  done
}

# =========================================================
# DETECTAR LTS
# =========================================================

is_lts() {

    local ver="$1"
    local major="${ver%%.*}"

    # Ajusta aquí las versiones LTS reales
    if [[ "$major" -le 31 ]]; then
        echo "LTS"
    else
        echo "STABLE"
    fi
}

# =========================================================
# VERSION
# =========================================================

select_version(){

check_internet

    get_nextcloud_versions || return

    echo
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW} Selecciona versión de Nextcloud${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo

    MENU=()

    i=1
    for v in $VERSIONS; do

        TYPE=$(is_lts "$v")

        if [[ "$TYPE" == "LTS" ]]; then
            LABEL="${GREEN}$v (LTS)${RESET}"
        else
            LABEL="${CYAN}$v (STABLE)${RESET}"
        fi

        MENU+=("$v")
        echo -e "${YELLOW}$i)${RESET} $LABEL"
        ((i++))

    done

    echo -e "${YELLOW}l)${RESET} latest"
    echo

    read -rp "Selecciona opción: " opt

    if [[ "$opt" == "l" ]]; then
        VERSION="latest"
        return
    fi

    if [[ "$opt" =~ ^[0-9]+$ ]] && (( opt >= 1 && opt <= ${#MENU[@]} )); then
        VERSION="${MENU[$((opt-1))]}"
    else
        echo -e "${RED}✘ Selección inválida${RESET}"
        return 1
    fi

    echo -e "${GREEN}✔ Versión seleccionada: $VERSION${RESET}"

}
# =========================================================
# Obteniendo versiones disponibles
# =========================================================
get_nextcloud_versions() {

    echo -e "${CYAN}Obteniendo versiones disponibles...${RESET}"

    VERSIONS=$(curl -s https://download.nextcloud.com/server/releases/ \
        | grep -oP 'nextcloud-\K[0-9]+\.[0-9]+\.[0-9]+' \
        | sort -Vr \
        | uniq \
        | head -n 10)

    if [[ -z "$VERSIONS" ]]; then
        echo -e "${RED}✘ No se pudieron obtener versiones${RESET}"
        return 1
    fi
}
# =========================================================
# VHOST
# =========================================================
create_vhost(){

echo -ne "${YELLOW}Dominio ${CYAN}Eje: nextcloud.ddns.net:${RESET} "
read DOMAIN
echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN}           CONFIGURAR SSL${RESET}"
echo -e "${CYAN}========================================${RESET}"

echo -e "${YELLOW}1)${RESET} TurnKey (.pem)"
echo -e "${YELLOW}2)${RESET} Let's Encrypt"
echo -e "${YELLOW}3)${RESET} Sin SSL"

echo
echo -ne "${GREEN}SSL:${RESET} "
read SSL

CONF="/etc/apache2/sites-available/nextcloud.conf"

if [ "$SSL" == "1" ]; then

cat > $CONF <<EOF
<VirtualHost *:80>
ServerName $DOMAIN
Redirect / https://$DOMAIN/
</VirtualHost>

<VirtualHost *:443>
ServerName $DOMAIN
DocumentRoot $NC_DIR
SSLEngine on
SSLCertificateFile /etc/ssl/private/cert.pem
SSLCertificateKeyFile /etc/ssl/private/cert.key
<Directory $NC_DIR/>
Require all granted
AllowOverride All
</Directory>
</VirtualHost>
EOF

elif [ "$SSL" == "2" ]; then

apt install -y certbot python3-certbot-apache

cat > $CONF <<EOF
<VirtualHost *:80>
ServerName $DOMAIN
DocumentRoot $NC_DIR
</VirtualHost>
EOF

a2ensite nextcloud.conf
systemctl reload apache2
certbot --apache -d $DOMAIN

else

cat > $CONF <<EOF
<VirtualHost *:80>
ServerName $DOMAIN
DocumentRoot $NC_DIR
</VirtualHost>
EOF

fi

a2ensite nextcloud.conf
systemctl reload apache2

echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN}           VHOST CONFIGURADO ${RESET}"
echo -e "${CYAN}========================================${RESET}"
pause
}

# =========================================================
# PERMISOS
# =========================================================

fix_permissions(){

chown -R $WEB_USER:$WEB_USER $NC_DIR
chown -R $WEB_USER:$WEB_USER $DATA_DIR

find $NC_DIR -type d -exec chmod 750 {} \;
find $NC_DIR -type f -exec chmod 640 {} \;

chmod 770 $DATA_DIR

}

# =========================================================
# REDIS
# =========================================================

configure_redis(){

[ ! -f "$NC_DIR/config/config.php" ] && return

sudo -u $WEB_USER php -d memory_limit=1G $NC_DIR/occ config:system:set memcache.local --value='\OC\Memcache\APCu'

sudo -u $WEB_USER php -d memory_limit=1G $NC_DIR/occ config:system:set memcache.locking --value='\OC\Memcache\Redis'

sudo -u $WEB_USER php -d memory_limit=1G $NC_DIR/occ config:system:set redis host --value='127.0.0.1'

sudo -u $WEB_USER php -d memory_limit=1G $NC_DIR/occ config:system:set redis port --value='6379'

}

# =========================================================
# CRON
# =========================================================

configure_cron(){

(crontab -u www-data -l 2>/dev/null; \
echo "*/5 * * * * php -f $NC_DIR/cron.php") | crontab -u www-data -

sudo -u $WEB_USER php -d memory_limit=1G $NC_DIR/occ background:cron

}
# =========================================================
# VERIFICAR INSTALACIÓN NEXTCLOUD
# =========================================================

check_nextcloud_installed() {

    echo
    echo -e "${CYAN}Verificando instalación de Nextcloud...${RESET}"
    echo

    NEXTCLOUD_FOUND=false

    # Posibles rutas
    POSSIBLE_DIRS=(
        "/var/www/nextcloud"
        "/var/www/html/nextcloud"
        "/srv/www/nextcloud"
    )

    NC_PATH=""
    NC_VERSION=""
    VHOST_FILES=()
    DOMAINS=()

    # =====================================================
    # BUSCAR INSTALLATION
    # =====================================================

    for dir in "${POSSIBLE_DIRS[@]}"; do

        if [ -f "$dir/version.php" ]; then
            NEXTCLOUD_FOUND=true
            NC_PATH="$dir"
            break
        fi

    done

    # Buscar en Apache si no encontró ruta conocida
    if [ "$NEXTCLOUD_FOUND" = false ]; then

        FOUND=$(find /var/www -maxdepth 3 -type f -name version.php 2>/dev/null \
            | grep nextcloud | head -n1)

        if [ -n "$FOUND" ]; then
            NEXTCLOUD_FOUND=true
            NC_PATH=$(dirname "$FOUND")
        fi

    fi

    # =====================================================
    # SI NEXTCLOUD EXISTE
    # =====================================================

    if [ "$NEXTCLOUD_FOUND" = true ]; then

        # Obtener versión
        if [ -f "$NC_PATH/version.php" ]; then

            NC_VERSION=$(php -r "
                include '$NC_PATH/version.php';
                echo \$OC_VersionString;
            " 2>/dev/null)

        fi

        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${GREEN}NEXTCLOUD YA ESTÁ INSTALADO${RESET}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo

        echo -e "${CYAN}Versión:${RESET} ${YELLOW}${NC_VERSION:-Desconocida}${RESET}"
        echo -e "${CYAN}Ruta:${RESET} ${YELLOW}$NC_PATH${RESET}"
        echo

        # =================================================
        # BUSCAR VHOSTS APACHE
        # =================================================

        echo -e "${CYAN}VirtualHosts detectados:${RESET}"
        echo

        while IFS= read -r file; do

            if grep -qi "DocumentRoot.*$NC_PATH" "$file"; then
                VHOST_FILES+=("$file")
            fi

        done < <(find /etc/apache2/sites-enabled \
                        /etc/apache2/sites-available \
                        -type f -name "*.conf" 2>/dev/null)

        if [ ${#VHOST_FILES[@]} -eq 0 ]; then

            echo -e "${YELLOW}No se encontraron VirtualHosts asociados.${RESET}"

        else

            for vh in "${VHOST_FILES[@]}"; do

                echo -e "${GREEN}Archivo:${RESET} $vh"

                SERVERNAME=$(grep -i "ServerName" "$vh" \
                    | awk '{print $2}' \
                    | head -n1)

                SERVERALIAS=$(grep -i "ServerAlias" "$vh" \
                    | cut -d' ' -f2-)

                DOCROOT=$(grep -i "DocumentRoot" "$vh" \
                    | awk '{print $2}' \
                    | head -n1)

                [ -n "$SERVERNAME" ] && \
                    echo -e "  ${CYAN}DNS:${RESET} $SERVERNAME"

                [ -n "$SERVERALIAS" ] && \
                    echo -e "  ${CYAN}Alias:${RESET} $SERVERALIAS"

                [ -n "$DOCROOT" ] && \
                    echo -e "  ${CYAN}DocumentRoot:${RESET} $DOCROOT"

                echo

            done

        fi

        echo -e "${GREEN}⚠ Nextcloud ya está instalado.${RESET}"
        echo -e "${YELLOW}Debes desinstalar Nextcloud antes de continuar.${RESET}"
        echo
        echo
        echo
        printf "${CYAN}Presiona ENTER para continuar...${RESET}"
        read _
        return 1


    fi

    # =====================================================
    # NO INSTALADO
    # =====================================================

    echo -e "${GREEN}✔ No se encontró una instalación de Nextcloud.${RESET}"
    echo -e "${GREEN}Continuando instalación...${RESET}"
    echo

    return 0
}
# =========================================================
# INSTALL NEXTCLOUD PRO (FIXED) - Instalador Inteligente PRO
# =========================================================

install_nextcloud(){
check_nextcloud_installed || return
install_dependencies
setup_database
select_version

source "$DB_FILE"

cd /tmp || return

rm -f nextcloud.zip

# =========================================================
# CONSTRUIR URL DE DESCARGA SEGURA
# =========================================================

if [[ "$VERSION" == "latest" ]]; then

    DL="https://download.nextcloud.com/server/releases/latest.zip"

else

    # validar formato versión (ej: 29.0.6)
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}✘ Versión inválida: $VERSION${RESET}"
        pause
        return 1
    fi

    DL="https://download.nextcloud.com/server/releases/nextcloud-${VERSION}.zip"

    # validar existencia URL
    if ! curl -s --head --fail "$DL" >/dev/null; then
        echo -e "${RED}✘ No existe esta versión en Nextcloud:${RESET} $VERSION"
        pause
        return 1
    fi

fi

# =========================================================
# DESCARGAR NEXTCLOUD
# =========================================================

echo
echo -e "${YELLOW}Descargando Nextcloud...${RESET}"
echo "$DL"
echo

wget -q --show-progress -O nextcloud.zip "$DL" || {
    echo -e "${RED}✘ Error descargando Nextcloud${RESET}"
    pause
    return 1
}

# =========================================================
# VALIDAR TIPO ARCHIVO
# =========================================================

if ! file nextcloud.zip | grep -q "Zip archive"; then
    echo -e "${RED}✘ El archivo descargado no es un ZIP válido${RESET}"
    pause
    return 1
fi

# =========================================================
# VALIDAR ZIP
# =========================================================

echo
echo -e "${CYAN}Verificando integridad ZIP...${RESET}"

if ! unzip -t nextcloud.zip &>/dev/null; then
    echo -e "${RED}✘ ZIP corrupto${RESET}"
    pause
    return 1
fi

echo -e "${GREEN}✔ Archivo verificado${RESET}"

# =========================================================
# ELIMINAR INSTALACION ANTERIOR
# =========================================================

echo
echo -e "${CYAN}Eliminando instalación anterior...${RESET}"

rm -rf "$NC_DIR"

# =========================================================
# EXTRAER
# =========================================================

echo
echo -e "${CYAN}Extrayendo archivos...${RESET}"
echo

unzip -o nextcloud.zip >/dev/null || {
    echo -e "${RED}✘ Error extrayendo archivos${RESET}"
    pause
    return 1
}

echo
echo -e "${GREEN}✔ Archivos extraídos${RESET}"

# =========================================================
# MOVER
# =========================================================

echo
echo -e "${CYAN}Moviendo carpeta Nextcloud a $NC_DIR ...${RESET}"
echo

mv nextcloud "$NC_DIR" || {
    echo -e "${RED}✘ Error moviendo Nextcloud${RESET}"
    pause
    return 1
}

echo
echo -e "${GREEN}✔ Movido con éxito${RESET}"

# =========================================================
# CREAR DATA DIR
# =========================================================

mkdir -p "$DATA_DIR"

# =========================================================
# PERMISOS
# =========================================================

echo
echo -e "${CYAN}Aplicando permisos...${RESET}"

fix_permissions

# =========================================================
# APACHE
# =========================================================

echo
echo -e "${CYAN}Creando VirtualHost Apache...${RESET}"
echo
echo
create_vhost

# =========================================================
# ADMIN
# =========================================================

echo
echo -e "${YELLOW}==================================================${RESET}"
echo -e "${YELLOW}     Configuración Crear Administrador            ${RESET}"
echo -e "${CYAN}  Puedes Crear User Que Tenga Carpeta en DATA        ${RESET}"
echo -e "${YELLOW}==================================================${RESET}"

read -rp "Usuario admin: " ADMIN_USER
read -srp "Password admin: " ADMIN_PASS
echo

# =========================================================
# LIMPIAR RESIDUOS DATA NEXTCLOUD
# =========================================================

if [ -d "$DATA_DIR" ] && [ "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then

    echo
    echo -e "${YELLOW}⚠ DATA existente detectado${RESET}"
    echo -e "${CYAN}Ruta:${RESET} $DATA_DIR"
    echo

    printf "${CYAN}¿Limpiar residuos de instalación anterior? (s/n): ${RESET}"
    read CLEAN_DATA

    if [[ "$CLEAN_DATA" =~ ^[sS]$ ]]; then

        echo
        echo -e "${CYAN}Limpiando residuos Nextcloud...${RESET}"

        # =====================================================
        # CARPETAS APPDATA Y UPDATER
        # =====================================================

        echo
        echo -e "${CYAN}Eliminando cache appdata...${RESET}"

        rm -rf "$DATA_DIR"/appdata_* 2>/dev/null
        rm -rf "$DATA_DIR"/updater-* 2>/dev/null

        echo -e "${GREEN}✔ Cache eliminada${RESET}"

        # =====================================================
        # LOGS
        # =====================================================

        echo
        echo -e "${CYAN}Eliminando logs Nextcloud...${RESET}"

        rm -f "$DATA_DIR/nextcloud.log" 2>/dev/null

        find "$DATA_DIR" -type f -name "*.log" -delete 2>/dev/null

        echo -e "${GREEN}✔ Logs eliminados${RESET}"

        # =====================================================
        # ARCHIVOS TEMPORALES
        # =====================================================

        echo
        echo -e "${CYAN}Eliminando archivos temporales...${RESET}"

        find "$DATA_DIR" -type f \( \
            -name "*.html" -o \
            -name "*.txt"  -o \
            -name "*.config" -o \
            -name "*.bak" -o \
            -name "*.old" \
        \) -delete 2>/dev/null

        echo -e "${GREEN}✔ Temporales eliminados${RESET}"

        # =====================================================
        # REPARAR PERMISOS
        # =====================================================

        echo
        echo -e "${CYAN}Corrigiendo permisos...${RESET}"

        chown -R "$WEB_USER:$WEB_USER" "$DATA_DIR"

        find "$DATA_DIR" -type d -exec chmod 750 {} \;
        find "$DATA_DIR" -type f -exec chmod 640 {} \;

        echo -e "${GREEN}✔ Permisos corregidos${RESET}"

        echo
        echo -e "${GREEN}✔ Residuos eliminados correctamente${RESET}"

    else

        echo
        echo -e "${YELLOW}Limpieza cancelada${RESET}"

    fi

fi

# =========================================================
# INSTALAR NEXTCLOUD
# REUTILIZANDO DATA EXISTENTE DEL ADMIN
# =========================================================

echo
echo -e "${CYAN}Instalando Nextcloud...${RESET}"

USER_DATA_DIR="$DATA_DIR/$ADMIN_USER"
TEMP_BACKUP="${DATA_DIR}/.${ADMIN_USER}_backup_$(date +%s)"

RESTORE_ADMIN=0

# =========================================================
# DETECTAR DATA EXISTENTE
# =========================================================

if [ -d "$USER_DATA_DIR" ]; then

    echo
    echo -e "${YELLOW}⚠ DATA existente detectada para:${RESET} $ADMIN_USER"
    echo -e "${CYAN}Ruta:${RESET} $USER_DATA_DIR"
    echo

    printf "${CYAN}¿Reutilizar archivos existentes? (s/n): ${RESET}"
    read REUSE_ADMIN

    if [[ "$REUSE_ADMIN" =~ ^[sS]$ ]]; then

        echo
        echo -e "${CYAN}Respaldando carpeta temporalmente...${RESET}"

        mv "$USER_DATA_DIR" "$TEMP_BACKUP"

        if [ $? -ne 0 ]; then
            echo -e "${RED}✘ Error moviendo carpeta${RESET}"
            return
        fi

        RESTORE_ADMIN=1

        echo -e "${GREEN}✔ Respaldo realizado${RESET}"

    fi
fi

# =========================================================
# LIMPIAR RESIDUOS
# =========================================================

rm -rf "$DATA_DIR"/appdata_* 2>/dev/null
rm -rf "$DATA_DIR"/updater-* 2>/dev/null
rm -f "$DATA_DIR"/nextcloud.log 2>/dev/null

# =========================================================
# INSTALAR NEXTCLOUD
# =========================================================

echo
echo -e "${CYAN}Ejecutando instalación...${RESET}"

sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" maintenance:install \
--database "mysql" \
--database-name "$DB_NAME" \
--database-user "$DB_USER" \
--database-pass "$DB_PASS" \
--admin-user "$ADMIN_USER" \
--admin-pass "$ADMIN_PASS" \
--data-dir "$DATA_DIR"

# =========================================================
# VALIDAR INSTALACIÓN
# =========================================================

if [ $? -ne 0 ]; then

    echo
    echo -e "${RED}✘ Error instalando Nextcloud${RESET}"

    # Restaurar carpeta original
    if [ "$RESTORE_ADMIN" = "1" ] && [ -d "$TEMP_BACKUP" ]; then
        mv "$TEMP_BACKUP" "$USER_DATA_DIR"
    fi

    return
fi

# =========================================================
# RESTAURAR ARCHIVOS ADMIN
# =========================================================

if [ "$RESTORE_ADMIN" = "1" ]; then

    echo
    echo -e "${CYAN}Restaurando archivos del administrador...${RESET}"

    mkdir -p "$USER_DATA_DIR/files"

    # Restaurar SOLO archivos útiles
    if [ -d "$TEMP_BACKUP/files" ]; then

        rsync -a \
          --exclude="cache" \
          --exclude="uploads" \
          --exclude="files_trashbin" \
          --exclude="files_versions" \
          --exclude="appdata_*" \
          --exclude=".cache" \
          "$TEMP_BACKUP/files/" "$USER_DATA_DIR/files/"

    fi

    # Limpiar residuos
    rm -rf "$USER_DATA_DIR/files/cache" 2>/dev/null
    rm -rf "$USER_DATA_DIR/files/uploads" 2>/dev/null
    rm -rf "$USER_DATA_DIR/files/files_trashbin" 2>/dev/null
    rm -rf "$USER_DATA_DIR/files/files_versions" 2>/dev/null

    # Eliminar backup temporal
    rm -rf "$TEMP_BACKUP"

    echo -e "${GREEN}✔ Archivos restaurados${RESET}"

fi

# =========================================================
# REPARAR PERMISOS
# =========================================================

echo
echo -e "${CYAN}Corrigiendo permisos...${RESET}"

chown -R "$WEB_USER:$WEB_USER" "$DATA_DIR"

find "$DATA_DIR" -type d -exec chmod 750 {} \;
find "$DATA_DIR" -type f -exec chmod 640 {} \;

echo -e "${GREEN}✔ Permisos corregidos${RESET}"

# =========================================================
# REINDEXAR ARCHIVOS
# =========================================================

echo
echo -e "${CYAN}Escaneando archivos...${RESET}"

sudo -u "$WEB_USER" php "$NC_DIR/occ" files:scan --path="$ADMIN_USER/files"

echo -e "${GREEN}✔ Archivos indexados${RESET}"

echo
echo -e "${GREEN}✔ Nextcloud instalado correctamente${RESET}"

# =========================================================
# CONTINUAR SCRIPT
# =========================================================

# NO pausa
# NO return
# continúa automáticamente con el resto del script

# =========================================================
# REDIS + CRON
# =========================================================

echo
echo -e "${CYAN}Configurando REDIS...${RESET}"
configure_redis
echo
echo -e "${CYAN}REDIS Configurado ...${RESET}"
echo
echo -e "${CYAN}Configurando CRON...${RESET}"
configure_cron
echo
echo -e "${CYAN}CRON Configurado ...${RESET}"
# =========================================================
# REPARAR NEXTCLOUD
# =========================================================

echo
echo -e "${CYAN}Reparando instalación...${RESET}"

sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" maintenance:repair || true

# =========================================================
# DB FIXES
# =========================================================

echo
echo -e "${CYAN}Agregando índices faltantes...${RESET}"

sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" db:add-missing-indices || true

echo
echo -e "${CYAN}Agregando columnas faltantes...${RESET}"

sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" db:add-missing-columns || true

# =========================================================
# ESCANEO DE ARCHIVOS (IMPORTANTE)
# =========================================================

echo
echo -e "${CYAN}Escaneando archivos de usuarios...${RESET}"
echo -e "${YELLOW}Esto puede tardar dependiendo del tamaño del DATA...${RESET}"

sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" files:scan --all

echo -e "${GREEN}✔ Escaneo completado${RESET}"

# =========================================================
# TRUSTED DOMAINS
# =========================================================

echo
echo -e "${CYAN}========================================${RESET}"
echo -e "${CYAN} Agrega Dominio/IP a trusted_domains (config.php) ${RESET}"
echo -e "${CYAN}========================================${RESET}"
echo
echo -e "${YELLOW} Ingresa Dominios o IP WAN/LAN (de uno en uno)"
echo
echo -e "${CYAN} Ejemplos:"
echo
echo -e "${YELLOW}  llancor-nextcloud.duckdns.org"
echo
echo -e "${YELLOW}  192.168.10.100"
echo
echo -e "${CYAN} Escribe 'fin' Para Terminar"
echo

DOMAINS=()

while true; do

printf "${CYAN}INGRESAR Dominio / IP:${RESET} "
read domain

    domain=$(echo "$domain" | tr -d '\r\n ')

    # salir
    [[ "$domain" == "fin" ]] && break

    # vacío
    if [[ -z "$domain" ]]; then
        echo -e "${YELLOW}⚠ Campo vacío ignorado${RESET}"
        continue
    fi

    # duplicado
    if [[ " ${DOMAINS[*]} " =~ " $domain " ]]; then
        echo -e "${YELLOW}⚠ Ya existe:${RESET} $domain"
        continue
    fi

    DOMAINS+=("$domain")

done

# fallback
if [ ${#DOMAINS[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠ No se ingresaron dominios, usando IP local${RESET}"
    DOMAINS+=("$(hostname -I | awk '{print $1}')")
fi

# =========================================================
# APLICAR TRUSTED DOMAINS
# =========================================================

echo
echo -e "${CYAN}Aplicando trusted_domains...${RESET}"

i=0

for domain in "${DOMAINS[@]}"; do

    echo -e "${CYAN}→ Agregando:${RESET} $domain"

    sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" \
        config:system:set trusted_domains "$i" --value="$domain"

    ((i++))

done

echo
echo -e "${GREEN}✔ trusted_domains configurado correctamente${RESET}"

# =========================================================
# PERMISOS FINALES
# =========================================================

echo
echo -e "${CYAN}Aplicando permisos finales...${RESET}"

fix_permissions

# =========================================================
# RESTART APACHE
# =========================================================

echo
echo -e "${CYAN}Reiniciando Apache...${RESET}"

systemctl restart apache2 || {
    echo -e "${RED}✘ Error reiniciando Apache${RESET}"
    pause
    return 1
}
# =========================================================
# OBTENER INFORMACIÓN
# =========================================================

IP=$(hostname -I | awk '{print $1}')

# versión Nextcloud
NC_VERSION=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" status \
    | grep "version:" | awk '{print $2}')

# PHP
PHP_VERSION=$(php -v | head -n1)

# MariaDB
MARIADB_VERSION=$(mysql -V)

# Redis
REDIS_VERSION=$(redis-server --version | head -n1)

# estado apache
if systemctl is-active --quiet apache2; then
    APACHE_STATUS="ACTIVO"
else
    APACHE_STATUS="DETENIDO"
fi

# estado redis
if systemctl is-active --quiet redis-server; then
    REDIS_STATUS="ACTIVO"
else
    REDIS_STATUS="DETENIDO"
fi

# estado cron
if systemctl is-active --quiet cron; then
    CRON_STATUS="ACTIVO"
else
    CRON_STATUS="DETENIDO"
fi

# =========================================================
# ARCHIVO RESUMEN
# =========================================================

INFO_FILE="/root/nextcloud_install_$(date +%F_%H-%M-%S).txt"

# =========================================================
# MOSTRAR EN PANTALLA
# =========================================================

echo
echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}        NEXTCLOUD INSTALADO CORRECTAMENTE${RESET}"
echo -e "${GREEN}====================================================${RESET}"

echo
echo -e "${CYAN}Versión Nextcloud:${RESET} $NC_VERSION"
echo -e "${CYAN}PHP:${RESET} $PHP_VERSION"

echo
echo -e "${CYAN}Directorio NC:${RESET} $NC_DIR"
echo -e "${CYAN}Data Directory:${RESET} $DATA_DIR"

echo
echo -e "${CYAN}Acceso local:${RESET} http://$IP"

echo
echo -e "${CYAN}Trusted Domains:${RESET}"

for domain in "${DOMAINS[@]}"; do
    echo " - $domain"
done

echo
echo -e "${CYAN}Usuario administrador:${RESET} $ADMIN_USER"

echo
echo -e "${CYAN}Estado servicios:${RESET}"
echo -e " Apache : $APACHE_STATUS"
echo -e " Redis  : $REDIS_STATUS"
echo -e " Cron   : $CRON_STATUS"

# =========================================================
# GUARDAR INFO EN ARCHIVO
# =========================================================

{
echo "===================================================="
echo "        NEXTCLOUD INSTALADO CORRECTAMENTE"
echo "===================================================="
echo

echo "Fecha                 : $(date)"
echo "Versión Nextcloud     : $NC_VERSION"

echo
echo "PHP                   : $PHP_VERSION"
echo "MariaDB               : $MARIADB_VERSION"
echo "Redis                 : $REDIS_VERSION"

echo
echo "Directorio NC         : $NC_DIR"
echo "Data Directory        : $DATA_DIR"

echo
echo "Acceso local          : http://$IP"

echo
echo "Trusted Domains:"

for domain in "${DOMAINS[@]}"; do
    echo " - $domain"
done

echo
echo "Usuario administrador : $ADMIN_USER"

echo
echo "Estado servicios:"
echo " Apache               : $APACHE_STATUS"
echo " Redis                : $REDIS_STATUS"
echo " Cron                 : $CRON_STATUS"

echo
echo "===================================================="

} > "$INFO_FILE"

chmod 600 "$INFO_FILE"

echo
echo -e "${GREEN}✔ Resumen guardado:${RESET}"
echo -e "${CYAN}$INFO_FILE${RESET}"
echo

pause
}

# =========================================================
# STATUS SERVICIOS NEXTCLOUD PRO
# =========================================================

status_services(){

clear

echo -e "${CYAN}========================================${RESET}"
echo -e "${WHITE}        ESTADO NEXTCLOUD PRO${RESET}"
echo -e "${CYAN}========================================${RESET}"

echo

# =========================================================
# SERVICIOS
# =========================================================

check_service(){

SERVICE_NAME="$1"
DISPLAY_NAME="$2"

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${GREEN}✔${RESET} $DISPLAY_NAME: active"
else
    echo -e "${RED}✘${RESET} $DISPLAY_NAME: inactive"
fi

}

check_service apache2 "Apache"
check_service mariadb "MariaDB"
check_service redis-server "Redis"

echo

# =========================================================
# PHP
# =========================================================

PHP_VERSION=$(php -v 2>/dev/null | head -n 1)

echo -e "${CYAN}PHP:${RESET} ${PHP_VERSION:-No instalado}"

echo

# =========================================================
# RAM / DISCO
# =========================================================

echo -e "${CYAN}RAM:${RESET}"
free -h | awk 'NR==2 {print "Usada: "$3" / Total: "$2}'

echo

echo -e "${CYAN}DISCO:${RESET}"
df -h / | awk 'NR==2 {print "Usado: "$3" / Total: "$2" ("$5")"}'

echo

# =========================================================
# NEXTCLOUD
# =========================================================

if [ -f "$NC_DIR/occ" ]; then

    STATUS=$(
        sudo -u "$WEB_USER" php \
        -d memory_limit=1G \
        "$NC_DIR/occ" status 2>/dev/null || true
    )

    VERSION=$(echo "$STATUS" \
    | grep "version:" \
    | head -n1 \
    | cut -d':' -f2 \
    | xargs)

    INSTALLED=$(echo "$STATUS" \
    | grep "installed:" \
    | head -n1 \
    | cut -d':' -f2 \
    | xargs)

    MAINT=$(echo "$STATUS" \
    | grep "maintenance:" \
    | head -n1 \
    | cut -d':' -f2 \
    | xargs)

    EDITION=$(echo "$STATUS" \
    | grep "edition:" \
    | head -n1 \
    | cut -d':' -f2 \
    | xargs)

    echo -e "${GREEN}✔ Nextcloud instalado${RESET}"

    echo
    echo -e "${CYAN}Versión:${RESET} ${VERSION:-Desconocida}"
    echo -e "${CYAN}Instalado:${RESET} ${INSTALLED:-Unknown}"
    echo -e "${CYAN}Maintenance:${RESET} ${MAINT:-Unknown}"

    [ -n "$EDITION" ] && \
    echo -e "${CYAN}Edition:${RESET} $EDITION"

    echo


# =========================================================
# URL DESDE VHOST NEXTCLOUD
# =========================================================

VHOST_FILE=$(find /etc/apache2/sites-enabled \
-name "*nextcloud*.conf" 2>/dev/null | head -n1)

if [ -z "$VHOST_FILE" ]; then
    VHOST_FILE=$(find /etc/apache2/sites-available \
    -name "*nextcloud*.conf" 2>/dev/null | head -n1)
fi

if [ -n "$VHOST_FILE" ]; then

    DOMAIN=$(grep -i "^ServerName" "$VHOST_FILE" \
    | awk '{print $2}' \
    | head -n1)

    SSL_ENABLED="false"

    if grep -qi "SSLEngine on" "$VHOST_FILE"; then
        SSL_ENABLED="true"
    fi

    if [ -n "$DOMAIN" ]; then

        if [ "$SSL_ENABLED" = "true" ]; then
            echo -e "${CYAN}URL:${RESET} https://$DOMAIN"
        else
            echo -e "${CYAN}URL:${RESET} http://$DOMAIN"
        fi

    else

        echo -e "${YELLOW}ServerName no detectado${RESET}"

    fi

else

    echo -e "${YELLOW}VHost Nextcloud no encontrado${RESET}"

fi

echo

    # =========================================================
    # DATA DIRECTORY
    # =========================================================

    DATA_DIR=$(grep "'datadirectory'" "$NC_DIR/config/config.php" \
    | cut -d"'" -f4)

    echo -e "${CYAN}Data:${RESET} ${DATA_DIR:-No detectado}"

    echo

    # =========================================================
    # APPS IMPORTANTES
    # =========================================================

    echo -e "${CYAN}Apps:${RESET}"

    APPS=(
        "files"
        "activity"
        "calendar"
        "contacts"
        "music"
        "onlyoffice"
        "richdocuments"
        "spreed"
    )

    ENABLED_APPS=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list 2>/dev/null)

    for APP in "${APPS[@]}"; do

        if echo "$ENABLED_APPS" \
        | grep -A999 "Enabled:" \
        | grep -q " - $APP"; then

            echo -e "${GREEN}✔${RESET} $APP"

        else

            echo -e "${RED}✘${RESET} $APP"

        fi

    done

    echo

    # =========================================================
    # CRON
    # =========================================================

    echo -e "${CYAN}Cron:${RESET}"

    if crontab -u "$WEB_USER" -l 2>/dev/null | grep -q "cron.php"; then
        echo -e "${GREEN}✔ Cron configurado${RESET}"
    else
        echo -e "${RED}✘ Cron NO configurado${RESET}"
    fi

else

    echo -e "${RED}❌ Nextcloud NO instalado${RESET}"

fi

echo
echo -e "${CYAN}========================================${RESET}"

pause
}


# =========================================================
# UPDATE NEXTCLOUD PRO
# =========================================================

update_nextcloud(){

    clear

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}     UPDATE NEXTCLOUD PRO${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    # =========================================
    # VALIDAR NEXTCLOUD
    # =========================================

    if [ ! -f "$NC_DIR/occ" ]; then
        echo -e "${RED}❌ No se encontró Nextcloud.${RESET}"
        read -rp "Presiona ENTER para continuar..." || true
        return 0
    fi

    # =========================================
    # VALIDAR UPDATER
    # =========================================

    if [ ! -f "$NC_DIR/updater/updater.phar" ]; then
        echo -e "${RED}❌ No se encontró updater.phar${RESET}"
        read -rp "Presiona ENTER para continuar..." || true
        return 0
    fi

    # =========================================
    # VERSION ACTUAL
    # =========================================

    VERSION_ACTUAL=$(
        sudo -u "$WEB_USER" php "$NC_DIR/occ" status --output=json 2>/dev/null \
        | grep -oP '"version"\s*:\s*"\K[^"]+'
    )

    [ -z "$VERSION_ACTUAL" ] && VERSION_ACTUAL="Desconocida"

    # =========================================
    # VERSION DISPONIBLE
    # =========================================

    echo -e "${CYAN}Buscando nueva versión de Nextcloud...${RESET}"
    echo

    CHECK_UPDATE=$(
        sudo -u "$WEB_USER" php "$NC_DIR/occ" update:check 2>/dev/null
    )

    echo "$CHECK_UPDATE"
    echo

    VERSION_NUEVA=$(
        echo "$CHECK_UPDATE" \
        | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' \
        | head -n1
    )

    # =========================================
    # VALIDAR RESULTADO
    # =========================================

    if [[ -z "$VERSION_NUEVA" || "$VERSION_NUEVA" == "$VERSION_ACTUAL" ]]; then
        VERSION_NUEVA="Sin actualizaciones"
    fi

    # =========================================
    # MOSTRAR VERSIONES
    # =========================================

    echo -e "${GREEN}Versión actual:${RESET} ${VERSION_ACTUAL}"
    echo -e "${CYAN}Nueva versión:${RESET} ${VERSION_NUEVA}"
    echo

    # =========================================
    # YA ACTUALIZADO
    # =========================================

    if [ "$VERSION_NUEVA" = "Sin actualizaciones" ]; then
        echo -e "${GREEN}✔ Nextcloud ya está actualizado.${RESET}"
        echo
        read -rp "Presiona ENTER para continuar..." || true
        return 0
    fi

    # =========================================
    # CONFIRMAR ACTUALIZACION
    # =========================================

    read -rp "¿Deseas actualizar Nextcloud? [s/N]: " CONFIRM_UPDATE

    case "$CONFIRM_UPDATE" in
        s|S|si|SI|y|Y)
            echo
            echo -e "${GREEN}Iniciando actualización...${RESET}"
            ;;
        *)
            echo
            echo -e "${YELLOW}Actualización cancelada.${RESET}"
            read -rp "Presiona ENTER para continuar..." || true
            return 0
            ;;
    esac

    # =========================================
    # INFO SISTEMA
    # =========================================

    echo -e "${CYAN}Espacio disponible:${RESET}"
    df -h /

    echo
    echo -e "${CYAN}Memoria:${RESET}"
    free -h

    echo

    # =========================================
    # DATA DIRECTORY
    # =========================================

    DATA_DIR=$(
        sudo -u "$WEB_USER" php "$NC_DIR/occ" \
        config:system:get datadirectory 2>/dev/null
    )

    echo -e "${CYAN}Directorio de datos:${RESET} ${DATA_DIR:-No detectado}"
    echo

    # =========================================
    # BACKUP DB
    # =========================================

    echo -e "${CYAN}➜ Realizando backup de base de datos...${RESET}"

    DB_BACKUP=$(backup_db_nc)

    if [ -z "$DB_BACKUP" ]; then
        echo -e "${RED}❌ Error creando backup DB.${RESET}"
        read -rp "Presiona ENTER para continuar..." || true
        return 1
    fi

    echo -e "${GREEN}✔ Backup DB:${RESET} $DB_BACKUP"
    echo

    # =========================================
    # MAINTENANCE MODE ON
    # =========================================

    echo -e "${YELLOW}➜ Activando modo mantenimiento...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:mode --on || true

    echo

    # =========================================
    # UPDATER
    # =========================================

    echo -e "${CYAN}➜ Ejecutando updater...${RESET}"
    echo

    LOG_UPDATE="/tmp/nextcloud_update.log"

    sudo -u "$WEB_USER" php \
        -d memory_limit=1G \
        -d max_execution_time=0 \
        "$NC_DIR/updater/updater.phar" \
        --no-interaction | tee "$LOG_UPDATE"

    UPDATE_STATUS=${PIPESTATUS[0]}

    echo

    # =========================================
    # VALIDAR BACKUP UPDATER
    # =========================================

    UPDATER_BACKUP=$(find "$DATA_DIR" -type d -path "*/backups" 2>/dev/null | head -n 1)

    if [ -n "$UPDATER_BACKUP" ]; then
        echo -e "${GREEN}✔ Backup updater creado:${RESET}"
        echo "$UPDATER_BACKUP"
    else
        echo -e "${YELLOW}⚠ No se encontró backup del updater.${RESET}"
    fi

    echo

    # =========================================
    # VALIDAR SI YA ESTA ACTUALIZADO
    # =========================================

    if grep -qiE \
"No update available|Nothing to do|is up to date|already latest|No hay actualizaciones disponibles|Ya está actualizado|Nextcloud ya está actualizado" \
"$LOG_UPDATE"; then

        echo -e "${GREEN}✔ Nextcloud ya está actualizado.${RESET}"

        sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:mode --off || true

        echo
        read -rp "Presiona ENTER para continuar..." || true
        return 0
    fi

    # =========================================
    # VALIDAR ERROR UPDATE
    # =========================================

    if [ "$UPDATE_STATUS" != "0" ]; then

        echo -e "${RED}❌ Error durante actualización.${RESET}"

        echo
        echo -e "${YELLOW}Log:${RESET} $LOG_UPDATE"

        sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:mode --off || true

        echo
        read -rp "Presiona ENTER para continuar..." || true
        return 1
    fi

# =========================================
# OCC UPGRADE
# =========================================

echo -e "${CYAN}➜ Ejecutando OCC upgrade...${RESET}"
echo

OCC_LOG="/tmp/nextcloud_occ_upgrade.log"

sudo -u "$WEB_USER" php \
-d memory_limit=1G \
"$NC_DIR/occ" upgrade 2>&1 | tee "$OCC_LOG"

OCC_STATUS=${PIPESTATUS[0]}

echo

# =========================================
# VALIDAR OCC
# =========================================

if [ "$OCC_STATUS" != "0" ]; then

    echo -e "${RED}❌ Error durante OCC upgrade${RESET}"
    echo

    echo -e "${YELLOW}Log:${RESET}"
    echo "$OCC_LOG"

    echo
    echo -e "${YELLOW}Últimas líneas:${RESET}"
    tail -20 "$OCC_LOG"

    echo

    sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:mode --off || true

    read -rp "Presiona ENTER para continuar..." || true

    return 1

fi

    # =========================================
    # REPARACIONES
    # =========================================

    echo -e "${CYAN}➜ Reparando instalación...${RESET}"
    echo

    sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:repair 
    sudo -u "$WEB_USER" php "$NC_DIR/occ" db:add-missing-indices
    sudo -u "$WEB_USER" php "$NC_DIR/occ" db:add-missing-columns
    sudo -u "$WEB_USER" php "$NC_DIR/occ" db:add-missing-primary-keys

    echo

    # =========================================
    # LIMPIEZA
    # =========================================

    echo -e "${CYAN}➜ Limpiando archivos temporales...${RESET}"

    rm -rf /tmp/nextcloud_update.log.old 2>/dev/null || true

    echo

    # =========================================
    # PERMISOS
    # =========================================

    echo -e "${CYAN}➜ Corrigiendo permisos...${RESET}"

    fix_permissions || true

    echo

    # =========================================
    # RESTART APACHE
    # =========================================

    echo -e "${CYAN}➜ Reiniciando Apache...${RESET}"

    systemctl restart apache2 || true

    echo

    # =========================================
    # MAINTENANCE MODE OFF
    # =========================================

    echo -e "${YELLOW}➜ Desactivando modo mantenimiento...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:mode --off || true

    echo

    # =========================================
    # VERSION FINAL
    # =========================================

    NUEVA_VERSION=$(
        sudo -u "$WEB_USER" php "$NC_DIR/occ" status --output=json 2>/dev/null \
        | grep -oP '"version"\s*:\s*"\K[^"]+'
    )

    # =========================================
    # STATUS FINAL
    # =========================================

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${GREEN}✔ UPDATE COMPLETADO${RESET}"
    echo -e "${GREEN}Versión:${RESET} ${VERSION_ACTUAL:-?} → ${NUEVA_VERSION:-?}"
    echo -e "${CYAN}========================================${RESET}"

    echo

    # =========================================
    # VERIFICACION FINAL
    # =========================================

    echo -e "${CYAN}➜ Verificando estado final...${RESET}"
    echo

    sudo -u "$WEB_USER" php "$NC_DIR/occ" check

    echo
    read -rp "Presiona ENTER para continuar..." || true
}

# ===========================================================
# MENU DOCUMENTSERVER COMMUNITY + COLLABORA ONLINE
# ===========================================================

menu_office_app(){

while true; do
clear

echo -e "${CYAN}===== DOCUMENTSERVER COMMUNITY + OnlyOffice =====${RESET}"
echo
echo -e "${YELLOW}1)${RESET} Instalar DocumentServer + OnlyOffice"
echo -e "${YELLOW}2)${RESET} Desinstalar DocumentServer + OnlyOffice"
echo -e "${YELLOW}3)${RESET} Actualizar DocumentServer + OnlyOffice"
echo -e "${YELLOW}4)${RESET} Estado DocumentServer + OnlyOffice"
echo -e "${YELLOW}5)${RESET} Reconstruir fuentes DocumentServer"
echo
echo -e "${YELLOW}=====================================${RESET}"
echo
echo -e "${GREEN}===== COLLABORA ONLINE + NEXTCLOUD OFFICE =====${RESET}"
echo
echo -e "${YELLOW}6)${RESET} Instalar Collabora Online + Nextcloud Office"
echo -e "${YELLOW}7)${RESET} Desinstalar Collabora Online + Nextcloud Office"
echo -e "${YELLOW}8)${RESET} Actualizar Collabora Online + Nextcloud Office"
echo -e "${YELLOW}9)${RESET} Estado Collabora Online + Nextcloud Office"
echo -e "${YELLOW}10)${RESET} Reparar Fuentes Collabora Online"
echo -e "${YELLOW}0)${RESET} Volver"


read -p "Opción: " op

case $op in

1)
    echo
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW} Instalando documentserver_community${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo

    spin='-\|/'

    echo -e "${CYAN}Descargando aplicación...${RESET}"
	echo
    echo -e "${CYAN}Esto puede tardar unos minutos...${RESET}"
	
    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:install documentserver_community &
    PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        for i in 0 1 2 3; do
            printf "\rInstalando documentserver... %s" "${spin:$i:1}"
            sleep 0.2
        done
    done

    wait "$PID"

    echo -e "\n${CYAN}Habilitando aplicación...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:enable documentserver_community

    echo
    echo -e "${GREEN}✔ documentserver_community instalado${RESET}"

    echo
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW} Instalando onlyoffice${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo

    echo -e "${CYAN}Descargando aplicación...${RESET}"

    sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" app:install onlyoffice &
    PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        for i in 0 1 2 3; do
            printf "\rInstalando onlyoffice... %s" "${spin:$i:1}"
            sleep 0.2
        done
    done

    wait "$PID"

    echo -e "\n${CYAN}Habilitando aplicación...${RESET}"

    sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" app:enable onlyoffice

    echo
    echo -e "${GREEN}✔ onlyoffice instalado${RESET}"
    echo

IP=$(hostname -I | awk '{print $1}')

echo -e "${CYAN}Servidor Nextcloud:${RESET}"
echo -e "${YELLOW}http://$IP${RESET}"

echo
echo -e "${CYAN}IMPORTANTE:${RESET}"
echo "Debes configurar un servidor ONLYOFFICE Document Server."
echo

echo -e "${YELLOW}Ejemplos:${RESET}"
echo "  http://ip-servidor/index.php/apps/documentserver_community/"
echo "  https://office.midominio.com/index.php/apps/documentserver_community/"

pause
;;

2)
echo
echo -e "${YELLOW}========================================${RESET}"
echo -e "${YELLOW} Desinstalando documentserver_community${RESET}"
echo -e "${YELLOW}========================================${RESET}"
echo

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q "documentserver_community:"; then

    echo -e "${CYAN}Deshabilitando aplicación...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:disable documentserver_community

    echo
    echo -e "${CYAN}Intentando eliminar aplicación...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:remove documentserver_community 2>/dev/null

    echo
    echo -e "${CYAN}Eliminando archivos residuales...${RESET}"

    rm -rf "$NC_DIR/apps/documentserver_community"

    echo
    echo -e "${GREEN}✔ documentserver_community eliminado completamente${RESET}"

else

    echo -e "${YELLOW}documentserver_community no está instalado${RESET}"

fi

echo
echo -e "${YELLOW}========================================${RESET}"
echo -e "${YELLOW} Desinstalando onlyoffice${RESET}"
echo -e "${YELLOW}========================================${RESET}"
echo

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q "onlyoffice:"; then

    echo -e "${CYAN}Deshabilitando aplicación...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:disable onlyoffice

    echo
    echo -e "${CYAN}Intentando eliminar aplicación...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:remove onlyoffice 2>/dev/null

    echo
    echo -e "${CYAN}Eliminando archivos residuales...${RESET}"

    rm -rf "$NC_DIR/apps/onlyoffice"

    echo
    echo -e "${GREEN}✔ onlyoffice eliminado completamente${RESET}"

else

    echo -e "${YELLOW}onlyoffice no está instalado${RESET}"

fi

echo
echo -e "${CYAN}Ejecutando reparación de Nextcloud...${RESET}"

sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:repair

echo
echo -e "${GREEN}✔ Limpieza finalizada${RESET}"

pause
;;

3)
echo
echo -e "${YELLOW}========================================${RESET}"
echo -e "${YELLOW} Actualizando documentserver_community${RESET}"
echo -e "${YELLOW}========================================${RESET}"
echo

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q documentserver_community; then

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:update documentserver_community

    echo
    echo -e "${GREEN}✔ documentserver_community actualizado${RESET}"

else

    echo -e "${YELLOW}documentserver_community no está instalado${RESET}"

fi

echo
echo -e "${YELLOW}========================================${RESET}"
echo -e "${YELLOW} Actualizando onlyoffice${RESET}"
echo -e "${YELLOW}========================================${RESET}"
echo

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q onlyoffice; then

    sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" app:update onlyoffice

    echo
    echo -e "${GREEN}✔ onlyoffice actualizado${RESET}"

else

    echo -e "${YELLOW}onlyoffice no está instalado${RESET}"

fi

echo
echo -e "${CYAN}Ejecutando reparación de Nextcloud...${RESET}"

sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:repair

echo
echo -e "${GREEN}✔ Reparación completada${RESET}"

pause
;;

4)
echo
echo -e "${YELLOW}========================================${RESET}"
echo -e "${YELLOW} Estado aplicaciones Office${RESET}"
echo -e "${YELLOW}========================================${RESET}"
echo

# ========================================
# documentserver_community
# ========================================

echo -e "${CYAN}documentserver_community:${RESET}"

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q "documentserver_community:"; then

    echo -e "${GREEN}✔ Instalado${RESET}"

    if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -A999 enabled | grep -q "documentserver_community"; then
        echo -e "${GREEN}✔ Estado: Habilitado${RESET}"
    else
        echo -e "${YELLOW}⚠ Estado: Deshabilitado${RESET}"
    fi

else

    echo -e "${RED}✘ No instalado${RESET}"

fi

echo

# ========================================
# onlyoffice
# ========================================

echo -e "${CYAN}onlyoffice:${RESET}"

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q "onlyoffice:"; then

    echo -e "${GREEN}✔ Instalado${RESET}"

    if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -A999 enabled | grep -q "onlyoffice"; then
        echo -e "${GREEN}✔ Estado: Habilitado${RESET}"
    else
        echo -e "${YELLOW}⚠ Estado: Deshabilitado${RESET}"
    fi

else

    echo -e "${RED}✘ No instalado${RESET}"

fi

echo
    pause
;;

5)
    echo -e "${YELLOW}Reconstruyendo fuentes DocumentServer...${RESET}"

    if sudo -u $WEB_USER php $NC_DIR/occ list | grep -q documentserver:fonts; then

        sudo -u $WEB_USER php $NC_DIR/occ documentserver:fonts --rebuild

        echo
        echo -e "${GREEN}✔ Fuentes reconstruidas correctamente${RESET}"

    else

        echo -e "${RED}DocumentServer Community no instalado${RESET}"

    fi

    pause
;;


6)

    echo
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW} Instalando Nextcloud Office${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo

    spin='-\|/'

    # =========================================================
    # RICHDOCUMENTS
    # =========================================================

    echo -e "${CYAN}Instalando richdocuments...${RESET}"
	echo
    echo -e "${CYAN}Esto puede tardar unos minutos...${RESET}"
	
    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:install richdocuments &
    PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        for i in 0 1 2 3; do
            printf "\rInstalando richdocuments... %s" "${spin:$i:1}"
            sleep 0.2
        done
    done

    wait "$PID"

    echo -e "\n${CYAN}Habilitando richdocuments...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:enable richdocuments

    # =========================================================
    # RICHDOCUMENTSCODE (COLLABORA CODE SERVER)
    # =========================================================

    echo
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW} Instalando CODE Server (Collabora)${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo

    echo -e "${CYAN}Instalando richdocumentscode...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:install richdocumentscode &
    PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        for i in 0 1 2 3; do
            printf "\rInstalando richdocumentscode... %s" "${spin:$i:1}"
            sleep 0.2
        done
    done

    wait "$PID"

    echo -e "\n${CYAN}Habilitando richdocumentscode...${RESET}"

    sudo -u "$WEB_USER" php "$NC_DIR/occ" app:enable richdocumentscode

    # =========================================================
    # FINAL
    # =========================================================

    echo
    echo -e "${GREEN}✔ Collabora Online instalado${RESET}"
    echo -e "${GREEN}✔ Nextcloud Office habilitado${RESET}"
    echo

echo
echo -e "${YELLOW}IMPORTANTE:${RESET}"
echo "Si usas proxy reverso o HTTPS,"
echo "verifica la configuración en:"
echo "Ajustes → Administración → Nextcloud Office"

pause
;;

7)
    echo
    echo -e "${YELLOW}========================================${RESET}"
    echo -e "${YELLOW} Desinstalando Collabora${RESET}"
    echo -e "${YELLOW}========================================${RESET}"
    echo

    echo
    echo -e "${CYAN}Eliminando richdocumentscode...${RESET}"

    sudo -u $WEB_USER php $NC_DIR/occ app:remove richdocumentscode


    echo
    echo -e "${CYAN}Eliminando richdocuments...${RESET}"

    sudo -u $WEB_USER php $NC_DIR/occ app:remove richdocuments

    echo
    echo -e "${GREEN}✔ Collabora eliminado${RESET}"

    pause
;;

8)
echo
echo -e "${YELLOW}========================================${RESET}"
echo -e "${YELLOW} Actualizando Collabora${RESET}"
echo -e "${YELLOW}========================================${RESET}"
echo

# ========================================
# richdocuments
# ========================================

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q richdocuments; then

    echo -e "${CYAN}Actualizando richdocuments...${RESET}"

    sudo -u "$WEB_USER" php -d memory_limit=1G "$NC_DIR/occ" app:update richdocuments

    echo
    echo -e "${GREEN}✔ richdocuments actualizado${RESET}"

else

    echo -e "${YELLOW}richdocuments no está instalado${RESET}"

fi

echo

# ========================================
# richdocumentscode
# ========================================

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q richdocumentscode; then

    echo -e "${CYAN}Actualizando richdocumentscode...${RESET}"
    echo -e "${YELLOW}Esto puede tardar varios minutos...${RESET}"
    echo

    (
    sudo -u "$WEB_USER" php -d memory_limit=2G "$NC_DIR/occ" app:update richdocumentscode
    ) &

    PID=$!

    spin='-\|/'

    while kill -0 $PID 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r${CYAN}Actualizando CODE Server... ${spin:$i:1}${RESET}"
            sleep 0.2
        done
    done

    wait $PID
    STATUS=$?

    echo

    if [ $STATUS -eq 0 ]; then
        echo -e "${GREEN}✔ richdocumentscode actualizado${RESET}"
    else
        echo -e "${RED}✘ Error actualizando richdocumentscode${RESET}"
    fi

else

    echo -e "${YELLOW}richdocumentscode no está instalado${RESET}"

fi

echo
echo -e "${CYAN}Ejecutando reparación de Nextcloud...${RESET}"

sudo -u "$WEB_USER" php "$NC_DIR/occ" maintenance:repair

echo
echo -e "${CYAN}Ejecutando limpieza de caché...${RESET}"
sudo -u "$WEB_USER" php "$NC_DIR/occ" files:scan-app-data

echo
echo -e "${GREEN}✔ Collabora actualizado${RESET}"

pause
;;


9)
echo
echo -e "${YELLOW}========================================${RESET}"
echo -e "${YELLOW} Estado Nextcloud Office${RESET}"
echo -e "${YELLOW}========================================${RESET}"
echo

# ========================================
# richdocuments
# ========================================

echo -e "${CYAN}Nextcloud Office (richdocuments):${RESET}"

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q "richdocuments:"; then

    echo -e "${GREEN}✔ Instalado${RESET}"

    if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list --enabled | grep -q "richdocuments"; then
        echo -e "${GREEN}✔ Estado: Habilitado${RESET}"
    else
        echo -e "${YELLOW}⚠ Estado: Deshabilitado${RESET}"
    fi

else

    echo -e "${RED}✘ No instalado${RESET}"

fi

echo

# ========================================
# richdocumentscode
# ========================================

echo -e "${CYAN}Collabora Online CODE (richdocumentscode):${RESET}"

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list | grep -q "richdocumentscode:"; then

    echo -e "${GREEN}✔ Instalado${RESET}"

    if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list --enabled | grep -q "richdocumentscode"; then
        echo -e "${GREEN}✔ Estado: Habilitado${RESET}"
    else
        echo -e "${YELLOW}⚠ Estado: Deshabilitado${RESET}"
    fi

else

    echo -e "${RED}✘ No instalado${RESET}"

fi

echo

# ========================================
# Configuración WOPI
# ========================================

echo -e "${CYAN}Configuración WOPI:${RESET}"

WOPI_URL=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" config:app:get richdocuments wopi_url 2>/dev/null)

if [ -n "$WOPI_URL" ]; then

    echo -e "${GREEN}✔ Configurado${RESET}"
    echo "$WOPI_URL"

else

    echo -e "${YELLOW}⚠ No configurado${RESET}"

fi

echo

# ========================================
# Verificación final
# ========================================

if sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list --enabled | grep -q "richdocuments" \
&& sudo -u "$WEB_USER" php "$NC_DIR/occ" app:list --enabled | grep -q "richdocumentscode"; then

    echo -e "${GREEN}✔ Collabora Online instalado${RESET}"
    echo -e "${GREEN}✔ Nextcloud Office habilitado${RESET}"

else

    echo -e "${RED}✘ Configuración incompleta${RESET}"

fi

pause
;;

10)
   echo -e "${YELLOW}Reparando Collabora / Nextcloud Office...${RESET}"
    echo

    if sudo -u $WEB_USER php $NC_DIR/occ app:list | grep -q richdocuments; then

        echo -e "${CYAN}Activando configuración...${RESET}"

        sudo -u $WEB_USER php $NC_DIR/occ richdocuments:activate-config

        echo
        echo -e "${CYAN}Instalando fuentes...${RESET}"

        sudo -u $WEB_USER php $NC_DIR/occ richdocuments:install-fonts

        echo
        echo -e "${CYAN}Actualizando templates...${RESET}"

        sudo -u $WEB_USER php $NC_DIR/occ richdocuments:update-empty-templates

        echo
        echo -e "${GREEN}✔ Collabora reparado correctamente${RESET}"

    else

        echo -e "${RED}Collabora / Nextcloud Office no instalado${RESET}"

    fi

    pause
;;
0) break ;;

*)
    echo -e "${RED}Opción inválida${RESET}"
    sleep 1
;;

esac

done
}
# =========================================================
# BACKUP
# =========================================================

backup_nextcloud(){

source $DB_FILE

DATE=$(date +%F-%H%M)

BACKUP_DIR="/root/nextcloud-backups/$DATE"

mkdir -p $BACKUP_DIR

sudo -u $WEB_USER php -d memory_limit=1G $NC_DIR/occ maintenance:mode --on || true

mysqldump $DB_NAME > $BACKUP_DIR/db.sql

cp -a $NC_DIR $BACKUP_DIR/
cp -a $DATA_DIR $BACKUP_DIR/

tar -czf /root/nextcloud-backup-$DATE.tar.gz $BACKUP_DIR

sudo -u $WEB_USER php -d memory_limit=1G $NC_DIR/occ maintenance:mode --off || true

echo -e "${GREEN}✔ Backup realizado${RESET}"

pause
}

# =========================================================
# UNINSTALL NEXTCLOUD PRO COMPLETO
# =========================================================

uninstall_nextcloud(){

echo
echo -e "${RED}========================================${RESET}"
echo -e "${RED} DESINSTALADOR NEXTCLOUD PRO${RESET}"
echo -e "${RED}========================================${RESET}"
echo

# =========================================================
# CARGAR DB
# =========================================================

source "$DB_FILE" 2>/dev/null || true

# =========================================================
# CONFIRMACIONES
# =========================================================

printf "${CYAN}¿Eliminar instalación Nextcloud? (s/n): ${RESET}"
read DEL_NC

printf "${CYAN}¿Eliminar directorio DATA? (s/n): ${RESET}"
read DEL_DATA

printf "${CYAN}¿Eliminar base de datos MySQL? (s/n): ${RESET}"
read DEL_DB

printf "${CYAN}¿Eliminar VirtualHost Apache? (s/n): ${RESET}"
read DEL_VHOST

printf "${CYAN}¿Eliminar cron jobs Nextcloud? (s/n): ${RESET}"
read DEL_CRON

printf "${CYAN}¿Limpiar Redis cache? (s/n): ${RESET}"
read DEL_REDIS

echo

# =========================================================
# CONFIRMACION FINAL
# =========================================================

echo -e "${YELLOW}⚠ ADVERTENCIA FINAL${RESET}"
echo -e "${CYAN} Esta operación puede eliminar completamente Nextcloud."
echo

read -rp "Escribe YES para continuar: " FINAL_CONFIRM

if [[ "$(echo "$FINAL_CONFIRM" | tr '[:lower:]' '[:upper:]')" != "YES" ]]; then

    echo -e "${YELLOW}Operación cancelada${RESET}"
    return

fi

# =========================================================
# DETENER SERVICIOS
# =========================================================

echo
echo -e "${CYAN}Deteniendo servicios...${RESET}"

systemctl stop apache2 >/dev/null 2>&1 || true

echo -e "${GREEN}✔ Servicios detenidos${RESET}"

# =========================================================
# ELIMINAR NEXTCLOUD
# =========================================================

if [[ "$DEL_NC" =~ ^[sS]$ ]]; then

    echo
    echo -e "${CYAN}Eliminando instalación Nextcloud...${RESET}"

    rm -rf "$NC_DIR"

    echo -e "${GREEN}✔ Instalación eliminada${RESET}"

fi

# =========================================================
# ELIMINAR DATA
# =========================================================

if [[ "$DEL_DATA" =~ ^[sS]$ ]]; then

    echo
    echo -e "${RED}⚠ ADVERTENCIA${RESET}"
    echo -e "${YELLOW}Esto eliminará TODOS los archivos de usuarios.${RESET}"
    echo -e "${YELLOW}Directorio:${RESET} $DATA_DIR"
    echo

    printf "${RED}Escribe DELETE para confirmar:${RESET} "
    read CONFIRM_DATA

    if [[ "$CONFIRM_DATA" == "DELETE" ]]; then

        echo
        echo -e "${CYAN}Eliminando directorio DATA...${RESET}"

        if [[ "$(echo "$CONFIRM_DATA" | tr '[:lower:]' '[:upper:]')" == "DELETE" ]]; then

            rm -rf "$DATA_DIR"

            echo -e "${GREEN}✔ DATA eliminada${RESET}"

        else

            echo -e "${RED}✘ Ruta DATA inválida:${RESET} $DATA_DIR"

        fi

    else

        echo
        echo -e "${YELLOW}⚠ Eliminación DATA cancelada${RESET}"

    fi

fi

# =========================================================
# ELIMINAR BASE DE DATOS (SELECCIÓN MANUAL)
# =========================================================

if [[ "$DEL_DB" =~ ^[sS]$ ]]; then

    echo
    echo -e "${CYAN}Listando bases de datos MySQL...${RESET}"
    echo

    DBS=($(mysql -N -e "SHOW DATABASES;" \
        | grep -Ev "information_schema|mysql|performance_schema|sys"))

    if [ ${#DBS[@]} -eq 0 ]; then
        echo -e "${RED}✘ No se encontraron bases de datos${RESET}"
        return 1
    fi

    echo -e "${YELLOW}Elija la Base de Datos a Borrar ${CYAN}(MySQL):${RESET}"
    echo

    select DB_TO_DELETE in "${DBS[@]}"; do
        if [ -n "$DB_TO_DELETE" ]; then
            break
        else
            echo -e "${RED}Selección inválida${RESET}"
        fi
    done

    echo
    echo -e "${RED}⚠ BASE SELECCIONADA:${RESET} $DB_TO_DELETE"
    echo

    read -rp "Escribe DELETE para confirmar: " CONFIRM_DB

if [[ "$(echo "$CONFIRM_DB" | tr '[:lower:]' '[:upper:]')" == "DELETE" ]]; then

        echo
        echo -e "${CYAN}Eliminando base de datos...${RESET}"

        mysql -e "DROP DATABASE IF EXISTS \`$DB_TO_DELETE\`;"

        echo -e "${GREEN}✔ Base de datos eliminada${RESET}"

        echo
        echo -e "${CYAN}Eliminando usuario MySQL...${RESET}"

        mysql -e "DROP USER IF EXISTS '$DB_USER'@'localhost';"
        mysql -e "FLUSH PRIVILEGES;"

        echo -e "${GREEN}✔ Usuario eliminado${RESET}"

    else

        echo -e "${YELLOW}⚠ Eliminación cancelada${RESET}"

    fi

fi

# =========================================================
# ELIMINAR APACHE VHOST
# =========================================================

if [[ "$DEL_VHOST" =~ ^[sS]$ ]]; then

    echo
    echo -e "${CYAN}Eliminando VirtualHost Apache...${RESET}"

    a2dissite nextcloud.conf >/dev/null 2>&1 || true

    rm -f /etc/apache2/sites-enabled/nextcloud.conf
    rm -f /etc/apache2/sites-available/nextcloud.conf

    echo -e "${GREEN}✔ VirtualHost eliminado${RESET}"

fi

# =========================================================
# ELIMINAR CRON
# =========================================================

if [[ "$DEL_CRON" =~ ^[sS]$ ]]; then

    echo
    echo -e "${CYAN}Eliminando cron jobs Nextcloud...${RESET}"

    crontab -u "$WEB_USER" -l 2>/dev/null | \
    grep -v "$NC_DIR" | crontab -u "$WEB_USER" -

    echo -e "${GREEN}✔ Cron limpiado${RESET}"

fi

# =========================================================
# LIMPIAR REDIS
# =========================================================

if [[ "$DEL_REDIS" =~ ^[sS]$ ]]; then

    echo
    echo -e "${CYAN}Limpiando Redis cache...${RESET}"

    redis-cli FLUSHALL >/dev/null 2>&1 || true

    echo -e "${GREEN}✔ Redis limpiado${RESET}"

fi

# =========================================================
# LIMPIAR TEMPORALES
# =========================================================

echo
echo -e "${CYAN}Limpiando archivos temporales...${RESET}"

rm -f /tmp/nextcloud.zip
rm -rf /tmp/nextcloud

echo -e "${GREEN}✔ Temporales eliminados${RESET}"

# =========================================================
# REINICIAR SERVICIOS
# =========================================================

echo
echo -e "${CYAN}Reiniciando Apache...${RESET}"

systemctl restart apache2 >/dev/null 2>&1 || true

echo -e "${GREEN}✔ Apache reiniciado${RESET}"

# =========================================================
# FINAL
# =========================================================

echo
echo -e "${GREEN}========================================${RESET}"
echo -e "${GREEN} NEXTCLOUD ELIMINADO CORRECTAMENTE${RESET}"
echo -e "${GREEN}========================================${RESET}"

echo
pause

}

# ========= Configuración Apache / Nextcloud =========
menu_config_nextcloud(){
  while true; do
    clear
    echo -e "${CYAN}${BOLD}=== CONFIGURACIÓN APACHE / NEXTCLOUD ===${NC}"
    echo -e " ${YELLOW}1)${NC} Editar VirtualHost Apache"
    echo -e " ${YELLOW}2)${NC} Editar config.php de Nextcloud"
    echo -e " ${YELLOW}3)${NC} Verificar configuración de Apache"
    echo -e " ${YELLOW}4)${NC} Habilitar VirtualHost"
    echo -e " ${YELLOW}5)${NC} Deshabilitar VirtualHost"
    echo -e " ${YELLOW}6)${NC} Editar puertos Apache (ports.conf)"
    echo -e " ${YELLOW}7)${NC} Crear VirtualHost Generico/Reverse Proxy"
    echo -e " ${YELLOW}8)${NC} Eliminar VirtualHost"
    echo -e " ${CYAN}0) Volver${NC}"


    read -rp "> " op
    case "$op" in
     1)
    echo "=== Editar VirtualHost Apache ==="
    echo

    mapfile -t FILES < <(ls "$APACHE_SITES"/*.conf 2>/dev/null)

    if [ ${#FILES[@]} -eq 0 ]; then
        warn "No se encontraron archivos .conf en $APACHE_SITES"
        pausa
        break
    fi

    select f in "${FILES[@]}" "Cancelar"; do
        if [[ "$REPLY" -gt 0 && "$REPLY" -le ${#FILES[@]} ]]; then
            echo "Editando: $f"
            sudo "$EDITOR_BIN" "$f"

            echo
            echo "🔧 Validando configuración Apache..."
            if apachectl configtest; then
                echo "🔄 Recargando Apache..."
                systemctl reload apache2
                echo "✔ Apache recargado correctamente"
            else
                echo "❌ Error en la configuración, NO se recargó Apache"
            fi

            break
        elif [[ "$f" == "Cancelar" ]]; then
            break
        else
            warn "Selección inválida"
        fi
    done

    pausa
    ;;
      2) sudo $EDITOR_BIN "$NEXTCLOUD_DIR/config/config.php"; pausa ;;
      3) sudo apache2ctl -t; pausa ;;
      4)
         FILES=$(ls $APACHE_SITES/*.conf 2>/dev/null | xargs -n1 basename)
         select sitio in $FILES; do
           [ -n "$sitio" ] || { warn "Selección inválida"; break; }
           sudo a2ensite "$sitio" && sudo systemctl reload apache2
           ok "Sitio $sitio habilitado."
           break
         done
         pausa
         ;;
      5)
         FILES=$(ls $APACHE_SITES/*.conf 2>/dev/null | xargs -n1 basename)
         select sitio in $FILES; do
           [ -n "$sitio" ] || { warn "Selección inválida"; break; }
           sudo a2dissite "$sitio" && sudo systemctl reload apache2
           ok "Sitio $sitio deshabilitado."
           break
         done
         pausa
         ;;
      6) sudo $EDITOR_BIN /etc/apache2/ports.conf; pausa ;;
7)
read -rp "Nombre del VirtualHost (ej: ejemplo.conf): " vhost
read -rp "Dominio o ServerName (ej: ejemplo.com): " dominio
read -rp "Ruta DocumentRoot (ej: /var/www/html/ejemplo): " docroot

echo
echo "Tipo de configuración:"
echo "1) Sitio web normal (WordPress, HTML, etc)"
echo "2) Reverse Proxy (Odoo, apps en puerto)"
echo "3) Alias (ej: /zabbix)"
read -rp "Selecciona opción [1-3]: " tipo

echo
echo "Tipo de certificado SSL:"
echo "1) Let's Encrypt (Certbot)"
echo "2) Certificado autofirmado (TurnKey)"
read -rp "Selecciona opción [1-2]: " ssl_tipo

# Validación básica
if [ "$ssl_tipo" != "1" ] && [ "$ssl_tipo" != "2" ]; then
    echo "Opción inválida, usando certificado TurnKey por defecto"
    ssl_tipo="2"
fi

# Variables SSL dinámicas
if [ "$ssl_tipo" == "1" ]; then
    SSL_CERT="/etc/letsencrypt/live/$dominio/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$dominio/privkey.pem"
else
    SSL_CERT="/etc/ssl/private/cert.pem"
    SSL_KEY="/etc/ssl/private/cert.key"
fi

sudo mkdir -p "$docroot"
sudo chown -R $USER_WEB:$USER_WEB "$docroot"

CONFIG=""

# ===============================
# SITIO NORMAL
# ===============================
if [ "$tipo" == "1" ]; then

CONFIG=$(cat <<EOF
<VirtualHost *:80>
    ServerName $dominio
    DocumentRoot $docroot

    <Directory $docroot>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

    ErrorLog \${APACHE_LOG_DIR}/$dominio-error.log
    CustomLog \${APACHE_LOG_DIR}/$dominio-access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName $dominio
    DocumentRoot $docroot

    <Directory $docroot>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    SSLEngine on
    SSLCertificateFile $SSL_CERT
    SSLCertificateKeyFile $SSL_KEY

    ErrorLog \${APACHE_LOG_DIR}/$dominio-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/$dominio-ssl-access.log combined
</VirtualHost>
EOF
)

# ===============================
# REVERSE PROXY
# ===============================
elif [ "$tipo" == "2" ]; then

read -rp "Puerto backend (ej: 8069): " puerto

CONFIG=$(cat <<EOF
<VirtualHost *:80>
    ServerName $dominio

    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:$puerto/
    ProxyPassReverse / http://127.0.0.1:$puerto/

    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

    ErrorLog \${APACHE_LOG_DIR}/$dominio-error.log
    CustomLog \${APACHE_LOG_DIR}/$dominio-access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName $dominio

    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:$puerto/
    ProxyPassReverse / http://127.0.0.1:$puerto/

    SSLEngine on
    SSLCertificateFile $SSL_CERT
    SSLCertificateKeyFile $SSL_KEY

    ErrorLog \${APACHE_LOG_DIR}/$dominio-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/$dominio-ssl-access.log combined
</VirtualHost>
EOF
)

# ===============================
# ALIAS
# ===============================
elif [ "$tipo" == "3" ]; then

read -rp "Alias (ej: /zabbix): " alias

CONFIG=$(cat <<EOF
<VirtualHost *:80>
    ServerName $dominio

    Alias $alias $docroot

    <Directory $docroot>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

    ErrorLog \${APACHE_LOG_DIR}/$dominio-error.log
    CustomLog \${APACHE_LOG_DIR}/$dominio-access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName $dominio

    Alias $alias $docroot

    <Directory $docroot>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    SSLEngine on
    SSLCertificateFile $SSL_CERT
    SSLCertificateKeyFile $SSL_KEY

    ErrorLog \${APACHE_LOG_DIR}/$dominio-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/$dominio-ssl-access.log combined
</VirtualHost>
EOF
)

fi

# ===============================
# GUARDAR CONFIG
# ===============================
echo "$CONFIG" | sudo tee "$APACHE_SITES/$vhost" > /dev/null

# ===============================
# ACTIVAR MÓDULOS
# ===============================
sudo a2enmod ssl rewrite

if [ "$tipo" == "2" ]; then
    sudo a2enmod proxy proxy_http
fi

# ===============================
# ACTIVAR SITIO
# ===============================
sudo a2ensite "$vhost"

# ===============================
# LETSENCRYPT
# ===============================
if [ "$ssl_tipo" == "1" ]; then
    echo "Generando certificado Let's Encrypt..."
    sudo apt update
    sudo apt install -y certbot python3-certbot-apache
    sudo certbot --apache -d "$dominio" --non-interactive --agree-tos -m admin@$dominio
fi

# ===============================
# RELOAD APACHE
# ===============================
sudo systemctl reload apache2

ok "VirtualHost $vhost creado correctamente con SSL 🚀"
pausa
;;

      8)
         FILES=$(ls $APACHE_SITES/*.conf 2>/dev/null | xargs -n1 basename)
         select vhost in $FILES; do
           [ -n "$vhost" ] || { warn "Selección inválida"; break; }
           sudo a2dissite "$vhost"
           sudo rm "$APACHE_SITES/$vhost"
           sudo systemctl reload apache2
           ok "VirtualHost $vhost eliminado."
           break
         done
         pausa
         ;;
      0) return ;;
      *) warn "Opción inválida"; pausa ;;
    esac
  done
}
# Menu OCC 
# =========================================================
# FUNCIONES AVANCE PRO
# =========================================================

spinner() {

    local pid=$1
    local delay=0.1
    local spinstr='|/-\'

    while ps -p "$pid" > /dev/null 2>&1; do

        printf " [%c]  " "$spinstr"
        spinstr=${spinstr#?}${spinstr%"${spinstr#?}"}

        sleep $delay

        printf "\b\b\b\b\b\b"

    done

    printf "      \b\b\b\b\b\b"
}

run_live() {

    local MSG="$1"
    shift

    echo -e "${CYAN}${MSG}${NC}"

    local START
    START=$(date +%s)

    "$@" 2>&1 | while IFS= read -r line; do
        echo -e "  ${YELLOW}➜${NC} $line"
    done

    local STATUS=${PIPESTATUS[0]}

    local END
    END=$(date +%s)

    if [[ $STATUS -eq 0 ]]; then

        echo -e "${GREEN}✔ Completado en $((END-START))s${NC}"
        return 0

    else

        echo -e "${RED}✘ Error en: $MSG${NC}"
        return 1

    fi
}

# =========================================================
# MENU NEXTCLOUD OCC
# =========================================================

menu_nextcloud_occ(){

while true; do

    clear

    echo -e "${CYAN}${BOLD}=== Restaurar y Reparar Nextcloud 24.3 - Instalador Nextcloud===${NC}"
    echo
    echo -e " ${YELLOW}1)${NC} Mantenimiento ON"
    echo -e " ${YELLOW}2)${NC} Mantenimiento OFF"
    echo -e " ${YELLOW}3)${NC} Actualizar y Reparar Instalación/DB (occ upgrade)"
    echo -e " ${YELLOW}4)${NC} Actualizar apps (occ app:update --all)"
    echo -e " ${YELLOW}5)${NC} Activa/Desactivar APP API"
    echo -e " ${YELLOW}6)${NC} ${YELLOW}Restaurar Nextcloud Online ${CYAN}Seguro"
    echo -e " ${YELLOW}7)${NC} Eliminar Copias de Seguridad Antiguas"
    echo -e " ${YELLOW}8)${NC} Reparación Nextcloud Inteligente"
    echo -e " ${YELLOW}9)${NC} ${YELLOW}Actualizar Nextcloud ${CYAN}Versión Nueva (updater.phar)"
    echo -e " ${YELLOW}10)${NC} OPcache FULL PRO"
    echo -e " ${YELLOW}11)${NC} Reparar tipos MIME"
    echo -e " ${YELLOW}12)${NC} Ver errores Nextcloud"
    echo -e " ${YELLOW}13)${NC} Gestión usuarios Nextcloud"
    echo -e " ${YELLOW}14)${NC} ${YELLOW}Restaurar ${CYAN}Copias de Seguridad Old/New FORZADO/SEGURO"
    echo -e " ${CYAN}0)${NC} Volver"

    echo

    read -rp "> " op

    case "$op" in

# =========================================================
# MANTENIMIENTO ON
# =========================================================

1)

echo -e "${CYAN}Activando modo mantenimiento...${NC}"

if sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" maintenance:mode --on; then

    echo -e "${GREEN}✔ Modo mantenimiento ACTIVADO${NC}"

else

    echo -e "${RED}✘ Error activando mantenimiento${NC}"

fi

pausa

;;

# =========================================================
# MANTENIMIENTO OFF
# =========================================================

2)

echo -e "${CYAN}Desactivando modo mantenimiento...${NC}"

if sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" maintenance:mode --off; then

    echo -e "${GREEN}✔ Modo mantenimiento DESACTIVADO${NC}"

else

    echo -e "${RED}✘ Error desactivando mantenimiento${NC}"

fi

pausa

;;

# =========================================================
# REPARAR / UPGRADE
# =========================================================

3)

    run_live "Activando mantenimiento" \
    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" maintenance:mode --on

    run_live "Upgrade Nextcloud" \
    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" upgrade

    autoreparacion_nc

    run_live "Desactivando mantenimiento" \
    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" maintenance:mode --off

    pausa

;;

# =========================================================
# UPDATE APPS
# =========================================================

4)

    run_live "Activando mantenimiento" \
    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" maintenance:mode --on

    run_live "Actualizando apps" \
    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" app:update --all

    run_live "Upgrade DB" \
    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" upgrade

    autoreparacion_nc

    run_live "Desactivando mantenimiento" \
    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" maintenance:mode --off

    pausa

;;

# =========================================================
# APP API
# =========================================================

5)

    gestionar_appapi_nct

;;

# =========================================================
# RESTORE
# =========================================================

6)
    nextcloud_restore
    
;;

# =========================================================
# DELETE BACKUPS
# =========================================================

7)

    nextcloud_delete_backups

;;

# =========================================================
# AUTOREPARACION
# =========================================================

8)

    run_live "Activando mantenimiento" \
    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" maintenance:mode --on

    autoreparacion_nc

    run_live "Desactivando mantenimiento" \
    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" maintenance:mode --off

    pausa

;;
9)
# =========================================================
# UPDATE PRO
# =========================================================

echo -e "${CYAN}Buscando nueva versión de Nextcloud...${NC}"

    VERSION_ACTUAL=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" status --output=json | grep -oP '"version":\s*"\K[^"]+')
    echo -e "Versión actual: ${YELLOW}$VERSION_ACTUAL${NC}"

    CHECK=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" update:check)
    echo "$CHECK"

    NUEVA_VERSION=$(echo "$CHECK" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)

    if [[ -z "$NUEVA_VERSION" || "$NUEVA_VERSION" == "$VERSION_ACTUAL" ]]; then
        warn "No hay nueva versión disponible"
        pausa
        break
    fi

    echo -e "${GREEN}Nueva versión detectada: $NUEVA_VERSION${NC}"
    confirmar "¿Actualizar de $VERSION_ACTUAL a $NUEVA_VERSION?" || break

    # ===== BACKUP =====
    echo -e "${CYAN}Realizando backup de base de datos...${NC}"
    DB_BACKUP=$(backup_db_nc) || { err "Error backup DB"; break; }
    echo -e "${GREEN}✔ Backup listo: $DB_BACKUP${NC}"

    # ===== MODO MANTENIMIENTO =====
    run_live "Activando modo mantenimiento" \
        sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --on || break

    # ===== UPDATER =====
    run_live "Ejecutando updater oficial (descarga + instalación)" \
        sudo -u $USER_WEB php "$NEXTCLOUD_DIR/updater/updater.phar" --no-interaction || {
            err "Error en actualización → rollback"
            restore_db_nc "$DB_BACKUP"
            sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --off
            break
    }

    # ===== UPGRADE =====
    run_live "Aplicando upgrade de base de datos" \
        sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" upgrade || {
            err "Error en upgrade → rollback"
            restore_db_nc "$DB_BACKUP"
            sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --off
            break
    }

    # ===== REPARACIÓN =====
    run_live "Ejecutando autoreparación" autoreparacion_nc

    # ===== SALIDA =====
    run_live "Desactivando modo mantenimiento" \
        sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --off

    echo -e "${GREEN}✔ Nextcloud actualizado correctamente${NC}"

         ;;

# =========================================================
# OPCACHE
# =========================================================

10)

    opcache_full_pro_nc

;;

# =========================================================
# MIME
# =========================================================

11)

    reparar_mime_nc

;;

# =========================================================
# LOGS
# =========================================================

12)

    ver_errores_nc

;;

# =========================================================
# USERS
# =========================================================

13)

    menu_usuarios_nextcloud

;;

# =========================================================
# RESTORE FORZADO
# =========================================================

14)

    restaurar_backup_forzado

;;

# =========================================================
# SALIR
# =========================================================

0)

    return

;;

# =========================================================
# INVALIDO
# =========================================================

*)

    warn "Opción inválida"

    pausa

;;

    esac

done

}

# ========= FUNCIONES AUXILIARES Nextcloud OCC =========
ok(){ echo -e "\e[32m$1\e[0m"; }
warn(){ echo -e "\e[33m$1\e[0m"; }
err(){ echo -e "\e[31m$1\e[0m"; }
pausa(){ read -rp "Presiona ENTER para continuar..."; }

confirmar(){
    read -rp "$1 (s/n): " c
    [[ "$c" =~ ^[sS]$ ]]
}
# ========= VER ERRORES NEXTCLOUD OCC =========
ver_errores_nc(){

    clear
    echo -e "${CYAN}${BOLD}=== ERRORES NEXTCLOUD ===${NC}"
    echo ""

    LOG_FILE="$NEXTCLOUD_DIR/data/nextcloud.log"

    if [ ! -f "$LOG_FILE" ]; then
        err "No se encontró el log"
        pausa
        return
    fi

    echo "Últimos 30 errores:"
    echo "-----------------------------------"
    tail -n 30 "$LOG_FILE"
    echo "-----------------------------------"

    echo ""
    echo "1) Ver en tiempo real"
    echo "2) Limpiar log"
    echo "0) Salir"
    echo ""

    read -rp "Seleccione: " op

    case "$op" in
        1)
            sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" log:tail
        ;;
        2)
            confirmar "¿Borrar log actual?" || return
            sudo truncate -s 0 "$LOG_FILE"
            ok "✔ Log limpiado"
        ;;
        0) return ;;
        *) err "Opción inválida" ;;
    esac

    pausa
}


# ========= REPARAR MIME TYPES OCC =========
reparar_mime_nc(){

    clear
    echo -e "${CYAN}${BOLD}=== Reparar Tipos MIME (Nextcloud) ===${NC}"

    echo "Esto puede tardar dependiendo del tamaño de tu servidor."
    echo ""

    confirmar "¿Ejecutar reparación completa de MIME?" || return

    echo ""
    echo "Activando modo mantenimiento..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --on

    echo "Ejecutando reparación (esto puede tardar)..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:repair --include-expensive

    echo "Desactivando modo mantenimiento..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --off

    ok "✔ Migración de tipos MIME completada"

    pausa
}

# ========= DETECTAR PHP.INI OCC =========
detectar_php_ini(){

    PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")

    if systemctl is-active --quiet apache2; then
        PHP_INI="/etc/php/$PHP_VERSION/apache2/php.ini"
        SERVICIO="apache2"
    else
        PHP_FPM=$(systemctl list-units --type=service | grep -oP "php$PHP_VERSION-fpm")

        if [ -n "$PHP_FPM" ]; then
            PHP_INI="/etc/php/$PHP_VERSION/fpm/php.ini"
            SERVICIO="$PHP_FPM"
        else
            echo "ERROR"
            return 1
        fi
    fi

    if [ ! -f "$PHP_INI" ]; then
        echo "ERROR"
        return 1
    fi

    echo "$PHP_INI|$SERVICIO"
}

# ========= OPCACHE FULL PRO OCC =========
opcache_full_pro_nc(){

    clear
    echo -e "${CYAN}${BOLD}=== OPcache FULL PRO (Nextcloud) ===${NC}"

    # ========= DETECCIÓN =========
 DATA=$(detectar_php_ini)
if [ $? -ne 0 ] || [ -z "$DATA" ]; then
    err "Error detectando php.ini"
    pausa
    return
fi

    PHP_INI=$(echo "$DATA" | cut -d'|' -f1)
    SERVICIO=$(echo "$DATA" | cut -d'|' -f2)

    if [ ! -f "$PHP_INI" ]; then
        err "No se encontró php.ini"
        pausa
        return
    fi

    echo -e "Archivo detectado: ${YELLOW}$PHP_INI${NC}"
    echo -e "Servicio detectado: ${YELLOW}$SERVICIO${NC}"

    # ========= VALORES ACTUALES =========
    echo ""
    echo "Valores actuales:"
    grep -E "opcache.memory_consumption|opcache.interned_strings_buffer|opcache.max_accelerated_files|opcache.revalidate_freq" "$PHP_INI" || echo "No definidos (usando defaults)"

    echo ""
    echo "=== PERFILES ==="
    echo "1) Básico (servidor pequeño) ✅"
    echo "2) Recomendado (Nextcloud normal) 🚀"
    echo "3) Alto rendimiento (servidor potente) 🔥"
    echo "4) Personalizado"
    echo "0) Cancelar"
    echo ""

    read -rp "Seleccione [2]: " op
    op=${op:-2}

    case "$op" in
        1)
            MEM=128
            STR=16
            FILES=10000
            REVAL=2
        ;;
        2)
            MEM=256
            STR=16
            FILES=20000
            REVAL=60
        ;;
        3)
            MEM=512
            STR=32
            FILES=100000
            REVAL=120
        ;;
        4)
            read -rp "memory_consumption (MB): " MEM
            read -rp "interned_strings_buffer (MB): " STR
            read -rp "max_accelerated_files: " FILES
            read -rp "revalidate_freq: " REVAL
        ;;
        0) return ;;
        *) err "Opción inválida"; pausa; return ;;
    esac

    echo ""
    confirmar "Aplicar configuración OPcache PRO?" || return

    # ========= FUNCIÓN ROBUSTA =========
    aplicar_config(){
        PARAM=$1
        VAL=$2

        if grep -Eq "^[;[:space:]]*$PARAM" "$PHP_INI"; then
            sudo sed -i "s|^[;[:space:]]*$PARAM.*|$PARAM=$VAL|" "$PHP_INI"
        else
            echo "$PARAM=$VAL" | sudo tee -a "$PHP_INI" > /dev/null
        fi
    }

    echo ""
    echo "Aplicando optimización..."

    aplicar_config "opcache.enable" "1"
    aplicar_config "opcache.memory_consumption" "$MEM"
    aplicar_config "opcache.interned_strings_buffer" "$STR"
    aplicar_config "opcache.max_accelerated_files" "$FILES"
    aplicar_config "opcache.revalidate_freq" "$REVAL"
    aplicar_config "opcache.save_comments" "1"
    aplicar_config "opcache.enable_cli" "1"

    ok "✔ Parámetros aplicados"

    # ========= REINICIO =========
    echo "Reiniciando servicio $SERVICIO..."
    sudo systemctl restart "$SERVICIO"

    if systemctl is-active --quiet "$SERVICIO"; then
        ok "✔ Servicio reiniciado correctamente"
    else
        err "Error al reiniciar servicio"
        pausa
        return
    fi

    # ========= VALIDACIÓN =========
    echo ""
    echo "Validando configuración aplicada..."

    sleep 2

    VAL_CHECK=$(php -i | grep "opcache.interned_strings_buffer" | awk '{print $5}')

    if [ -z "$VAL_CHECK" ]; then
        warn "No se pudo validar automáticamente (posible entorno distinto CLI/Web)"
    else
        echo "Valor detectado en CLI: $VAL_CHECK MB"

        if [ "$VAL_CHECK" -lt "$STR" ]; then
            warn "⚠ Posible php.ini incorrecto (CLI ≠ Apache/FPM)"
        else
            ok "✔ OPcache aplicado correctamente en CLI"
        fi
    fi

    # ========= CHECK NEXTCLOUD =========
    echo ""
    echo "Verificando estado en Nextcloud..."

    NC_CHECK=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:list system 2>/dev/null)

    if [ $? -eq 0 ]; then
        ok "✔ Nextcloud responde correctamente"
    else
        warn "No se pudo verificar Nextcloud (no crítico)"
    fi

    echo ""
    echo "=== RESULTADO FINAL ==="

    if [ "$STR" -ge 16 ]; then
        ok "✔ Buffer de strings optimizado (>=16MB)"
    else
        warn "Buffer bajo (puede seguir warning)"
    fi

    echo ""
    echo "Revisa en Nextcloud:"
    echo "→ Configuración → Administración → Información"

    echo ""
    echo "Si el warning sigue:"
    echo "- Recarga con Ctrl+F5"
    echo "- Espera 1-2 minutos (cache)"
    echo "- Verifica que no uses PHP-FPM aparte"

    echo ""
    ok "✔ Optimización OPcache FULL PRO completada"

    pausa
}

# == Autoreparacion Inteligente de Nextcloud occ ==
autoreparacion_nc() {
    echo "=== Autoreparacion Inteligente de Nextcloud ==="

    # Activar modo mantenimiento
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --on

    # Detectar version
    NC_VERSION=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" status --output=json | grep -oP '"version":\s*"\K[^"]+')
    echo "Nextcloud version: $NC_VERSION"

    # Detectar comandos disponibles
    OCC_CMDS=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" list)
    [[ "$OCC_CMDS" =~ "maintenance:repair" ]] && CMD_REPAIR="maintenance:repair" || CMD_REPAIR=""
    [[ "$OCC_CMDS" =~ "files:scan" ]] && CMD_SCAN="files:scan --all" || CMD_SCAN=""
    [[ "$OCC_CMDS" =~ "files:cleanup" ]] && CMD_CLEANUP="files:cleanup" || CMD_CLEANUP=""
    [[ "$OCC_CMDS" =~ "db:add-missing-indices" ]] && CMD_INDICES="db:add-missing-indices" || CMD_INDICES=""

    echo "Ejecutando reparaciones disponibles..."

    # 1. Reparacion general
    [ -n "$CMD_REPAIR" ] && sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" $CMD_REPAIR

    # 2. Limpieza de archivos huérfanos / inconsistentes
    [ -n "$CMD_CLEANUP" ] && sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" $CMD_CLEANUP

    # 3. Añadir índices faltantes (mejora rendimiento)
    [ -n "$CMD_INDICES" ] && sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" $CMD_INDICES

    # 4. Escaneo de todos los archivos para sincronizar DB
    [ -n "$CMD_SCAN" ] && sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" $CMD_SCAN

    # Apagar modo mantenimiento antes de listar apps y configuraciones
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:mode --off

    # 5. Verificar apps instaladas
    echo "Verificando apps instaladas..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:list | grep -E "enabled|disabled"

    # 6. Revisar configuraciones criticas
    echo "Comprobando configuraciones criticas..."
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get dbhost
    sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get datadirectory

    echo "Autoreparacion inteligente completada para Nextcloud $NC_VERSION"
    read -p "Presiona ENTER para continuar..."
}

# =========================================================
# BACKUP DB NEXTCLOUD PRO
# =========================================================

backup_db_nc(){

    FECHA=$(date +%Y%m%d_%H%M%S)

    BACKUP_DIR="/root/BackupDB"
    mkdir -p "$BACKUP_DIR"

    # =========================================================
    # VALIDAR NEXTCLOUD
    # =========================================================

    if [ ! -f "$NC_DIR/occ" ]; then

        echo -e "${RED}❌ OCC no encontrado${RESET}"
        echo -e "${YELLOW}Ruta:${RESET} $NC_DIR/occ"

        return 1
    fi

    # =========================================================
    # VERSION NEXTCLOUD
    # =========================================================

    NC_VERSION=$(
        sudo -u "$WEB_USER" php "$NC_DIR/occ" status --output=json 2>/dev/null \
        | grep -oP '"version"\s*:\s*"\K[^"]+'
    )

    [ -z "$NC_VERSION" ] && NC_VERSION="unknown"

    # limpiar caracteres raros
    NC_VERSION_CLEAN=$(echo "$NC_VERSION" | tr '.' '_')

    # =========================================================
    # ARCHIVO BACKUP
    # =========================================================

    DB_BACKUP="$BACKUP_DIR/nextcloud_v${NC_VERSION_CLEAN}_${FECHA}.sql.gz"

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}      BACKUP DATABASE NEXTCLOUD${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    echo -e "${GREEN}Versión Nextcloud:${RESET} $NC_VERSION"
    echo

    # =========================================================
    # OBTENER CONFIG DB
    # =========================================================

    DB_NAME=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" config:system:get dbname 2>/dev/null)

    DB_USER=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" config:system:get dbuser 2>/dev/null)

    DB_PASS=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" config:system:get dbpassword 2>/dev/null)

    DB_HOST_RAW=$(sudo -u "$WEB_USER" php "$NC_DIR/occ" config:system:get dbhost 2>/dev/null)

    # =========================================================
    # VALIDAR CONFIG
    # =========================================================

    if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ]; then

        echo -e "${RED}❌ No se pudo obtener configuración DB${RESET}"
        return 1

    fi

    # =========================================================
    # HOST / PUERTO
    # =========================================================

    DB_HOST=$(echo "$DB_HOST_RAW" | cut -d':' -f1)
    DB_PORT=$(echo "$DB_HOST_RAW" | cut -s -d':' -f2)

    [ -z "$DB_HOST" ] && DB_HOST="localhost"
    [ -z "$DB_PORT" ] && DB_PORT="3306"

    echo -e "${CYAN}Base:${RESET} $DB_NAME"
    echo -e "${CYAN}Usuario:${RESET} $DB_USER"
    echo -e "${CYAN}Host:${RESET} $DB_HOST"
    echo -e "${CYAN}Puerto:${RESET} $DB_PORT"

    echo
    echo -e "${YELLOW}➜ Creando backup comprimido...${RESET}"
    echo

    # =========================================================
    # MYSQLDUMP
    # =========================================================

    export MYSQL_PWD="$DB_PASS"

    mysqldump \
        --single-transaction \
        --quick \
        --lock-tables=false \
        --default-character-set=utf8mb4 \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        "$DB_NAME" 2>/tmp/nc_backup_error.log | gzip > "$DB_BACKUP"

    DUMP_STATUS=$?

    unset MYSQL_PWD

    # =========================================================
    # RESULTADO
    # =========================================================

    if [ "$DUMP_STATUS" = "0" ] && [ -f "$DB_BACKUP" ]; then

        SIZE=$(du -h "$DB_BACKUP" | awk '{print $1}')

        echo -e "${GREEN}✔ Backup completado${RESET}"
        echo -e "${CYAN}Archivo:${RESET} $DB_BACKUP"
        echo -e "${CYAN}Tamaño:${RESET} $SIZE"

        echo

        # devolver ruta para:
        # DB_BACKUP=$(backup_db_nc)

        echo "$DB_BACKUP"

        return 0

    else

        echo -e "${RED}❌ Error creando backup${RESET}"

        [ -f /tmp/nc_backup_error.log ] && cat /tmp/nc_backup_error.log

        rm -f "$DB_BACKUP"

        return 1

    fi
}

# ========= RESTORE DB =========
restore_db_nc(){
    DB_FILE="$1"

    DB_NAME=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get dbname)
    DB_USER=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get dbuser)
    DB_PASS=$(sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" config:system:get dbpassword)

    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$DB_FILE"
}

# =========================================
# DELETE BACKUPS NEXTCLOUD
# =========================================

nextcloud_delete_backups(){

    listar_backups_nextcloud || return 0

    echo -e "${RED}a)${NC} Eliminar TODOS"
    echo -e "${CYAN}0)${NC} Cancelar"

    echo

    read -rp "Seleccione opción: " OP || true

    [[ -z "$OP" ]] && return 0

    # =========================================
    # CANCELAR
    # =========================================

    if [[ "$OP" == "0" ]]; then

        info "Cancelado."

        echo
        read -rp "Presiona ENTER para continuar..." || true

        return 0
    fi

    # =========================================
    # ELIMINAR TODOS
    # =========================================

    if [[ "$OP" =~ ^[aA]$ ]]; then

        echo
        echo -e "${RED}⚠ Se eliminarán TODOS los backups.${NC}"
        echo

        read -rp "Confirmar eliminación total (s/n): " CONF || true

        if [[ "$CONF" =~ ^[sS]$ ]]; then

            for BACKUP in "${BACKUPS[@]}"; do
                rm -rf "$BACKUP"
            done

            echo
            ok "✔ Todos los backups eliminados."

        else

            warn "Operación cancelada."
        fi

        echo
        read -rp "Presiona ENTER para continuar..." || true

        return 0
    fi

    # =========================================
    # ELIMINAR UNO
    # =========================================

    if [[ "$OP" =~ ^[0-9]+$ ]] && (( OP >= 1 && OP <= ${#BACKUPS[@]} )); then

        BACKUP="${BACKUPS[$((OP-1))]}"

        echo
        echo -e "${YELLOW}Backup seleccionado:${NC}"
        echo "$BACKUP"

        echo

        read -rp "⚠ Confirmar eliminación (s/n): " CONF || true

        if [[ "$CONF" =~ ^[sS]$ ]]; then

            rm -rf "$BACKUP"

            echo
            ok "✔ Backup eliminado."

        else

            warn "Operación cancelada."
        fi

    else

        error "❌ Opción inválida."
    fi

    echo
    read -rp "Presiona ENTER para continuar..." || true
}


# ========= GESTIÓN APP API (TOGGLE PRO) =========
gestionar_appapi_nct(){

    clear
    echo -e "${CYAN}${BOLD}=== GESTIÓN APP API (Nextcloud) ===${NC}"
    echo ""

    # ===== VALIDAR NEXTCLOUD =====
    if [ ! -f "$NEXTCLOUD_DIR/occ" ]; then
        err "No se encontró Nextcloud en $NEXTCLOUD_DIR"
        pausa
        return
    fi

    # ===== VERIFICAR SI EXISTE =====
    if ! sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:list | grep -q "app_api"; then
        warn "AppAPI no está instalado en Nextcloud"
        pausa
        return
    fi

    # ===== DETECTAR ESTADO =====
    if sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:list | grep -A1 "Enabled:" | grep -q "app_api"; then
        ESTADO="ACTIVO"
    else
        ESTADO="INACTIVO"
    fi

    echo -e "Estado actual: ${YELLOW}$ESTADO${NC}"
    echo ""

    echo "1) Activar AppAPI"
    echo "2) Desactivar AppAPI"
    echo "3) Toggle automático (recomendado) 🔄"
    echo "0) Cancelar"
    echo ""

    read -rp "Seleccione [3]: " op
    op=${op:-3}

    case "$op" in
        1)
            ACCION="activar"
        ;;
        2)
            ACCION="desactivar"
        ;;
        3)
            if [ "$ESTADO" = "ACTIVO" ]; then
                ACCION="desactivar"
            else
                ACCION="activar"
            fi
        ;;
        0) return ;;
        *) err "Opción inválida"; pausa; return ;;
    esac

    echo ""
    confirmar "¿Desea $ACCION AppAPI?" || return

    echo ""

    # ===== EJECUTAR ACCIÓN =====
    if [ "$ACCION" = "activar" ]; then
        if sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:enable app_api; then
            ok "✔ AppAPI activado correctamente"
        else
            err "Error al activar AppAPI"
            pausa
            return
        fi
    else
        if sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:disable app_api; then
            ok "✔ AppAPI desactivado correctamente"
        else
            err "Error al desactivar AppAPI"
            pausa
            return
        fi
    fi

    # ===== VERIFICACIÓN FINAL =====
    echo ""
    echo "Verificando estado..."

    if sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" app:list | grep -A1 "Enabled:" | grep -q "app_api"; then
        NUEVO_ESTADO="ACTIVO"
    else
        NUEVO_ESTADO="INACTIVO"
    fi

    echo -e "Nuevo estado: ${GREEN}$NUEVO_ESTADO${NC}"

    ok "✔ Operación completada"

    pausa
}
# =========================================
# LISTAR BACKUPS NEXTCLOUD UPDATER PRO
# =========================================

listar_backups_nextcloud(){

    clear

    BACKUPS=()

    # =========================================
    # BUSCAR BACKUPS
    # =========================================

    while IFS= read -r -d '' dir; do
        BACKUPS+=("$dir")
    done < <(
        find "$NEXTCLOUD_DATA" \
            -mindepth 3 \
            -maxdepth 3 \
            -type d \
            -path "*/updater-*/backups/*" \
            -print0 2>/dev/null | sort -z
    )

    # =========================================
    # VALIDAR
    # =========================================

    if [ ${#BACKUPS[@]} -eq 0 ]; then

        warn "No se encontraron backups del updater."

        echo
        read -rp "Presiona ENTER para continuar..." || true

        return 1
    fi

    # =========================================
    # VERSION ACTUAL
    # =========================================

CURRENT_VERSION=$(
    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" status --output=json 2>/dev/null \
    | grep -oP '"version"\s*:\s*"\K[^"]+'
)

    # =========================================
    # HEADER
    # =========================================

    echo -e "${CYAN}=================================================${NC}"
    echo -e "${WHITE}         BACKUPS NEXTCLOUD UPDATER${NC}"
    echo -e "${CYAN}=================================================${NC}"

    echo -e "${GREEN}Versión actual:${NC} ${WHITE}${CURRENT_VERSION:-Desconocida}${NC}"

    echo

    TOTAL_SIZE=0

    # =========================================
    # MOSTRAR BACKUPS
    # =========================================

    for i in "${!BACKUPS[@]}"; do

        BACKUP="${BACKUPS[$i]}"

        NAME=$(basename "$BACKUP")

        # =========================================
        # VERSION BACKUP
        # =========================================

        VERSION="Desconocida"

        if [ -f "$BACKUP/version.php" ]; then

            VERSION=$(grep "\$OC_VersionString" \
                "$BACKUP/version.php" \
                | cut -d"'" -f2)
        fi

        # =========================================
        # SIZE
        # =========================================

        SIZE=$(du -sh "$BACKUP" 2>/dev/null | awk '{print $1}')

        SIZE_BYTES=$(du -sb "$BACKUP" 2>/dev/null | awk '{print $1}')

        TOTAL_SIZE=$((TOTAL_SIZE + SIZE_BYTES))

        # =========================================
        # FECHA
        # =========================================

        FECHA=$(stat -c '%y' "$BACKUP" \
            2>/dev/null | cut -d'.' -f1)

        # =========================================
        # ARCHIVOS
        # =========================================

        FILES=$(find "$BACKUP" -type f 2>/dev/null | wc -l)

        # =========================================
        # UPDATER
        # =========================================

        UPDATER=$(echo "$BACKUP" | grep -oP 'updater-[^/]+' || true)

        # =========================================
        # MOSTRAR INFO
        # =========================================

        echo -e "${YELLOW}$((i+1)))${NC} ${WHITE}$NAME${NC}"

        if [[ "$VERSION" == "$CURRENT_VERSION" ]]; then

            echo -e "   ${CYAN}Versión :${NC} ${GREEN}${VERSION} ✔ ACTUAL${NC}"

        else

            echo -e "   ${CYAN}Versión :${NC} ${VERSION:-?}"

        fi

        echo -e "   ${CYAN}Tamaño  :${NC} ${SIZE:-?}"
        echo -e "   ${CYAN}Fecha   :${NC} ${FECHA:-?}"
        echo -e "   ${CYAN}Archivos:${NC} $FILES"
        echo -e "   ${CYAN}Updater :${NC} ${UPDATER:-?}"
        echo -e "   ${CYAN}Ruta    :${NC} $BACKUP"

        echo
    done

    # =========================================
    # TOTAL
    # =========================================

    TOTAL_HUMAN=$(numfmt --to=iec "$TOTAL_SIZE" 2>/dev/null)

    echo -e "${CYAN}=================================================${NC}"
    echo -e "${GREEN}Total backups :${NC} ${#BACKUPS[@]}"
    echo -e "${GREEN}Espacio usado :${NC} ${TOTAL_HUMAN:-?}"
    echo -e "${CYAN}=================================================${NC}"

    echo

    return 0
}

# =========================================================
# REINSTALAR NEXTCLOUD DESDE INTERNET
# REPARA INSTALACION DAÑADA
# CONSERVA DB + DATA + CONFIG
# =========================================================

nextcloud_restore(){

    clear

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${WHITE}   REINSTALAR NEXTCLOUD DESDE INTERNET${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo

    # =========================================================
    # VALIDAR NEXTCLOUD
    # =========================================================

    if [ ! -f "$NEXTCLOUD_DIR/version.php" ]; then

        echo -e "${RED}❌ No se encontró Nextcloud${RESET}"

        read -rp "ENTER para continuar..."
        return 1
    fi

    # =========================================================
    # DETECTAR VERSION
    # =========================================================

    echo -e "${CYAN}➜ Detectando versión instalada...${RESET}"

    VERSION_ACTUAL=$(
        grep "\$OC_VersionString" \
        "$NEXTCLOUD_DIR/version.php" \
        | cut -d"'" -f2
    )

    if [ -z "$VERSION_ACTUAL" ]; then

        VERSION_ACTUAL=$(
            sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
            status --output=json 2>/dev/null \
            | grep -oP '"version"\s*:\s*"\K[^"]+'
        )
    fi

    if [ -z "$VERSION_ACTUAL" ]; then

        echo -e "${RED}❌ No se pudo detectar la versión${RESET}"

        read -rp "ENTER para continuar..."
        return 1
    fi

    echo -e "${GREEN}✔ Versión detectada:${RESET} $VERSION_ACTUAL"
    echo

    confirmar "¿Reinstalar Nextcloud $VERSION_ACTUAL?" || return

    # =========================================================
    # OBTENER CONFIG
    # =========================================================

    DATA_DIR=$(
        sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
        config:system:get datadirectory 2>/dev/null
    )

    [ -z "$DATA_DIR" ] && DATA_DIR="/var/www/nextcloud-data"

    echo -e "${CYAN}Data directory:${RESET} $DATA_DIR"
    echo

    # =========================================================
    # MODO MANTENIMIENTO
    # =========================================================

    echo -e "${YELLOW}➜ Activando modo mantenimiento...${RESET}"

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
    maintenance:mode --on || true

    echo

    # =========================================================
    # DETENER SERVICIOS
    # =========================================================

    detener_servicios_nextcloud

    # =========================================================
    # TEMPORAL
    # =========================================================

    TMP_DIR="/tmp/nextcloud_reinstall"

    rm -rf "$TMP_DIR"

    mkdir -p "$TMP_DIR"

    cd "$TMP_DIR" || return 1

    # =========================================================
    # URLS DESCARGA
    # =========================================================

    BASE_URL="https://download.nextcloud.com/server/releases"

    ZIP_URL="$BASE_URL/nextcloud-$VERSION_ACTUAL.zip"

    TAR_URL="$BASE_URL/nextcloud-$VERSION_ACTUAL.tar.bz2"

    # =========================================================
    # DESCARGA
    # =========================================================

    echo -e "${CYAN}➜ Descargando Nextcloud $VERSION_ACTUAL...${RESET}"
    echo

    FORMATO=""

    if wget -q --spider "$ZIP_URL"; then

        echo -e "${GREEN}✔ ZIP encontrado${RESET}"

        wget -O nextcloud.zip "$ZIP_URL"

        ARCHIVO="nextcloud.zip"

        FORMATO="zip"

    else

        echo -e "${YELLOW}⚠ ZIP no disponible${RESET}"
        echo -e "${CYAN}Intentando TAR.BZ2...${RESET}"

        if wget -q --spider "$TAR_URL"; then

            echo -e "${GREEN}✔ TAR.BZ2 encontrado${RESET}"

            wget -O nextcloud.tar.bz2 "$TAR_URL"

            ARCHIVO="nextcloud.tar.bz2"

            FORMATO="tar"

        else

            echo -e "${RED}❌ No existe la versión:${RESET} $VERSION_ACTUAL"

            iniciar_servicios_nextcloud

            read -rp "ENTER para continuar..."
            return 1
        fi
    fi

    echo
    echo -e "${GREEN}✔ Descarga completada${RESET}"
    echo

    # =========================================================
    # EXTRAER
    # =========================================================

    echo -e "${CYAN}➜ Extrayendo archivos...${RESET}"

    if [ "$FORMATO" = "zip" ]; then

        unzip -q "$ARCHIVO"

    else

        tar -xjf "$ARCHIVO"

    fi

    if [ ! -d "$TMP_DIR/nextcloud" ]; then

        echo -e "${RED}❌ Error extrayendo Nextcloud${RESET}"

        iniciar_servicios_nextcloud
        return 1
    fi

    echo -e "${GREEN}✔ Archivos extraídos${RESET}"
    echo

    # =========================================================
    # BACKUP CONFIG
    # =========================================================

    echo -e "${CYAN}➜ Resguardando config.php...${RESET}"

    mkdir -p /tmp/nc_restore_backup

    cp "$NEXTCLOUD_DIR/config/config.php" \
       /tmp/nc_restore_backup/config.php.bak

    # =========================================================
    # ELIMINAR INSTALACION DAÑADA
    # =========================================================

    echo -e "${CYAN}➜ Eliminando instalación dañada...${RESET}"

    find "$NEXTCLOUD_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        ! -name "data" \
        -exec rm -rf {} +

    echo

    # =========================================================
    # COPIAR NUEVA INSTALACION
    # =========================================================

    echo -e "${CYAN}➜ Instalando nueva copia...${RESET}"

    rsync -Aax --info=progress2 \
        "$TMP_DIR/nextcloud"/ \
        "$NEXTCLOUD_DIR"/

    if [ $? != 0 ]; then

        echo -e "${RED}❌ Error copiando archivos${RESET}"

        iniciar_servicios_nextcloud
        return 1
    fi

    echo
    echo -e "${GREEN}✔ Archivos instalados${RESET}"
    echo

    # =========================================================
    # RESTAURAR CONFIG
    # =========================================================

    mkdir -p "$NEXTCLOUD_DIR/config"

    cp /tmp/nc_restore_backup/config.php.bak \
       "$NEXTCLOUD_DIR/config/config.php"

    echo -e "${GREEN}✔ Config restaurado${RESET}"
    echo

    # =========================================================
    # DATA DIRECTORY
    # =========================================================

    mkdir -p "$DATA_DIR"

    touch "$DATA_DIR/.ocdata"

    # =========================================================
    # PERMISOS
    # =========================================================

    echo -e "${CYAN}➜ Corrigiendo permisos...${RESET}"

    chown -R "$USER_WEB:$USER_WEB" "$NEXTCLOUD_DIR"

    find "$NEXTCLOUD_DIR" -type d -exec chmod 750 {} \;

    find "$NEXTCLOUD_DIR" -type f -exec chmod 640 {} \;

    chmod +x "$NEXTCLOUD_DIR/occ"

    echo

    # =========================================================
    # INICIAR SERVICIOS
    # =========================================================

    iniciar_servicios_nextcloud
# =========================================================
# UPGRADE NEXTCLOUD
# =========================================================

echo
echo -e "${YELLOW}➜ Ejecutando upgrade...${RESET}"
echo

sudo -u "$USER_WEB" php \
-d memory_limit=1G \
"$NEXTCLOUD_DIR/occ" upgrade

UPGRADE_STATUS=$?

echo

if [ "$UPGRADE_STATUS" != "0" ]; then

    echo -e "${RED}❌ Upgrade terminó con errores${RESET}"
    echo

    sudo -u "$USER_WEB" php \
    "$NEXTCLOUD_DIR/occ" maintenance:mode --off || true

    iniciar_servicios_nextcloud

    read -rp "ENTER para continuar..."
    return 1
fi

echo -e "${GREEN}✔ Upgrade completado${RESET}"
echo

    # =========================================================
    # REPARACION
    # =========================================================

    echo -e "${CYAN}➜ Reparando instalación...${RESET}"

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" maintenance:repair || true

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" db:add-missing-indices || true

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" db:add-missing-columns || true

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" db:add-missing-primary-keys || true

    echo

    # =========================================================
    # MAINTENANCE OFF
    # =========================================================

    echo -e "${CYAN}➜ Desactivando mantenimiento...${RESET}"

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
    maintenance:mode --off || true

    echo

    # =========================================================
    # LIMPIEZA
    # =========================================================

    rm -rf "$TMP_DIR"

    # =========================================================
    # VERSION FINAL
    # =========================================================

    VERSION_FINAL=$(
        sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" \
        status --output=json 2>/dev/null \
        | grep -oP '"version"\s*:\s*"\K[^"]+'
    )

    # =========================================================
    # FINAL
    # =========================================================

    echo -e "${CYAN}========================================${RESET}"
    echo -e "${GREEN}✔ NEXTCLOUD REINSTALADO${RESET}"
    echo -e "${GREEN}Versión:${RESET} $VERSION_FINAL"
    echo -e "${CYAN}========================================${RESET}"

    echo

    sudo -u "$USER_WEB" php "$NEXTCLOUD_DIR/occ" check || true

    echo
    read -rp "ENTER para continuar..."
}

# =========================================================
# FIN REINSTALAR NEXTCLOUD
# =========================================================

# ========= RESTORE COPIA DE SEGURIDAD FORZADO =========

restaurar_backup_forzado(){
echo -e "${YELLOW}📂 Buscando backups disponibles...${NC}"
  listar_backups_nextcloud || return

  read -rp "Selecciona la copia a restaurar (0=cancelar): " n
  [[ "$n" == "0" ]] && warn "Cancelado." && return
  [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#BACKUPS[@]} )) || { err "Número inválido."; return; }

  SELECTED_BACKUP="${BACKUPS[$((n-1))]}"
echo
echo -e "${CYAN}📦 Backup seleccionado:${NC} ${WHITE}$SELECTED_BACKUP${NC}"
  confirmar "¿Restaurar desde $SELECTED_BACKUP?" || return

echo
echo -e "${YELLOW}🔍 Verificando dependencia pv...${NC}"

  # ===== Verificar pv (sin cortar ejecución) =====
USE_PV=true

if ! command -v pv >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠ pv no está instalado. Intentando instalar...${NC}"
  
  if apt update -qq && apt install -y -qq pv; then
    echo -e "${GREEN}✔ pv instalado correctamente${NC}"
  else
    echo -e "${RED}❌ No se pudo instalar pv, continuando sin barra de progreso...${NC}"
    USE_PV=false
  fi
fi

echo -e "${YELLOW}⛔ Deteniendo servicios Nextcloud...${NC}"
  detener_servicios_nextcloud

  echo
  echo -e "${CYAN}🧹 Eliminando instalación actual...${NC}"

  # BORRADO TOTAL (fuerza bruta)
  rm -rf "$NEXTCLOUD_DIR"/*
  echo -e "${GREEN}✔ Instalación anterior eliminada${NC}"

  echo
  echo -e "${CYAN}📥 Restaurando archivos desde backup...${NC}"
  
  # ===== RESTORE CON PROGRESO (MISMA LÓGICA CP) =====
TOTAL_FILES=$(find "$SELECTED_BACKUP" -type f | wc -l)
  echo -e "${WHITE}📄 Total de archivos a restaurar:${NC} $TOTAL_FILES"
cd "$SELECTED_BACKUP" || return

find . -type f -print0 | pv -0 -l -s "$TOTAL_FILES" -w 80 \
-F "Progreso: [%b] %p%% (%c/$TOTAL_FILES archivos) ETA %t" \
| while IFS= read -r -d '' file; do
  mkdir -p "$NEXTCLOUD_DIR/$(dirname "$file")"
  cp -a "$file" "$NEXTCLOUD_DIR/$file"
done

echo

  echo
  echo -e "${YELLOW}🔐 Aplicando permisos seguros...${NC}"
  # PERMISOS

# PROPIETARIO
chown -R $USER_WEB:$USER_WEB "$NEXTCLOUD_DIR"
echo -e "${YELLOW}🔐 Aplicado Permisos Propietario...${NC}"

# PERMISOS SEGUROS
find "$NEXTCLOUD_DIR" -type d -exec chmod 750 {} \;
find "$NEXTCLOUD_DIR" -type f -exec chmod 640 {} \;
echo -e "${YELLOW}🔐 Aplicado Permisos Nextcloud chmod 750/640...${NC}"

# OCC EJECUTABLE
chmod +x "$NEXTCLOUD_DIR/occ"
echo -e "${YELLOW}🔐 Aplicado Permiso Ejecutable OCC...${NC}"

# CARPETAS QUE NEXTCLOUD NECESITA ESCRIBIR

chmod -R 770 "$NEXTCLOUD_DIR/config"
chmod -R 770 "$NEXTCLOUD_DIR/apps"
chmod -R 770 "$NEXTCLOUD_DIR/custom_apps"
chmod -R 770 "$NEXTCLOUD_DIR/updater"
echo -e "${YELLOW}🔐 Aplicado Permiso Carpetas que necesta Escribir...${NC}"
# DATA
chown -R $USER_WEB:$USER_WEB "$DATA_DIR"
find "$DATA_DIR" -type d -exec chmod 750 {} \;
find "$DATA_DIR" -type f -exec chmod 640 {} \; 
echo -e "${YELLOW}🔐 Aplicado Permisos nextcloud-data 750/640...${NC}"
echo
echo
echo -e "${GREEN}✔ Permisos aplicados${NC}"  
  
  echo
  echo -e "${YELLOW}▶ Iniciando servicios Nextcloud...${NC}"
  iniciar_servicios_nextcloud
  
  echo -e "${YELLOW}Intentando upgrade...${NC}"
  sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" upgrade 2>/dev/null
  
  echo -e "${YELLOW} Deshabilitando modo mantenimiento ${NC}"
  sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off
  
  # REPARACION BASICA
  echo -e "${YELLOW}Ejecutando reparación básica...${NC}"
  sudo -u $USER_WEB php "$NEXTCLOUD_DIR/occ" maintenance:repair 2>/dev/null
  
printf "\n"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}   ✔ Restauración completada correctamente  ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo
echo -e "${CYAN}📌 Presiona Enter para volver al menú...${NC}"
read

}

# ========= FIN RESTORE COPIA DE SEGURIDAD FORZADO =========

# INICIAR SERVICIOS DE Nextcloud

iniciar_servicios_nextcloud() {
    echo -e "${CYAN}Iniciando servicios de Nextcloud...${NC}"

    systemctl start apache2 2>/dev/null
    systemctl start nginx 2>/dev/null

    systemctl start php8.3-fpm 2>/dev/null
    systemctl start php8.2-fpm 2>/dev/null
    systemctl start php8.1-fpm 2>/dev/null

    echo -e "${GREEN}✔ Servicios iniciados${NC}"
}

# FIN INICIAR SERVICIOS DE Nextcloud

# DETENER SERVICIOS DE Nextcloud
detener_servicios_nextcloud() {
    echo -e "${CYAN}Deteniendo servicios de Nextcloud...${NC}"

    # Apache
    systemctl stop apache2 2>/dev/null

    # Nginx
    systemctl stop nginx 2>/dev/null

    # PHP-FPM (varias versiones posibles)
    systemctl stop php8.3-fpm 2>/dev/null
    systemctl stop php8.2-fpm 2>/dev/null
    systemctl stop php8.1-fpm 2>/dev/null

    # Cron de Nextcloud (www-data normalmente)
    crontab -u www-data -l 2>/dev/null | grep -v "cron.php" | crontab -u www-data -

    echo -e "${GREEN}✔ Servicios detenidos${NC}"
}
# FIN DETENER SERVICIOS DE Nextcloud
# =========================================================
# NEXTCLOUD USER MANAGER (STANDALONE)
# =========================================================

# ========= COLORES =========

RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'

# ========= CONFIG =========

NC_PATH="/var/www/nextcloud"
NC_USER="www-data"

# Detectar DATA_DIR automáticamente
DATA_DIR=$(sudo -u "$NC_USER" php "$NC_PATH/occ" config:system:get datadirectory 2>/dev/null)

# Usuario web
WEB_USER="www-data"

# ========= FUNCIONES BASE =========

pausa(){
    echo
    read -rp "Presiona ENTER para continuar..."
}

ok(){
    echo -e "${GREEN}✔ $1${RESET}"
}

warn(){
    echo -e "${YELLOW}⚠ $1${RESET}"
}

err(){
    echo -e "${RED}✘ $1${RESET}"
}

# =========================================================
# VALIDAR NEXTCLOUD
# =========================================================

validar_nextcloud(){

    if [ ! -f "$NC_PATH/occ" ]; then

        err "No se encontró Nextcloud en:"
        echo "$NC_PATH"
        exit 1

    fi

    if [ -z "$DATA_DIR" ]; then

        err "No se pudo detectar DATA_DIR"
        exit 1

    fi

}

# =========================================================
# MENU PRINCIPAL
# =========================================================

menu_usuarios_nextcloud(){

  while true; do

    clear

    echo -e "${CYAN}${BOLD}=========================================${RESET}"
    echo -e "${CYAN}${BOLD}      NEXTCLOUD USER MANAGER            ${RESET}"
    echo -e "${CYAN}${BOLD}=========================================${RESET}"

    echo
    echo -e "${CYAN}Nextcloud:${RESET} $NC_PATH"
    echo -e "${CYAN}DATA:${RESET} $DATA_DIR"

    echo
    echo -e " ${YELLOW}1)${RESET} Listar usuarios"
    echo -e " ${YELLOW}2)${RESET} Crear usuario"
    echo -e " ${YELLOW}3)${RESET} Eliminar usuario"
    echo -e " ${YELLOW}4)${RESET} Resetear contraseña"
    echo -e " ${YELLOW}5)${RESET} Cambiar contraseña automático"
    echo -e " ${YELLOW}6)${RESET} Hacer administrador"
    echo -e " ${YELLOW}7)${RESET} Información usuario"
    echo -e " ${YELLOW}0)${RESET} Volver"

    echo
    read -rp "> " op

    case "$op" in

      1) nc_listar_usuarios ;;
      2) nc_crear_usuario ;;
      3) nc_eliminar_usuario ;;
      4) nc_resetear_password ;;
      5) nc_cambiar_password ;;
      6) nc_hacer_admin ;;
      7) nc_info_usuario ;;
      0) return ;;

      *) warn "Opción inválida"; pausa ;;

    esac

  done
}

# =========================================================
# LISTAR USUARIOS
# =========================================================

nc_listar_usuarios(){

    clear

    echo
    echo -e "${YELLOW}==================================================${RESET}"
    echo -e "${YELLOW}           USUARIOS NEXTCLOUD                     ${RESET}"
    echo -e "${YELLOW}==================================================${RESET}"
    echo

    USERS=$(sudo -u "$NC_USER" php "$NC_PATH/occ" user:list \
        | cut -d: -f2 \
        | sed 's/^ //')

    if [ -z "$USERS" ]; then

        err "No hay usuarios registrados"
        pausa
        return

    fi

    COUNT=1

    for USER in $USERS; do

        IS_ADMIN=$(sudo -u "$NC_USER" php "$NC_PATH/occ" group:list "$USER" 2>/dev/null | grep -w admin)

        QUOTA=$(sudo -u "$NC_USER" php "$NC_PATH/occ" user:info "$USER" 2>/dev/null \
            | grep "quota:" \
            | awk -F': ' '{print $2}')

        [ -z "$QUOTA" ] && QUOTA="Default"

        if [ -n "$IS_ADMIN" ]; then

            echo -e "${CYAN}[$COUNT]${RESET} ${GREEN}$USER${RESET} ${YELLOW}(ADMIN)${RESET}"

        else

            echo -e "${CYAN}[$COUNT]${RESET} ${GREEN}$USER${RESET}"

        fi

        echo -e "    ${CYAN}Cuota:${RESET} $QUOTA"

        if [ -d "$DATA_DIR/$USER" ]; then

            SIZE=$(du -sh "$DATA_DIR/$USER" 2>/dev/null | awk '{print $1}')

            echo -e "    ${CYAN}DATA:${RESET} ${GREEN}Existe${RESET} (${SIZE})"

        else

            echo -e "    ${CYAN}DATA:${RESET} ${RED}No encontrada${RESET}"

        fi

        echo

        COUNT=$((COUNT+1))

    done

    pausa
}

# =========================================================
# CREAR USUARIO
# =========================================================

nc_crear_usuario(){

    clear

    echo
    echo -e "${YELLOW}==================================================${RESET}"
    echo -e "${YELLOW}        CREAR USUARIO NEXTCLOUD                   ${RESET}"
    echo -e "${YELLOW}==================================================${RESET}"
    echo

    read -rp "Nuevo usuario: " USERNAME

    if [ -z "$USERNAME" ]; then

        err "Usuario vacío"
        pausa
        return

    fi

    USER_DIR="$DATA_DIR/$USERNAME"

    TEMP_BACKUP="${DATA_DIR}/.${USERNAME}_backup_$(date +%s)"

    RESTORE_USER=0

    if sudo -u "$NC_USER" php "$NC_PATH/occ" user:info "$USERNAME" >/dev/null 2>&1; then

        err "El usuario ya existe"
        pausa
        return

    fi

    if [ -d "$USER_DIR" ]; then

        echo
        warn "Carpeta existente detectada"
        echo -e "${CYAN}Ruta:${RESET} $USER_DIR"
        echo

        read -rp "¿Reutilizar DATA existente? (s/n): " REUSE_DATA

        if [[ "$REUSE_DATA" =~ ^[sS]$ ]]; then

            echo
            echo -e "${CYAN}Limpiando residuos...${RESET}"

            rm -rf "$USER_DIR/files_trashbin" 2>/dev/null
            rm -rf "$USER_DIR/files_versions" 2>/dev/null
            rm -rf "$USER_DIR/uploads" 2>/dev/null
            rm -rf "$USER_DIR/cache" 2>/dev/null

            find "$USER_DIR" -type d -name "appdata_*" -exec rm -rf {} + 2>/dev/null
            find "$USER_DIR" -type d -name "updater-*" -exec rm -rf {} + 2>/dev/null
            find "$USER_DIR" -type f -name "*.log" -delete 2>/dev/null

            mv "$USER_DIR" "$TEMP_BACKUP"

            if [ $? -ne 0 ]; then

                err "No se pudo mover DATA"
                pausa
                return

            fi

            RESTORE_USER=1

        else

            warn "Operación cancelada"
            pausa
            return

        fi

    fi

    echo
    echo -e "${CYAN}Creando usuario...${RESET}"

    sudo -u "$NC_USER" php "$NC_PATH/occ" user:add "$USERNAME"

    if [ $? -ne 0 ]; then

        err "Error creando usuario"

        if [ "$RESTORE_USER" = "1" ] && [ -d "$TEMP_BACKUP" ]; then
            mv "$TEMP_BACKUP" "$USER_DIR"
        fi

        pausa
        return

    fi

    if [ "$RESTORE_USER" = "1" ]; then

        echo
        echo -e "${CYAN}Restaurando DATA...${RESET}"

        rm -rf "$USER_DIR"
        mv "$TEMP_BACKUP" "$USER_DIR"

        chown -R "$WEB_USER:$WEB_USER" "$USER_DIR"

        find "$USER_DIR" -type d -exec chmod 750 {} \;
        find "$USER_DIR" -type f -exec chmod 640 {} \;

        echo
        echo -e "${CYAN}Escaneando archivos...${RESET}"

        sudo -u "$NC_USER" php "$NC_PATH/occ" files:scan --path="$USERNAME/files"

    fi

    ok "Usuario creado correctamente"

    pausa
}

# =========================================================
# ELIMINAR USUARIO NEXTCLOUD (SEGURO)
# CONSERVA DATA RENOMBRANDO ANTES
# =========================================================

nc_eliminar_usuario(){

    clear

    echo
    echo -e "${YELLOW}==================================================${RESET}"
    echo -e "${YELLOW}         ELIMINAR USUARIO NEXTCLOUD               ${RESET}"
    echo -e "${YELLOW}==================================================${RESET}"

    seleccionar_usuario_nc || return

    USER_DIR="$DATA_DIR/$SELECTED_USER"

    echo
    echo -e "${CYAN}Usuario:${RESET} ${GREEN}$SELECTED_USER${RESET}"
    echo

    read -rp "¿Eliminar también DATA del usuario? (s/n): " DEL_DATA

    # =====================================================
    # SI SE CONSERVA DATA
    # =====================================================

    if [[ ! "$DEL_DATA" =~ ^[sS]$ ]] && [ -d "$USER_DIR" ]; then

        echo
        echo -e "${CYAN}Protegiendo DATA usuario...${RESET}"

        # =================================================
        # RENOMBRAR DATA ANTES DE ELIMINAR
        # =================================================

        TEMP_BACKUP="${DATA_DIR}/.${SELECTED_USER}_backup_$(date +%s)"

        mv "$USER_DIR" "$TEMP_BACKUP"

        if [ $? -ne 0 ]; then

            err "No se pudo proteger DATA"

            pausa
            return

        fi

        ok "DATA protegida temporalmente"

    fi

    # =====================================================
    # ELIMINAR USUARIO NEXTCLOUD
    # =====================================================

    echo
    echo -e "${CYAN}Eliminando usuario Nextcloud...${RESET}"

    sudo -u "$NC_USER" php "$NC_PATH/occ" user:delete "$SELECTED_USER"

    if [ $? -ne 0 ]; then

        err "Error eliminando usuario"

        # =================================================
        # RESTAURAR DATA SI FALLA
        # =================================================

        if [ -d "$TEMP_BACKUP" ]; then

            mv "$TEMP_BACKUP" "$USER_DIR"

            ok "DATA restaurada"

        fi

        pausa
        return

    fi

    ok "Usuario eliminado"

    # =====================================================
    # ELIMINAR DATA DEFINITIVAMENTE
    # =====================================================

    if [[ "$DEL_DATA" =~ ^[sS]$ ]]; then

        echo
        echo -e "${CYAN}Eliminando DATA usuario...${RESET}"

        rm -rf "$USER_DIR"

        if [ $? -eq 0 ]; then

            ok "DATA eliminada"
        else
            err "No se pudo eliminar DATA"
        fi

    else

        # =================================================
        # RESTAURAR NOMBRE ORIGINAL
        # =================================================

        echo
        echo -e "${CYAN}Restaurando DATA usuario...${RESET}"

        mv "$TEMP_BACKUP" "$USER_DIR"

        if [ $? -ne 0 ]; then

            err "No se pudo restaurar DATA"

            pausa
            return

        fi

        # =================================================
        # REPARAR PERMISOS
        # =================================================

        chown -R "$WEB_USER:$WEB_USER" "$USER_DIR"

        find "$USER_DIR" -type d -exec chmod 750 {} \;
        find "$USER_DIR" -type f -exec chmod 640 {} \;

        ok "DATA restaurada correctamente"

        echo
        echo -e "${GREEN}✔ DATA conservada:${RESET}"
        echo "$USER_DIR"

    fi

    pausa
}

# =========================================================
# SELECCIONAR USUARIO
# =========================================================

seleccionar_usuario_nc(){

    USERS=$(sudo -u "$NC_USER" php "$NC_PATH/occ" user:list \
        | cut -d: -f2 \
        | sed 's/^ //')

    if [ -z "$USERS" ]; then

        err "No hay usuarios"
        return 1

    fi

    echo

    USER_ARRAY=()

    COUNT=1

    for USER in $USERS; do

        USER_ARRAY+=("$USER")

        echo -e "${CYAN}[$COUNT]${RESET} ${GREEN}$USER${RESET}"

        COUNT=$((COUNT+1))

    done

    echo -e "${CYAN}[$COUNT]${RESET} ${RED}Volver${RESET}"
    echo

    while true; do

        read -rp "Selecciona usuario: " OPTION

        if ! [[ "$OPTION" =~ ^[0-9]+$ ]]; then

            warn "Ingresa un número válido"
            continue

        fi

        if [ "$OPTION" -eq "$COUNT" ]; then
            return 1
        fi

        INDEX=$((OPTION-1))

        if [ -n "${USER_ARRAY[$INDEX]}" ]; then

            SELECTED_USER="${USER_ARRAY[$INDEX]}"
            return 0

        fi

        warn "Selección inválida"

    done
}

# =========================================================
# RESET PASSWORD
# =========================================================

nc_resetear_password(){

    clear

    seleccionar_usuario_nc || return

    echo
    echo -e "${CYAN}Usuario:${RESET} ${GREEN}$SELECTED_USER${RESET}"
    echo

    sudo -u "$NC_USER" php "$NC_PATH/occ" user:resetpassword "$SELECTED_USER"

    pausa
}

# =========================================================
# PASSWORD AUTOMATICO
# =========================================================

nc_cambiar_password(){

    clear

    seleccionar_usuario_nc || return

    echo
    echo -e "${CYAN}Usuario:${RESET} ${GREEN}$SELECTED_USER${RESET}"
    echo

    read -rsp "Nueva contraseña: " pass
    echo

    if [ -z "$pass" ]; then

        warn "Contraseña vacía"
        pausa
        return

    fi

    sudo -u "$NC_USER" OC_PASS="$pass" php "$NC_PATH/occ" \
        user:resetpassword --password-from-env "$SELECTED_USER"

    if [ $? -eq 0 ]; then
        ok "Contraseña actualizada"
    else
        err "Error cambiando contraseña"
    fi

    pausa
}

# =========================================================
# HACER ADMIN
# =========================================================

nc_hacer_admin(){

    clear

    seleccionar_usuario_nc || return

    echo
    echo -e "${CYAN}Usuario:${RESET} ${GREEN}$SELECTED_USER${RESET}"
    echo

    sudo -u "$NC_USER" php "$NC_PATH/occ" group:add admin >/dev/null 2>&1

    sudo -u "$NC_USER" php "$NC_PATH/occ" \
        group:adduser admin "$SELECTED_USER"

    if [ $? -eq 0 ]; then
        ok "Usuario ahora es ADMIN"
    else
        err "Error asignando permisos"
    fi

    pausa
}

# =========================================================
# INFO USUARIO
# =========================================================

nc_info_usuario(){

    clear

    seleccionar_usuario_nc || return

    echo
    echo -e "${CYAN}Usuario:${RESET} ${GREEN}$SELECTED_USER${RESET}"
    echo

    sudo -u "$NC_USER" php "$NC_PATH/occ" user:info "$SELECTED_USER"

    pausa
}
# =========================================================
# ACTUALIZAR SCRIPT DESDE GITHUB
# DESCARGA Y GUARDA CON EL MISMO NOMBRE
# =========================================================

update_script(){

    echo
    echo -e "${CYAN}Buscando scripts disponibles...${RESET}"

    # =====================================================
    # CONFIG GITHUB
    # =====================================================

    GITHUB_USER="llancor-cmd"
    GITHUB_REPO="script-llancor"
    GITHUB_BRANCH="main"
    GITHUB_PATH="Script_Unificados_3.0"

    API_URL="https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO/contents/$GITHUB_PATH"

    # =====================================================
    # VERIFICAR DEPENDENCIAS
    # =====================================================

    for cmd in curl jq wget; do

        if ! command -v "$cmd" >/dev/null 2>&1; then

            echo
            echo -e "${YELLOW}Instalando dependencia:${RESET} $cmd"

            apt update -y

            case $cmd in

                jq)
                    apt install -y jq
                ;;

                *)
                    apt install -y curl wget
                ;;

            esac
        fi
    done

    # =====================================================
    # VALIDAR INTERNET
    # =====================================================

    if ! ping -c 1 github.com >/dev/null 2>&1; then

        echo
        echo -e "${RED}Sin conexión a internet.${RESET}"

        return
    fi

    # =====================================================
    # OBTENER ARCHIVOS DESDE GITHUB
    # =====================================================

    HTTP_CODE=$(curl -s -o /tmp/github_scripts.json -w "%{http_code}" "$API_URL")

    if [ "$HTTP_CODE" != "200" ]; then

        echo
        echo -e "${RED}Error accediendo al repositorio GitHub.${RESET}"

        return
    fi

    # =====================================================
    # LISTAR ARCHIVOS .SH
    # =====================================================

    mapfile -t FILES < <(
        jq -r '.[] | select(.name | endswith(".sh")) | .name' /tmp/github_scripts.json
    )

    # =====================================================
    # VALIDAR ARCHIVOS
    # =====================================================

    if [ ${#FILES[@]} -eq 0 ]; then

        echo
        echo -e "${RED}No se encontraron scripts .sh${RESET}"

        return
    fi

    # =====================================================
    # MENU
    # =====================================================

    while true; do

        clear

        echo -e "${YELLOW}========================================${RESET}"
        echo -e "${YELLOW}      SCRIPTS DISPONIBLES GITHUB        ${RESET}"
        echo -e "${YELLOW}========================================${RESET}"
        echo

        for i in "${!FILES[@]}"; do

            echo -e "${CYAN}[$((i+1))]${RESET} ${GREEN}${FILES[$i]}${RESET}"

        done

        echo
        echo -e "${RED}[0]${RESET} Volver"
        echo

        read -rp "Seleccione script: " opt

        # =================================================
        # VOLVER
        # =================================================

        if [[ "$opt" == "0" ]]; then
            return
        fi

        # =================================================
        # VALIDAR OPCION
        # =================================================

        if ! [[ "$opt" =~ ^[0-9]+$ ]]; then

            echo
            echo -e "${RED}Opción inválida.${RESET}"

            sleep 2
            continue
        fi

        if (( opt < 1 || opt > ${#FILES[@]} )); then

            echo
            echo -e "${RED}Número fuera de rango.${RESET}"

            sleep 2
            continue
        fi

        FILE="${FILES[$((opt-1))]}"

        echo
        echo -e "${GREEN}✔ Script seleccionado:${RESET} ${YELLOW}$FILE${RESET}"

        break

    done

    # =====================================================
    # URL RAW GITHUB
    # =====================================================

    RAW_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH/$GITHUB_PATH/$FILE"

    # =====================================================
    # SCRIPT ACTUAL
    # =====================================================

    CURRENT_SCRIPT="$(realpath "$0")"

    SCRIPT_DIR="$(dirname "$CURRENT_SCRIPT")"

    # =====================================================
    # NUEVO NOMBRE
    # =====================================================

    NEW_SCRIPT_PATH="$SCRIPT_DIR/$FILE"

    TMP_FILE="/tmp/$FILE"

    echo
    echo -e "${CYAN}Descargando script...${RESET}"

    # =====================================================
    # DESCARGAR SCRIPT
    # =====================================================

    if ! wget -q -O "$TMP_FILE" "$RAW_URL"; then

        echo
        echo -e "${RED}Error descargando script.${RESET}"

        return
    fi

    # =====================================================
    # VALIDAR SCRIPT
    # =====================================================

    if ! grep -q "#!/bin/bash" "$TMP_FILE"; then

        echo
        echo -e "${RED}Archivo descargado inválido.${RESET}"

        rm -f "$TMP_FILE"

        return
    fi

    # =====================================================
    # BACKUP
    # =====================================================

    BACKUP_FILE="${CURRENT_SCRIPT}.bak.$(date +%F-%H%M%S)"

    cp "$CURRENT_SCRIPT" "$BACKUP_FILE"

    echo
    echo -e "${GREEN}✔ Backup creado:${RESET}"
    echo -e "${YELLOW}$BACKUP_FILE${RESET}"

    # =====================================================
    # REEMPLAZAR SCRIPT
    # =====================================================

    mv "$TMP_FILE" "$NEW_SCRIPT_PATH"

    chmod +x "$NEW_SCRIPT_PATH"

    echo
    echo -e "${GREEN}✔ Script actualizado correctamente${RESET}"

    echo
    echo -e "${CYAN}Nuevo script:${RESET}"
    echo -e "${GREEN}$NEW_SCRIPT_PATH${RESET}"

    sleep 2

    echo
    echo -e "${YELLOW}Reiniciando script...${RESET}"

    sleep 2

    exec "$NEW_SCRIPT_PATH"
}
# =========================================================
# MENU
# =========================================================
while true; do

clear

echo
echo -e "${CYAN}=============================================================${RESET}"
echo -e "${CYAN} INSTALADOR DE NEXTCLOUD PRO v8.0 Descargar Scripts GitHub   ${RESET}"
echo -e "${CYAN}=============================================================${RESET}"
echo

echo -e "${YELLOW}1)${RESET}  ${CYAN}Instalar Nextcloud Full Verciones / Restaura Archidos de (nextcloud-data)"
echo -e "${YELLOW}2)${RESET}  ${WHITE}Instalar Dependencias ${CYAN}(Apache/MySQL/PHP/wget/Cron)${RESET}"
echo -e "${YELLOW}3)${RESET}  ${WHITE}Actualizar Nextcloud ${CYAN}(updater.phar)${RESET}"
echo -e "${YELLOW}4)${RESET}  ${YELLOW}Menu${RESET} ${CYAN}Mantenimiento Reparar/Restaurar/Configurar Nextcloud OCC${RESET}"
echo -e "${YELLOW}5)${RESET}  ${YELLOW}Menu${RESET} ${WHITE}Configuración Apache / Vhost / config.php${RESET}"
echo -e "${YELLOW}6)${RESET}  ${YELLOW}Menu${RESET} ${WHITE}Office DocumentServer / Collabora${RESET}"
echo -e "${YELLOW}7)${RESET}  ${YELLOW}Menu${RESET} ${WHITE}Respaldar / Restaurar / Crear / Borrar Base de Datos${RESET}"
echo -e "${YELLOW}8)${RESET}  ${WHITE}Crear Base de Datos${RESET}"
echo -e "${YELLOW}9)${RESET}  ${CYAN}Desinstalar${RESET} ${WHITE}Nextcloud Completamente${RESET}"
echo -e "${YELLOW}10)${RESET} ${CYAN}Estado Servicios Nextcloud${RESET}"
echo -e "${YELLOW}↓"
echo -e "${YELLOW}11)${RESET} ${YELLOW} Descargar Script desde GITHUB${RESET}"
echo
echo -e "${CYAN}0)${RESET}  ${CYAN}SALIR${RESET}"
echo

echo

read -p "Opción: " op

case $op in

1) install_nextcloud ;;
2) install_dependencies ;;
3) update_nextcloud ;;
4) menu_nextcloud_occ ;;
5) menu_config_nextcloud ;;
6) menu_office_app ;;
7) menu_mysql_backup ;;
8) setup_database ;;
9) uninstall_nextcloud ;;
10) status_services ;;
11) update_script ;;
0) exit ;;

*)
echo "Inválido"
sleep 1
;;

esac

done