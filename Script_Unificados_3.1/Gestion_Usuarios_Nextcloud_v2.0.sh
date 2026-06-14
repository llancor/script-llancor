#!/bin/bash

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
    echo -e " ${YELLOW}0)${RESET} Salir"

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
      0) clear ; exit 0 ;;

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
# INICIO
# =========================================================

validar_nextcloud
menu_usuarios_nextcloud
