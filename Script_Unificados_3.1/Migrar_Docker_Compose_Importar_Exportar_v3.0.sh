#!/bin/bash
# Colores
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

set -e

BACKUP_BASE="/root/docker-backups"

mkdir -p "$BACKUP_BASE"
verificar_pv() {

    if command -v pv >/dev/null 2>&1; then

        echo "✓ pv instalado"
        return

    fi

    echo
    echo "Instalando pv..."
    echo

    apt update
    apt install -y pv

    if ! command -v pv >/dev/null 2>&1; then

        echo "Error al instalar pv."
        return 1

    fi

}
listar_apps() {

    APPS=()

    while IFS= read -r APP
    do
        APPS+=("$APP")
    done < <(
        find /opt -mindepth 1 -maxdepth 1 -type d | sort
    )

    if [ ${#APPS[@]} -eq 0 ]; then

        echo
        echo "No se encontraron aplicaciones en /opt"
        echo

        read -rp "Presione Enter para continuar..." _
        return 0

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

    verificar_pv || return

    seleccionar_apps || return

    FECHA=$(date +%Y%m%d-%H%M%S)
    HOST=$(hostname)

    echo
    read -rp "Nombre del backup [$HOST]: " NOMBRE_BACKUP

    NOMBRE_BACKUP=${NOMBRE_BACKUP:-$HOST}
    NOMBRE_BACKUP=$(echo "$NOMBRE_BACKUP" | tr ' /' '--')

    BACKUP_BASE="/root/docker-backups"

    mkdir -p "$BACKUP_BASE"

    DESTINO="${BACKUP_BASE}/${NOMBRE_BACKUP}-${FECHA}"

    mkdir -p "$DESTINO/apps"

    echo
    echo "═══════════════════════════════════════"
    echo " CREANDO BACKUP"
    echo "═══════════════════════════════════════"
    echo
    echo "Destino:"
    echo "$DESTINO"
    echo

    echo "Guardando aplicaciones..."
    echo

    > "$DESTINO/apps.list"

    TOTAL=${#SELECCIONADAS[@]}
    ACTUAL=0

    for APP in "${SELECCIONADAS[@]}"
    do

        ACTUAL=$((ACTUAL+1))

        NOMBRE=$(basename "$APP")

        echo
        echo "═══════════════════════════════════════"
        echo "[$ACTUAL/$TOTAL] Respaldando $NOMBRE"
        echo "═══════════════════════════════════════"

        echo "$NOMBRE" >> "$DESTINO/apps.list"

        SIZE=$(du -sb "$APP" 2>/dev/null | awk '{print $1}')

        tar cf - \
            -C /opt \
            "$NOMBRE" \
        | pv -petrab -s "$SIZE" \
        | gzip \
        > "$DESTINO/apps/${NOMBRE}.tar.gz"

    done

    echo
    echo "═══════════════════════════════════════"
    echo " GUARDANDO VOLÚMENES DOCKER"
    echo "═══════════════════════════════════════"

    if [ -d /var/lib/docker/volumes ]; then

        SIZE=$(du -sb /var/lib/docker/volumes 2>/dev/null | awk '{print $1}')

        tar cf - /var/lib/docker/volumes \
        | pv -petrab -s "$SIZE" \
        | gzip \
        > "$DESTINO/docker-volumes.tar.gz"

    fi

    echo
    echo "═══════════════════════════════════════"
    echo " GUARDANDO CONFIGURACIÓN DOCKER"
    echo "═══════════════════════════════════════"

    if [ -d /etc/docker ]; then

        SIZE=$(du -sb /etc/docker 2>/dev/null | awk '{print $1}')

        tar cf - /etc/docker \
        | pv -petrab -s "$SIZE" \
        | gzip \
        > "$DESTINO/docker-config.tar.gz"

    fi

    echo
    echo "═══════════════════════════════════════"
    echo " GUARDANDO CERTIFICADOS SSL"
    echo "═══════════════════════════════════════"

    if [ -d /etc/letsencrypt ]; then

        SIZE=$(du -sb /etc/letsencrypt 2>/dev/null | awk '{print $1}')

        tar cf - /etc/letsencrypt \
        | pv -petrab -s "$SIZE" \
        | gzip \
        > "$DESTINO/letsencrypt.tar.gz"

    fi

    echo
    echo "═══════════════════════════════════════"
    echo " GUARDANDO INFORMACIÓN DOCKER"
    echo "═══════════════════════════════════════"

    docker network ls \
        > "$DESTINO/docker-networks.txt" 2>/dev/null || true

    docker volume ls \
        > "$DESTINO/docker-volume-list.txt" 2>/dev/null || true

    docker ps -a \
        > "$DESTINO/docker-containers.txt" 2>/dev/null || true

    docker version \
        > "$DESTINO/docker-version.txt" 2>/dev/null || true

    docker compose version \
        > "$DESTINO/docker-compose-version.txt" 2>/dev/null || true

    uname -a \
        > "$DESTINO/system-info.txt" 2>/dev/null || true

    echo
    echo "═══════════════════════════════════════"
    echo " BACKUP COMPLETADO"
    echo "═══════════════════════════════════════"
    echo

    echo "Tamaño final del backup:"
    du -sh "$DESTINO"

    echo

}
importar_simple() {

    BACKUP_BASE="/root/docker-backups"

    mapfile -t BACKUPS < <(
    find "$BACKUP_BASE" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    | sort -r
)

    if [ ${#BACKUPS[@]} -eq 0 ]; then

        echo "No se encontraron backups."
        return

    fi

    echo
    echo "Backups disponibles:"
    echo

    for i in "${!BACKUPS[@]}"
    do

        SIZE=$(du -sh "${BACKUPS[$i]}" | awk '{print $1}')

        echo "$((i+1))) $(basename "${BACKUPS[$i]}") [$SIZE]"

    done

    echo

    read -rp "Seleccione backup: " N

    IDX=$((N-1))

    BACKUP="${BACKUPS[$IDX]}"

    echo
    echo "Restaurando:"
    echo "$BACKUP"
    echo

    mkdir -p /opt

    while IFS= read -r APP
    do

        echo "-> Restaurando $APP"

        tar xzpf \
            "$BACKUP/apps/${APP}.tar.gz" \
            -C /opt

    done < "$BACKUP/apps.list"

    if [ -f "$BACKUP/docker-config.tar.gz" ]; then

        echo
        echo "Restaurando Docker..."

        tar xzpf \
            "$BACKUP/docker-config.tar.gz" \
            -C /

    fi

    if [ -f "$BACKUP/letsencrypt.tar.gz" ]; then

        echo
        echo "Restaurando SSL..."

        tar xzpf \
            "$BACKUP/letsencrypt.tar.gz" \
            -C /

    fi

    if [ -f "$BACKUP/docker-volumes.tar.gz" ]; then

        echo
        echo "Restaurando volúmenes..."

        systemctl stop docker
        systemctl stop containerd

        tar xzpf \
            "$BACKUP/docker-volumes.tar.gz" \
            -C /

        systemctl start containerd
        systemctl start docker

    fi

    echo
    echo "Iniciando stacks..."

    while IFS= read -r APP
    do

        DIR="/opt/$APP"

        if [ -f "$DIR/docker-compose.yml" ] || [ -f "$DIR/compose.yml" ]; then

            echo "-> $APP"

            cd "$DIR" || continue

            docker compose pull
            docker compose up -d

        fi

    done < "$BACKUP/apps.list"

    echo
    echo "Importación completada."

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
    echo -e "${CYAN}Aplicaciones seleccionadas:${NC}"
    echo

    for APP in "${SELECCIONADAS[@]}"
    do
        echo -e " - ${YELLOW}$(basename "$APP")${NC}"
    done

    echo
    echo -e "${RED}⚠ ADVERTENCIA${NC}"
    echo
    echo "Se eliminarán:"
    echo " - Directorios de las aplicaciones"
    echo " - Contenedores Docker"
    echo " - Redes Docker del proyecto"
    echo " - Volúmenes Docker del proyecto"
    echo
    echo "Opcional:"
    echo " - Imágenes Docker del proyecto"
    echo

    echo -ne "Escriba ${YELLOW}ELIMINAR${NC} para continuar: "
    read -r CONFIRMAR

    if [[ "${CONFIRMAR^^}" != "ELIMINAR" ]]; then

        echo
        echo -e "${RED}Operación cancelada.${NC}"
        return

    fi

    echo
    read -rp "¿Eliminar también las imágenes Docker? [s/n]: " ELIMINAR_IMAGENES

    for APP in "${SELECCIONADAS[@]}"
    do

        NOMBRE=$(basename "$APP")

        echo
        echo -e "${YELLOW}Eliminando ${NOMBRE}...${NC}"

        cd "$APP" 2>/dev/null || continue

        if [ -f docker-compose.yml ] || [ -f compose.yml ]; then

            if [[ "$ELIMINAR_IMAGENES" =~ ^[Ss]$ ]]; then

                docker compose down \
                    --volumes \
                    --remove-orphans \
                    --rmi local 2>/dev/null || true

            else

                docker compose down \
                    --volumes \
                    --remove-orphans 2>/dev/null || true

            fi

        fi

        rm -rf "$APP"

        echo -e "${GREEN}✓ ${NOMBRE} eliminado${NC}"

    done

    echo
    echo -e "${YELLOW}Limpiando recursos Docker sin uso...${NC}"

    if [[ "$ELIMINAR_IMAGENES" =~ ^[Ss]$ ]]; then

        docker image prune -f >/dev/null 2>&1

    fi

    docker volume prune -f >/dev/null 2>&1
    docker network prune -f >/dev/null 2>&1

    echo
    echo -e "${GREEN}Proceso finalizado correctamente.${NC}"
    echo

}
eliminar_todo() {

    echo
    echo -e "${RED}⚠️  ATENCIÓN${NC}"
    echo
    echo "Se eliminarán:"
    echo " - Todos los contenedores"
    echo " - Todas las imágenes"
    echo " - Todos los volúmenes"
    echo " - Todas las redes Docker"
    echo " - Todo /opt"
    echo

    echo -ne "Escriba ${YELLOW}ELIMINAR${NC} para continuar: "
    read -r CONFIRMAR

    if [[ "${CONFIRMAR^^}" != "ELIMINAR" ]]; then
        echo -e "${RED}Operación cancelada.${NC}"
        return
    fi

    echo
    echo -e "${YELLOW}Deteniendo contenedores...${NC}"

    docker ps -aq | xargs -r docker stop

    echo -e "${YELLOW}Eliminando contenedores...${NC}"

    docker ps -aq | xargs -r docker rm -f

    echo -e "${YELLOW}Eliminando imágenes...${NC}"

    docker images -aq | xargs -r docker rmi -f

    echo -e "${YELLOW}Eliminando volúmenes...${NC}"

    docker volume ls -q | xargs -r docker volume rm

    echo -e "${YELLOW}Eliminando redes...${NC}"

    docker network prune -f

    echo -e "${YELLOW}Vaciando /opt...${NC}"

    find /opt -mindepth 1 -delete

    echo
    echo -e "${GREEN}Docker y /opt limpiados completamente.${NC}"
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
limpiar_docker() {

    echo
    echo -e "${YELLOW}Recursos Docker sin uso:${NC}"
    echo

    docker system df

    echo
    echo -e "${RED}⚠ Se eliminarán:${NC}"
    echo " - Contenedores detenidos"
    echo " - Imágenes sin uso"
    echo " - Redes sin uso"
    echo " - Volúmenes huérfanos"
    echo

    echo -ne "Escriba ${YELLOW}LIMPIAR${NC} para continuar: "
    read -r CONFIRMAR

    if [[ "${CONFIRMAR^^}" != "LIMPIAR" ]]; then
        echo -e "${RED}Operación cancelada.${NC}"
        return
    fi

    docker system prune -a --volumes -f

    echo
    echo -e "${GREEN}Limpieza completada.${NC}"
    echo
}
reiniciar_contenedores() {

    mapfile -t CONTENEDORES < <(
        docker ps -a --format '{{.Names}}'
    )

    if [ ${#CONTENEDORES[@]} -eq 0 ]; then

        echo
        echo -e "${RED}No se encontraron contenedores.${NC}"
        echo
        return

    fi

    echo
    echo -e "${CYAN}Contenedores disponibles:${NC}"
    echo

    for i in "${!CONTENEDORES[@]}"
    do

        NOMBRE="${CONTENEDORES[$i]}"

        ESTADO=$(docker inspect \
            --format='{{.State.Status}}' \
            "$NOMBRE" 2>/dev/null)

        case "$ESTADO" in
            running)
                ESTADO_COLOR="${GREEN}🟢 Activo${NC}"
                ;;
            exited)
                ESTADO_COLOR="${RED}🔴 Detenido${NC}"
                ;;
            *)
                ESTADO_COLOR="${YELLOW}🟡 ${ESTADO}${NC}"
                ;;
        esac

        printf "%2d) %-35s %b\n" \
            "$((i+1))" \
            "$NOMBRE" \
            "$ESTADO_COLOR"

    done

    echo
    echo "A) Reiniciar todos"
    echo "S) Seleccionar"
    echo

    read -rp "Opción: " OPCION

    echo

    if [[ "$OPCION" =~ ^[Aa]$ ]]; then

        echo -e "${CYAN}Reiniciando todos los contenedores...${NC}"
        echo

        for CONT in "${CONTENEDORES[@]}"
        do

            echo -ne "→ $CONT ... "

            if docker restart "$CONT" >/dev/null 2>&1; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}ERROR${NC}"
            fi

        done

    else

        read -rp "Números (ej: 1 3 5): " SELECCION

        echo

        for N in $SELECCION
        do

            IDX=$((N-1))

            if [ "$IDX" -ge 0 ] && \
               [ "$IDX" -lt "${#CONTENEDORES[@]}" ]; then

                CONT="${CONTENEDORES[$IDX]}"

                echo -ne "→ $CONT ... "

                if docker restart "$CONT" >/dev/null 2>&1; then
                    echo -e "${GREEN}OK${NC}"
                else
                    echo -e "${RED}ERROR${NC}"
                fi

            fi

        done

    fi

    echo
    echo -e "${GREEN}Proceso finalizado.${NC}"
    echo

}
eliminar_red_docker() {

    echo
    echo -e "${CYAN}====================================${NC}"
    echo -e "${CYAN}      ELIMINAR RED DOCKER0          ${NC}"
    echo -e "${CYAN}====================================${NC}"
    echo

    if ! ip link show docker0 >/dev/null 2>&1; then
        echo -e "${GREEN}✅ La interfaz docker0 no existe${NC}"
        read -rp "ENTER para continuar..."
        return
    fi

    IP_DOCKER=$(ip -4 addr show docker0 2>/dev/null | awk '/inet / {print $2}')

    echo -e "${YELLOW}⚠ Se encontró la interfaz docker0${NC}"
    echo -e "${WHITE}IP:${NC} $IP_DOCKER"
    echo

    RED_EN_USO=0

    if command -v docker >/dev/null 2>&1; then

        CONTENEDORES=$(docker network inspect bridge \
            --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)

        if [ -n "$CONTENEDORES" ]; then

            RED_EN_USO=1

            echo -e "${RED}❌ La red bridge está siendo utilizada${NC}"
            echo
            echo -e "${WHITE}Contenedores asociados:${NC}"
            echo

            docker ps -a \
                --filter network=bridge \
                --format "ID: {{.ID}} | Nombre: {{.Names}} | Imagen: {{.Image}}"

            echo
        else
            echo -e "${GREEN}✅ Ningún contenedor utiliza la red bridge${NC}"
            echo
        fi
    fi

    echo -e "${RED}⚠️  ATENCIÓN${NC}"
    echo

    echo "Se realizará la siguiente acción:"
    echo " - Eliminar la interfaz docker0"

    if [ "$RED_EN_USO" -eq 1 ]; then
        echo " - La red está siendo utilizada por contenedores"
    fi

    echo " - Docker podría recrearla al reiniciar el servicio"
    echo

    echo -ne "Escriba ${YELLOW}ELIMINAR${NC} para continuar: "
    read -r CONFIRMAR

    if [ "$CONFIRMAR" != "ELIMINAR" ]; then
        echo
        echo -e "${YELLOW}Operación cancelada${NC}"
        read -rp "ENTER para continuar..."
        return
    fi

    echo
    echo -e "${YELLOW}Deteniendo Docker...${NC}"

    systemctl stop docker >/dev/null 2>&1
    systemctl stop docker.socket >/dev/null 2>&1

    sleep 2

    echo
    echo -e "${YELLOW}Eliminando interfaz docker0...${NC}"

    ip link set docker0 down >/dev/null 2>&1
    ip link delete docker0 >/dev/null 2>&1

    echo

    if ip link show docker0 >/dev/null 2>&1; then
        echo -e "${RED}❌ No fue posible eliminar docker0${NC}"
    else
        echo -e "${GREEN}✅ Interfaz docker0 eliminada correctamente${NC}"
    fi

    echo

    if systemctl is-active docker >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Docker continúa activo${NC}"
    else
        echo -e "${GREEN}✅ Docker detenido${NC}"
    fi

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
echo -e "${YELLOW}[1]${BLUE} Exportar aplicaciones"
echo -e "${YELLOW}[2]${GREEN} Importar aplicaciones"
echo -e "${YELLOW} *"
echo -e "${YELLOW}[3]${CYAN} Listar aplicaciones"
echo -e "${YELLOW}[4]${CYAN} Instalar Docker Compose"
echo -e "${YELLOW} *"
echo -e "${YELLOW}[5]${RED} Eliminar Docker + Contenedor - ${YELLOW}Selección"
echo -e "${YELLOW}[6]${RED} Eliminar Docker + Contenedor - ${YELLOW}Todos"
echo -e "${YELLOW} *"
echo -e "${YELLOW}[7]${RED} Desinstalar Docker Compose - ${YELLOW}Completo"
echo -e "${YELLOW}[8]${RED} Eliminar Contenedores - ${YELLOW}Sin Uso"
echo -e "${YELLOW}[9]${RED} Eliminar Red Docker - ${YELLOW}Sin Uso"
echo -e "${YELLOW} *"
echo -e "${YELLOW}[10]${YELLOW} Estado de Docker ${CYAN}/ IP:PUERTO"
echo -e "${YELLOW}[11]${YELLOW} Reiniciar Contenedores ${CYAN}/ Ver Estados"
echo -e "${YELLOW} *"
echo -e "${CYAN}[0]${CYAN} Salir"
echo -e "${YELLOW} *"
echo -ne "${CYAN}Seleccione una opción:${NC} "

echo -ne "${YELLOW}Opción:${NC} "
read -r OP

case "$OP" in

        1)
            exportar
            read -rp "ENTER..."
            ;;

        2)
            importar_simple
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
            limpiar_docker
            read -rp "ENTER..."
            ;;	
 	    9)
            eliminar_red_docker
            read -rp "ENTER..."
            ;;			
			
 	    10)
            mostrar_docker
            read -rp "ENTER..."
            ;;
 	    11)
            reiniciar_contenedores
            read -rp "ENTER..."
            ;;
			
				
        0)
            exit 0
            ;;

    esac

done