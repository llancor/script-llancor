#!/bin/bash
# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

set -e

BACKUP_BASE="/root/docker-backups"

mkdir -p "$BACKUP_BASE"

listar_apps() {

    APPS=()

    while IFS= read -r APP
    do
        APPS+=("$APP")
    done < <(
        find /opt -mindepth 1 -maxdepth 1 -type d | sort
    )

    if [ ${#APPS[@]} -eq 0 ]; then
        echo "No se encontraron aplicaciones en /opt"
        return 1
    fi

    echo
    echo "Aplicaciones encontradas:"
    echo

    for i in "${!APPS[@]}"
    do
        echo "$((i+1))) $(basename "${APPS[$i]}")"
    done

    echo
}

seleccionar_apps() {

    listar_apps || return 1

    echo "A) Todas"
    echo

    read -rp "Seleccione (ej: 1 3 5 o A): " RESP

    SELECCIONADAS=()

    if [[ "$RESP" =~ ^[Aa]$ ]]; then

        for APP in "${APPS[@]}"
        do
            SELECCIONADAS+=("$APP")
        done

    else

        for N in $RESP
        do
            IDX=$((N-1))

            if [ "$IDX" -ge 0 ] && [ "$IDX" -lt "${#APPS[@]}" ]; then
                SELECCIONADAS+=("${APPS[$IDX]}")
            fi
        done

    fi

    if [ ${#SELECCIONADAS[@]} -eq 0 ]; then
        echo "Nada seleccionado."
        return 1
    fi

    return 0
}

exportar() {

    seleccionar_apps || return

    FECHA=$(date +%Y%m%d-%H%M%S)
    HOST=$(hostname)

    BACKUP_BASE="/root/docker-backups"

    mkdir -p "$BACKUP_BASE"

    DESTINO="${BACKUP_BASE}/export-${HOST}-${FECHA}"

    mkdir -p "$DESTINO/apps"

    echo
    echo "Creando backup en:"
    echo "$DESTINO"
    echo

    echo "Guardando aplicaciones..."

    > "$DESTINO/apps.list"

    for APP in "${SELECCIONADAS[@]}"
    do

        NOMBRE=$(basename "$APP")

        echo "-> $NOMBRE"

        echo "$NOMBRE" >> "$DESTINO/apps.list"

        tar czpf \
            "$DESTINO/apps/${NOMBRE}.tar.gz" \
            -C /opt \
            "$NOMBRE"

    done

    echo
    echo "Guardando imágenes Docker..."

    > "$DESTINO/images.txt"

    for APP in "${SELECCIONADAS[@]}"
    do

        COMPOSE=""

        [ -f "$APP/docker-compose.yml" ] && COMPOSE="$APP/docker-compose.yml"
        [ -f "$APP/compose.yml" ] && COMPOSE="$APP/compose.yml"

        if [ -n "$COMPOSE" ]; then

            grep "image:" "$COMPOSE" \
            | awk '{print $2}' \
            >> "$DESTINO/images.txt"

        fi

    done

    sort -u "$DESTINO/images.txt" -o "$DESTINO/images.txt"

    if [ -s "$DESTINO/images.txt" ]; then

        docker save \
            $(cat "$DESTINO/images.txt") \
            -o "$DESTINO/docker-images.tar"

    fi

    echo
    echo "Guardando volúmenes Docker..."

    if [ -d /var/lib/docker/volumes ]; then

        tar czpf \
            "$DESTINO/docker-volumes.tar.gz" \
            /var/lib/docker/volumes

    fi

    echo
    echo "Guardando configuración Docker..."

    if [ -d /etc/docker ]; then

        tar czpf \
            "$DESTINO/docker-config.tar.gz" \
            /etc/docker

    fi

    echo
    echo "Guardando certificados SSL..."

    if [ -d /etc/letsencrypt ]; then

        tar czpf \
            "$DESTINO/letsencrypt.tar.gz" \
            /etc/letsencrypt

    fi

    docker network ls \
        > "$DESTINO/docker-networks.txt"

    docker volume ls \
        > "$DESTINO/docker-volume-list.txt"

    docker ps -a \
        > "$DESTINO/docker-containers.txt"

    docker version \
        > "$DESTINO/docker-version.txt" 2>/dev/null || true

    echo
    echo "═══════════════════════════════════════"
    echo " BACKUP COMPLETADO"
    echo "═══════════════════════════════════════"
    echo

    du -sh "$DESTINO"

}
importar() {

echo
echo "Buscando backups..."
echo

BACKUP_BASE="/root/docker-backups"

mapfile -t BACKUPS < <(
    find "$BACKUP_BASE" \
    -maxdepth 1 \
    -type d \
    -name "export-*" \
    | sort -r
)

    if [ ${#BACKUPS[@]} -eq 0 ]; then

        echo "No se encontraron backups."
        return

    fi

    echo

    for i in "${!BACKUPS[@]}"
    do

        SIZE=$(du -sh "${BACKUPS[$i]}" 2>/dev/null | awk '{print $1}')

        echo "$((i+1))) $(basename "${BACKUPS[$i]}") [$SIZE]"

    done

    echo

    read -rp "Seleccione backup: " N

    IDX=$((N-1))

    if [ "$IDX" -lt 0 ] || [ "$IDX" -ge "${#BACKUPS[@]}" ]; then

        echo "Selección inválida."
        return

    fi

    BACKUP="${BACKUPS[$IDX]}"

    echo
    echo "Backup seleccionado:"
    echo "$BACKUP"
    echo

    if ! command -v docker >/dev/null 2>&1; then

        echo "Docker no instalado."
        return

    fi

    if ! docker compose version >/dev/null 2>&1; then

        echo
        echo "Instalando Docker Compose Plugin..."

        apt update
        apt install -y docker-compose-plugin

    fi

    echo
    echo "Aplicaciones disponibles:"
    echo

    nl -w2 -s') ' "$BACKUP/apps.list"

    echo
    echo "A) Importar todas"
    echo "S) Seleccionar"

    read -rp "Opción: " OP

    IMPORTAR=()

    if [[ "$OP" =~ ^[Aa]$ ]]; then

        while IFS= read -r APP
        do
            IMPORTAR+=("$APP")
        done < "$BACKUP/apps.list"

    else

        read -rp "Números: " SEL

        mapfile -t LISTA < "$BACKUP/apps.list"

        for N in $SEL
        do

            IDX=$((N-1))

            if [ "$IDX" -ge 0 ] && [ "$IDX" -lt "${#LISTA[@]}" ]; then

                IMPORTAR+=("${LISTA[$IDX]}")

            fi

        done

    fi

    echo
    echo "Restaurando aplicaciones..."

    mkdir -p /opt

    for APP in "${IMPORTAR[@]}"
    do

        echo "-> $APP"

        tar xzpf \
            "$BACKUP/apps/${APP}.tar.gz" \
            -C /opt

    done

    if [ -f "$BACKUP/docker-config.tar.gz" ]; then

        echo
        echo "Restaurando configuración Docker..."

        tar xzpf \
            "$BACKUP/docker-config.tar.gz" \
            -C /

    fi

    if [ -f "$BACKUP/letsencrypt.tar.gz" ]; then

        echo
        echo "Restaurando certificados SSL..."

        tar xzpf \
            "$BACKUP/letsencrypt.tar.gz" \
            -C /

    fi

    if [ -f "$BACKUP/docker-volumes.tar.gz" ]; then

        echo
        echo "Restaurando volúmenes Docker..."

        systemctl stop docker 2>/dev/null || true
        systemctl stop containerd 2>/dev/null || true

        tar xzpf \
            "$BACKUP/docker-volumes.tar.gz" \
            -C /

        systemctl start containerd 2>/dev/null || true
        systemctl start docker 2>/dev/null || true

    fi

    if [ -f "$BACKUP/docker-images.tar" ]; then

        echo
        echo "Importando imágenes..."

        docker load -i "$BACKUP/docker-images.tar"

    fi

    echo
    read -rp "¿Iniciar los stacks importados? [s/n]: " RESP

    if [[ "$RESP" =~ ^[Ss]$ ]]; then

        for APP in "${IMPORTAR[@]}"
        do

            DIR="/opt/$APP"

            if [ -f "$DIR/docker-compose.yml" ]; then

                echo "Iniciando $APP"

                cd "$DIR"

                docker compose up -d

            elif [ -f "$DIR/compose.yml" ]; then

                echo "Iniciando $APP"

                cd "$DIR"

                docker compose up -d

            fi

        done

    fi

    echo
    echo "═══════════════════════════════════════"
    echo " IMPORTACIÓN COMPLETADA"
    echo "═══════════════════════════════════════"
    echo

}
verificar_dependencias() {

    echo
    echo -e "${CYAN}Verificando dependencias...${NC}"
    echo

    # =========================================================
    # LIMPIEZA DE REPOS ROTOS (IMPORTANTE)
    # =========================================================
    echo "🧹 Limpiando posibles repositorios antiguos de Docker..."

    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/sources.list.d/docker*.list 2>/dev/null

    apt update -y >/dev/null 2>&1

    # =========================================================
    # INSTALAR DEPENDENCIAS BASE
    # =========================================================
    echo "📦 Instalando dependencias base..."

    apt install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1

    # =========================================================
    # AGREGAR REPO OFICIAL DOCKER
    # =========================================================
    echo "🔧 Configurando repositorio oficial de Docker..."

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    chmod a+r /etc/apt/keyrings/docker.gpg

    VERSION_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")

    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian \
$VERSION_CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list

    apt update

    # =========================================================
    # DOCKER
    # =========================================================
    if command -v docker >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Docker ya instalado${NC}"
        docker --version
    else
        echo -e "${YELLOW}📦 Instalando Docker...${NC}"

        if apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
            systemctl enable docker >/dev/null 2>&1
            systemctl start docker >/dev/null 2>&1
            echo -e "${GREEN}✅ Docker instalado correctamente${NC}"
        else
            echo -e "${RED}❌ Error instalando Docker${NC}"
            return 1
        fi
    fi

    echo

    # =========================================================
    # DOCKER COMPOSE
    # =========================================================
    if docker compose version >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Docker Compose funcionando${NC}"
        docker compose version
    else
        echo -e "${YELLOW}📦 Corrigiendo Docker Compose...${NC}"

        if apt install -y docker-compose-plugin; then
            echo -e "${GREEN}✅ Docker Compose instalado correctamente${NC}"
        else
            echo -e "${RED}❌ No se pudo instalar Docker Compose${NC}"
            echo "👉 Revisa conexión o versión de Debian"
            return 1
        fi
    fi

    echo

    # =========================================================
    # VALIDACIÓN FINAL REAL
    # =========================================================
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then

        echo -e "${GREEN}"
        echo "════════════════════════════════════"
        echo "   SISTEMA LISTO PARA INSTALAR"
        echo "════════════════════════════════════"
        echo -e "${NC}"

    else

        echo -e "${RED}"
        echo "════════════════════════════════════"
        echo "   ERROR: DEPENDENCIAS INCOMPLETAS"
        echo "════════════════════════════════════"
        echo -e "${NC}"

        return 1
    fi

    echo
    read -rp "ENTER para continuar..."
}
eliminar_apps() {

    seleccionar_apps || return

    echo
    echo "Aplicaciones seleccionadas:"
    echo

    for APP in "${SELECCIONADAS[@]}"
    do
        echo " - $(basename "$APP")"
    done

    echo
    read -rp "¿Continuar? [s/n]: " CONF

    [[ ! "$CONF" =~ ^[Ss]$ ]] && return

    for APP in "${SELECCIONADAS[@]}"
    do

        NOMBRE=$(basename "$APP")

        echo
        echo "Eliminando $NOMBRE..."

        cd "$APP" 2>/dev/null || continue

        if [ -f docker-compose.yml ] || [ -f compose.yml ]; then

            docker compose down --remove-orphans 2>/dev/null || true

        fi

        rm -rf "$APP"

        echo "OK"

    done

    echo
    echo "Proceso finalizado."
}
eliminar_todo() {

    echo
    echo "⚠️  ATENCIÓN"
    echo
    echo "Se eliminarán:"
    echo " - Todos los contenedores"
    echo " - Todas las imágenes"
    echo " - Todos los volúmenes"
    echo " - Todas las redes Docker"
    echo " - Todo /opt"
    echo

    read -rp "Escriba ELIMINAR para continuar: " CONF

    [ "$CONF" != "ELIMINAR" ] && return

    echo
    echo "Deteniendo contenedores..."

    docker stop $(docker ps -aq) 2>/dev/null || true

    echo "Eliminando contenedores..."

    docker rm -f $(docker ps -aq) 2>/dev/null || true

    echo "Eliminando imágenes..."

    docker rmi -f $(docker images -aq) 2>/dev/null || true

    echo "Eliminando volúmenes..."

    docker volume rm $(docker volume ls -q) 2>/dev/null || true

    echo "Eliminando redes..."

    docker network prune -f

    echo "Eliminando /opt..."

    rm -rf /opt/*

    echo
    echo "Docker limpiado completamente."
}
eliminar_docker_compose() {

    clear

    echo
    echo "════════════════════════════════════════════"
    echo "     DESINSTALAR DOCKER COMPLETAMENTE"
    echo "════════════════════════════════════════════"
    echo
    echo "Se eliminará:"
    echo
    echo "• Docker Engine"
    echo "• Docker Compose"
    echo "• Containerd"
    echo "• Todos los contenedores"
    echo "• Todas las imágenes"
    echo "• Todos los volúmenes"
    echo "• Todas las redes Docker"
    echo "• /var/lib/docker"
    echo "• /var/lib/containerd"
    echo

    read -rp "Escriba ELIMINAR para continuar: " CONFIRMAR

    [ "$CONFIRMAR" != "ELIMINAR" ] && return

    echo
    echo "Deteniendo servicios..."

    systemctl stop docker 2>/dev/null || true
    systemctl stop docker.socket 2>/dev/null || true
    systemctl stop containerd 2>/dev/null || true

    echo
    echo "Eliminando paquetes..."

    apt remove -y \
        docker-ce \
        docker-ce-cli \
        docker-buildx-plugin \
        docker-compose-plugin \
        docker-ce-rootless-extras \
        containerd.io \
        docker.io \
        docker-compose \
        containerd \
        runc 2>/dev/null || true

    apt purge -y \
        docker-ce \
        docker-ce-cli \
        docker-buildx-plugin \
        docker-compose-plugin \
        docker-ce-rootless-extras \
        containerd.io \
        docker.io \
        docker-compose \
        containerd \
        runc 2>/dev/null || true

    echo
    echo "Eliminando directorios..."

    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd
    rm -rf /etc/docker
    rm -rf /etc/containerd

    rm -f /usr/local/bin/docker-compose
    rm -f /usr/bin/docker-compose

    echo
    echo "Limpiando paquetes..."

    apt autoremove -y
    apt autoclean

    echo
    echo "Verificando..."

    if command -v docker >/dev/null 2>&1; then
        echo "⚠ Docker aún existe en el sistema"
    else
        echo "✓ Docker eliminado correctamente"
    fi

    if command -v docker-compose >/dev/null 2>&1; then
        echo "⚠ Docker Compose aún existe"
    else
        echo "✓ Docker Compose eliminado correctamente"
    fi

    echo
    echo "Proceso finalizado."
    echo
}
mostrar_docker() {

    clear

    IP_SERVIDOR=$(hostname -I | awk '{print $1}')

    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}              CONTENEDORES DOCKER${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo

    printf "%-25s %-20s %s\n" \
        "CONTENEDOR" \
        "ESTADO" \
        "ACCESO"

    echo -e "${CYAN}────────────────────────────────────────────────────────────────────${NC}"

    docker ps -a --format "{{.Names}}" | while read -r CONT
    do

        ESTADO_REAL=$(docker inspect -f '{{.State.Status}}' "$CONT" 2>/dev/null)

        if [ "$ESTADO_REAL" = "running" ]; then
            ESTADO="${GREEN}🟢 Activo${NC}"
        else
            ESTADO="${RED}🔴 Detenido${NC}"
        fi

        ACCESO="${YELLOW}Sin puerto publicado${NC}"

        PUERTO=$(docker port "$CONT" 2>/dev/null \
            | head -n1 \
            | awk -F: '{print $NF}')

        if [ -n "$PUERTO" ]; then
            ACCESO="${YELLOW}http://${IP_SERVIDOR}:${PUERTO}${NC}"
        fi

        printf "%-25s " "$CONT"
        echo -e "$ESTADO    $ACCESO"

    done

    echo
    echo -e "${WHITE}IP Servidor:${NC} ${GREEN}${IP_SERVIDOR}${NC}"
    echo

    read -rp "ENTER para continuar..."
}
while true
do

    clear

echo
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          MIGRADOR DOCKER /OPT                ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo
echo -e "${YELLOW}[1]${CYAN} Exportar aplicaciones"
echo -e "${YELLOW}[2]${YELLOW} Importar aplicaciones"
echo -e "${YELLOW}[3]${CYAN} Listar aplicaciones"
echo -e "${YELLOW}[4]${GREEN} Instalar Docker Compose"
echo -e "${YELLOW}[5]${YELLOW} Eliminar Seleccion - Docker"
echo -e "${YELLOW}[6]${YELLOW} Eliminar Todos - Docker"
echo -e "${YELLOW}[7]${YELLOW} Desinstalar Docker Compose Completo"
echo
echo -e "${YELLOW}[8]${CYAN} Estado de Docker / IP:PUERTO"
echo
echo -e "${CYAN}[0]${CYAN} Salir"
echo
echo -ne "${MAGENTA}Seleccione una opción:${NC} "

    read -rp "Opción: " OP

    case "$OP" in

        1)
            exportar
            read -rp "ENTER..."
            ;;

        2)
            importar
            read -rp "ENTER..."
            ;;

        3)
            listar_apps
            read -rp "ENTER..."
            ;;
        4)
            verificar_dependencias
            read -rp "ENTER..."
            ;;
        5)
            eliminar_apps
            read -rp "ENTER..."
            ;;			
	    6)
            eliminar_todo
            read -rp "ENTER..."
            ;;			
	    7)
            eliminar_docker_compose
            read -rp "ENTER..."
            ;;	
 	    8)
            mostrar_docker
            read -rp "ENTER..."
            ;;		
        0)
            exit 0
            ;;

    esac

done