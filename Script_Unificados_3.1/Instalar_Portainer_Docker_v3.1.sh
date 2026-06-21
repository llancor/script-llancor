#!/bin/bash

# ==================================================
# PORTAINER MANAGER PRO v3.1
# Debian 12 / Ubuntu
# Portainer CE LTS
# ==================================================

# ---------- COLORES ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---------- VARIABLES ----------
PORTAINER_NAME="portainer"
PORTAINER_PORT="9443"
VOLUME_NAME="portainer_data"

BACKUP_DIR="/opt/portainer"

FALTANTES=()

# ---------- MENSAJES ----------

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

question() {
    echo -e "${CYAN}[?]${NC} $1"
}

pause() {
    echo
    read -rp "Presione ENTER para continuar..."
}


# ---------- SISTEMA ----------

verificar_root() {

    if [ "$EUID" -ne 0 ]; then
        error "Debe ejecutar este script como root"
        exit 1
    fi
}

verificar_so() {

    if [ -f /etc/os-release ]; then
        . /etc/os-release

        info "Sistema: $PRETTY_NAME"
    fi
}

verificar_arquitectura() {

    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64)
            success "Arquitectura AMD64"
            ;;
        aarch64)
            success "Arquitectura ARM64"
            ;;
        *)
            warning "Arquitectura detectada: $ARCH"
            ;;
    esac
}

mostrar_url() {

    IP=$(hostname -I | awk '{print $1}')

    echo
    success "URL DE ACCESO"
    echo
    echo "https://$IP:$PORTAINER_PORT"
    echo
}
# ==================================================
# DEPENDENCIAS
# ==================================================

verificar_dependencias() {

    FALTANTES=()

    DEPENDENCIAS=(
        curl
        wget
        ca-certificates
        gnupg
        nano
        tar
        gzip
        apparmor
        apparmor-utils
    )

    echo

    for dep in "${DEPENDENCIAS[@]}"; do

        if dpkg -s "$dep" >/dev/null 2>&1; then
            success "$dep"
        else
            warning "$dep no instalado"
            FALTANTES+=("$dep")
        fi

    done

    if command -v docker >/dev/null 2>&1; then
        success "docker"
    else
        warning "docker no instalado"
        FALTANTES+=(docker.io)
    fi

    echo

    if [ ${#FALTANTES[@]} -gt 0 ]; then

        warning "Faltan dependencias"

        printf ' - %s\n' "${FALTANTES[@]}"

    else

        success "Todas las dependencias instaladas"

    fi

    echo
	
}

instalar_dependencias() {

    if [ ${#FALTANTES[@]} -eq 0 ]; then
        return
    fi

    info "Instalando dependencias..."

    apt update || {
        error "Error actualizando repositorios"
        return 1
    }

    apt install -y "${FALTANTES[@]}" || {
        error "Error instalando dependencias"
        return 1
    }

    success "Dependencias instaladas"
}

# ==================================================
# DOCKER
# ==================================================

verificar_docker() {

    echo

    if ! command -v docker >/dev/null 2>&1; then

        error "Docker no instalado"
        return 1

    fi

    success "Docker instalado"

    systemctl enable docker >/dev/null 2>&1
    systemctl start docker

    if ! systemctl is-active --quiet docker; then

        error "Docker no está ejecutándose"
        return 1

    fi

    success "Docker activo"

    if docker info >/dev/null 2>&1; then

        success "Docker operativo"

    else

        error "Docker presenta errores"
        return 1

    fi

    return 0
}

probar_docker() {

    echo

    info "Ejecutando prueba Docker..."

    if docker run --rm hello-world >/dev/null 2>&1; then

        success "Docker funciona correctamente"

    else

        error "La prueba Docker falló"

    fi
}

reiniciar_docker() {

    header

    info "Reiniciando Docker..."

    systemctl restart docker

    sleep 3

    if systemctl is-active --quiet docker; then

        success "Docker reiniciado"

    else

        error "Docker no inició"

    fi

    pause
}

diagnosticar_docker() {

    header

    echo
    info "Versión Docker"
    docker version

    echo
    info "Información Docker"
    docker info

    echo
    info "Estado servicio Docker"
    systemctl status docker --no-pager

    pause
}

# ==================================================
# RED Y PUERTOS
# ==================================================

verificar_puertos() {

    echo

    info "Verificando puertos utilizados..."

    ss -tulpn | grep -E ':9443|:9000|:8000'

    echo
}

verificar_puerto_9443() {

    if ss -tulpn | grep -q ":9443 "; then

        warning "Puerto 9443 ocupado"

        ss -tulpn | grep ":9443 "

        return 1
    fi

    return 0
}

ver_red() {

    header

    echo
    info "Interfaces de red"
    ip addr

    echo
    info "IPs detectadas"
    hostname -I

    pause
}

# ==================================================
# FIREWALL
# ==================================================

verificar_firewall() {

    echo

    if command -v ufw >/dev/null 2>&1; then

        info "Estado UFW"

        ufw status

    else

        warning "UFW no instalado"

    fi
}

abrir_puerto_9443() {

    if command -v ufw >/dev/null 2>&1; then

        ufw allow 9443/tcp >/dev/null 2>&1

        success "Puerto 9443 permitido en UFW"

    fi
}

# ==================================================
# INFORMACIÓN
# ==================================================

estado_portainer() {

    header

    docker ps -a --filter "name=$PORTAINER_NAME"

    echo

    mostrar_url

    pause
}
# ==================================================
# INSTALACIÓN
# ==================================================
# ==================================================
# PORTAINER
# ==================================================

PORTAINER_NAME="portainer"
VOLUME_NAME="portainer_data"

seleccionar_version_portainer() {

    echo
    echo "===================================="
    echo "      VERSION DE PORTAINER"
    echo "===================================="
    echo
    echo " 1) LTS (Recomendada)"
    echo " 2) Latest"
    echo
    read -rp "Seleccione una opción [1-2]: " OPCION

    case "$OPCION" in
        2)
            PORTAINER_IMAGE="portainer/portainer-ce:latest"
            PORTAINER_VERSION="Latest"
        ;;
        *)
            PORTAINER_IMAGE="portainer/portainer-ce:lts"
            PORTAINER_VERSION="LTS"
        ;;
    esac

    success "Versión seleccionada: $PORTAINER_VERSION"
}

instalar_portainer() {

    header

    verificar_root
    verificar_dependencias
    instalar_dependencias

    verificar_so
    verificar_arquitectura

    echo

    if ! verificar_docker; then
        pause
        return
    fi

    echo

    if docker ps -a --format '{{.Names}}' | grep -q "^${PORTAINER_NAME}$"; then

        warning "Portainer ya existe"

        read -rp "¿Desea repararlo automáticamente? [s/N]: " RESP

        if [[ "$RESP" =~ ^[Ss]$ ]]; then
            reparar_portainer
        fi

        pause
        return
    fi

    seleccionar_version_portainer

    mkdir -p "$BACKUP_DIR"

    echo
    info "Creando volumen..."

    docker volume create "$VOLUME_NAME" >/dev/null 2>&1

    echo
    info "Descargando imagen $PORTAINER_VERSION..."

    docker pull "$PORTAINER_IMAGE" || {

        error "Error descargando imagen"

        pause
        return 1
    }

    echo
    info "Instalando Portainer..."

    docker run -d \
        --name "$PORTAINER_NAME" \
        --restart unless-stopped \
        -p 9443:9443 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v ${VOLUME_NAME}:/data \
        "$PORTAINER_IMAGE"

    sleep 10

    if docker ps --format '{{.Names}}' | grep -q "^${PORTAINER_NAME}$"; then

        success "Portainer $PORTAINER_VERSION instalado correctamente"

        abrir_puerto_9443

        mostrar_url

    else

        error "Portainer no inició"

        docker logs "$PORTAINER_NAME" --tail 50
    fi

    pause
}

# ==================================================
# LOGS
# ==================================================

ver_logs() {

    header

    docker logs --tail 100 "$PORTAINER_NAME"

    pause
}

logs_tiempo_real() {

    header

    echo
    echo "CTRL+C para salir"
    echo

    docker logs -f "$PORTAINER_NAME"
}

# ==================================================
# REINICIO
# ==================================================

reiniciar_portainer() {

    header

    if ! docker ps -a --format '{{.Names}}' | grep -q "^${PORTAINER_NAME}$"; then

        error "Portainer no existe"

        pause
        return
    fi

    docker restart "$PORTAINER_NAME"

    success "Portainer reiniciado"

    pause
}

# ==================================================
# REPARACIÓN
# ==================================================

reparar_portainer() {

    header

    warning "Se reparará Portainer"

    echo
    read -rp "¿Continuar? [s/N]: " RESP

    [[ ! "$RESP" =~ ^[Ss]$ ]] && return

    info "Deteniendo contenedor..."

    docker stop "$PORTAINER_NAME" 2>/dev/null || true

    info "Eliminando contenedor..."

    docker rm "$PORTAINER_NAME" 2>/dev/null || true

    info "Eliminando imagen..."

    docker rmi "$PORTAINER_IMAGE" 2>/dev/null || true

    echo

    info "Descargando imagen nueva..."

    docker pull "$PORTAINER_IMAGE" || {

        error "No fue posible descargar la imagen"

        pause
        return
    }

    echo

    info "Creando contenedor..."

    docker run -d \
        --name "$PORTAINER_NAME" \
        --restart unless-stopped \
        -p 9443:9443 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v ${VOLUME_NAME}:/data \
        "$PORTAINER_IMAGE"

    sleep 10

    if docker ps --format '{{.Names}}' | grep -q "^${PORTAINER_NAME}$"; then

        success "Portainer reparado"

        mostrar_url

    else

        error "La reparación falló"

        docker logs "$PORTAINER_NAME" --tail 100

    fi

    pause
}

# ==================================================
# ACTUALIZACIÓN
# ==================================================

actualizar_portainer() {

    header

    backup_portainer

    echo

    info "Actualizando imagen..."

    docker pull "$PORTAINER_IMAGE" || {

        error "Error descargando imagen"

        pause
        return
    }

    docker stop "$PORTAINER_NAME" 2>/dev/null || true
    docker rm "$PORTAINER_NAME" 2>/dev/null || true

    docker run -d \
        --name "$PORTAINER_NAME" \
        --restart unless-stopped \
        -p 9443:9443 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v ${VOLUME_NAME}:/data \
        "$PORTAINER_IMAGE"

    sleep 10

    if docker ps --format '{{.Names}}' | grep -q "^${PORTAINER_NAME}$"; then

        success "Portainer actualizado"

    else

        error "Error al iniciar"

        docker logs "$PORTAINER_NAME" --tail 50

    fi

    pause
}

# ==================================================
# DESINSTALAR
# ==================================================

desinstalar_portainer() {

    header

    warning "Se eliminará Portainer"

    echo

    read -rp "¿Continuar? [s/N]: " RESP

    [[ ! "$RESP" =~ ^[Ss]$ ]] && return

    docker stop "$PORTAINER_NAME" 2>/dev/null || true

    docker rm "$PORTAINER_NAME" 2>/dev/null || true

    echo

    read -rp "¿Eliminar volumen de datos? [s/N]: " RESP2

    if [[ "$RESP2" =~ ^[Ss]$ ]]; then

        docker volume rm "$VOLUME_NAME" 2>/dev/null || true

        success "Datos eliminados"
    fi

    success "Portainer desinstalado"

    pause
}
# ==================================================
# BACKUP
# ==================================================

backup_portainer() {

    mkdir -p "$BACKUP_DIR"

    FECHA=$(date +%Y%m%d-%H%M%S)

    ARCHIVO="$BACKUP_DIR/portainer-$FECHA.tar.gz"

    echo
    info "Creando backup..."

    docker run --rm \
        -v ${VOLUME_NAME}:/data \
        -v ${BACKUP_DIR}:/backup \
        alpine \
        tar czf "/backup/portainer-$FECHA.tar.gz" /data >/dev/null 2>&1

    if [ -f "$ARCHIVO" ]; then

        success "Backup creado"

        echo "$ARCHIVO"

    else

        error "Error creando backup"

    fi
}

restaurar_portainer() {

    header

    mkdir -p "$BACKUP_DIR"

    echo
    echo "Backups disponibles:"
    echo

    ls -lh "$BACKUP_DIR"

    echo

    read -rp "Nombre del archivo: " ARCHIVO

    if [ ! -f "$BACKUP_DIR/$ARCHIVO" ]; then

        error "Archivo no encontrado"

        pause
        return
    fi

    warning "Se restaurarán los datos"

    read -rp "¿Continuar? [s/N]: " RESP

    [[ ! "$RESP" =~ ^[Ss]$ ]] && return

    docker stop "$PORTAINER_NAME" 2>/dev/null || true

    docker run --rm \
        -v ${VOLUME_NAME}:/data \
        -v ${BACKUP_DIR}:/backup \
        alpine \
        sh -c "cd / && tar xzf /backup/$ARCHIVO"

    docker start "$PORTAINER_NAME"

    success "Restauración completada"

    pause
}

listar_backups() {

    header

    mkdir -p "$BACKUP_DIR"

    echo
    ls -lh "$BACKUP_DIR"

    pause
}
ver_repositorios_templates() {

    header

    echo
    echo                   "REPOSITORIO RECOMENDADO"
    echo "================================================================================"
    echo -e "${CYAN}" Latest Verción mas de 50 stack"${NC}"
    echo -e "${CYAN}"https://raw.githubusercontent.com/Lissy93/portainer-templates/main/templates.json"${NC}"
	echo
	echo -e "${CYAN}" LTS Verción "${NC}"
    echo -e "${CYAN}"https://raw.githubusercontent.com/TomChantler/portainer-templates/refs/heads/v3/templates_v3.json"${NC}"
    echo
    echo "================================================================================"
    pause
}
reparar_dns_docker_portainer() {

    header

    echo "===================================="
    echo "   REPARAR DNS DOCKER / PORTAINER"
    echo "===================================="
    echo

    if [ "$(id -u)" -ne 0 ]; then
        error "Debe ejecutarse como root"
        return 1
    fi

    info "Creando respaldo de configuración DNS..."

    mkdir -p /root/backups

    if [ -f /etc/docker/daemon.json ]; then
        cp /etc/docker/daemon.json \
        /root/backups/daemon.json.$(date +%Y%m%d-%H%M%S)
    fi

    info "Configurando DNS de Docker..."

    mkdir -p /etc/docker

    cat > /etc/docker/daemon.json <<EOF
{
  "dns": [
    "1.1.1.1",
    "8.8.8.8"
  ]
}
EOF

    info "Reiniciando Docker..."

    systemctl daemon-reload
    systemctl restart docker

    sleep 5

    if ! docker info >/dev/null 2>&1; then
        error "Docker no está funcionando correctamente"
        return 1
    fi

    success "Docker operativo"

    if docker ps -a --format '{{.Names}}' | grep -q "^portainer$"; then

        info "Reiniciando Portainer..."

        docker restart portainer >/dev/null 2>&1

        sleep 8

        success "Portainer reiniciado"

        echo
        info "DNS dentro del contenedor:"
        docker exec portainer cat /etc/resolv.conf 2>/dev/null || true

        echo
        info "Prueba de conectividad:"
        docker exec portainer getent hosts github.com 2>/dev/null || warning "No resuelve aún"

    else
        warning "Portainer no está instalado o no se llama 'portainer'"
    fi

    echo
    success "Reparación de DNS finalizada"
    pause
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
# ==================================================
# MENÚ
# ==================================================

menu() {

while true; do

header
clear
echo
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}      PORTAINER MANAGER PRO v3.1        ${NC}"
echo -e "${CYAN}========================================${NC}"
echo

echo -e "${YELLOW}[1]${NC}  Verificar dependencias"
echo -e "${YELLOW}[2]${NC}  Instalar Portainer"
echo -e "${YELLOW}[3]${NC}  Estado Portainer"
echo -e "${YELLOW}[4]${NC}  Mostrar URL"
echo -e "${YELLOW}[5]${NC}  Ver logs"
echo -e "${YELLOW}[6]${NC}  Logs en tiempo real"
echo -e "${YELLOW}[7]${NC}  Reiniciar Portainer"
echo -e "${YELLOW}[8]${NC}  Reparar Portainer"
echo -e "${YELLOW}[9]${NC}  Actualizar Portainer"

echo
echo -e "${YELLOW}[10]${NC} Crear backup"
echo -e "${YELLOW}[11]${NC} Restaurar backup"
echo -e "${YELLOW}[12]${NC} Ver backups"

echo
echo -e "${YELLOW}[13]${NC} Reiniciar Docker"
echo -e "${YELLOW}[14]${NC} Diagnosticar Docker"
echo -e "${YELLOW}[15]${NC} Probar Docker"

echo
echo -e "${YELLOW}[16]${NC} Ver red"
echo -e "${YELLOW}[17]${NC} Ver puertos"
echo -e "${YELLOW}[18]${NC} Ver firewall"
echo
echo -e "${YELLOW}[19]${NC} Ver Repositorios de Templates"
echo -e "${YELLOW}[20]${NC} Reparar DNS Para Descargar Repositorios"
echo -e "${YELLOW}[21]${NC} Ver Estado de Stack / Docker / Aplicaciones"
echo
echo -e "${YELLOW}[22]${NC} Desinstalar Portainer"

echo
echo -e "${RED}[0]${NC} Salir"
echo

read -rp "Seleccione una opción: " OPCION

case "$OPCION" in

    1)
        header
        verificar_dependencias
        pause
        ;;

    2)
        instalar_portainer
        ;;

    3)
        estado_portainer
        ;;

    4)
        header
        mostrar_url
        pause
        ;;

    5)
        ver_logs
        ;;

    6)
        logs_tiempo_real
        ;;

    7)
        reiniciar_portainer
        ;;

    8)
        reparar_portainer
        ;;

    9)
        actualizar_portainer
        ;;

    10)
        header
        backup_portainer
        pause
        ;;

    11)
        restaurar_portainer
        ;;

    12)
        listar_backups
        ;;

    13)
        reiniciar_docker
        ;;

    14)
        diagnosticar_docker
        ;;

    15)
        header
        probar_docker
        pause
        ;;

    16)
        ver_red
        ;;

    17)
        header
        verificar_puertos
        pause
        ;;

    18)
        header
        verificar_firewall
        pause
        ;;
		
	19)
        
        ver_repositorios_templates
        
        ;;
		
    20)
        
        reparar_dns_docker_portainer
        
        ;;
		
	21)
        
        mostrar_docker
        
        ;;

    22)
        desinstalar_portainer
        ;;

    0)
        clear
        exit 0
        ;;

    *)
        error "Opción inválida"
        sleep 2
        ;;

esac

done
}

# ==================================================
# INICIO
# ==================================================

verificar_root
menu