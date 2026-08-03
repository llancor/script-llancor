#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="${GUARDIAPRO_REPO_URL:-https://github.com/llancor/script-llancor.git}"
INSTALL_ROOT="${GUARDIAPRO_INSTALL_DIR:-$HOME/guardiapro}"
PROJECT_SUBDIR="Control_Entrada_Guardia"
APP_DIR="$SCRIPT_DIR"

# Si el instalador está separado del proyecto, reutiliza una descarga anterior.
if [[ ! -f "$APP_DIR/docker-compose.yml" && -f "$INSTALL_ROOT/$PROJECT_SUBDIR/docker-compose.yml" ]]; then
  APP_DIR="$INSTALL_ROOT/$PROJECT_SUBDIR"
fi
cd "$APP_DIR"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; B='\033[1m'; N='\033[0m'

title(){ clear; printf "${C}${B}========================================\n  GuardiaPro · Administrador Debian\n========================================${N}\n\n"; }
pause(){ printf '\nPresiona Enter para continuar...'; read -r; }
has(){ command -v "$1" >/dev/null 2>&1; }
root(){ if [[ ${EUID:-$(id -u)} -eq 0 ]]; then "$@"; else sudo "$@"; fi; }
dc(){
  if ! has docker; then printf "${R}Docker no está instalado.${N}\n"; return 1; fi
  if ! docker info >/dev/null 2>&1; then printf "${R}Docker no está accesible. Usa sudo o vuelve a iniciar sesión tras agregarte al grupo docker.${N}\n"; return 1; fi
  docker compose "$@"
}

project_ready(){ [[ -f "$APP_DIR/docker-compose.yml" && -d "$APP_DIR/backend" && -d "$APP_DIR/frontend" ]]; }

download_project(){
  if project_ready; then return 0; fi
  title
  printf "${B}Descargando Control de Seguridad desde GitHub...${N}\n\n"
  if ! has git; then
    root apt-get update || return 1
    root apt-get install -y git ca-certificates || return 1
  fi
  if [[ -d "$INSTALL_ROOT/.git" ]]; then
    printf 'Actualizando instalación existente...\n'
    git -C "$INSTALL_ROOT" pull --ff-only || return 1
  elif [[ -e "$INSTALL_ROOT" ]]; then
    printf "${R}La ruta $INSTALL_ROOT ya existe pero no es un repositorio Git.${N}\n"
    printf 'Elimínala, muévela o define otra ruta con GUARDIAPRO_INSTALL_DIR.\n'
    return 1
  else
    mkdir -p "$(dirname "$INSTALL_ROOT")" || return 1
    git clone --depth 1 --branch main "$REPO_URL" "$INSTALL_ROOT" || return 1
  fi
  APP_DIR="$INSTALL_ROOT/$PROJECT_SUBDIR"
  if [[ ! -f "$APP_DIR/docker-compose.yml" ]]; then
    printf "${R}No se encontró $PROJECT_SUBDIR/docker-compose.yml en el repositorio.${N}\n"
    return 1
  fi
  cd "$APP_DIR" || return 1
  printf "${G}Proyecto descargado en $APP_DIR.${N}\n"
}
setenv(){
  local k="$1" v="$2"; touch .env
  if grep -q "^${k}=" .env; then sed -i "s|^${k}=.*|${k}=${v}|" .env; else printf '%s=%s\n' "$k" "$v" >>.env; fi
}
getenv(){ local v; v="$(grep -E "^$1=" .env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"; printf '%s' "${v:-$2}"; }
prepare_env(){
  if [[ ! -f .env ]]; then
    if [[ -f .env.docker.example ]]; then
      cp .env.docker.example .env
    else
      printf '%s\n' \
        'MYSQL_PASSWORD=' \
        'MYSQL_ROOT_PASSWORD=' \
        'JWT_SECRET=' \
        'APP_URL=' \
        'HTTP_PORT=80' \
        'GOOGLE_CLIENT_ID=' \
        'SMTP_HOST=' \
        'SMTP_PORT=587' \
        'SMTP_USER=' \
        'SMTP_PASS=' \
        'MAIL_FROM=GuardiaPro <no-reply@guardiapro.local>' > .env
      printf "${Y}No se encontró .env.docker.example; se creó una configuración nueva.${N}\n"
    fi
    setenv MYSQL_PASSWORD "$(openssl rand -hex 24)"
    setenv MYSQL_ROOT_PASSWORD "$(openssl rand -hex 24)"
    setenv JWT_SECRET "$(openssl rand -hex 48)"
    setenv HTTP_PORT 80
    local server_ip
    server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [[ -n "$server_ip" ]] && setenv APP_URL "http://${server_ip}"
  fi
}

dependencies(){
  title; printf "${B}Instalando dependencias oficiales de Docker...${N}\n\n"
  if has docker && docker compose version >/dev/null 2>&1; then printf "${G}Docker y Compose ya están instalados.${N}\n"; return; fi
  root apt-get update || return
  root apt-get install -y ca-certificates curl git openssl || return
  root install -m 0755 -d /etc/apt/keyrings || return
  root curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc || return
  root chmod a+r /etc/apt/keyrings/docker.asc || return
  local code arch; code="$(. /etc/os-release && printf '%s' "$VERSION_CODENAME")"; arch="$(dpkg --print-architecture)"
  printf 'Types: deb\nURIs: https://download.docker.com/linux/debian\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' "$code" "$arch" | root tee /etc/apt/sources.list.d/docker.sources >/dev/null
  root apt-get update || return
  root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return
  root systemctl enable --now docker || return
  if [[ ${EUID:-$(id -u)} -ne 0 ]] && ! id -nG "$USER" | grep -qw docker; then
    root usermod -aG docker "$USER"
    printf "${Y}Usuario agregado al grupo docker. Cierra sesión y vuelve a entrar antes de continuar.${N}\n"
  else printf "${G}Dependencias listas.${N}\n"; fi
}

show_url(){
  prepare_env; local port url ip; port="$(getenv HTTP_PORT 80)"; url="$(getenv APP_URL '')"; ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf "\n${B}Puerto publicado:${N} %s\n" "$port"
  [[ -n "$url" ]] && printf "${B}URL configurada:${N} ${C}%s${N}\n" "$url"
  [[ -n "$ip" ]] && printf "${B}Acceso por IP:${N} ${C}http://%s:%s${N}\n" "$ip" "$port"
}

install_app(){
  title
  if ! has docker; then printf "${R}Primero usa la opción Instalar dependencias.${N}\n"; return; fi
  download_project || return
  title
  prepare_env; local url; printf "URL actual: ${C}%s${N}\n" "$(getenv APP_URL '')"; read -rp 'URL pública (Enter para conservar): ' url
  [[ -n "$url" ]] && setenv APP_URL "$url"
  printf "\n${B}Construyendo y arrancando GuardiaPro...${N}\n"
  if dc up -d --build; then printf "${G}Instalación terminada.${N}\n"; show_url; else printf "${R}Falló la instalación. Revisa los registros desde el menú de estado.${N}\n"; fi
}

services(){
  while true; do title; printf "${B}Estado y control del servicio${N}\n\n1) Ver estado\n2) Iniciar\n3) Detener\n4) Reiniciar\n5) Ver registros\n6) Volver\n\n"; read -rp 'Opción: ' o
    case "$o" in 1) dc ps; pause;; 2) dc up -d; pause;; 3) dc stop; pause;; 4) dc restart; pause;; 5) dc logs --tail=150; pause;; 6) return;; *) printf "${R}Opción inválida.${N}\n"; sleep 1;; esac
  done
}

port(){
  title; prepare_env; local p; printf "Puerto actual: ${C}%s${N}\n" "$(getenv HTTP_PORT 80)"; read -rp 'Nuevo puerto (1-65535): ' p
  if ! [[ "$p" =~ ^[0-9]+$ ]] || ((p<1 || p>65535)); then printf "${R}Puerto inválido.${N}\n"; return; fi
  setenv HTTP_PORT "$p"
  if dc up -d --force-recreate frontend; then printf "${G}Puerto actualizado.${N}\n"; show_url; fi
}

users(){
  while true; do title; printf "${B}Gestión de usuarios${N}\n\n1) Listar usuarios\n2) Restablecer contraseña\n3) Volver\n\n"; read -rp 'Opción: ' o
    case "$o" in
      1) dc exec -T backend node dist/src/admin-cli.js list-users; pause;;
      2)
        local email pass confirm; read -rp 'Email: ' email; read -rsp 'Nueva contraseña (mínimo 8 caracteres): ' pass; printf '\n'; read -rsp 'Confirmar contraseña: ' confirm; printf '\n'
        if [[ ${#pass} -lt 8 ]]; then printf "${R}Debe tener al menos 8 caracteres.${N}\n"; elif [[ "$pass" != "$confirm" ]]; then printf "${R}Las contraseñas no coinciden.${N}\n"; else dc exec -T backend node dist/src/admin-cli.js reset-password "$email" "$pass"; fi; pause;;
      3) return;; *) printf "${R}Opción inválida.${N}\n"; sleep 1;;
    esac
  done
}

uninstall_app(){
  title; printf "${Y}${B}Desinstalar GuardiaPro${N}\n\n1) Quitar contenedores conservando datos\n2) Quitar contenedores y ELIMINAR base de datos\n3) Cancelar\n\n"; read -rp 'Opción: ' o
  case "$o" in
    1) dc down --remove-orphans; printf "${G}Aplicación retirada; datos conservados.${N}\n";;
    2) local x; read -rp 'Escribe ELIMINAR para borrar todos los datos: ' x; if [[ "$x" == ELIMINAR ]]; then dc down -v --remove-orphans; printf "${R}Aplicación y base de datos eliminadas.${N}\n"; else printf 'Cancelado.\n'; fi;;
    *) printf 'Cancelado.\n';;
  esac
}

while true; do
  title; printf '1) Instalar dependencias\n2) Instalar Control de Seguridad\n3) Estado y control del servicio\n4) Cambiar puerto de Docker\n5) Ver URL y puerto\n6) Gestión de usuarios\n7) Desinstalar\n0) Salir\n\n'; read -rp 'Selecciona una opción: ' o
  case "$o" in 1) dependencies; pause;; 2) install_app; pause;; 3) services;; 4) port; pause;; 5) title; show_url; pause;; 6) users;; 7) uninstall_app; pause;; 0) exit 0;; *) printf "${R}Opción inválida.${N}\n"; sleep 1;; esac
done
