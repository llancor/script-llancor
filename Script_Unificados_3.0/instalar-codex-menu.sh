#!/usr/bin/env bash

# ============================================================
#  ADMINISTRADOR CODEX CLI - OpenAI
#  Instalación, autenticación y revocación por código de equipo
# ============================================================

set -uo pipefail

export PATH="$HOME/.local/bin:$PATH"

# -----------------------------
# Colores
# -----------------------------
C='\033[0;36m'   # Cyan
Y='\033[1;33m'   # Amarillo
G='\033[0;32m'   # Verde
R='\033[0;31m'   # Rojo
W='\033[1;37m'   # Blanco
D='\033[0;90m'   # Gris
N='\033[0m'      # Normal
B='\033[1m'      # Negrita

clear_screen() {
    clear 2>/dev/null || printf '\033c'
}

line() {
    printf "${D}══════════════════════════════════════════════════════${N}\n"
}

header() {
    clear_screen
    printf "${C}${B}══════════════════════════════════════════════════════${N}\n"
    printf "${C}${B}                ADMINISTRADOR CODEX CLI              ${N}\n"
    printf "${C}${B}══════════════════════════════════════════════════════${N}\n\n"
}

pause() {
    printf "\n"
    read -rp "Presiona ENTER para continuar..." _
}

codex_bin() {
    if command -v codex >/dev/null 2>&1; then
        command -v codex
    elif [[ -x "$HOME/.local/bin/codex" ]]; then
        printf '%s\n' "$HOME/.local/bin/codex"
    else
        return 1
    fi
}

codex_installed() {
    codex_bin >/dev/null 2>&1
}

show_version() {
    if codex_installed; then
        local bin
        bin="$(codex_bin)"
        printf "${G}Instalado:${N} %s\n" "$($bin --version 2>/dev/null || printf 'Codex CLI')"
        printf "${D}Ruta:${N}      %s\n" "$bin"
    else
        printf "${Y}Estado:${N}    Codex CLI no está instalado.\n"
    fi
}

install_codex() {
    header
    printf "${C}${B}INSTALAR CODEX CLI${N}\n\n"

    if codex_installed; then
        printf "${Y}Codex CLI ya está instalado.${N}\n\n"
        show_version
        printf "\n${D}Usa la opción de actualizar si quieres buscar una versión nueva.${N}\n"
        pause
        return
    fi

    if ! command -v curl >/dev/null 2>&1; then
        printf "${Y}Instalando curl...${N}\n"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y curl || {
                printf "${R}No fue posible instalar curl.${N}\n"
                pause
                return
            }
        else
            printf "${R}curl no está instalado y no se encontró apt-get.${N}\n"
            pause
            return
        fi
    fi

    printf "${Y}Descargando e instalando Codex CLI...${N}\n\n"
    if curl -fsSL https://chatgpt.com/codex/install.sh | sh; then
        export PATH="$HOME/.local/bin:$PATH"
        printf "\n${G}✓ Codex CLI instalado correctamente.${N}\n\n"
        show_version
    else
        printf "\n${R}✗ La instalación de Codex CLI falló.${N}\n"
    fi

    pause
}

update_codex() {
    header
    printf "${C}${B}ACTUALIZAR CODEX CLI${N}\n\n"

    if ! codex_installed; then
        printf "${Y}Codex CLI no está instalado.${N}\n"
        printf "Instálalo primero desde la opción 1.\n"
        pause
        return
    fi

    local bin
    bin="$(codex_bin)"

    printf "${Y}Buscando actualizaciones...${N}\n\n"
    if "$bin" update; then
        printf "\n${G}✓ Proceso de actualización finalizado.${N}\n"
    else
        printf "\n${Y}La versión instalada no pudo actualizarse con 'codex update'.${N}\n"
        printf "${D}Puedes reinstalar usando el instalador oficial si fuera necesario.${N}\n"
    fi

    pause
}

device_login() {
    header
    printf "${C}${B}AUTORIZAR ESTE EQUIPO${N}\n\n"

    if ! codex_installed; then
        printf "${R}Codex CLI no está instalado.${N}\n"
        printf "Instálalo primero desde la opción 1.\n"
        pause
        return
    fi

    local bin
    bin="$(codex_bin)"

    printf "${W}Codex mostrará a continuación:${N}\n"
    printf "  ${Y}• El enlace que debes abrir en tu navegador${N}\n"
    printf "  ${Y}• El código/número temporal de autorización${N}\n\n"
    printf "${D}Abre el enlace desde tu PC o teléfono, inicia sesión en ChatGPT\n"
    printf "e ingresa el código que aparecerá abajo.${N}\n\n"
    line
    printf "\n"

    if "$bin" login --device-auth; then
        printf "\n${G}✓ Equipo autorizado correctamente.${N}\n"
    else
        printf "\n${R}✗ No se pudo completar la autorización.${N}\n"
    fi

    pause
}

login_status() {
    header
    printf "${C}${B}ESTADO DE AUTENTICACIÓN${N}\n\n"

    if ! codex_installed; then
        printf "${R}Codex CLI no está instalado.${N}\n"
        pause
        return
    fi

    local bin
    bin="$(codex_bin)"

    show_version
    printf "\n"
    line
    printf "\n"

    if "$bin" login status; then
        printf "\n${G}✓ Codex tiene una sesión autorizada.${N}\n"
    else
        printf "\n${Y}Codex no tiene una sesión autorizada actualmente.${N}\n"
    fi

    pause
}

logout_codex() {
    header
    printf "${C}${B}REVOCAR AUTORIZACIÓN LOCAL${N}\n\n"

    if ! codex_installed; then
        printf "${R}Codex CLI no está instalado.${N}\n"
        pause
        return
    fi

    printf "${Y}Esta opción eliminará las credenciales guardadas de Codex\n"
    printf "en este equipo.${N}\n\n"
    read -rp "¿Revocar la sesión local? [s/N]: " ans

    case "$ans" in
        s|S|si|SI|sí|Sí)
            local bin
            bin="$(codex_bin)"
            if "$bin" logout; then
                printf "\n${G}✓ Autorización local revocada.${N}\n"
            else
                printf "\n${R}✗ No se pudo cerrar la sesión de Codex.${N}\n"
            fi
            ;;
        *)
            printf "\n${Y}Operación cancelada.${N}\n"
            ;;
    esac

    pause
}

recreate_device_code() {
    header
    printf "${C}${B}REVOCAR Y GENERAR NUEVO CÓDIGO${N}\n\n"

    if ! codex_installed; then
        printf "${R}Codex CLI no está instalado.${N}\n"
        pause
        return
    fi

    printf "${Y}Se cerrará la autorización actual de este equipo y luego\n"
    printf "Codex generará un nuevo enlace y un nuevo código temporal.${N}\n\n"
    read -rp "¿Continuar? [s/N]: " ans

    case "$ans" in
        s|S|si|SI|sí|Sí)
            local bin
            bin="$(codex_bin)"

            printf "\n${Y}Revocando autorización actual...${N}\n"
            "$bin" logout >/dev/null 2>&1 || true

            printf "${G}✓ Credenciales locales eliminadas.${N}\n\n"
            printf "${W}NUEVA AUTORIZACIÓN${N}\n"
            line
            printf "\n"
            printf "${Y}Copia el enlace y el código que Codex mostrará ahora:${N}\n\n"

            if "$bin" login --device-auth; then
                printf "\n${G}✓ Nuevo código autorizado correctamente.${N}\n"
            else
                printf "\n${R}✗ No se pudo completar la nueva autorización.${N}\n"
            fi
            ;;
        *)
            printf "\n${Y}Operación cancelada.${N}\n"
            ;;
    esac

    pause
}

run_codex() {
    header
    printf "${C}${B}EJECUTAR CODEX${N}\n\n"

    if ! codex_installed; then
        printf "${R}Codex CLI no está instalado.${N}\n"
        pause
        return
    fi

    local bin
    bin="$(codex_bin)"

    if ! "$bin" login status >/dev/null 2>&1; then
        printf "${Y}Codex no está autorizado en este equipo.${N}\n"
        printf "Usa primero la opción 3 para generar el enlace y código.\n"
        pause
        return
    fi

    printf "${G}Iniciando Codex...${N}\n\n"
    "$bin" || true
}

main_menu() {
    while true; do
        header
        show_version
        printf "\n"
        line
        printf "\n"
        printf "${Y}[01]${N} Instalar Codex CLI\n"
        printf "${Y}[02]${N} Actualizar Codex CLI\n"
        printf "${Y}[03]${N} Autorizar equipo - mostrar enlace y código\n"
        printf "${Y}[04]${N} Ver estado de autenticación\n"
        printf "${Y}[05]${N} Revocar autorización local\n"
        printf "${Y}[06]${N} Revocar y generar nuevo código\n"
        printf "${Y}[07]${N} Ejecutar Codex\n"
        printf "${Y}[00]${N} Salir\n"
        printf "\n"
        line
        printf "\n"
        read -rp "Selecciona una opción: " option

        case "$option" in
            1|01) install_codex ;;
            2|02) update_codex ;;
            3|03) device_login ;;
            4|04) login_status ;;
            5|05) logout_codex ;;
            6|06) recreate_device_code ;;
            7|07) run_codex ;;
            0|00) clear_screen; exit 0 ;;
            *)
                printf "\n${R}Opción inválida.${N}\n"
                sleep 1
                ;;
        esac
    done
}

main_menu
