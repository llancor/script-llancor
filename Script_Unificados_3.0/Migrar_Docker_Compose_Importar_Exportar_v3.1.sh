#!/bin/bash
# Colores
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Detecta fallos dentro de tuberías (tar | pv | gzip), pero no usa "set -e":
# un error recuperable de Docker no debe cerrar todo el menú sin avisar.
set -o pipefail

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
            if ! [[ "$N" =~ ^[0-9]+$ ]]; then
                echo "Selección ignorada: $N no es un número válido."
                continue
            fi

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
# ══════════════════════════════════════════════════════════════════════════════
# BUSCAR ARCHIVO COMPOSE
# ══════════════════════════════════════════════════════════════════════════════

buscar_compose() {

    local APP="$1"

    for ARCHIVO in \
        "$APP/docker-compose.yml" \
        "$APP/docker-compose.yaml" \
        "$APP/compose.yml" \
        "$APP/compose.yaml"
    do
        if [ -f "$ARCHIVO" ]; then
            echo "$ARCHIVO"
            return 0
        fi
    done

    return 1
}

# ══════════════════════════════════════════════════════════════════════════════
# OBTENER CONTENEDORES DEL STACK
# ══════════════════════════════════════════════════════════════════════════════

obtener_contenedores_stack() {

    local APP="$1"
    local COMPOSE="$2"

    if [ -n "$COMPOSE" ]; then
        (
            cd "$APP" || exit 1
            docker compose -f "$COMPOSE" ps -aq 2>/dev/null
        )
    fi
}


# ══════════════════════════════════════════════════════════════════════════════
# OBTENER VOLÚMENES DEL STACK
# ══════════════════════════════════════════════════════════════════════════════

obtener_volumenes_stack() {

    local APP="$1"
    local COMPOSE="$2"

    local CONTENEDORES
    local CONTENEDOR

    CONTENEDORES=$(obtener_contenedores_stack "$APP" "$COMPOSE")

    for CONTENEDOR in $CONTENEDORES
    do

        docker inspect \
            --format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
            "$CONTENEDOR" 2>/dev/null

    done | sort -u
}


# ══════════════════════════════════════════════════════════════════════════════
# RESPALDAR MYSQL / MARIADB
# ══════════════════════════════════════════════════════════════════════════════

respaldar_base_datos() {

    local APP="$1"
    local COMPOSE="$2"
    local DESTINO="$3"

    mkdir -p "$DESTINO/databases"

    local CONTENEDORES
    local CONTENEDOR
    local IMAGEN
    local NOMBRE

    CONTENEDORES=$(obtener_contenedores_stack "$APP" "$COMPOSE")

    for CONTENEDOR in $CONTENEDORES
    do

        IMAGEN=$(docker inspect \
            --format '{{.Config.Image}}' \
            "$CONTENEDOR" 2>/dev/null)

        NOMBRE=$(docker inspect \
            --format '{{.Name}}' \
            "$CONTENEDOR" 2>/dev/null | sed 's#^/##')

        if echo "$IMAGEN $NOMBRE" | grep -Eqi 'mysql|mariadb'
        then

            echo
            echo "Base de datos detectada:"
            echo "  Contenedor : $NOMBRE"
            echo "  Imagen     : $IMAGEN"
            echo

            local ROOT_PASS
            local MYSQL_USER
            local MYSQL_PASS

            ROOT_PASS=$(docker inspect \
                --format '{{range .Config.Env}}{{println .}}{{end}}' \
                "$CONTENEDOR" 2>/dev/null \
                | grep -E '^(MYSQL_ROOT_PASSWORD|MARIADB_ROOT_PASSWORD)=' \
                | head -n1 \
                | cut -d= -f2-)

            MYSQL_USER=$(docker inspect \
                --format '{{range .Config.Env}}{{println .}}{{end}}' \
                "$CONTENEDOR" 2>/dev/null \
                | grep -E '^(MYSQL_USER|MARIADB_USER)=' \
                | head -n1 \
                | cut -d= -f2-)

            MYSQL_PASS=$(docker inspect \
                --format '{{range .Config.Env}}{{println .}}{{end}}' \
                "$CONTENEDOR" 2>/dev/null \
                | grep -E '^(MYSQL_PASSWORD|MARIADB_PASSWORD)=' \
                | head -n1 \
                | cut -d= -f2-)

            echo "Creando dump SQL completo..."

            if [ -n "$ROOT_PASS" ]; then

                if docker exec "$CONTENEDOR" \
                    sh -c 'command -v mariadb-dump >/dev/null 2>&1'
                then

                    docker exec \
                        -e MYSQL_PWD="$ROOT_PASS" \
                        "$CONTENEDOR" \
                        mariadb-dump \
                        -uroot \
                        --all-databases \
                        --single-transaction \
                        --routines \
                        --events \
                        --triggers \
                        2>/dev/null \
                    | gzip \
                    > "$DESTINO/databases/${NOMBRE}-all.sql.gz"

                else

                    docker exec \
                        -e MYSQL_PWD="$ROOT_PASS" \
                        "$CONTENEDOR" \
                        mysqldump \
                        -uroot \
                        --all-databases \
                        --single-transaction \
                        --routines \
                        --events \
                        --triggers \
                        2>/dev/null \
                    | gzip \
                    > "$DESTINO/databases/${NOMBRE}-all.sql.gz"

                fi

            elif [ -n "$MYSQL_USER" ] && [ -n "$MYSQL_PASS" ]; then

                echo "No se encontró contraseña root."
                echo "Intentando respaldo con usuario $MYSQL_USER..."

                if docker exec "$CONTENEDOR" \
                    sh -c 'command -v mariadb-dump >/dev/null 2>&1'
                then

                    docker exec \
                        -e MYSQL_PWD="$MYSQL_PASS" \
                        "$CONTENEDOR" \
                        mariadb-dump \
                        -u"$MYSQL_USER" \
                        --all-databases \
                        --single-transaction \
                        --routines \
                        --events \
                        --triggers \
                        2>/dev/null \
                    | gzip \
                    > "$DESTINO/databases/${NOMBRE}-all.sql.gz"

                else

                    docker exec \
                        -e MYSQL_PWD="$MYSQL_PASS" \
                        "$CONTENEDOR" \
                        mysqldump \
                        -u"$MYSQL_USER" \
                        --all-databases \
                        --single-transaction \
                        --routines \
                        --events \
                        --triggers \
                        2>/dev/null \
                    | gzip \
                    > "$DESTINO/databases/${NOMBRE}-all.sql.gz"

                fi

            else

                echo "ADVERTENCIA:"
                echo "No se encontraron credenciales MySQL/MariaDB."
                echo "La base igualmente quedará respaldada mediante su volumen Docker."

            fi

            if [ -s "$DESTINO/databases/${NOMBRE}-all.sql.gz" ]; then
                echo "✓ Dump SQL creado correctamente."
            else
                rm -f "$DESTINO/databases/${NOMBRE}-all.sql.gz"
            fi

        fi

    done
}

exportar() {

    verificar_pv || return
    seleccionar_apps || return

    local FECHA
    local HOST
    local NOMBRE_BACKUP
    local BACKUP_BASE
    local DESTINO
    local TOTAL
    local ACTUAL

    FECHA=$(date +%Y%m%d-%H%M%S)
    HOST=$(hostname)

    echo
    read -rp "Nombre del backup [$HOST]: " NOMBRE_BACKUP

    NOMBRE_BACKUP=${NOMBRE_BACKUP:-$HOST}
    NOMBRE_BACKUP=$(echo "$NOMBRE_BACKUP" | tr ' /' '--')

    BACKUP_BASE="/root/docker-backups"
    DESTINO="${BACKUP_BASE}/${NOMBRE_BACKUP}-${FECHA}"

    mkdir -p "$DESTINO/apps"
    mkdir -p "$DESTINO/databases"
    mkdir -p "$DESTINO/volumes"
    mkdir -p "$DESTINO/info"

    > "$DESTINO/apps.list"
    > "$DESTINO/apps-paths.list"

    echo
    echo "══════════════════════════════════════════════"
    echo "       CREAR RESPALDO COMPLETO"
    echo "══════════════════════════════════════════════"
    echo
    echo "Destino:"
    echo "$DESTINO"
    echo

    TOTAL=${#SELECCIONADAS[@]}
    ACTUAL=0


    # ════════════════════════════════════════════════════════════════
    # RECORRER STACKS SELECCIONADOS
    # ════════════════════════════════════════════════════════════════

    for APP in "${SELECCIONADAS[@]}"
    do

        ACTUAL=$((ACTUAL + 1))

        local NOMBRE
        local COMPOSE=""
        local COMPOSE_REL=""
        local CONTENEDORES=""
        local SERVICIOS_ACTIVOS=""
        local VOLUMENES=""

        NOMBRE=$(basename "$APP")

        echo
        echo "══════════════════════════════════════════════"
        echo "[$ACTUAL/$TOTAL] RESPALDANDO: $NOMBRE"
        echo "══════════════════════════════════════════════"
        echo

        echo "$NOMBRE" >> "$DESTINO/apps.list"
        echo "$NOMBRE|$APP" >> "$DESTINO/apps-paths.list"

        mkdir -p "$DESTINO/databases/$NOMBRE"
        mkdir -p "$DESTINO/volumes/$NOMBRE"
        mkdir -p "$DESTINO/info/$NOMBRE"


        # ════════════════════════════════════════════════════════════
        # DETECTAR DOCKER COMPOSE
        # ════════════════════════════════════════════════════════════

        for ARCHIVO in \
            "$APP/docker-compose.yml" \
            "$APP/docker-compose.yaml" \
            "$APP/compose.yml" \
            "$APP/compose.yaml"
        do

            if [ -f "$ARCHIVO" ]; then
                COMPOSE="$ARCHIVO"
                COMPOSE_REL=$(basename "$ARCHIVO")
                break
            fi

        done


        echo "Proyecto:"
        echo "  $APP"
        echo

        if [ -n "$COMPOSE" ]; then

            echo "Docker Compose:"
            echo "  $COMPOSE_REL"

        else

            echo "Docker Compose:"
            echo "  No detectado"

        fi

        echo


        # ════════════════════════════════════════════════════════════
        # INFORMACIÓN DEL STACK
        # ════════════════════════════════════════════════════════════

        if [ -n "$COMPOSE" ]; then

            (
                cd "$APP" || exit 1

                docker compose -f "$COMPOSE_REL" ps \
                    > "$DESTINO/info/$NOMBRE/containers.txt" \
                    2>/dev/null || true

                docker compose -f "$COMPOSE_REL" config \
                    > "$DESTINO/info/$NOMBRE/compose-resolved.yml" \
                    2>/dev/null || true

                docker compose -f "$COMPOSE_REL" ps -aq \
                    > "$DESTINO/info/$NOMBRE/container-ids.txt" \
                    2>/dev/null || true
            )

            CONTENEDORES=$(
                cd "$APP" &&
                docker compose -f "$COMPOSE_REL" ps -aq 2>/dev/null
            )

            SERVICIOS_ACTIVOS=$(
                cd "$APP" &&
                docker compose -f "$COMPOSE_REL" ps \
                    --services \
                    --filter status=running \
                    2>/dev/null
            )

            printf '%s\n' "$SERVICIOS_ACTIVOS" \
                > "$DESTINO/info/$NOMBRE/running-services.txt"

        fi


        # ════════════════════════════════════════════════════════════
        # DETECTAR Y RESPALDAR BASES DE DATOS
        # ════════════════════════════════════════════════════════════

        echo
        echo "══════════════════════════════════════════════"
        echo " DETECTANDO BASES DE DATOS"
        echo "══════════════════════════════════════════════"
        echo

        local DB_DETECTADA=0

        for CONTENEDOR in $CONTENEDORES
        do

            [ -z "$CONTENEDOR" ] && continue

            local IMAGEN
            local CNOMBRE

            IMAGEN=$(docker inspect \
                --format '{{.Config.Image}}' \
                "$CONTENEDOR" 2>/dev/null)

            CNOMBRE=$(docker inspect \
                --format '{{.Name}}' \
                "$CONTENEDOR" 2>/dev/null | sed 's#^/##')


            # ────────────────────────────────────────────────────────
            # MYSQL / MARIADB
            # ────────────────────────────────────────────────────────

            if echo "$IMAGEN $CNOMBRE" | grep -Eqi 'mysql|mariadb'
            then

                DB_DETECTADA=1

                echo "[✓] MySQL / MariaDB"
                echo "    Contenedor : $CNOMBRE"
                echo "    Imagen     : $IMAGEN"

                local ROOT_PASS
                local MYSQL_USER
                local MYSQL_PASS
                local ARCHIVO_SQL

                ROOT_PASS=$(
                    docker inspect \
                        --format '{{range .Config.Env}}{{println .}}{{end}}' \
                        "$CONTENEDOR" 2>/dev/null |
                    grep -E '^(MYSQL_ROOT_PASSWORD|MARIADB_ROOT_PASSWORD)=' |
                    head -n1 |
                    cut -d= -f2-
                )

                MYSQL_USER=$(
                    docker inspect \
                        --format '{{range .Config.Env}}{{println .}}{{end}}' \
                        "$CONTENEDOR" 2>/dev/null |
                    grep -E '^(MYSQL_USER|MARIADB_USER)=' |
                    head -n1 |
                    cut -d= -f2-
                )

                MYSQL_PASS=$(
                    docker inspect \
                        --format '{{range .Config.Env}}{{println .}}{{end}}' \
                        "$CONTENEDOR" 2>/dev/null |
                    grep -E '^(MYSQL_PASSWORD|MARIADB_PASSWORD)=' |
                    head -n1 |
                    cut -d= -f2-
                )

                ARCHIVO_SQL="$DESTINO/databases/$NOMBRE/${CNOMBRE}-mysql-all.sql.gz"

                rm -f "$ARCHIVO_SQL"

                echo "    Creando dump SQL..."

                if [ -n "$ROOT_PASS" ]; then

                    if docker exec "$CONTENEDOR" \
                        sh -c 'command -v mariadb-dump >/dev/null 2>&1'
                    then

                        docker exec \
                            -e MYSQL_PWD="$ROOT_PASS" \
                            "$CONTENEDOR" \
                            mariadb-dump \
                            -uroot \
                            --all-databases \
                            --single-transaction \
                            --routines \
                            --events \
                            --triggers \
                            2>/dev/null |
                        gzip > "$ARCHIVO_SQL"

                    elif docker exec "$CONTENEDOR" \
                        sh -c 'command -v mysqldump >/dev/null 2>&1'
                    then

                        docker exec \
                            -e MYSQL_PWD="$ROOT_PASS" \
                            "$CONTENEDOR" \
                            mysqldump \
                            -uroot \
                            --all-databases \
                            --single-transaction \
                            --routines \
                            --events \
                            --triggers \
                            2>/dev/null |
                        gzip > "$ARCHIVO_SQL"

                    fi


                elif [ -n "$MYSQL_USER" ] && [ -n "$MYSQL_PASS" ]; then

                    if docker exec "$CONTENEDOR" \
                        sh -c 'command -v mariadb-dump >/dev/null 2>&1'
                    then

                        docker exec \
                            -e MYSQL_PWD="$MYSQL_PASS" \
                            "$CONTENEDOR" \
                            mariadb-dump \
                            -u"$MYSQL_USER" \
                            --all-databases \
                            --single-transaction \
                            --routines \
                            --events \
                            --triggers \
                            2>/dev/null |
                        gzip > "$ARCHIVO_SQL"

                    elif docker exec "$CONTENEDOR" \
                        sh -c 'command -v mysqldump >/dev/null 2>&1'
                    then

                        docker exec \
                            -e MYSQL_PWD="$MYSQL_PASS" \
                            "$CONTENEDOR" \
                            mysqldump \
                            -u"$MYSQL_USER" \
                            --all-databases \
                            --single-transaction \
                            --routines \
                            --events \
                            --triggers \
                            2>/dev/null |
                        gzip > "$ARCHIVO_SQL"

                    fi

                fi


                if [ -s "$ARCHIVO_SQL" ]; then

                    echo "    ✓ Dump SQL creado"

                else

                    rm -f "$ARCHIVO_SQL"

                    echo "    ⚠ No fue posible crear dump lógico."
                    echo "      Se respaldará igualmente el volumen."

                fi

                echo

            fi


            # ────────────────────────────────────────────────────────
            # POSTGRESQL
            # ────────────────────────────────────────────────────────

            if echo "$IMAGEN $CNOMBRE" | grep -Eqi 'postgres|postgresql'
            then

                DB_DETECTADA=1

                echo "[✓] PostgreSQL"
                echo "    Contenedor : $CNOMBRE"
                echo "    Imagen     : $IMAGEN"

                local POSTGRES_USER
                local POSTGRES_PASSWORD
                local ARCHIVO_POSTGRES

                POSTGRES_USER=$(
                    docker inspect \
                        --format '{{range .Config.Env}}{{println .}}{{end}}' \
                        "$CONTENEDOR" 2>/dev/null |
                    grep '^POSTGRES_USER=' |
                    head -n1 |
                    cut -d= -f2-
                )

                POSTGRES_PASSWORD=$(
                    docker inspect \
                        --format '{{range .Config.Env}}{{println .}}{{end}}' \
                        "$CONTENEDOR" 2>/dev/null |
                    grep '^POSTGRES_PASSWORD=' |
                    head -n1 |
                    cut -d= -f2-
                )

                POSTGRES_USER=${POSTGRES_USER:-postgres}

                ARCHIVO_POSTGRES="$DESTINO/databases/$NOMBRE/${CNOMBRE}-postgres-all.sql.gz"

                rm -f "$ARCHIVO_POSTGRES"

                echo "    Usuario    : $POSTGRES_USER"
                echo "    Creando pg_dumpall..."

                if [ -n "$POSTGRES_PASSWORD" ]; then

                    docker exec \
                        -e PGPASSWORD="$POSTGRES_PASSWORD" \
                        "$CONTENEDOR" \
                        pg_dumpall \
                        -U "$POSTGRES_USER" \
                        2>/dev/null |
                    gzip > "$ARCHIVO_POSTGRES"

                else

                    docker exec \
                        "$CONTENEDOR" \
                        pg_dumpall \
                        -U "$POSTGRES_USER" \
                        2>/dev/null |
                    gzip > "$ARCHIVO_POSTGRES"

                fi


                if [ -s "$ARCHIVO_POSTGRES" ]; then

                    echo "    ✓ Dump PostgreSQL creado"

                else

                    rm -f "$ARCHIVO_POSTGRES"

                    echo "    ⚠ No fue posible crear pg_dumpall."
                    echo "      Se respaldará igualmente el volumen."

                fi

                echo

            fi

        done


        if [ "$DB_DETECTADA" -eq 0 ]; then
            echo "No se detectaron bases MySQL, MariaDB o PostgreSQL."
            echo
        fi


        # ════════════════════════════════════════════════════════════
        # DETECTAR VOLÚMENES DEL STACK
        # ════════════════════════════════════════════════════════════

        for CONTENEDOR in $CONTENEDORES
        do

            docker inspect \
                --format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
                "$CONTENEDOR" \
                2>/dev/null

        done |
        sort -u |
        sed '/^$/d' \
            > "$DESTINO/info/$NOMBRE/volumes.list"


        VOLUMENES=$(cat "$DESTINO/info/$NOMBRE/volumes.list" 2>/dev/null)


        # ════════════════════════════════════════════════════════════
        # DETENER STACK PARA COPIA CONSISTENTE
        # ════════════════════════════════════════════════════════════

        if [ -n "$COMPOSE" ] && [ -n "$SERVICIOS_ACTIVOS" ]; then

            echo
            echo "Deteniendo temporalmente el stack..."
            echo

            (
                cd "$APP" || exit 1
                docker compose -f "$COMPOSE_REL" stop
            )

        fi


        # ════════════════════════════════════════════════════════════
        # RESPALDAR CARPETA COMPLETA
        # ════════════════════════════════════════════════════════════

        echo
        echo "Respaldando archivos del proyecto..."
        echo
        echo " ✓ Frontend"
        echo " ✓ Backend"
        echo " ✓ Docker Compose"
        echo " ✓ Archivo .env"
        echo " ✓ Dockerfile"
        echo " ✓ Configuración"
        echo " ✓ Código fuente"
        echo

        local SIZE_APP

        SIZE_APP=$(du -sb "$APP" 2>/dev/null | awk '{print $1}')
        SIZE_APP=${SIZE_APP:-0}

        tar cf - \
            -C "$(dirname "$APP")" \
            "$NOMBRE" \
        | pv -petrab -s "$SIZE_APP" \
        | gzip \
        > "$DESTINO/apps/${NOMBRE}.tar.gz"


        # ════════════════════════════════════════════════════════════
        # RESPALDAR VOLÚMENES DEL STACK
        # ════════════════════════════════════════════════════════════

        echo
        echo "══════════════════════════════════════════════"
        echo " RESPALDANDO VOLÚMENES DOCKER"
        echo "══════════════════════════════════════════════"
        echo

        if [ -n "$VOLUMENES" ]; then

            while IFS= read -r VOLUMEN
            do

                [ -z "$VOLUMEN" ] && continue

                local MOUNTPOINT
                local SIZE_VOL

                MOUNTPOINT=$(docker volume inspect \
                    "$VOLUMEN" \
                    --format '{{.Mountpoint}}' \
                    2>/dev/null)

                if [ -z "$MOUNTPOINT" ] || [ ! -d "$MOUNTPOINT" ]; then

                    echo " ⚠ No se pudo acceder al volumen: $VOLUMEN"
                    continue

                fi

                echo " → $VOLUMEN"

                SIZE_VOL=$(du -sb "$MOUNTPOINT" 2>/dev/null | awk '{print $1}')
                SIZE_VOL=${SIZE_VOL:-0}

                tar cf - \
                    -C "$MOUNTPOINT" \
                    . \
                | pv -petrab -s "$SIZE_VOL" \
                | gzip \
                > "$DESTINO/volumes/$NOMBRE/${VOLUMEN}.tar.gz"

            done < "$DESTINO/info/$NOMBRE/volumes.list"

        else

            echo "No se detectaron volúmenes Docker."

        fi


        # ════════════════════════════════════════════════════════════
        # VOLVER A LEVANTAR STACK
        # ════════════════════════════════════════════════════════════

        if [ -n "$COMPOSE" ] && [ -n "$SERVICIOS_ACTIVOS" ]; then

            echo
            echo "Reiniciando servicios..."
            echo

            (
                cd "$APP" || exit 1

                while IFS= read -r SERVICIO
                do
                    [ -z "$SERVICIO" ] && continue

                    docker compose \
                        -f "$COMPOSE_REL" \
                        start "$SERVICIO"

                done <<< "$SERVICIOS_ACTIVOS"
            )

        fi

        echo
        echo "✓ $NOMBRE respaldado correctamente."
        echo

    done


    # ════════════════════════════════════════════════════════════════
    # CONFIGURACIÓN GENERAL DOCKER
    # ════════════════════════════════════════════════════════════════

    echo
    echo "══════════════════════════════════════════════"
    echo " GUARDANDO CONFIGURACIÓN DOCKER"
    echo "══════════════════════════════════════════════"
    echo

    if [ -d /etc/docker ]; then

        tar czf \
            "$DESTINO/docker-config.tar.gz" \
            -C / \
            etc/docker

        echo "✓ /etc/docker"

    else

        echo "No existe /etc/docker"

    fi


    # ════════════════════════════════════════════════════════════════
    # LET'S ENCRYPT
    # ════════════════════════════════════════════════════════════════

    echo
    echo "══════════════════════════════════════════════"
    echo " GUARDANDO CERTIFICADOS SSL"
    echo "══════════════════════════════════════════════"
    echo

    if [ -d /etc/letsencrypt ]; then

        tar czf \
            "$DESTINO/letsencrypt.tar.gz" \
            -C / \
            etc/letsencrypt

        echo "✓ /etc/letsencrypt"

    else

        echo "No existe /etc/letsencrypt"

    fi


    # ════════════════════════════════════════════════════════════════
    # INFORMACIÓN DEL SERVIDOR
    # ════════════════════════════════════════════════════════════════

    docker network ls \
        > "$DESTINO/info/docker-networks.txt" \
        2>/dev/null || true

    docker volume ls \
        > "$DESTINO/info/docker-volumes.txt" \
        2>/dev/null || true

    docker ps -a \
        > "$DESTINO/info/docker-containers.txt" \
        2>/dev/null || true

    docker images \
        > "$DESTINO/info/docker-images.txt" \
        2>/dev/null || true

    docker version \
        > "$DESTINO/info/docker-version.txt" \
        2>/dev/null || true

    docker compose version \
        > "$DESTINO/info/docker-compose-version.txt" \
        2>/dev/null || true

    uname -a \
        > "$DESTINO/info/system-info.txt" \
        2>/dev/null || true

    hostname \
        > "$DESTINO/info/hostname.txt" \
        2>/dev/null || true

    date \
        > "$DESTINO/info/backup-date.txt" \
        2>/dev/null || true


    echo
    echo "══════════════════════════════════════════════"
    echo "       RESPALDO COMPLETADO"
    echo "══════════════════════════════════════════════"
    echo

    echo "Ubicación:"
    echo "$DESTINO"
    echo

    echo "Tamaño final:"
    du -sh "$DESTINO"
    echo
}
importar() {

    local BACKUP_BASE="/root/docker-backups"
    local RESPALDO
    local OPCION
    local CONFIRMAR

    # ════════════════════════════════════════════════════════════════
    # VERIFICAR BACKUPS
    # ════════════════════════════════════════════════════════════════

    if [ ! -d "$BACKUP_BASE" ]; then

        echo
        echo "No existe el directorio:"
        echo "$BACKUP_BASE"
        echo
        return 1

    fi


    mapfile -t BACKUPS < <(
        find "$BACKUP_BASE" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -printf '%f\n' \
            2>/dev/null |
        sort -r
    )


    if [ "${#BACKUPS[@]}" -eq 0 ]; then

        echo
        echo "No existen respaldos disponibles."
        echo
        return 1

    fi


    # ════════════════════════════════════════════════════════════════
    # MOSTRAR RESPALDOS
    # ════════════════════════════════════════════════════════════════

    echo
    echo "══════════════════════════════════════════════"
    echo "       RESPALDOS DISPONIBLES"
    echo "══════════════════════════════════════════════"
    echo

    local I=1

    for BACKUP in "${BACKUPS[@]}"
    do

        printf "[%02d] %s\n" "$I" "$BACKUP"

        I=$((I + 1))

    done

    echo
    echo "[0] Cancelar"
    echo

    read -rp "Seleccione respaldo: " OPCION


    if [ "$OPCION" = "0" ]; then
        return
    fi


    if ! [[ "$OPCION" =~ ^[0-9]+$ ]]; then

        echo
        echo "Opción inválida."
        return 1

    fi


    if [ "$OPCION" -lt 1 ] || \
       [ "$OPCION" -gt "${#BACKUPS[@]}" ]; then

        echo
        echo "Opción inválida."
        return 1

    fi


    RESPALDO="$BACKUP_BASE/${BACKUPS[$((OPCION - 1))]}"


    # ════════════════════════════════════════════════════════════════
    # VALIDAR BACKUP
    # ════════════════════════════════════════════════════════════════

    if [ ! -f "$RESPALDO/apps.list" ]; then

        echo
        echo "ERROR:"
        echo "El respaldo no contiene apps.list"
        echo
        return 1

    fi


    echo
    echo "══════════════════════════════════════════════"
    echo "       RESTAURAR RESPALDO COMPLETO"
    echo "══════════════════════════════════════════════"
    echo

    echo "Respaldo:"
    echo "$RESPALDO"
    echo

    echo "Stacks incluidos:"
    echo

    nl -w2 -s') ' "$RESPALDO/apps.list"

    echo

    read -rp "¿Continuar con la restauración? [s/N]: " CONFIRMAR


    case "$CONFIRMAR" in

        s|S|si|SI|Si)
            ;;

        *)
            echo
            echo "Restauración cancelada."
            return
            ;;

    esac


    # ════════════════════════════════════════════════════════════════
    # RESTAURAR STACKS
    # ════════════════════════════════════════════════════════════════

    while IFS= read -r NOMBRE
    do

        [ -z "$NOMBRE" ] && continue

        local DESTINO_APP="/opt/$NOMBRE"
        local ARCHIVO_APP="$RESPALDO/apps/${NOMBRE}.tar.gz"
        local COMPOSE=""
        local COMPOSE_REL=""
        local LISTA_VOL="$RESPALDO/info/$NOMBRE/volumes.list"


        # Intentar obtener la ruta original
        if [ -f "$RESPALDO/apps-paths.list" ]; then

            local RUTA_ORIGINAL

            RUTA_ORIGINAL=$(
                grep "^${NOMBRE}|" \
                    "$RESPALDO/apps-paths.list" |
                head -n1 |
                cut -d'|' -f2-
            )

            if [ -n "$RUTA_ORIGINAL" ]; then
                DESTINO_APP="$RUTA_ORIGINAL"
            fi

        fi


        echo
        echo "══════════════════════════════════════════════"
        echo " RESTAURANDO: $NOMBRE"
        echo "══════════════════════════════════════════════"
        echo

        echo "Destino:"
        echo "$DESTINO_APP"
        echo


        # ════════════════════════════════════════════════════════════
        # DETENER STACK EXISTENTE
        # ════════════════════════════════════════════════════════════

        if [ -d "$DESTINO_APP" ]; then

            for ARCHIVO in \
                "$DESTINO_APP/docker-compose.yml" \
                "$DESTINO_APP/docker-compose.yaml" \
                "$DESTINO_APP/compose.yml" \
                "$DESTINO_APP/compose.yaml"
            do

                if [ -f "$ARCHIVO" ]; then

                    COMPOSE="$ARCHIVO"
                    COMPOSE_REL=$(basename "$ARCHIVO")
                    break

                fi

            done


            if [ -n "$COMPOSE" ]; then

                echo "Deteniendo stack existente..."
                echo

                (
                    cd "$DESTINO_APP" || exit 1

                    docker compose \
                        -f "$COMPOSE_REL" \
                        down
                ) 2>/dev/null || true

            fi

        fi


        # ════════════════════════════════════════════════════════════
        # RESPALDAR INSTALACIÓN ACTUAL ANTES DE SOBRESCRIBIR
        # ════════════════════════════════════════════════════════════

        if [ -d "$DESTINO_APP" ]; then

            local ANTERIOR

            ANTERIOR="${DESTINO_APP}.antes-restauracion-$(date +%Y%m%d-%H%M%S)"

            echo "Guardando instalación actual:"
            echo "$ANTERIOR"
            echo

            mv "$DESTINO_APP" "$ANTERIOR"

        fi


        # ════════════════════════════════════════════════════════════
        # RESTAURAR FRONTEND / BACKEND / COMPOSE / ENV
        # ════════════════════════════════════════════════════════════

        if [ ! -f "$ARCHIVO_APP" ]; then

            echo "ERROR:"
            echo "No existe:"
            echo "$ARCHIVO_APP"
            echo

            continue

        fi


        echo "Restaurando archivos del proyecto..."
        echo

        mkdir -p "$(dirname "$DESTINO_APP")"


        # El tar contiene la carpeta con el nombre del stack
        tar xzf \
            "$ARCHIVO_APP" \
            -C "$(dirname "$DESTINO_APP")"


        echo "✓ Frontend"
        echo "✓ Backend"
        echo "✓ Docker Compose"
        echo "✓ Archivo .env"
        echo "✓ Configuración"
        echo


        # ════════════════════════════════════════════════════════════
        # DETECTAR COMPOSE RESTAURADO
        # ════════════════════════════════════════════════════════════

        COMPOSE=""
        COMPOSE_REL=""

        for ARCHIVO in \
            "$DESTINO_APP/docker-compose.yml" \
            "$DESTINO_APP/docker-compose.yaml" \
            "$DESTINO_APP/compose.yml" \
            "$DESTINO_APP/compose.yaml"
        do

            if [ -f "$ARCHIVO" ]; then

                COMPOSE="$ARCHIVO"
                COMPOSE_REL=$(basename "$ARCHIVO")
                break

            fi

        done


        # ════════════════════════════════════════════════════════════
        # CREAR VOLÚMENES QUE DEFINE COMPOSE
        # ════════════════════════════════════════════════════════════

        if [ -n "$COMPOSE" ]; then

            echo
            echo "Preparando volúmenes Docker..."
            echo

            (
                cd "$DESTINO_APP" || exit 1

                # Crea redes y volúmenes sin necesidad
                # de dejar permanentemente los servicios ejecutándose.
                docker compose \
                    -f "$COMPOSE_REL" \
                    create \
                    2>/dev/null || true
            )

        fi


        # ════════════════════════════════════════════════════════════
        # RESTAURAR VOLÚMENES
        # ════════════════════════════════════════════════════════════

        echo
        echo "══════════════════════════════════════════════"
        echo " RESTAURANDO VOLÚMENES"
        echo "══════════════════════════════════════════════"
        echo


        if [ -f "$LISTA_VOL" ]; then

            while IFS= read -r VOLUMEN
            do

                [ -z "$VOLUMEN" ] && continue

                local ARCHIVO_VOL
                local MOUNTPOINT

                ARCHIVO_VOL="$RESPALDO/volumes/$NOMBRE/${VOLUMEN}.tar.gz"


                if [ ! -f "$ARCHIVO_VOL" ]; then

                    echo "⚠ No existe backup del volumen:"
                    echo "  $VOLUMEN"
                    continue

                fi


                if ! docker volume inspect "$VOLUMEN" >/dev/null 2>&1; then

                    echo "Creando volumen:"
                    echo "  $VOLUMEN"

                    docker volume create "$VOLUMEN" >/dev/null

                fi


                MOUNTPOINT=$(docker volume inspect \
                    "$VOLUMEN" \
                    --format '{{.Mountpoint}}' \
                    2>/dev/null)


                if [ -z "$MOUNTPOINT" ] || [ ! -d "$MOUNTPOINT" ]; then

                    echo "⚠ No se pudo localizar:"
                    echo "  $VOLUMEN"
                    continue

                fi


                echo "Restaurando:"
                echo "  $VOLUMEN"


                # Limpiar contenido actual
                find "$MOUNTPOINT" \
                    -mindepth 1 \
                    -maxdepth 1 \
                    -exec rm -rf -- {} +


                # Restaurar contenido
                tar xzf \
                    "$ARCHIVO_VOL" \
                    -C "$MOUNTPOINT"


                echo "✓ $VOLUMEN"
                echo

            done < "$LISTA_VOL"

        else

            echo "No existe lista de volúmenes para este stack."

        fi


        # ════════════════════════════════════════════════════════════
        # MOSTRAR DUMPS DISPONIBLES
        # ════════════════════════════════════════════════════════════

        if [ -d "$RESPALDO/databases/$NOMBRE" ]; then

            local NUM_DUMPS

            NUM_DUMPS=$(
                find "$RESPALDO/databases/$NOMBRE" \
                    -type f \
                    -name '*.sql.gz' \
                    2>/dev/null |
                wc -l
            )


            if [ "$NUM_DUMPS" -gt 0 ]; then

                echo
                echo "Copias lógicas de base de datos disponibles:"
                echo

                find "$RESPALDO/databases/$NOMBRE" \
                    -type f \
                    -name '*.sql.gz' \
                    -printf '  ✓ %f\n'

                echo
                echo "La restauración completa utiliza los"
                echo "volúmenes Docker originales."
                echo
                echo "Los .sql.gz quedan como respaldo adicional."

            fi

        fi


        # ════════════════════════════════════════════════════════════
        # DESCARGAR / CONSTRUIR / INICIAR
        # ════════════════════════════════════════════════════════════

        if [ -n "$COMPOSE" ]; then

            echo
            echo "══════════════════════════════════════════════"
            echo " PREPARANDO IMÁGENES DOCKER"
            echo "══════════════════════════════════════════════"
            echo

            echo "Las imágenes que no existan serán descargadas."
            echo "Las imágenes con build: serán reconstruidas."
            echo


            (
                cd "$DESTINO_APP" || exit 1


                # Descargar imágenes remotas.
                # Si existen servicios build:, pull puede avisar
                # que no tiene imagen; eso no impide continuar.
                docker compose \
                    -f "$COMPOSE_REL" \
                    pull \
                    --ignore-buildable \
                    2>/dev/null || true


                echo
                echo "Construyendo imágenes locales..."
                echo

                docker compose \
                    -f "$COMPOSE_REL" \
                    build \
                    2>/dev/null || true


                echo
                echo "Iniciando stack..."
                echo

                docker compose \
                    -f "$COMPOSE_REL" \
                    up -d \
                    --build
            )


            echo
            echo "Esperando verificación inicial..."
            sleep 3

            echo
            echo "Estado:"
            echo

            (
                cd "$DESTINO_APP" || exit 1

                docker compose \
                    -f "$COMPOSE_REL" \
                    ps
            )

        else

            echo
            echo "⚠ No se encontró Docker Compose."
            echo "  Los archivos y volúmenes fueron restaurados,"
            echo "  pero el stack no pudo iniciarse automáticamente."

        fi


        echo
        echo "══════════════════════════════════════════════"
        echo " ✓ $NOMBRE RESTAURADO"
        echo "══════════════════════════════════════════════"
        echo

    done < "$RESPALDO/apps.list"


    # ════════════════════════════════════════════════════════════════
    # CONFIGURACIÓN DOCKER
    # ════════════════════════════════════════════════════════════════

    if [ -f "$RESPALDO/docker-config.tar.gz" ]; then

        echo
        echo "Existe respaldo de /etc/docker."
        echo

        read -rp "¿Restaurar configuración Docker? [s/N]: " RESP


        case "$RESP" in

            s|S|si|SI|Si)

                local DOCKER_ANTERIOR

                DOCKER_ANTERIOR="/root/docker-config-anterior-$(date +%Y%m%d-%H%M%S)"

                mkdir -p "$DOCKER_ANTERIOR"


                if [ -d /etc/docker ]; then

                    cp -a \
                        /etc/docker/. \
                        "$DOCKER_ANTERIOR/" \
                        2>/dev/null || true

                fi


                tar xzf \
                    "$RESPALDO/docker-config.tar.gz" \
                    -C /


                echo
                echo "✓ Configuración Docker restaurada."
                echo

                ;;

        esac

    fi


    # ════════════════════════════════════════════════════════════════
    # LET'S ENCRYPT
    # ════════════════════════════════════════════════════════════════

    if [ -f "$RESPALDO/letsencrypt.tar.gz" ]; then

        echo
        echo "Existe respaldo de certificados Let's Encrypt."
        echo

        read -rp "¿Restaurar certificados SSL? [s/N]: " RESP


        case "$RESP" in

            s|S|si|SI|Si)

                if [ -d /etc/letsencrypt ]; then

                    mv \
                        /etc/letsencrypt \
                        "/etc/letsencrypt.antes-restauracion-$(date +%Y%m%d-%H%M%S)"

                fi


                tar xzf \
                    "$RESPALDO/letsencrypt.tar.gz" \
                    -C /


                echo
                echo "✓ Certificados SSL restaurados."
                echo

                ;;

        esac

    fi


    echo
    echo "══════════════════════════════════════════════"
    echo "       RESTAURACIÓN COMPLETADA"
    echo "══════════════════════════════════════════════"
    echo

    echo "Contenedores actuales:"
    echo

    docker ps \
        --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

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

    return
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
gestionar_contenedores() {

    if ! command -v docker >/dev/null 2>&1; then
        echo
        echo -e "${RED}Docker no está instalado.${NC}"
        echo
        return
    fi

    if ! docker info >/dev/null 2>&1; then
        echo
        echo -e "${RED}Docker no está iniciado o no responde.${NC}"
        echo
        return
    fi

    mapfile -t CONTENEDORES < <(
        docker ps -a --format '{{.Names}}' | sort
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
    echo "I) Iniciar"
    echo "D) Detener"
    echo "R) Reiniciar"
    echo "0) Volver al menú"
    echo

    read -rp "Acción: " ACCION

    case "${ACCION^^}" in
        I) COMANDO="start"; DESCRIPCION="Iniciando" ;;
        D) COMANDO="stop"; DESCRIPCION="Deteniendo" ;;
        R) COMANDO="restart"; DESCRIPCION="Reiniciando" ;;
        0) return ;;
        *) echo -e "${RED}Acción no válida.${NC}"; return ;;
    esac

    echo
    read -rp "Contenedores (ej: 1 3 5 o A para todos): " SELECCION

    SELECCIONADOS=()

    if [[ "$SELECCION" =~ ^[Aa]$ ]]; then
        SELECCIONADOS=("${CONTENEDORES[@]}")
    else
        for N in $SELECCION
        do
            if ! [[ "$N" =~ ^[0-9]+$ ]]; then
                echo -e "${YELLOW}Selección ignorada: $N${NC}"
                continue
            fi

            IDX=$((N-1))
            if [ "$IDX" -ge 0 ] && [ "$IDX" -lt "${#CONTENEDORES[@]}" ]; then
                SELECCIONADOS+=("${CONTENEDORES[$IDX]}")
            else
                echo -e "${YELLOW}Número fuera de rango: $N${NC}"
            fi
        done
    fi

    if [ ${#SELECCIONADOS[@]} -eq 0 ]; then
        echo -e "${RED}No se seleccionó ningún contenedor.${NC}"
        return
    fi

    echo
    echo -e "${CYAN}${DESCRIPCION} contenedores...${NC}"
    echo

    for CONT in "${SELECCIONADOS[@]}"
    do
        echo -ne "→ $CONT ... "

        if docker "$COMANDO" "$CONT" >/dev/null 2>&1; then
            NUEVO_ESTADO=$(docker inspect --format='{{.State.Status}}' "$CONT" 2>/dev/null || echo "desconocido")
            echo -e "${GREEN}OK${NC} (${NUEVO_ESTADO})"
        else
            echo -e "${RED}ERROR${NC}"
        fi
    done

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
}
while true
do

    clear

echo
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          MIGRADOR DOCKER /OPT   v3.1         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo
echo -e "${YELLOW}[1]${GREEN} Exportar aplicaciones Fronted/Backend/DB"
echo -e "${YELLOW}[2]${GREEN} Importar aplicaciones Fronted/Backend/DB"
echo -e "${YELLOW} *"
echo -e "${YELLOW}[3]${CYAN} Listar aplicaciones"
echo -e "${YELLOW}[4]${CYAN} Instalar Docker Compose"
echo -e "${YELLOW} *"
echo -e "${YELLOW}[5]${YELLOW} Eliminar Docker + Contenedor - ${YELLOW}Selección"
echo -e "${YELLOW}[6]${YELLOW} Eliminar Docker + Contenedor - ${YELLOW}Todos"
echo -e "${YELLOW} *"
echo -e "${YELLOW}[7]${YELLOW} Desinstalar Docker Compose - ${YELLOW}Completo"
echo -e "${YELLOW}[8]${YELLOW} Eliminar Contenedores - ${YELLOW}Sin Uso"
echo -e "${YELLOW}[9]${YELLOW} Eliminar Red Docker - ${YELLOW}Sin Uso"
echo -e "${YELLOW} *"
echo -e "${YELLOW}[10]${CYAN} Estado de Docker ${CYAN}/ IP:PUERTO"
echo -e "${YELLOW}[11]${CYAN} Detener/Iniciar/Reiniciar Contenedores ${CYAN}/ Ver Estados"
echo -e "${YELLOW} *"
echo -e "${CYAN}[0]${CYAN} Salir"
echo -e "${YELLOW} *"
echo -ne "${YELLOW}Opción:${NC} "
read -r OP

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
            gestionar_contenedores
            read -rp "ENTER..."
            ;;
			
				
        0)
            exit 0
            ;;

    esac

done
