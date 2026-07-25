#!/bin/bash

#############################################################
#                                                           #
#              ORANGEHRM MANAGER v2.0                       #
#                                                           #
# Administrador multi-instalación OrangeHRM                 #
# Debian 12 + Docker Compose                                #
#                                                           #
#############################################################

set -euo pipefail


#############################################################
# VERSION
#############################################################

VERSION="2.0"


#############################################################
# RUTAS DEL SISTEMA
#############################################################

BASE_DIR="/opt/orangehrm"

INSTANCES_DIR="$BASE_DIR/instances"

BACKUP_DIR="$BASE_DIR/backups"

LOG_DIR="$BASE_DIR/logs"

TMP_DIR="$BASE_DIR/tmp"

DB_FILE="$BASE_DIR/instances.db"

LOG_FILE="$LOG_DIR/orangehrm-manager.log"


#############################################################
# COLORES
#############################################################

RESET="\e[0m"

BOLD="\e[1m"

RED="\e[31m"

GREEN="\e[32m"

YELLOW="\e[33m"

BLUE="\e[34m"

MAGENTA="\e[35m"

CYAN="\e[36m"

WHITE="\e[97m"


#############################################################
# CREAR ESTRUCTURA
#############################################################

crear_estructura(){

mkdir -p "$BASE_DIR"

mkdir -p "$INSTANCES_DIR"

mkdir -p "$BACKUP_DIR"

mkdir -p "$LOG_DIR"

mkdir -p "$TMP_DIR"


if [ ! -f "$DB_FILE" ]; then

touch "$DB_FILE"

fi


if [ ! -f "$LOG_FILE" ]; then

touch "$LOG_FILE"

fi


}


#############################################################
# LOG DEL SISTEMA
#############################################################

log(){

MENSAJE="$1"

echo "$(date '+%Y-%m-%d %H:%M:%S') | $MENSAJE" >> "$LOG_FILE"

}


#############################################################
# MENSAJES
#############################################################

mensaje_ok(){

echo -e "${GREEN}✔${RESET} $1"

log "OK - $1"

}


mensaje_error(){

echo -e "${RED}✘${RESET} $1"

log "ERROR - $1"

}


mensaje_info(){

echo -e "${CYAN}➜${RESET} $1"

log "INFO - $1"

}


mensaje_warn(){

echo -e "${YELLOW}⚠${RESET} $1"

log "WARN - $1"

}



#############################################################
# PAUSA
#############################################################

pausa(){

echo

read -rp "Presione ENTER para continuar..."

}



#############################################################
# LIMPIAR PANTALLA
#############################################################

limpiar(){

clear

}



#############################################################
# BANNER
#############################################################

banner(){

clear


echo -e "${CYAN}"

cat <<'EOF'


 ██████╗ ██████╗  █████╗ ███╗   ██╗ ██████╗ ███████╗
██╔═══██╗██╔══██╗██╔══██╗████╗  ██║██╔════╝ ██╔════╝
██║   ██║██████╔╝███████║██╔██╗ ██║██║  ███╗█████╗
██║   ██║██╔══██╗██╔══██║██║╚██╗██║██║   ██║██╔══╝
╚██████╔╝██║  ██║██║  ██║██║ ╚████║╚██████╔╝███████╗
 ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝


              ORANGEHRM MANAGER v2.0


EOF


echo -e "${RESET}"

echo -e "${GREEN}Sistema:${RESET} Debian 12"

echo -e "${GREEN}Ruta:${RESET} $BASE_DIR"

echo

}



#############################################################
# COMPROBAR ROOT
#############################################################

comprobar_root(){

if [ "$EUID" -ne 0 ]; then

mensaje_error "Ejecute el script como ROOT"

exit 1

fi

}



#############################################################
# INICIALIZAR SISTEMA
#############################################################

inicializar(){

crear_estructura

comprobar_root

banner

mensaje_ok "Sistema inicializado"

}
#############################################################
# VERIFICAR DEBIAN 12
#############################################################

verificar_debian(){

if ! grep -q "Debian" /etc/os-release; then

mensaje_error "El sistema no es Debian"

exit 1

fi


VERSION_DEBIAN=$(grep VERSION_ID /etc/os-release | cut -d '"' -f2)


if [ "$VERSION_DEBIAN" != "12" ]; then

mensaje_warn "Se recomienda Debian 12"

fi


mensaje_ok "Sistema Debian detectado"

}



#############################################################
# VERIFICAR INTERNET
#############################################################

verificar_internet(){

mensaje_info "Comprobando conexión a Internet..."


if ping -c 2 8.8.8.8 >/dev/null 2>&1; then

mensaje_ok "Internet disponible"

else

mensaje_error "No existe conexión a Internet"

exit 1

fi


}



#############################################################
# VERIFICAR MEMORIA RAM
#############################################################

verificar_ram(){

RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')


if [ "$RAM_TOTAL" -lt 2048 ]; then

mensaje_warn "RAM inferior a 2GB ($RAM_TOTAL MB)"

else

mensaje_ok "RAM correcta: $RAM_TOTAL MB"

fi


}



#############################################################
# VERIFICAR ESPACIO DISCO
#############################################################

verificar_disco(){

ESPACIO=$(df / | awk 'NR==2 {print $4}')


ESPACIO_GB=$((ESPACIO/1024/1024))


if [ "$ESPACIO_GB" -lt 10 ]; then

mensaje_warn "Menos de 10GB disponibles"

else

mensaje_ok "Espacio disponible: ${ESPACIO_GB}GB"

fi


}



#############################################################
# VERIFICAR ARQUITECTURA
#############################################################

verificar_arquitectura(){

ARQ=$(uname -m)


case $ARQ in

x86_64)

mensaje_ok "Arquitectura AMD64"

;;


aarch64)

mensaje_ok "Arquitectura ARM64"

;;


*)

mensaje_warn "Arquitectura no probada: $ARQ"

;;

esac


}



#############################################################
# COMPROBAR DOCKER
#############################################################

docker_instalado(){


if command -v docker >/dev/null 2>&1; then

return 0

else

return 1

fi


}



#############################################################
# COMPROBAR COMPOSE
#############################################################

compose_instalado(){


if docker compose version >/dev/null 2>&1; then

return 0

else

return 1

fi


}



#############################################################
# INSTALAR DEPENDENCIAS BASE
#############################################################

#############################################################
# INSTALAR DEPENDENCIAS BASE
#############################################################

instalar_dependencias_base(){

mensaje_info "Actualizando repositorios..."

apt update


mensaje_info "Instalando paquetes necesarios..."


apt install -y \
curl \
wget \
nano \
git \
unzip \
tar \
openssl \
ca-certificates \
gnupg \
lsb-release \
apt-transport-https \
software-properties-common \
net-tools \
lsof


mensaje_ok "Dependencias instaladas"

}

#############################################################
# INSTALAR DOCKER
#############################################################

instalar_docker(){

if docker_instalado; then

    mensaje_ok "Docker ya está instalado"

else

    mensaje_info "Instalando Docker..."

    curl -fsSL https://get.docker.com -o get-docker.sh

    sh get-docker.sh

    rm -f get-docker.sh

    systemctl enable docker

    systemctl start docker

    mensaje_ok "Docker instalado"

fi

}



#############################################################
# INSTALAR DOCKER COMPOSE
#############################################################

instalar_compose(){


if compose_instalado; then


mensaje_ok "Docker Compose disponible"


else


mensaje_info "Instalando Docker Compose..."


mkdir -p /usr/local/lib/docker/cli-plugins


curl -SL \
https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m) \
-o /usr/local/lib/docker/cli-plugins/docker-compose



chmod +x /usr/local/lib/docker/cli-plugins/docker-compose



mensaje_ok "Docker Compose instalado"



fi



}



#############################################################
# PREPARAR SERVIDOR DOCKER
#############################################################

preparar_servidor(){


banner


mensaje_info "Preparando servidor..."


verificar_debian

verificar_internet

verificar_ram

verificar_disco

verificar_arquitectura


instalar_dependencias_base

instalar_docker

instalar_compose


mensaje_ok "Servidor preparado correctamente"


pausa


}
#############################################################
# BASE DE DATOS DE INSTANCIAS
#############################################################

# Formato:
# nombre|puerto|ruta|contenedor|estado


crear_db_instancias(){

if [ ! -f "$DB_FILE" ]; then

touch "$DB_FILE"

fi

}



#############################################################
# VALIDAR NOMBRE INSTANCIA
#############################################################

validar_nombre(){

NOMBRE="$1"


if [[ ! "$NOMBRE" =~ ^[a-zA-Z0-9_-]+$ ]]; then

return 1

fi


return 0

}



#############################################################
# COMPROBAR SI EXISTE INSTANCIA
#############################################################

existe_instancia(){

NOMBRE="$1"


if grep -q "^$NOMBRE|" "$DB_FILE"; then

return 0

else

return 1

fi


}



#############################################################
# VALIDAR PUERTO
#############################################################

puerto_disponible(){

PUERTO="$1"


if lsof -i :"$PUERTO" >/dev/null 2>&1; then

return 1

else

return 0

fi


}



#############################################################
# BUSCAR PUERTO LIBRE
#############################################################

buscar_puerto_libre(){


PUERTO=8080


while ! puerto_disponible "$PUERTO"

do

((PUERTO++))

done


echo "$PUERTO"


}



#############################################################
# REGISTRAR INSTANCIA
#############################################################

registrar_instancia(){

NOMBRE="$1"

PUERTO="$2"

RUTA="$3"

CONTENEDOR="$4"

ESTADO="$5"



echo "$NOMBRE|$PUERTO|$RUTA|$CONTENEDOR|$ESTADO" >> "$DB_FILE"



log "Instancia registrada: $NOMBRE"



}



#############################################################
# ELIMINAR REGISTRO
#############################################################

eliminar_registro(){


NOMBRE="$1"


grep -v "^$NOMBRE|" "$DB_FILE" > "$DB_FILE.tmp"


mv "$DB_FILE.tmp" "$DB_FILE"


log "Registro eliminado: $NOMBRE"



}



#############################################################
# LISTAR INSTANCIAS
#############################################################

listar_instancias(){


banner


echo "================================================"

echo "             INSTANCIAS ORANGEHRM"

echo "================================================"

echo


if [ ! -s "$DB_FILE" ]; then


mensaje_warn "No existen instancias creadas"


pausa

return


fi



NUM=1


while IFS="|" read -r NOMBRE PUERTO RUTA CONTENEDOR ESTADO

do


echo -e "${GREEN}$NUM)${RESET} $NOMBRE"

echo "   Puerto     : $PUERTO"

echo "   Ruta       : $RUTA"

echo "   Contenedor : $CONTENEDOR"

echo "   Estado     : $ESTADO"

echo


((NUM++))


done < "$DB_FILE"


pausa


}



#############################################################
# OBTENER DATOS INSTANCIA
#############################################################

obtener_instancia(){


NOMBRE="$1"



if ! existe_instancia "$NOMBRE"; then


mensaje_error "Instancia no encontrada"

return 1


fi



grep "^$NOMBRE|" "$DB_FILE"



}


#############################################################
# PARTE 2 - CREACION DE INSTANCIAS ORANGEHRM
#############################################################


#############################################################
# GENERAR PASSWORD SEGURO
#############################################################

generar_password(){

openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c16

}



#############################################################
# CREAR ESTRUCTURA INSTANCIA
#############################################################

crear_directorio_instancia(){

NOMBRE="$1"


RUTA="$INSTANCES_DIR/$NOMBRE"


mkdir -p "$RUTA"

mkdir -p "$RUTA/database"

mkdir -p "$RUTA/orangehrm"



}



#############################################################
# CREAR ARCHIVO ENV
#############################################################

crear_env_instancia(){

echo "DEBUG crear_env_instancia argumentos:"
echo "Cantidad: $#"
echo "Datos: $@"

RUTA="${1:-}"
NOMBRE="${2:-}"
DB_PASS="${3:-}"
ROOT_PASS="${4:-}"



cat > "$RUTA/.env" <<EOF

# OrangeHRM $NOMBRE

MYSQL_ROOT_PASSWORD=$ROOT_PASS

MYSQL_DATABASE=orangehrm

MYSQL_USER=orangehrm

MYSQL_PASSWORD=$DB_PASS


EOF



}



#############################################################
# CREAR DOCKER COMPOSE
#############################################################

crear_compose_instancia(){


RUTA="$1"

NOMBRE="$2"

PUERTO="$3"



cat > "$RUTA/docker-compose.yml" <<EOF

services:


  database:


    image: mariadb:10.11


    container_name: ${NOMBRE}_db


    restart: unless-stopped


    env_file:

      - .env


    volumes:


      - ./database:/var/lib/mysql



  orangehrm:


    image: orangehrm/orangehrm:latest


    container_name: ${NOMBRE}


    restart: unless-stopped


    depends_on:


      - database



    ports:


      - "${PUERTO}:80"



    environment:


      ORANGEHRM_DATABASE_HOST: database


      ORANGEHRM_DATABASE_PORT: 3306


      ORANGEHRM_DATABASE_NAME: orangehrm


      ORANGEHRM_DATABASE_USER: orangehrm


      ORANGEHRM_DATABASE_PASSWORD: \${MYSQL_PASSWORD}

EOF

}



#############################################################
# LEVANTAR INSTANCIA
#############################################################

levantar_instancia(){


RUTA="$1"


cd "$RUTA"


mensaje_info "Descargando imágenes Docker..."


docker compose pull



mensaje_info "Iniciando contenedores..."


docker compose up -d



mensaje_ok "Contenedores iniciados"



}



#############################################################
# CREAR NUEVA INSTANCIA
#############################################################

crear_instancia(){


banner


echo "================================"

echo " CREAR NUEVA INSTANCIA"

echo "================================"

echo



read -rp "Nombre de instancia: " NOMBRE



if [ -z "$NOMBRE" ]; then


mensaje_error "Nombre vacío"


pausa

return


fi



if ! validar_nombre "$NOMBRE"; then


mensaje_error "Nombre inválido. Use letras, números, - o _"


pausa

return


fi



if existe_instancia "$NOMBRE"; then


mensaje_error "La instancia ya existe"


pausa

return


fi




PUERTO=$(buscar_puerto_libre)



echo

echo "Puerto sugerido: $PUERTO"


read -rp "Puerto web [$PUERTO]: " PUERTO_USER



if [ -n "$PUERTO_USER" ]; then

PUERTO="$PUERTO_USER"

fi




if ! puerto_disponible "$PUERTO"; then


mensaje_error "El puerto está ocupado"


pausa

return


fi




DB_PASSWORD=$(generar_password)


ROOT_PASSWORD=$(generar_password)



RUTA="$INSTANCES_DIR/$NOMBRE"



CONTENEDOR="$NOMBRE"



mensaje_info "Creando estructura..."


crear_directorio_instancia "$NOMBRE"



mensaje_info "Creando configuración..."


crear_env_instancia \
"$RUTA" \
"$NOMBRE" \
"$DB_PASSWORD" \
"$ROOT_PASSWORD"



crear_compose_instancia \
"$RUTA" \
"$NOMBRE" \
"$PUERTO"




mensaje_info "Levantando OrangeHRM..."



levantar_instancia "$RUTA"




registrar_instancia \
"$NOMBRE" \
"$PUERTO" \
"$RUTA" \
"$CONTENEDOR" \
"running"




echo


mensaje_ok "Instancia creada correctamente"



echo

echo "Acceso web:"

echo

echo "http://IP_SERVIDOR:$PUERTO"

echo



echo "Datos MariaDB:"

echo

echo "Base: orangehrm"

echo "Usuario: orangehrm"

echo "Password: $DB_PASSWORD"

echo



pausa



}
#############################################################
# PARTE 4 - AJUSTES Y MANTENIMIENTO
#############################################################


#############################################################
# MOSTRAR CONFIGURACION BASE DATOS
#############################################################

ver_base_datos(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"


clear


echo "================================"

echo " DATOS BASE DE DATOS"

echo "================================"

echo


ENV_FILE="$RUTA/.env"



if [ -f "$ENV_FILE" ]; then


grep -v "^#" "$ENV_FILE"


else


mensaje_error "No existe archivo .env"


fi


echo


echo "Host MariaDB: database"

echo "Puerto: 3306"

echo "Contenedor BD: ${NOMBRE}_db"


pausa


}



#############################################################
# CAMBIAR PUERTO
#############################################################

cambiar_puerto(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"



echo

echo "Puerto actual: $PUERTO"


read -rp "Nuevo puerto: " NUEVO_PUERTO



if [ -z "$NUEVO_PUERTO" ]; then


mensaje_error "Puerto vacío"


pausa

return


fi



if ! puerto_disponible "$NUEVO_PUERTO"; then


mensaje_error "Puerto ocupado"


pausa

return


fi



COMPOSE="$RUTA/docker-compose.yml"



sed -i \
"s/- \"${PUERTO}:80\"/- \"${NUEVO_PUERTO}:80\"/" \
"$COMPOSE"



sed -i \
"s/^$NOMBRE|$PUERTO|/$NOMBRE|$NUEVO_PUERTO|/" \
"$DB_FILE"



cd "$RUTA"



docker compose down


docker compose up -d



mensaje_ok "Puerto cambiado a $NUEVO_PUERTO"


pausa


}



#############################################################
# ACTUALIZAR ORANGEHRM
#############################################################

actualizar_orangehrm(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"



mensaje_info "Actualizando $NOMBRE"



cd "$RUTA"



docker compose pull



docker compose up -d



mensaje_ok "Actualización completada"



pausa


}



#############################################################
# BACKUP COMPLETO INSTANCIA
#############################################################

backup_instancia(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"



FECHA=$(date +"%Y-%m-%d_%H-%M")



DESTINO="$BACKUP_DIR/${NOMBRE}_$FECHA.tar.gz"



mensaje_info "Creando backup..."



tar -czf "$DESTINO" \
-C "$INSTANCES_DIR" \
"$NOMBRE"



mensaje_ok "Backup creado:"

echo

echo "$DESTINO"


pausa


}



#############################################################
# BACKUP BASE DATOS
#############################################################

backup_database(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"



FECHA=$(date +"%Y-%m-%d_%H-%M")



BACKUP="$BACKUP_DIR/${NOMBRE}_db_$FECHA.sql"



ENV_FILE="$RUTA/.env"



PASSWORD=$(grep MYSQL_PASSWORD "$ENV_FILE" | cut -d= -f2)



docker exec "${NOMBRE}_db" \
mysqldump \
-uorangehrm \
-p"$PASSWORD" \
orangehrm > "$BACKUP"



mensaje_ok "Backup BD creado"

echo

echo "$BACKUP"



pausa


}



#############################################################
# RESTAURAR BASE DATOS
#############################################################

restaurar_database(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"



echo

ls -lh "$BACKUP_DIR"



echo

read -rp "Archivo SQL: " ARCHIVO



if [ ! -f "$ARCHIVO" ]; then


mensaje_error "Archivo no existe"


pausa

return


fi



ENV_FILE="$RUTA/.env"


PASSWORD=$(grep MYSQL_PASSWORD "$ENV_FILE" | cut -d= -f2)



cat "$ARCHIVO" | docker exec -i "${NOMBRE}_db" \
mysql \
-uorangehrm \
-p"$PASSWORD" \
orangehrm



mensaje_ok "Base restaurada"



pausa


}



#############################################################
# CAMBIAR PASSWORD BD
#############################################################

cambiar_password_bd(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"



NUEVA=$(generar_password)



sed -i \
"s/^MYSQL_PASSWORD=.*/MYSQL_PASSWORD=$NUEVA/" \
"$RUTA/.env"



mensaje_warn "Debe reiniciar la instancia"



cd "$RUTA"


docker compose restart



mensaje_ok "Password actualizado"




pausa


}



#############################################################
# MENU AJUSTES
#############################################################

ajustes_orangehrm(){


while true

do


banner


echo "================================"

echo " AJUSTES ORANGEHRM"

echo "================================"

echo


echo "1) Ver datos Base de Datos"

echo "2) Cambiar puerto"

echo "3) Actualizar OrangeHRM"

echo "4) Backup completo"

echo "5) Backup MariaDB"

echo "6) Restaurar MariaDB"

echo "7) Cambiar contraseña BD"



echo

echo "0) Volver"

echo



read -rp "Seleccione: " OPCION



case $OPCION in


1)

ver_base_datos

;;


2)

cambiar_puerto

;;


3)

actualizar_orangehrm

;;


4)

backup_instancia

;;


5)

backup_database

;;


6)

restaurar_database

;;


7)

cambiar_password_bd

;;


0)

return

;;


*)

mensaje_error "Opción inválida"

;;

esac



done


}

#############################################################
# PARTE 4 - AJUSTES Y MANTENIMIENTO
#############################################################


#############################################################
# MOSTRAR CONFIGURACION BASE DATOS
#############################################################

ver_base_datos(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"


clear


echo "================================"

echo " DATOS BASE DE DATOS"

echo "================================"

echo


ENV_FILE="$RUTA/.env"



if [ -f "$ENV_FILE" ]; then


grep -v "^#" "$ENV_FILE"


else


mensaje_error "No existe archivo .env"


fi


echo


echo "Host MariaDB: database"

echo "Puerto: 3306"

echo "Contenedor BD: ${NOMBRE}_db"


pausa


}



#############################################################
# CAMBIAR PUERTO
#############################################################

cambiar_puerto(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"



echo

echo "Puerto actual: $PUERTO"


read -rp "Nuevo puerto: " NUEVO_PUERTO



if [ -z "$NUEVO_PUERTO" ]; then


mensaje_error "Puerto vacío"


pausa

return


fi



if ! puerto_disponible "$NUEVO_PUERTO"; then


mensaje_error "Puerto ocupado"


pausa

return


fi



COMPOSE="$RUTA/docker-compose.yml"



sed -i \
"s/- \"${PUERTO}:80\"/- \"${NUEVO_PUERTO}:80\"/" \
"$COMPOSE"



sed -i \
"s/^$NOMBRE|$PUERTO|/$NOMBRE|$NUEVO_PUERTO|/" \
"$DB_FILE"



cd "$RUTA"



docker compose down


docker compose up -d



mensaje_ok "Puerto cambiado a $NUEVO_PUERTO"


pausa


}



#############################################################
# ACTUALIZAR ORANGEHRM
#############################################################

actualizar_orangehrm(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"



mensaje_info "Actualizando $NOMBRE"



cd "$RUTA"



docker compose pull



docker compose up -d



mensaje_ok "Actualización completada"



pausa


}



#############################################################
# BACKUP COMPLETO INSTANCIA
#############################################################

backup_instancia(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"



FECHA=$(date +"%Y-%m-%d_%H-%M")



DESTINO="$BACKUP_DIR/${NOMBRE}_$FECHA.tar.gz"



mensaje_info "Creando backup..."



tar -czf "$DESTINO" \
-C "$INSTANCES_DIR" \
"$NOMBRE"



mensaje_ok "Backup creado:"

echo

echo "$DESTINO"


pausa


}



#############################################################
# BACKUP BASE DATOS
#############################################################

backup_database(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"



FECHA=$(date +"%Y-%m-%d_%H-%M")



BACKUP="$BACKUP_DIR/${NOMBRE}_db_$FECHA.sql"



ENV_FILE="$RUTA/.env"



PASSWORD=$(grep MYSQL_PASSWORD "$ENV_FILE" | cut -d= -f2)



docker exec "${NOMBRE}_db" \
mysqldump \
-uorangehrm \
-p"$PASSWORD" \
orangehrm > "$BACKUP"



mensaje_ok "Backup BD creado"

echo

echo "$BACKUP"



pausa


}



#############################################################
# RESTAURAR BASE DATOS
#############################################################

restaurar_database(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"



echo

ls -lh "$BACKUP_DIR"



echo

read -rp "Archivo SQL: " ARCHIVO



if [ ! -f "$ARCHIVO" ]; then


mensaje_error "Archivo no existe"


pausa

return


fi



ENV_FILE="$RUTA/.env"


PASSWORD=$(grep MYSQL_PASSWORD "$ENV_FILE" | cut -d= -f2)



cat "$ARCHIVO" | docker exec -i "${NOMBRE}_db" \
mysql \
-uorangehrm \
-p"$PASSWORD" \
orangehrm



mensaje_ok "Base restaurada"



pausa


}



#############################################################
# CAMBIAR PASSWORD BD
#############################################################

cambiar_password_bd(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"



NUEVA=$(generar_password)



sed -i \
"s/^MYSQL_PASSWORD=.*/MYSQL_PASSWORD=$NUEVA/" \
"$RUTA/.env"



mensaje_warn "Debe reiniciar la instancia"



cd "$RUTA"


docker compose restart



mensaje_ok "Password actualizado"




pausa


}



#############################################################
# MENU AJUSTES
#############################################################

ajustes_orangehrm(){


while true

do


banner


echo "================================"

echo " AJUSTES ORANGEHRM"

echo "================================"

echo


echo "1) Ver datos Base de Datos"

echo "2) Cambiar puerto"

echo "3) Actualizar OrangeHRM"

echo "4) Backup completo"

echo "5) Backup MariaDB"

echo "6) Restaurar MariaDB"

echo "7) Cambiar contraseña BD"



echo

echo "0) Volver"

echo



read -rp "Seleccione: " OPCION



case $OPCION in


1)

ver_base_datos

;;


2)

cambiar_puerto

;;


3)

actualizar_orangehrm

;;


4)

backup_instancia

;;


5)

backup_database

;;


6)

restaurar_database

;;


7)

cambiar_password_bd

;;


0)

return

;;


*)

mensaje_error "Opción inválida"

;;

esac



done


}

#############################################################
# PARTE 5 - SISTEMA FINAL
#############################################################


#############################################################
# DESINSTALAR INSTANCIA
#############################################################

desinstalar_instancia(){

    seleccionar_instancia || return

    cargar_datos_instancia "$INSTANCIA_ACTUAL"

    echo
    mensaje_warn "Se eliminará completamente: $NOMBRE"
    echo

    read -rp "¿Continuar? (s/n): " CONFIRMAR

    if [[ "$CONFIRMAR" != "s" && "$CONFIRMAR" != "S" ]]; then
        mensaje_info "Operación cancelada"
        pausa
        return
    fi

    if [ -d "$RUTA" ]; then
        cd "$RUTA" || return
    else
        mensaje_error "La carpeta de la instancia no existe."
        pausa
        return
    fi

    mensaje_info "Deteniendo contenedores..."
    docker compose down -v || true

    mensaje_info "Eliminando contenedores..."
    docker rm -f "$NOMBRE" 2>/dev/null || true
    docker rm -f "${NOMBRE}_db" 2>/dev/null || true

    mensaje_info "Eliminando archivos..."
    rm -rf "$RUTA" || true

    mensaje_info "Eliminando registro..."
    eliminar_registro "$NOMBRE" || true

    mensaje_ok "Instancia eliminada correctamente."

    pausa

}


#############################################################
# EXPORTAR INSTANCIA
#############################################################

exportar_instancia(){


seleccionar_instancia || return


cargar_datos_instancia "$INSTANCIA_ACTUAL"



FECHA=$(date +"%Y-%m-%d_%H-%M")



ARCHIVO="$BACKUP_DIR/export_${NOMBRE}_${FECHA}.tar.gz"



tar -czf "$ARCHIVO" \
-C "$INSTANCES_DIR" \
"$NOMBRE"



mensaje_ok "Exportación creada"

echo

echo "$ARCHIVO"



pausa


}



#############################################################
# IMPORTAR INSTANCIA
#############################################################

importar_instancia(){


banner


echo

echo "Backups disponibles:"

echo


ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null || true


echo


read -rp "Archivo completo: " ARCHIVO



if [ ! -f "$ARCHIVO" ]; then


mensaje_error "Archivo no encontrado"


pausa

return


fi



tar -xzf "$ARCHIVO" -C "$INSTANCES_DIR"



mensaje_ok "Archivos restaurados"



pausa


}

#############################################################
# SELECCIONAR INSTANCIA
#############################################################

seleccionar_instancia(){

banner

echo "========================================="
echo " SELECCIONAR INSTANCIA"
echo "========================================="
echo

if [ ! -s "$DB_FILE" ]; then

    mensaje_error "No existen instancias registradas"

    pausa

    return 1

fi

NUM=1

while IFS="|" read -r NOMBRE PUERTO RUTA CONTENEDOR ESTADO
do

    echo "$NUM) $NOMBRE (Puerto: $PUERTO - Estado: $ESTADO)"

    NUM=$((NUM+1))

done < "$DB_FILE"

echo

read -rp "Seleccione una instancia: " OPCION

LINEA=$(sed -n "${OPCION}p" "$DB_FILE")

if [ -z "$LINEA" ]; then

    mensaje_error "Selección inválida"

    pausa

    return 1

fi

INSTANCIA_ACTUAL=$(echo "$LINEA" | cut -d'|' -f1)

return 0

}
#############################################################
# CARGAR DATOS INSTANCIA
#############################################################

cargar_datos_instancia(){

NOMBRE="$1"

LINEA=$(grep "^${NOMBRE}|" "$DB_FILE")

if [ -z "$LINEA" ]; then

    mensaje_error "No se encontró la instancia"

    return 1

fi

NOMBRE=$(echo "$LINEA" | cut -d'|' -f1)
PUERTO=$(echo "$LINEA" | cut -d'|' -f2)
RUTA=$(echo "$LINEA" | cut -d'|' -f3)
CONTENEDOR=$(echo "$LINEA" | cut -d'|' -f4)
ESTADO=$(echo "$LINEA" | cut -d'|' -f5)

}
#############################################################
# LIMPIEZA DOCKER
#############################################################

limpieza_docker(){


banner



mensaje_warn "Esta operación eliminará recursos Docker sin uso."



read -rp "Continuar? (s/n): " RESP



if [[ "$RESP" != "s" && "$RESP" != "S" ]]; then

return

fi



docker system prune -af



mensaje_ok "Limpieza completada"



pausa


}



#############################################################
# VERIFICACION FINAL
#############################################################

verificacion_final(){


banner


echo "================================"

echo " VERIFICACION DEL SISTEMA"

echo "================================"

echo



echo "Docker:"

docker --version



echo


echo "Docker Compose:"

docker compose version



echo


echo "Instancias registradas:"



if [ -s "$DB_FILE" ]; then


cat "$DB_FILE"


else


echo "Sin instancias"


fi



echo


pausa



}



#############################################################
# MENU SISTEMA
#############################################################

menu_sistema(){


while true

do


banner


echo "================================"

echo " HERRAMIENTAS DEL SISTEMA"

echo "================================"

echo


echo "1) Desinstalar instancia"

echo "2) Exportar instancia"

echo "3) Importar instancia"

echo "4) Limpieza Docker"

echo "5) Verificación sistema"


echo

echo "0) Volver"


echo


read -rp "Seleccione: " OPCION



case $OPCION in


1)

desinstalar_instancia

;;


2)

exportar_instancia

;;


3)

importar_instancia

;;


4)

limpieza_docker

;;


5)

verificacion_final

;;


0)

return

;;


*)

mensaje_error "Opción inválida"

;;

esac



done


}



#############################################################
# MENU PRINCIPAL FINAL
#############################################################

menu_principal_final(){


while true

do


banner


echo "=========================================="

echo "        ORANGEHRM MANAGER v2.0"

echo "=========================================="

echo


echo -e "${YELLOW}1)${RESET} Preparar servidor Docker"

echo -e "${YELLOW}2)${RESET} Crear instancia OrangeHRM"

echo -e "${YELLOW}3)${RESET} Ver instancias"

echo -e "${YELLOW}4)${RESET} Administrar instancia"

echo -e "${YELLOW}5)${RESET} Ajustes OrangeHRM"

echo -e "${YELLOW}6)${RESET} Datos Base de Datos"

echo -e "${YELLOW}7)${RESET} Cambiar puerto"

echo -e "${YELLOW}8)${RESET} Herramientas del sistema"


echo

echo -e "${RED}0) Salir${RESET}"


echo


read -rp "Seleccione: " OPCION



case $OPCION in


1)

preparar_servidor

;;


2)

crear_instancia

;;


3)

listar_instancias

;;


4)

administrar_instancia

;;


5)

ajustes_orangehrm

;;


6)

ver_base_datos

;;


7)

cambiar_puerto

;;


8)

menu_sistema

;;


0)

mensaje_ok "Finalizando OrangeHRM Manager"

exit 0

;;


*)

mensaje_error "Opción inválida"

;;

esac


done


}
#############################################################
# ADMINISTRAR INSTANCIA
#############################################################

administrar_instancia(){

seleccionar_instancia || return

cargar_datos_instancia "$INSTANCIA_ACTUAL"

while true

do

banner

echo "=========================================="
echo " ADMINISTRAR INSTANCIA"
echo "=========================================="
echo

echo "Instancia : $NOMBRE"
echo "Puerto    : $PUERTO"
echo "Estado    : $ESTADO"
echo

echo "1) Iniciar instancia"
echo "2) Detener instancia"
echo "3) Reiniciar instancia"
echo "4) Ver estado"
echo "5) Ver logs"
echo "6) Abrir consola"
echo
echo "0) Volver"
echo

read -rp "Seleccione: " OPCION

case $OPCION in

1)

mensaje_info "Iniciando instancia..."

cd "$RUTA"

docker compose up -d

mensaje_ok "Instancia iniciada"

pausa

;;

2)

mensaje_info "Deteniendo instancia..."

cd "$RUTA"

docker compose stop

mensaje_ok "Instancia detenida"

pausa

;;

3)

mensaje_info "Reiniciando instancia..."

cd "$RUTA"

docker compose restart

mensaje_ok "Instancia reiniciada"

pausa

;;

4)

banner

echo "=========================================="
echo " ESTADO DE LA INSTANCIA"
echo "=========================================="
echo

docker ps -a --filter "name=$CONTENEDOR"

echo

docker ps -a --filter "name=${CONTENEDOR}_db"

echo

pausa

;;

5)

banner

echo "=========================================="
echo " LOGS DE LA INSTANCIA"
echo "=========================================="
echo

docker logs --tail=100 "$CONTENEDOR"

echo

pausa

;;

6)

mensaje_info "Abriendo consola del contenedor..."

docker exec -it "$CONTENEDOR" bash

;;

0)

return

;;

*)

mensaje_error "Opción inválida"

sleep 2

;;

esac

done

}

#############################################################
# INICIO DEFINITIVO
#############################################################

inicializar

menu_principal_final
