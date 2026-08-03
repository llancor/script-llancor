#!/bin/bash

# =========================================================
# CASAOS MANAGER
# Debian / Ubuntu
# =========================================================
############################################################
# COLORES 
############################################################

RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
BLUE='\e[94m'
MAGENTA='\e[95m'
CYAN='\e[96m'
WHITE='\e[97m'

BOLD='\e[1m'
NC='\e[0m'
APP_NAME="CasaOs"
APP_VERSION="2.0"
############################
# Colores
############################

ROJO="\e[1;31m"
VERDE="\e[1;32m"
AMARILLO="\e[1;33m"
AZUL="\e[1;34m"
MAGENTA="\e[1;35m"
CYAN="\e[1;36m"
BLANCO="\e[1;37m"
NC="\e[0m"

############################
# Header
############################

header() {
clear

echo -e "${CYAN}"
echo "======================================================="
echo "                 CASAOS MANAGER Versión ${APP_VERSION} "
echo "======================================================="
echo -e "${NC}"

if systemctl is-active --quiet casaos 2>/dev/null; then
    ESTADO="${VERDE}INSTALADO${NC}"
else
    ESTADO="${ROJO}NO INSTALADO${NC}"
fi

IP=$(hostname -I | awk '{print $1}')

echo -e "Estado : $ESTADO"
echo -e "Servidor: ${AMARILLO}$IP${NC}"
echo
}

pause(){
echo
read -p "Presione ENTER para continuar..."
}

############################
# Verificar Root
############################

verificar_root(){

if [ "$EUID" -ne 0 ]; then
    echo -e "${ROJO}Debe ejecutar este script como ROOT${NC}"
    exit
fi

}

############################
# Instalar
############################

instalar_casaos(){

header

echo -e "${VERDE}Instalando CasaOS...${NC}"
echo

apt update

apt install -y curl sudo

curl -fsSL https://get.casaos.io | bash

echo

if systemctl is-active --quiet casaos; then

    echo -e "${VERDE}"
    echo "======================================="
    echo " CasaOS instalado correctamente"
    echo "======================================="
    echo -e "${NC}"

    IP=$(hostname -I | awk '{print $1}')

    echo "Acceda desde:"
    echo
    echo "http://$IP"

else

    echo -e "${ROJO}La instalación falló.${NC}"

fi

pause

}

############################
# Desinstalar
############################

desinstalar_casaos(){

header

echo -e "${ROJO}"
echo "ATENCIÓN"
echo "Se eliminará CasaOS."
echo -e "${NC}"

echo
read -p "¿Desea continuar? (s/n): " resp

[[ "$resp" != "s" ]] && return

if command -v casaos-uninstall >/dev/null 2>&1; then

    casaos-uninstall

elif [ -f /usr/bin/casaos-uninstall ]; then

    /usr/bin/casaos-uninstall

else

    curl -fsSL https://get.casaos.io/uninstall | bash

fi

echo
echo -e "${VERDE}Proceso finalizado.${NC}"

pause

}

############################
# Estado
############################

estado(){

header

if systemctl is-active --quiet casaos; then

    echo -e "${VERDE}CasaOS está funcionando.${NC}"

else

    echo -e "${ROJO}CasaOS no está instalado o está detenido.${NC}"

fi

pause

}

############################
# Reiniciar
############################

reiniciar(){

header

systemctl restart casaos

echo -e "${VERDE}Servicio reiniciado.${NC}"

pause

}

############################
# Iniciar
############################

iniciar(){

header

systemctl start casaos

echo -e "${VERDE}Servicio iniciado.${NC}"

pause

}

############################
# Detener
############################

detener(){

header

systemctl stop casaos

echo -e "${VERDE}Servicio detenido.${NC}"

pause

}

############################
# IP
############################

mostrar_ip(){

header

IP=$(hostname -I | awk '{print $1}')

echo -e "${VERDE}"
echo "Acceda desde:"
echo
echo "http://$IP"
echo -e "${NC}"

pause

}
############################################################
# CASAOS PASSWORD MANAGER
############################################################

gestionar_password_casaos() {

    clear

    echo -e "${GREEN}====================================${NC}"
    echo -e "${GREEN}      CASAOS PASSWORD MANAGER${NC}"
    echo -e "${GREEN}====================================${NC}"


    verificar_sqlite_casaos || return


    DB="/var/lib/casaos/db/user.db"


    if [ ! -f "$DB" ]; then

        echo -e "${RED}No se encontró la base de datos CasaOS:${NC}"
        echo "$DB"

        pause
        return

    fi


    while true
    do
		clear
		echo -e "${GREEN}====================================${NC}"
        echo -e "${GREEN}      CASAOS PASSWORD MANAGER${NC}"
        echo -e "${GREEN}====================================${NC}"
        echo
        echo -e "${YELLOW}1)${BLANCO} Ver usuarios CasaOS${NC}"
        echo -e "${YELLOW}2)${BLANCO} Ver estructura base usuarios${NC}"
        echo -e "${YELLOW}3)${BLANCO} Restablecer contraseña${NC}"
        echo -e "${YELLOW}4)${BLANCO} Reiniciar servicios CasaOS${NC}"
        echo -e "${YELLOW}5)${CYAN} Salir${NC}"
        echo


        read -p "Seleccione una opción: " OP


        case $OP in


        ####################################################
        # VER USUARIOS
        ####################################################

        1)

            echo
            echo -e "${GREEN}Usuarios registrados:${NC}"

            sqlite3 "$DB" \
            "SELECT id,username,role,email FROM o_users;"


            echo

            pause

        ;;


        ####################################################
        # ESTRUCTURA BD
        ####################################################

        2)

            echo
            echo -e "${GREEN}Tablas disponibles:${NC}"

            sqlite3 "$DB" ".tables"


            echo
            echo -e "${GREEN}Estructura:${NC}"

            sqlite3 "$DB" ".schema"


            echo

            pause

        ;;


        3)

    echo
    echo -e "${GREEN}Usuarios CasaOS:${NC}"
    echo

    sqlite3 "$DB" \
    "SELECT id,username,role FROM o_users;"


    echo
    echo -e "${YELLOW}Ejemplo: si aparece 1|usuario@gmail.com|admin escriba 1${NC}"
    echo


    read -p "Ingrese ID del usuario: " CASAOS_ID


    EXISTE=$(sqlite3 "$DB" \
    "SELECT username FROM o_users WHERE id=$CASAOS_ID;")


    if [ -z "$EXISTE" ]; then

        echo -e "${RED}Usuario no encontrado.${NC}"
        pause
        continue

    fi


    echo
    echo -e "${GREEN}Usuario seleccionado:${NC} $EXISTE"
    echo


    read -s -p "Nueva contraseña: " PASS
    echo


    HASH=$(echo -n "$PASS" | md5sum | awk '{print $1}')


    sqlite3 "$DB" \
    "UPDATE o_users 
     SET password='$HASH',
     updated_at=datetime('now')
     WHERE id=$CASAOS_ID;"


    if [ $? -eq 0 ]; then

        echo
        echo -e "${GREEN}Contraseña actualizada correctamente.${NC}"

        echo
        echo "Reiniciando servicios CasaOS..."

        systemctl restart casaos-user-service
        systemctl restart casaos-gateway


        echo -e "${GREEN}Listo.${NC}"

    else

        echo -e "${RED}Error actualizando contraseña.${NC}"

    fi


    pause

;;


        ####################################################
        # REINICIAR SERVICIOS
        ####################################################

        4)

            echo
            echo "Reiniciando servicios CasaOS..."


            systemctl restart casaos-user-service
            systemctl restart casaos-gateway
            systemctl restart casaos


            echo -e "${GREEN}Servicios reiniciados.${NC}"


            pause

        ;;


        ####################################################
        # SALIR
        ####################################################

        5)

            break

        ;;


        *)

            echo -e "${RED}Opción inválida.${NC}"

        ;;


        esac

    done

}



############################################################
# VERIFICAR SQLITE
############################################################

verificar_sqlite_casaos() {


    if command -v sqlite3 >/dev/null 2>&1; then

        return 0

    fi


    echo -e "${YELLOW}SQLite3 no está instalado.${NC}"


    if command -v apt >/dev/null 2>&1; then

        apt update
        apt install sqlite3 -y

    else

        echo -e "${RED}No se encontró gestor apt.${NC}"

        return 1

    fi


    if command -v sqlite3 >/dev/null 2>&1; then

        return 0

    else

        echo -e "${RED}No se pudo instalar sqlite3.${NC}"

        return 1

    fi

}
############################
# Menú
############################

menu(){

while true

do

header

echo -e "${AMARILLO}1)${NC} Instalar CasaOS"
echo -e "${AMARILLO}2)${NC} Desinstalar CasaOS"
echo -e "${AMARILLO}3)${NC} Verificar Estado"
echo -e "${AMARILLO}4)${NC} Iniciar Servicio"
echo -e "${AMARILLO}5)${NC} Detener Servicio"
echo -e "${AMARILLO}6)${NC} Reiniciar Servicio"
echo -e "${AMARILLO}7)${NC} Mostrar IP de acceso"
echo -e "${AMARILLO}8)${NC} Gestionar contraseña CasaOS${NC}"
echo -e "${AMARILLO}0)${NC} Salir"

echo
read -p "Seleccione una opción: " op

case $op in

1) instalar_casaos ;;

2) desinstalar_casaos ;;

3) estado ;;

4) iniciar ;;

5) detener ;;

6) reiniciar ;;

7) mostrar_ip ;;

8) gestionar_password_casaos ;;

0) clear; exit ;;

*) echo "Opción inválida"; sleep 2 ;;

esac

done

}

############################
# Inicio
############################

verificar_root

menu
