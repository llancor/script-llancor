#!/bin/bash

# ==========================================================
# Gestor de Scripts GitHub - llancor/script-llancor
# Descarga, actualiza, ejecuta y elimina scripts
# ==========================================================

REPO="llancor/script-llancor"
RUTA="Script_Unificados_3.0"
DESTINO="/root"

mkdir -p "$DESTINO"
# ==========================================================
# COLORES
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'
# ----------------------------------------------------------
# Obtener lista de scripts desde GitHub
# ----------------------------------------------------------
obtener_scripts() {

    mapfile -t URLS < <(
        curl -s "https://api.github.com/repos/${REPO}/contents/${RUTA}" |
        grep '"download_url"' |
        cut -d '"' -f4 |
        grep -Ei '\.(sh|bash)$'
    )

    SCRIPTS=()

    for url in "${URLS[@]}"; do
        SCRIPTS+=("$(basename "$url")")
    done
}

# ----------------------------------------------------------
# Mostrar scripts disponibles en GitHub
# ----------------------------------------------------------
listar_remotos() {

    obtener_scripts

    if [ ${#SCRIPTS[@]} -eq 0 ]; then
        echo
        echo "❌ No se encontraron scripts en GitHub."
        return 1
    fi

    echo
    echo "══════════════════════════════════════"
    echo "      SCRIPTS DISPONIBLES"
    echo "══════════════════════════════════════"

for i in "${!SCRIPTS[@]}"; do
    printf "${YELLOW}[%02d]${NC} ${WHITE}%s${NC}\n" \
    "$((i+1))" "${SCRIPTS[$i]}"
done
}

# ----------------------------------------------------------
# Descargar script
# ----------------------------------------------------------
descargar_script() {

    listar_remotos || return

    read -rp "Seleccione script: " OPCION

    if ! [[ "$OPCION" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ Opción inválida${NC}"
        return
    fi

    IDX=$((OPCION-1))

    if [ -z "${URLS[$IDX]}" ]; then
        echo -e "${RED}❌ Opción fuera de rango${NC}"
        return
    fi

    URL="${URLS[$IDX]}"
    ARCHIVO="${SCRIPTS[$IDX]}"
    RUTA="$DESTINO/$ARCHIVO"

    echo
    echo -e "${CYAN}⬇️ Descargando ${GREEN}$ARCHIVO${NC}..."

    if curl -L --progress-bar -o "$RUTA" "$URL"; then

        chmod +x "$RUTA"

        echo
        echo -e "${GREEN}✅ Descargado correctamente${NC}"
        echo -e "${WHITE}📁 $RUTA${NC}"

        echo
        echo -e "${CYAN}🚀 Ejecutando $ARCHIVO...${NC}"
        echo

        bash "$RUTA"

    else
        echo -e "${RED}❌ Error al descargar${NC}"
    fi
}

ejecutar_script() {

    mapfile -t LOCALES < <(
        find "$DESTINO" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.bash" \) | sort
    )

    if [ ${#LOCALES[@]} -eq 0 ]; then
        echo
        echo -e "${RED}❌ No hay scripts descargados.${NC}"
        return
    fi

    echo
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${CYAN}      SCRIPTS DESCARGADOS${NC}"
    echo -e "${CYAN}══════════════════════════════════════${NC}"

    for i in "${!LOCALES[@]}"; do
        printf "${GREEN}[%02d]${NC} ${CYAN}%s${NC}\n" \
        "$((i+1))" "$(basename "${LOCALES[$i]}")"
    done

    echo
    read -rp "Seleccione script: " OPCION

    if ! [[ "$OPCION" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ Opción inválida${NC}"
        return
    fi

    IDX=$((OPCION-1))

    if [ -z "${LOCALES[$IDX]}" ]; then
        echo -e "${RED}❌ Opción fuera de rango${NC}"
        return
    fi

    echo
    echo -e "${CYAN}🚀 Ejecutando $(basename "${LOCALES[$IDX]}")...${NC}"
    echo

    bash "${LOCALES[$IDX]}"
}

# ----------------------------------------------------------
# Actualizar script
# ----------------------------------------------------------
actualizar_script() {

    listar_remotos || return

    read -rp "Seleccione script a actualizar: " OPCION

    if ! [[ "$OPCION" =~ ^[0-9]+$ ]]; then
        echo "❌ Opción inválida"
        return
    fi

    IDX=$((OPCION-1))

    URL="${URLS[$IDX]}"
    ARCHIVO="${SCRIPTS[$IDX]}"

    echo
    echo -e "${YELLOW}🔄 Actualizando $ARCHIVO...${NC}"

    if curl -L --progress-bar -o "$DESTINO/$ARCHIVO" "$URL"; then
        chmod +x "$DESTINO/$ARCHIVO"
        echo
        echo -e "${GREEN}✅ Actualizado correctamente${NC}"
    else
        echo -e "${RED}❌ Error al actualizar${NC}"
    fi
}

# ----------------------------------------------------------
# Eliminar script
# ----------------------------------------------------------
eliminar_script() {

    mapfile -t LOCALES < <(
        find "$DESTINO" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.bash" \) | sort
    )

    if [ ${#LOCALES[@]} -eq 0 ]; then
        echo
        echo "❌ No hay scripts descargados."
        return
    fi

    echo
    echo "══════════════════════════════════════"
    echo "      ELIMINAR SCRIPT"
    echo "══════════════════════════════════════"

    for i in "${!LOCALES[@]}"; do
        printf "[%02d] %s\n" "$((i+1))" "$(basename "${LOCALES[$i]}")"
    done

    echo
    read -rp "Seleccione script: " OPCION

    if ! [[ "$OPCION" =~ ^[0-9]+$ ]]; then
        echo "❌ Opción inválida"
        return
    fi

    IDX=$((OPCION-1))

    if [ -z "${LOCALES[$IDX]}" ]; then
        echo "❌ Opción fuera de rango"
        return
    fi

    ARCHIVO="${LOCALES[$IDX]}"

    read -rp "¿Eliminar $(basename "$ARCHIVO")? [s/N]: " RESP

    if [[ "$RESP" =~ ^[Ss]$ ]]; then
        rm -f "$ARCHIVO"
        echo -e "${GREEN}✅ Eliminado${NC}"
    else
        echo -e "${YELLOW}⚠️ Cancelado${NC}"
    fi
}

# ----------------------------------------------------------
# Ver scripts descargados
# ----------------------------------------------------------
ver_descargados() {

contador=1

find "$DESTINO" -maxdepth 1 -type f \
\( -name "*.sh" -o -name "*.bash" \) | sort |
while read -r archivo; do
    printf "${GREEN}[%02d]${NC} ${CYAN}%s${NC}\n" \
    "$contador" "$(basename "$archivo")"
    ((contador++))
done
}
# ----------------------------------------------------------
# Instalar/Actualizar dmenu
# ----------------------------------------------------------
instalar_dmenu() {

    echo
    echo -e "${CYAN}📦 Instalando/Actualizando dmenu...${NC}"

    SCRIPT_ACTUAL="$(realpath "$0")"

    cp -f "$SCRIPT_ACTUAL" /usr/local/bin/dmenu
    chmod +x /usr/local/bin/dmenu

    echo
    echo -e "${GREEN}✅ dmenu instalado correctamente${NC}"
    echo
    echo "Comando disponible:"
    echo "dmenu"
    echo
}
# ----------------------------------------------------------
# Menú principal
# ----------------------------------------------------------
while true; do

clear

echo -e "${CYAN}"
echo "══════════════════════════════════════════════"
echo "        GESTOR DE SCRIPTS LLANCOR"
echo "══════════════════════════════════════════════"
echo -e "${NC}"

echo -e "${GREEN}[1]${NC} Ver scripts disponibles en GitHub"
echo -e "${GREEN}[2]${NC} Descargar script"
echo -e "${GREEN}[3]${NC} Ejecutar script descargado"
echo -e "${GREEN}[4]${NC} Actualizar script"
echo -e "${GREEN}[5]${NC} Ver scripts descargados"
echo -e "${GREEN}[6]${NC} Eliminar script"
echo -e "${GREEN}[7]${NC} Instalar/Actualizar dmenu"
echo -e "${RED}[0]${NC} Salir"
echo

    read -rp "Seleccione una opción: " MENU

    case "$MENU" in
        1) listar_remotos; read -n1 -s -r -p "Presione una tecla..." ;;
        2) descargar_script; read -n1 -s -r -p "Presione una tecla..." ;;
        3) ejecutar_script ;;
        4) actualizar_script; read -n1 -s -r -p "Presione una tecla..." ;;
        5) ver_descargados; read -n1 -s -r -p "Presione una tecla..." ;;
        6) eliminar_script; read -n1 -s -r -p "Presione una tecla..." ;;
		7) instalar_dmenu; read -n1 -s -r -p "Presione una tecla..." ;;
        0) exit 0 ;;
        *) echo "❌ Opción inválida"; sleep 1 ;;
    esac

done
