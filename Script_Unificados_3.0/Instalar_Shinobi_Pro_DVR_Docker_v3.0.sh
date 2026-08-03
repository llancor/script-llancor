############################################################
# INSTALAR DEPENDENCIAS
############################################################
APP_NAME="Shinobi"
APP_VERSION="3.0"

BASE_DIR="/opt/shinobi"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"

CONTAINER_NAME="shinobi"

HTTP_PORT="8080"
TZ="America/Santiago"

############################################################
# COLORES BRILLANTES
############################################################

RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
BLUE='\e[94m'
MAGENTA='\e[95m'
CYAN='\e[96m'
WHITE='\e[97m'

NC='\e[0m'
############################################################
# TÍTULO
############################################################

titulo() {

    echo -e "${CYAN}============== ${YELLOW}$1${CYAN} ==============${NC}"
    echo

}
############################################################
# HEADER
############################################################

header() {

    clear

    echo -e "${CYAN}"
    echo "============================================================"
    echo "                  SHINOBI MANAGER"
    echo "                      Versión $APP_VERSION"
    echo "============================================================"
    echo -e "${NC}"

}
############################################################
# PAUSA
############################################################

pause() {

    echo
    echo -e "${YELLOW}Presione ENTER para continuar...${NC}"
    read -r

}
############################################################
# ESPERAR INICIO SHINOBI
############################################################

esperar_shinobi() {

    echo
    echo -e "${YELLOW}Esperando inicio de Shinobi...${NC}"

    CONTADOR=0

    while true
    do

        ESTADO=$(docker inspect -f '{{.State.Running}}' shinobi 2>/dev/null)

        if [ "$ESTADO" = "true" ]; then

            if curl -s http://localhost:${HTTP_PORT} >/dev/null 2>&1; then

                echo
                echo -e "${GREEN}✓ Shinobi está listo.${NC}"
                return 0

            fi

        fi


        CONTADOR=$((CONTADOR+1))


        if [ "$CONTADOR" -ge 60 ]; then

            echo
            echo -e "${RED}✗ Tiempo de espera agotado.${NC}"
            return 1

        fi


        echo -n "."
        sleep 5

    done

}
############################################################
# INSTALAR DEPENDENCIAS
############################################################

instalar_dependencias() {

    header

    titulo "INSTALAR DEPENDENCIAS"

    echo
    echo "Verificando dependencias..."
    echo

    if command -v docker >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Docker instalado${NC}"
        DOCKER_OK=1
    else
        echo -e "${YELLOW}✗ Docker no instalado${NC}"
        DOCKER_OK=0
    fi

    if docker compose version >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Docker Compose instalado${NC}"
        COMPOSE_OK=1
    else
        echo -e "${YELLOW}✗ Docker Compose no instalado${NC}"
        COMPOSE_OK=0
    fi

    if [ "$DOCKER_OK" = "1" ] && [ "$COMPOSE_OK" = "1" ]; then
        echo
        echo -e "${GREEN}Todas las dependencias ya están instaladas.${NC}"
        pause
        return
    fi

    apt update

    apt install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    install -m 0755 -d /etc/apt/keyrings

    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

        chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    if [ ! -f /etc/apt/sources.list.d/docker.list ]; then

        echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
> /etc/apt/sources.list.d/docker.list

    fi

    apt update

    apt install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable docker
    systemctl restart docker

    echo
    echo -e "${GREEN}Docker instalado correctamente.${NC}"

    pause

}
############################################################
# INSTALAR SHINOBI
############################################################

instalar_shinobi() {
instalar_dependencias

    header

    titulo "INSTALAR SHINOBI"


    if docker ps -a --format '{{.Names}}' | grep -q "^shinobi$"; then

        echo
        echo -e "${YELLOW}Shinobi ya está instalado.${NC}"
        pause
        return

    fi



    ########################################################
    # PUERTO WEB
    ########################################################

    read -rp "Puerto Web [8080]: " HTTP_PORT
    HTTP_PORT=${HTTP_PORT:-8080}



    ########################################################
    # DIRECTORIOS
    ########################################################

    mkdir -p "$BASE_DIR"


    mkdir -p \
        "$BASE_DIR/config" \
        "$BASE_DIR/database" \
        "$BASE_DIR/videos" \
        "$BASE_DIR/plugins" \
        "$BASE_DIR/customAutoLoad" \
        "$BASE_DIR/mysql"



    ########################################################
    # DOCKER COMPOSE
    ########################################################

    cat > "$COMPOSE_FILE" <<EOF
services:

  shinobi:

    image: registry.gitlab.com/shinobi-systems/shinobi:latest

    container_name: shinobi

    restart: unless-stopped


    ports:

      - "${HTTP_PORT}:8080"


    volumes:

      - ./config:/config
      - ./database:/var/lib/mysql
      - ./videos:/home/Shinobi/videos
      - ./plugins:/home/Shinobi/plugins
      - ./customAutoLoad:/home/Shinobi/libs/customAutoLoad
      - /dev/shm/shinobiStreams:/dev/shm/streams
      - /etc/localtime:/etc/localtime:ro


    environment:

      HOME: /home/Shinobi

      DB_HOST: shinobi-sql
      DB_USER: majesticflame
      DB_PASSWORD: "1234"
      DB_DATABASE: ccio

      SHINOBI_UPDATE: "false"


    depends_on:

      - shinobi-sql




  shinobi-sql:


    image: mariadb:10.11


    container_name: shinobi-sql


    restart: unless-stopped



    environment:

      MYSQL_ROOT_PASSWORD: rootpassword

      MYSQL_DATABASE: ccio

      MYSQL_USER: majesticflame

      MYSQL_PASSWORD: "1234"



    volumes:

      - ./mysql:/var/lib/mysql

EOF




    cd "$BASE_DIR" || return



    ########################################################
    # VALIDAR COMPOSE
    ########################################################

    echo
    echo -e "${YELLOW}Validando Docker Compose...${NC}"


    if ! docker compose config >/dev/null; then

        echo
        echo -e "${RED}Error en docker-compose.yml${NC}"
        pause
        return

    fi




    ########################################################
    # DESCARGAR IMAGENES
    ########################################################

    echo
    echo -e "${YELLOW}Descargando imágenes...${NC}"


    if ! docker compose pull; then

        echo
        echo -e "${RED}Error descargando imágenes.${NC}"
        pause
        return

    fi




    ########################################################
    # INICIAR SHINOBI
    ########################################################

    echo
    echo -e "${YELLOW}Iniciando Shinobi...${NC}"



    if docker compose up -d; then



        if esperar_shinobi; then


            IP=$(hostname -I | awk '{print $1}')



            echo
            echo -e "${CYAN}Configuración inicial Shinobi${NC}"
            echo



            read -rp "¿Desea configurar el idioma ahora? (s/n): " CONFIG_LANG


            if [[ "$CONFIG_LANG" =~ ^[sS]$ ]]; then

                cambiar_idioma_shinobi

            fi




            echo
            echo -e "${GREEN}======================================${NC}"
            echo -e "${GREEN} Shinobi instalado correctamente ${NC}"
            echo -e "${GREEN}======================================${NC}"



            echo

            echo "Acceso:"
            echo "http://${IP}:${HTTP_PORT}"



            echo

            echo -e "${CYAN}Superusuario por defecto:${NC}"

            echo

            echo "URL:"
            echo "http://${IP}:${HTTP_PORT}/super"


            echo

            echo "Usuario:"
            echo "admin@shinobi.video"


            echo

            echo "Clave:"
            echo "admin"



            echo

            echo -e "${GREEN}Directorio instalación:${NC}"
            echo "$BASE_DIR"



        else


            echo
            echo -e "${RED}Error esperando inicio de Shinobi.${NC}"

            echo

            echo "Revisar logs:"
            echo "cd $BASE_DIR"
            echo "docker compose logs"



        fi



    else


        echo
        echo -e "${RED}Error iniciando Shinobi.${NC}"


    fi



    pause

}
############################################################
# ADMINISTRAR SERVICIOS
############################################################

administrar_servicios() {

    while true; do

        header

        titulo "ADMINISTRAR SERVICIOS"

        echo
        echo -e " ${YELLOW}1)${NC} Iniciar Shinobi"
        echo -e " ${YELLOW}2)${NC} Detener Shinobi"
        echo -e " ${YELLOW}3)${NC} Reiniciar Shinobi"
        echo -e " ${YELLOW}4)${NC} Ver estado del contenedor"
        echo -e " ${YELLOW}5)${NC} Ver logs en tiempo real"
        echo
        echo -e " ${YELLOW}0)${NC} Volver"
        echo

        read -rp "Seleccione una opción: " opcion

        case "$opcion" in

            1)
                iniciar_shinobi
                ;;

            2)
                detener_shinobi
                ;;

            3)
                reiniciar_shinobi
                ;;

            4)
                estado_contenedor_shinobi
                ;;

            5)
                logs_shinobi
                ;;

            0)
                return
                ;;

            *)
                echo
                echo -e "${RED}Opción inválida.${NC}"
                sleep 2
                ;;

        esac

    done

}
############################################################
# INICIAR SHINOBI
############################################################

iniciar_shinobi() {

    header

    titulo "INICIAR SHINOBI"

    echo

    if [ ! -d "$BASE_DIR" ]; then
        echo -e "${RED}Shinobi no está instalado.${NC}"
        pause
        return
    fi

    cd "$BASE_DIR" || return

    echo -e "${YELLOW}Iniciando Shinobi...${NC}"
    echo

    docker compose up -d

    echo

    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${GREEN}✓ Shinobi iniciado correctamente.${NC}"
    else
        echo -e "${RED}✗ No fue posible iniciar Shinobi.${NC}"
    fi

    pause

}
############################################################
# DETENER SHINOBI
############################################################

detener_shinobi() {

    header

    titulo "DETENER SHINOBI"

    echo

    if [ ! -d "$BASE_DIR" ]; then
        echo -e "${RED}Shinobi no está instalado.${NC}"
        pause
        return
    fi

    cd "$BASE_DIR" || return

    echo -e "${YELLOW}Deteniendo Shinobi...${NC}"
    echo

    docker compose stop

    echo
    echo -e "${GREEN}✓ Shinobi detenido correctamente.${NC}"

    pause

}
############################################################
# REINICIAR SHINOBI
############################################################

reiniciar_shinobi() {

    header

    titulo "REINICIAR SHINOBI"

    echo

    if [ ! -d "$BASE_DIR" ]; then
        echo -e "${RED}Shinobi no está instalado.${NC}"
        pause
        return
    fi

    cd "$BASE_DIR" || return

    echo -e "${YELLOW}Reiniciando Shinobi...${NC}"
    echo

    docker compose restart

    echo
    echo -e "${GREEN}✓ Shinobi reiniciado correctamente.${NC}"

    pause

}
############################################################
# ESTADO DEL CONTENEDOR
############################################################

estado_contenedor_shinobi() {

    header

    titulo "ESTADO DEL CONTENEDOR"

    echo

    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${RED}Shinobi no está instalado.${NC}"
        echo
        pause
        return
    fi

    docker ps -a --filter "name=$CONTAINER_NAME"

    echo

    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${GREEN}Estado: EN EJECUCIÓN${NC}"
    else
        echo -e "${YELLOW}Estado: DETENIDO${NC}"
    fi

    echo

    pause

}
############################################################
# LOGS SHINOBI
############################################################

logs_shinobi() {

    header

    titulo "LOGS SHINOBI"

    echo

    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${RED}Shinobi no está instalado.${NC}"
        echo
        pause
        return
    fi

    echo -e "${YELLOW}Mostrando registros...${NC}"
    echo -e "${CYAN}Presione CTRL+C para volver al menú.${NC}"
    echo

    docker logs -f "$CONTAINER_NAME"

}

############################################################
# ESTADO SHINOBI
############################################################

estado_shinobi() {

    header

    titulo "ESTADO SHINOBI"

    echo

    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${RED}✗ Shinobi no está instalado.${NC}"
        echo
        pause
        return
    fi

    ESTADO=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)
    IMAGEN=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null)
    INICIO=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER_NAME" 2>/dev/null)
    PUERTOS=$(docker port "$CONTAINER_NAME" 2>/dev/null)

    IP_SERVIDOR=$(hostname -I | awk '{print $1}')

    CPU=$(docker stats --no-stream --format "{{.CPUPerc}}" "$CONTAINER_NAME" 2>/dev/null)
    MEMORIA=$(docker stats --no-stream --format "{{.MemUsage}}" "$CONTAINER_NAME" 2>/dev/null)

    echo -e "${CYAN}Estado del servicio${NC}"
    echo "──────────────────────────────────────────────"

    if [ "$ESTADO" = "running" ]; then
        echo -e "Estado             : ${GREEN}EN EJECUCIÓN${NC}"
    else
        echo -e "Estado             : ${YELLOW}${ESTADO^^}${NC}"
    fi

    echo "Contenedor         : $CONTAINER_NAME"
    echo "Imagen             : $IMAGEN"
    echo "Directorio         : $BASE_DIR"
    echo
    echo -e "${CYAN}Recursos${NC}"
    echo "──────────────────────────────────────────────"
    echo "CPU                : $CPU"
    echo "Memoria            : $MEMORIA"
    echo
    echo -e "${CYAN}Red${NC}"
    echo "──────────────────────────────────────────────"
    echo "$PUERTOS"
    echo
    echo "Iniciado           : $INICIO"
    echo
    echo "Acceso Web         : http://$IP_SERVIDOR:$HTTP_PORT"
    echo

    pause

}
############################################################
# MENÚ AJUSTES
############################################################

menu_ajustes() {

    while true; do

        header

        titulo "AJUSTES SHINOBI"

        echo
        echo -e " ${YELLOW}1)${NC} Cambiar puerto Web"
        echo -e " ${YELLOW}2)${NC} Cambiar zona horaria"
        echo -e " ${YELLOW}3)${NC} Actualizar Shinobi"
        echo -e " ${YELLOW}4)${NC} Recrear contenedor"
        echo
        echo -e " ${YELLOW}0)${NC} Volver"
        echo

        read -rp "Seleccione una opción: " opcion

        case "$opcion" in

            1)
                cambiar_puerto_web
                ;;

            2)
                cambiar_zona_horaria
                ;;

            3)
                actualizar_shinobi
                ;;

            4)
                recrear_contenedor
                ;;

            0)
                return
                ;;

            *)
                echo
                echo -e "${RED}Opción inválida.${NC}"
                sleep 2
                ;;

        esac

    done

}
############################################################
# CAMBIAR PUERTO WEB
############################################################

cambiar_puerto_web() {

    header

    titulo "CAMBIAR PUERTO WEB"

    echo
    echo "Puerto actual: $HTTP_PORT"
    echo

    read -rp "Nuevo puerto: " NUEVO_PUERTO

    [[ -z "$NUEVO_PUERTO" ]] && return

    if ss -tuln | grep -q ":${NUEVO_PUERTO} "; then
        echo
        echo -e "${RED}El puerto ${NUEVO_PUERTO} ya está en uso.${NC}"
        pause
        return
    fi

    sed -i "s/${HTTP_PORT}:8080/${NUEVO_PUERTO}:8080/g" "$COMPOSE_FILE"

    HTTP_PORT="$NUEVO_PUERTO"

    cd "$BASE_DIR" || return

    docker compose up -d

    echo
    echo -e "${GREEN}✓ Puerto actualizado correctamente.${NC}"
    echo
    echo "Nuevo acceso:"
    echo "http://$(hostname -I | awk '{print $1}'):$HTTP_PORT"

    pause

}
############################################################
# CAMBIAR ZONA HORARIA
############################################################

cambiar_zona_horaria() {

    header

    titulo "CAMBIAR ZONA HORARIA"

    echo
    echo "Zona actual: $TZ"
    echo

    read -rp "Nueva zona horaria: " NUEVA_TZ

    [[ -z "$NUEVA_TZ" ]] && return

    sed -i "s|TZ=.*|TZ=${NUEVA_TZ}|g" "$COMPOSE_FILE"

    TZ="$NUEVA_TZ"

    cd "$BASE_DIR" || return

    docker compose up -d

    echo
    echo -e "${GREEN}✓ Zona horaria actualizada.${NC}"

    pause

}
############################################################
# ACTUALIZAR SHINOBI
############################################################

actualizar_shinobi() {

    header

    titulo "ACTUALIZAR SHINOBI"

    echo
    echo -e "${YELLOW}Actualizando Shinobi...${NC}"
    echo

    cd "$BASE_DIR" || return

    docker compose pull

    docker compose up -d

    docker image prune -f

    echo
    echo -e "${GREEN}✓ Shinobi actualizado correctamente.${NC}"

    pause

}
############################################################
# RECREAR CONTENEDOR
############################################################

recrear_contenedor() {

    header

    titulo "RECREAR CONTENEDOR"

    echo
    echo -e "${YELLOW}Recreando contenedores...${NC}"
    echo

    cd "$BASE_DIR" || return

    docker compose down

    docker compose up -d

    echo
    echo -e "${GREEN}✓ Contenedores recreados correctamente.${NC}"

    pause

}
############################################################
# INFORMACIÓN SHINOBI
############################################################

informacion() {

    echo

    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${RED}✗ Shinobi no está instalado.${NC}"
        echo
        pause
        return
    fi

    IMAGE=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME")
    VERSION=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" | cut -d: -f2)
    CREATED=$(docker inspect -f '{{.Created}}' "$CONTAINER_NAME")
    RESTART=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$CONTAINER_NAME")

    echo -e "${CYAN}Información de Docker${NC}"
    echo "========================================="
    echo -e "Aplicación        : ${GREEN}${APP_NAME}${NC}"
    echo "Contenedor        : $CONTAINER_NAME"
    echo "Imagen            : $IMAGE"
    echo "Versión Imagen    : $VERSION"
    echo "Puerto Web        : $HTTP_PORT"
    echo "Directorio        : $BASE_DIR"
    echo "Docker Compose    : $COMPOSE_FILE"
    echo "Reinicio          : $RESTART"
    echo "Creado            : $CREATED"
    echo "Zona Horaria      : $TZ"
    echo "========================================="
    echo

    pause

}
############################################################
# DESINSTALAR SHINOBI
############################################################

desinstalar_shinobi() {

    while true; do

        header

        titulo "DESINSTALAR SHINOBI"

        echo
        echo -e " ${YELLOW}1)${NC} Eliminar solo los contenedores"
        echo -e " ${YELLOW}2)${NC} Eliminar contenedores e imágenes"
        echo -e " ${YELLOW}3)${NC} Eliminación completa"
        echo
        echo -e " ${YELLOW}0)${NC} Volver"
        echo

        read -rp "Seleccione una opción: " opcion

        case "$opcion" in

			            ##################################################
            # CONTENEDORES (OPCIONAL BASE DE DATOS)
            ##################################################
            1)

                echo
                echo -e "${YELLOW}Eliminar contenedores Shinobi${NC}"
                echo

                read -rp "¿Eliminar los contenedores? (s/n): " RESP

                [[ "$RESP" != "s" && "$RESP" != "S" ]] && continue


                cd "$BASE_DIR" 2>/dev/null


                docker compose down 2>/dev/null


                echo
                echo -e "${GREEN}✓ Contenedores eliminados correctamente.${NC}"


                echo
                echo -e "${CYAN}Datos actuales:${NC}"
                echo " • Base de datos MySQL"
                echo " • Usuarios Shinobi"
                echo " • Configuración"
                echo " • Grabaciones"
                echo


                read -rp "¿Desea eliminar también la base de datos MySQL? (s/n): " BORRAR_DB


                if [[ "$BORRAR_DB" =~ ^[sS]$ ]]; then


                    echo
                    echo -e "${RED}Eliminando base de datos...${NC}"


                    rm -rf "$BASE_DIR/mysql"


                    echo -e "${GREEN}✓ Base de datos eliminada.${NC}"


                else


                    echo
                    echo -e "${YELLOW}Base de datos conservada.${NC}"


                fi


                echo
                echo -e "${GREEN}Proceso terminado.${NC}"


                pause

                ;;

                        ##################################################
            # CONTENEDORES + IMÁGENES (OPCIONAL BASE DATOS)
            ##################################################
            2)

                echo
                echo -e "${YELLOW}Eliminar contenedores e imágenes${NC}"
                echo

                read -rp "¿Continuar? (s/n): " RESP

                [[ "$RESP" != "s" && "$RESP" != "S" ]] && continue


                cd "$BASE_DIR" 2>/dev/null


                docker compose down 2>/dev/null


                echo
                echo -e "${YELLOW}Eliminando imágenes Docker...${NC}"


                docker image rm "$SHINOBI_IMAGE" 2>/dev/null
                docker image rm "$MYSQL_IMAGE" 2>/dev/null


                docker image prune -f >/dev/null 2>&1


                echo
                echo -e "${GREEN}✓ Contenedores e imágenes eliminados.${NC}"


                echo
                echo -e "${CYAN}Datos actuales:${NC}"
                echo " • Base de datos MySQL"
                echo " • Usuarios Shinobi"
                echo " • Configuración"
                echo " • Grabaciones"
                echo


                read -rp "¿Desea eliminar también la base de datos MySQL? (s/n): " BORRAR_DB


                if [[ "$BORRAR_DB" =~ ^[sS]$ ]]; then


                    echo
                    echo -e "${RED}Eliminando base de datos MySQL...${NC}"


                    rm -rf "$BASE_DIR/mysql"


                    echo -e "${GREEN}✓ Base de datos eliminada.${NC}"


                else


                    echo
                    echo -e "${YELLOW}Base de datos conservada.${NC}"


                fi


                echo
                echo -e "${GREEN}Proceso terminado.${NC}"


                pause

                ;;
				

			##################################################
			# ELIMINACIÓN COMPLETA
			##################################################
			3)

    echo
    echo -e "${RED}¡¡ATENCIÓN!!${NC}"
    echo
    echo "Se eliminará completamente Shinobi:"
    echo
    echo " • Contenedores Docker"
    echo " • Imágenes Docker"
    echo " • Base de datos MySQL"
    echo " • Usuarios Shinobi"
    echo " • Configuración"
    echo " • Cámaras"
    echo " • Grabaciones"
    echo " • Plugins"
    echo " • Directorio:"
    echo "   $BASE_DIR"
    echo
    echo -e "${YELLOW}Docker y Docker Compose NO serán eliminados.${NC}"
    echo


    read -rp "Escriba ELIMINAR para continuar: " CONFIRMAR


    if [ "$CONFIRMAR" != "ELIMINAR" ]; then

        echo
        echo -e "${YELLOW}Operación cancelada.${NC}"
        pause
        continue

    fi



    echo
    echo -e "${YELLOW}Deteniendo contenedores...${NC}"


    cd "$BASE_DIR" 2>/dev/null


    docker compose down 2>/dev/null



    echo
    echo -e "${YELLOW}Eliminando imágenes Docker...${NC}"


    docker image rm "$SHINOBI_IMAGE" 2>/dev/null
    docker image rm "$MYSQL_IMAGE" 2>/dev/null



    echo
    echo -e "${YELLOW}Eliminando datos persistentes...${NC}"


    rm -rf "$BASE_DIR"


    echo
    echo -e "${YELLOW}Eliminando credenciales guardadas...${NC}"


    rm -f /root/shinobi-superusuario.txt



    docker image prune -f >/dev/null 2>&1



    echo
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN} Shinobi eliminado completamente ${NC}"
    echo -e "${GREEN}======================================${NC}"

    echo
    echo "Se eliminaron:"
    echo " ✓ Base de datos MySQL"
    echo " ✓ Usuarios Shinobi"
    echo " ✓ Configuración"
    echo " ✓ Grabaciones"
    echo " ✓ Contenedores"
    echo " ✓ Imágenes"
    echo


    pause

    ;;

            ##################################################
            # VOLVER
            ##################################################
            0)
                return
                ;;

            ##################################################
            # OPCIÓN INVÁLIDA
            ##################################################
            *)

                echo
                echo -e "${RED}Opción inválida.${NC}"
                sleep 2
                ;;

        esac

    done

}
############################################################
# CAMBIAR IDIOMA SHINOBI
############################################################

cambiar_idioma_shinobi() {

    clear

    # COLORES
    AMARILLO="\e[33m"
    VERDE="\e[32m"
    ROJO="\e[31m"
    CYAN="\e[36m"
    BLANCO="\e[97m"
    RESET="\e[0m"


    CONTAINER="shinobi"
    LANG_DIR="/home/Shinobi/languages"


    echo -e "${CYAN}"
    echo "=============================================="
    echo "             SHINOBI LANGUAGE MANAGER"
    echo "=============================================="
    echo -e "${RESET}"


    # Obtener idiomas disponibles

    mapfile -t IDIOMAS < <(
        docker exec "$CONTAINER" bash -c \
        "ls $LANG_DIR/*.json | xargs -n1 basename | sed 's/.json//' | sort"
    )


    if [ ${#IDIOMAS[@]} -eq 0 ]; then

        echo -e "${ROJO}❌ No se encontraron idiomas${RESET}"
        read -rp "Presione ENTER para continuar..."
        return

    fi


    echo -e "${BLANCO}Idiomas disponibles:${RESET}"
    echo


    NUM=1

    for LANG in "${IDIOMAS[@]}"
    do
        echo -e "${AMARILLO}${NUM})${RESET} ${LANG}"
        ((NUM++))
    done


    echo
    echo -e "${CYAN}==============================================${RESET}"


    read -rp "Seleccione idioma: " OPCION


    if ! [[ "$OPCION" =~ ^[0-9]+$ ]]; then

        echo -e "${ROJO}❌ Opción inválida${RESET}"
        read -rp "Presione ENTER..."
        return

    fi


    if [ "$OPCION" -lt 1 ] || [ "$OPCION" -gt "${#IDIOMAS[@]}" ]; then

        echo -e "${ROJO}❌ Opción fuera de rango${RESET}"
        read -rp "Presione ENTER..."
        return

    fi


    IDIOMA="${IDIOMAS[$((OPCION-1))]}"


    echo
    echo -e "${CYAN}==============================================${RESET}"
    echo -e "${BLANCO}Idioma seleccionado:${RESET}"
    echo -e "${VERDE}$IDIOMA${RESET}"
    echo -e "${CYAN}==============================================${RESET}"
    echo


    docker exec "$CONTAINER" bash -c "
cat > /tmp/cambiar_idioma.py <<'EOF'
import json

archivo='/home/Shinobi/conf.json'

with open(archivo,'r') as f:
    config=json.load(f)

config['language']='$IDIOMA'

with open(archivo,'w') as f:
    json.dump(config,f,indent=3)

EOF

python3 /tmp/cambiar_idioma.py
"


    if [ $? -eq 0 ]; then

        echo
        echo -e "${VERDE}✔ Idioma cambiado correctamente${RESET}"
        echo -e "${BLANCO}Nuevo idioma:${RESET} ${AMARILLO}$IDIOMA${RESET}"
        echo


        read -rp "¿Reiniciar Shinobi ahora? (s/n): " REINICIAR


        if [[ "$REINICIAR" =~ ^[sS]$ ]]; then

            echo
            echo -e "${CYAN}Reiniciando Shinobi...${RESET}"

            docker restart "$CONTAINER" >/dev/null

            echo -e "${VERDE}✔ Shinobi reiniciado${RESET}"

        else

            echo -e "${AMARILLO}⚠ Reinicio pendiente${RESET}"

        fi


    else

        echo
        echo -e "${ROJO}❌ Error cambiando idioma${RESET}"

    fi


    echo
    read -rp "Presione ENTER para continuar..."

}
############################################################
# MENÚ PRINCIPAL
############################################################

menu_principal() {

    while true; do

        header

        titulo "SHINOBI MANAGER"

        echo
        echo -e " ${YELLOW}1)${NC} Instalar dependencias Docker"
        echo -e " ${YELLOW}2)${NC} Instalar Shinobi"
        echo -e " ${YELLOW}3)${NC} Estado de Shinobi"
        echo -e " ${YELLOW}4)${NC} Administrar servicios"
        echo -e " ${YELLOW}5)${NC} Ajustes"
        echo -e " ${YELLOW}6)${NC} Información"
        echo -e " ${YELLOW}7)${NC} Desinstalar Shinobi"
		echo -e " ${YELLOW}8)${NC} Cambiar Idioma es/en_CA Shinobi"
        echo
        echo -e " ${YELLOW}0)${NC} Salir"
        echo

        read -rp "Seleccione una opción: " opcion

        case "$opcion" in

            1)
                instalar_dependencias
                ;;

            2)
                instalar_shinobi
                ;;

            3)
                estado_shinobi
                ;;

            4)
                administrar_servicios
                ;;

            5)
                menu_ajustes
                ;;

            6)
                informacion
                ;;

            7)
                desinstalar_shinobi
                ;;
			
			8)
				cambiar_idioma_shinobi
				;;
			
            0)
                clear
                exit 0
                ;;

            *)
                echo
                echo -e "${RED}Opción inválida.${NC}"
                sleep 2
                ;;

        esac

    done

}

############################################################
# INICIO
############################################################

menu_principal