#!/bin/bash

CONFIG="/etc/odoo/odoo.conf"
BACKUP_DIR="/opt/odoo/backups"
ADDONS_DIR="/opt/odoo/custom-addons"

# ===== COLORES =====
RED="\e[1;31m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
BLUE="\e[1;34m"
CYAN="\e[1;36m"
WHITE="\e[1;37m"
RESET="\e[0m"

clear; mkdir -p $BACKUP_DIR $ADDONS_DIR

# ===== BASE =====

pause(){ read -p "ENTER para continuar..."; }

backup_config(){
 cp $CONFIG $BACKUP_DIR/odoo.conf.$(date +%F-%H%M%S)
 echo -e "${BLUE}Backup config creado${RESET}"
}

restart(){
 systemctl restart postgresql
 systemctl restart odoo
 echo -e "${GREEN}Servicios reiniciados${RESET}"
}

ask_restart(){
 read -p "¿Reiniciar ahora? (s/n): " r
 [[ $r =~ [sS] ]] && restart
}

# ===== CONFIG =====
edit_config() {
    check_config

    echo -e "${CYAN}Abriendo configuración de Odoo...${RESET}"
    sleep 1

    nano "$CONFIG"

    echo ""
    echo -e "${YELLOW}Archivo cerrado${RESET}"

    ask_restart
}

fix_db(){
 backup_config
 sed -i "s/^db_host.*/db_host = False/" $CONFIG
 sed -i "s/^db_port.*/db_port = False/" $CONFIG
 sed -i "s/^db_password.*/db_password = False/" $CONFIG
 sed -i "s/^db_name.*/db_name = False/" $CONFIG
 echo -e "${GREEN}DB corregida${RESET}"
 ask_restart
}

master_pass(){
 backup_config
 read -p "Nueva master password: " p
 sed -i "s|^admin_passwd.*|admin_passwd = $p|" $CONFIG
 echo -e "${GREEN}Password actualizada${RESET}"
 ask_restart
}

toggle_db(){
 backup_config
 if grep -q "list_db = True" $CONFIG; then
   sed -i "s/list_db = True/list_db = False/" $CONFIG
   echo -e "${YELLOW}Gestor oculto${RESET}"
 else
   sed -i "s/list_db = False/list_db = True/" $CONFIG
   echo -e "${GREEN}Gestor visible${RESET}"
 fi
 ask_restart
}
# ===== check CONFIG =====
check_config() {
    if [ ! -f "$CONFIG" ]; then
        echo -e "${RED}❌ No se encontró $CONFIG${RESET}"
        exit 1
    fi
}
# ===== ADDONS =====
config_addons() {
    check_config

    ADDONS_DIR="/opt/odoo/custom-addons"
    DEFAULT="/usr/lib/python3/dist-packages/odoo/addons"

    echo -e "${YELLOW}Configurando addons_path correctamente...${RESET}"

    # Crear carpeta si no existe
    mkdir -p "$ADDONS_DIR"

    # Permisos
    chown -R odoo:odoo "$ADDONS_DIR"
    chmod -R 755 "$ADDONS_DIR"

    # Obtener addons_path actual (si existe)
    CURRENT=$(grep "^addons_path" "$CONFIG" | cut -d "=" -f2)

    # Limpiar espacios
    CURRENT=$(echo $CURRENT | tr -d ' ')

    # Construir nuevo addons_path sin duplicados
    NEW_PATH="$DEFAULT,$ADDONS_DIR"

    # Si ya tenía otros paths, mantenerlos
    if [[ ! -z "$CURRENT" ]]; then
        for path in $(echo $CURRENT | tr ',' ' '); do
            if [[ "$path" != "$DEFAULT" && "$path" != "$ADDONS_DIR" ]]; then
                NEW_PATH="$NEW_PATH,$path"
            fi
        done
    fi

    # Aplicar cambio
    sed -i "s|^addons_path.*|addons_path = $NEW_PATH|" "$CONFIG"

    echo -e "${GREEN}addons_path corregido:${RESET}"
    echo -e "${CYAN}$NEW_PATH${RESET}"

    # ===== DETECTAR ERROR COMÚN =====
    echo -e "${BLUE}Verificando estructura de addons...${RESET}"

    for dir in "$ADDONS_DIR"/*; do
        if [ -d "$dir" ]; then
            SUB=$(find "$dir" -maxdepth 1 -type d | wc -l)

            # Si hay subcarpeta duplicada tipo modulo/modulo
            if [ $SUB -eq 2 ]; then
                INNER=$(find "$dir" -mindepth 1 -maxdepth 1 -type d)
                if [ -f "$INNER/__manifest__.py" ]; then
                    echo -e "${YELLOW}Corrigiendo estructura: $(basename $dir)${RESET}"
                    mv "$INNER"/* "$dir"/
                    rmdir "$INNER"
                fi
            fi
        fi
    done

    echo -e "${GREEN}Estructura de addons verificada${RESET}"

    ask_restart
}

fix_permissions_addons() {
    ADDONS_DIR="/opt/odoo/custom-addons"

    echo -e "${YELLOW}Corrigiendo permisos de addons...${RESET}"

    if [ ! -d "$ADDONS_DIR" ]; then
        echo -e "${RED}La carpeta no existe, creando...${RESET}"
        mkdir -p "$ADDONS_DIR"
    fi

    chown -R odoo:odoo "$ADDONS_DIR"
    chmod -R 755 "$ADDONS_DIR"

    echo -e "${GREEN}Permisos corregidos${RESET}"
}

install_addon(){

 read -p "Ruta del addon (.zip o carpeta): " path

 if [[ $path == *.zip ]]; then
   unzip "$path" -d $ADDONS_DIR
 else
   cp -r "$path" $ADDONS_DIR
 fi

 chown -R odoo:odoo $ADDONS_DIR
fix_permissions_addons
config_addons
 echo -e "${GREEN}Addon instalado${RESET}"
 ask_restart
}

list_addons(){
 echo -e "${CYAN}Addons:${RESET}"
 ls $ADDONS_DIR
}

# ===== BASE DE DATOS =====

backup_db(){
 read -p "Nombre de la base: " db
 sudo -u postgres pg_dump $db > $BACKUP_DIR/$db.sql
 echo -e "${GREEN}Backup creado${RESET}"
}

restore_db(){
 read -p "Archivo .sql: " file
 read -p "Nombre nueva DB: " db

 sudo -u postgres createdb $db
 sudo -u postgres psql $db < $file

 echo -e "${GREEN}Base restaurada${RESET}"
}

list_db(){
 sudo -u postgres psql -l
}

# ===== DIAGNÓSTICO =====

status(){
 echo -e "${BLUE}Estado servicios:${RESET}"
 systemctl is-active odoo && echo "Odoo OK" || echo "Odoo ERROR"
 systemctl is-active postgresql && echo "PostgreSQL OK" || echo "PostgreSQL ERROR"
}

logs(){
 journalctl -u odoo -n 20
}

url(){
 IP=$(hostname -I | awk '{print $1}')
 echo -e "${CYAN}http://$IP:8069${RESET}"
}

# ===== MENU =====

while true; do
 clear
 echo -e "${CYAN}=========== ODOO NIVEL DIOS ===========${RESET}"
 echo ""

 status
 echo ""

 echo -e "${YELLOW}1)${RESET} Arreglar DB"
 echo -e "${YELLOW}2)${RESET} Cambiar Master Password"
 echo -e "${YELLOW}3)${RESET} Mostrar/Ocultar DB web"
 echo -e "${YELLOW}4)${RESET} Reiniciar servicios"
 echo -e "${YELLOW}5)${RESET} Instalar addon"
 echo -e "${YELLOW}6)${RESET} Listar addons"
 echo -e "${YELLOW}7)${RESET} Backup DB"
 echo -e "${YELLOW}8)${RESET} Restaurar DB"
 echo -e "${YELLOW}9)${RESET} Listar bases"
 echo -e "${YELLOW}10)${RESET} Ver logs"
 echo -e "${YELLOW}11)${RESET} Mostrar URL"
 echo -e "${YELLOW}12)${RESET} Editar odoo.conf"
 echo -e "${YELLOW}13)${RESET} Configurar addons /ruta en odoo.conf"
 echo -e "${YELLOW}14)${RESET} Corregir permisos de addons"
 echo -e "${YELLOW}0)${RESET} Salir"

 echo ""
 read -p "Opción: " op

 case $op in
 1) fix_db ;;
 2) master_pass ;;
 3) toggle_db ;;
 4) restart ;;
 5) install_addon ;;
 6) list_addons ;;
 7) backup_db ;;
 8) restore_db ;;
 9) list_db ;;
 10) logs ;;
 11) url ;;
 12) edit_config ;;
 13) config_addons ;;
 14) fix_permissions_addons ;;
 0) exit ;;
 *) echo "Error" ;;
 esac

 pause
done
