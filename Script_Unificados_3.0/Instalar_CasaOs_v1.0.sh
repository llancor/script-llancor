#!/bin/bash

# =========================================================
# CASAOS MANAGER
# Debian / Ubuntu
# =========================================================

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
echo "                 CASAOS MANAGER"
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
