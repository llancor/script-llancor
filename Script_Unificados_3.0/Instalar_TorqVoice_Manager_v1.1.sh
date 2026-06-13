#!/bin/bash
# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
TORQ_DIR="/opt/torqvoice"

header() {

    clear

    echo -e "${CYAN}"
    echo "═══════════════════════════════════════════════════════"
    echo "                 TORQVOICE MANAGER"
    echo "═══════════════════════════════════════════════════════"
    echo -e "${NC}"

}

verificar_dependencias() {

    echo
    echo -e "${CYAN}Verificando dependencias...${NC}"
    echo

    # Docker
    if command -v docker >/dev/null 2>&1; then

        echo -e "${GREEN}✅ Docker instalado${NC}"
        docker --version

    else

        echo -e "${RED}❌ Docker no instalado${NC}"
        echo

        read -rp "¿Desea instalar Docker? [S/n]: " RESP

        if [[ ! "$RESP" =~ ^[nN]$ ]]; then

            apt update

            apt install -y \
                ca-certificates \
                curl \
                gnupg \
                lsb-release

            install -m 0755 -d /etc/apt/keyrings

            curl -fsSL https://download.docker.com/linux/debian/gpg \
            -o /etc/apt/keyrings/docker.asc

            chmod a+r /etc/apt/keyrings/docker.asc

            echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
            https://download.docker.com/linux/debian \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
            > /etc/apt/sources.list.d/docker.list

            apt update

            apt install -y \
                docker-ce \
                docker-ce-cli \
                containerd.io \
                docker-buildx-plugin \
                docker-compose-plugin

            systemctl enable docker
            systemctl start docker

            echo
            echo -e "${GREEN}✅ Docker instalado correctamente${NC}"
        fi
    fi

    echo

    # Docker Compose
    if docker compose version >/dev/null 2>&1; then

        echo -e "${GREEN}✅ Docker Compose instalado${NC}"
        docker compose version

    else

        echo -e "${RED}❌ Docker Compose no instalado${NC}"
        echo

        read -rp "¿Desea instalar Docker Compose? [S/n]: " RESP

        if [[ ! "$RESP" =~ ^[nN]$ ]]; then

            apt update
            apt install -y docker-compose-plugin

            echo
            echo -e "${GREEN}✅ Docker Compose instalado correctamente${NC}"
        fi
    fi

    echo

    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then

        echo -e "${GREEN}"
        echo "════════════════════════════════════"
        echo "   SISTEMA LISTO PARA INSTALAR"
        echo "════════════════════════════════════"
        echo -e "${NC}"

    fi

    echo
    read -rp "ENTER para continuar..."
}

instalar_torqvoice() {

    echo
    echo "Instalando TorqVoice..."
    echo

    mkdir -p "$TORQ_DIR"
    cd "$TORQ_DIR" || return

    wget -q -O docker-compose.yml \
    https://raw.githubusercontent.com/Torqvoice/torqvoice/main/docker-compose.yml

    if [ ! -f .env ]; then

SECRET=$(openssl rand -hex 32)

configurar_url

cat > .env <<EOF
BETTER_AUTH_SECRET=$SECRET
NEXT_PUBLIC_APP_URL=$URL
EOF
    fi

    docker compose up -d

    echo
    echo "✅ Instalación completada"
    echo
    read -rp "ENTER para continuar..."
}

desinstalar_torqvoice() {

    echo
    read -rp "¿Eliminar TorqVoice completamente? [s/N]: " RESP

    [[ ! "$RESP" =~ ^[sS]$ ]] && return

    if [ -d "$TORQ_DIR" ]; then

        cd "$TORQ_DIR" || return

        docker compose down -v

        docker image rm \
            ghcr.io/torqvoice/torqvoice:latest \
            postgres:16-alpine 2>/dev/null

        rm -rf "$TORQ_DIR"

        echo
        echo "✅ TorqVoice eliminado"
    else
        echo
        echo "❌ No está instalado"
    fi

    read -rp "ENTER para continuar..."
}

estado_torqvoice() {

    echo

    if docker ps --format '{{.Names}}' | grep -q '^torqvoice$'; then

        echo "✅ TorqVoice funcionando"
        echo

        docker ps --filter name=torqvoice
        echo
        docker ps --filter name=torqvoice-db

    else
        echo "❌ TorqVoice detenido"
    fi

    echo
    read -rp "ENTER para continuar..."
}

reiniciar_torqvoice() {

    if [ ! -d "$TORQ_DIR" ]; then
        echo "❌ No instalado"
        read -rp "ENTER..."
        return
    fi

    cd "$TORQ_DIR" || return

    docker compose restart

    echo
    echo "✅ Servicios reiniciados"
    echo
    read -rp "ENTER..."
}

ver_logs() {

    if [ ! -d "$TORQ_DIR" ]; then
        echo "❌ No instalado"
        read -rp "ENTER..."
        return
    fi

    cd "$TORQ_DIR" || return

    docker compose logs -f
}

mostrar_url() {

    echo

    if [ -f "$TORQ_DIR/.env" ]; then

        grep NEXT_PUBLIC_APP_URL "$TORQ_DIR/.env"

    else

        echo "❌ Archivo .env no encontrado"

    fi

    echo
    read -rp "ENTER..."
}

actualizar_torqvoice() {

    if [ ! -d "$TORQ_DIR" ]; then
        echo "❌ No instalado"
        read -rp "ENTER..."
        return
    fi

    cd "$TORQ_DIR" || return

    docker compose pull
    docker compose up -d

    echo
    echo "✅ Actualizado"
    echo
    read -rp "ENTER..."
}
configurar_url() {

    IP=$(hostname -I | awk '{print $1}')

    echo
    echo "════════════════════════════════════"
    echo "      CONFIGURACIÓN DE URL"
    echo "════════════════════════════════════"
    echo
    echo "1) Usar IP detectada ($IP)"
    echo "2) Ingresar IP manual"
    echo "3) Ingresar DNS / Dominio"
    echo

    read -rp "Opción: " OPCION

    case "$OPCION" in

        1)
            URL="http://$IP:3000"
        ;;

        2)
            read -rp "Ingrese IP: " IP_MANUAL
            URL="http://$IP_MANUAL:3000"
        ;;

        3)
            read -rp "Ingrese dominio (ej: taller.midominio.cl): " DNS

            echo
            echo "1) HTTP"
            echo "2) HTTPS"
            echo

            read -rp "Protocolo: " PROTO

            if [ "$PROTO" = "2" ]; then
                URL="https://$DNS"
            else
                URL="http://$DNS"
            fi
        ;;

        *)
            URL="http://$IP:3000"
        ;;

    esac

    echo
    echo "URL configurada:"
    echo "$URL"
    echo
}
cambiar_url() {

    if [ ! -f "$TORQ_DIR/.env" ]; then
        echo "❌ TorqVoice no instalado"
        read -rp "ENTER..."
        return
    fi

    configurar_url

    sed -i "/^NEXT_PUBLIC_APP_URL=/d" "$TORQ_DIR/.env"
    echo "NEXT_PUBLIC_APP_URL=$URL" >> "$TORQ_DIR/.env"

    cd "$TORQ_DIR" || return

    docker compose down
    docker compose up -d

    echo
    echo "✅ URL actualizada"
    echo "$URL"
    echo

    read -rp "ENTER..."
}
while true; do

    header

echo -e "${WHITE}1)${NC} ${GREEN}Verificar dependencias${NC}"
echo -e "${WHITE}2)${NC} ${GREEN}Instalar TorqVoice${NC}"
echo -e "${WHITE}3)${NC} ${GREEN}Estado${NC}"
echo -e "${WHITE}4)${NC} ${GREEN}Reiniciar${NC}"
echo -e "${WHITE}5)${NC} ${GREEN}Ver logs${NC}"
echo -e "${WHITE}6)${NC} ${GREEN}Mostrar URL${NC}"
echo -e "${WHITE}7)${NC} ${GREEN}Actualizar${NC}"
echo -e "${WHITE}8)${NC} ${CYAN}Desinstalar${NC}"
echo -e "${WHITE}9)${NC} ${YELLOW}Cambiar URL${NC}"
echo
echo -e "${WHITE}0)${NC} ${CYAN}Salir${NC}"
echo

    read -rp "Opción: " OP

    case "$OP" in
        1) verificar_dependencias ;;
        2) instalar_torqvoice ;;
        3) estado_torqvoice ;;
        4) reiniciar_torqvoice ;;
        5) ver_logs ;;
        6) mostrar_url ;;
        7) actualizar_torqvoice ;;
        8) desinstalar_torqvoice ;;
		9) cambiar_url ;;
        0) exit 0 ;;
    esac

done
