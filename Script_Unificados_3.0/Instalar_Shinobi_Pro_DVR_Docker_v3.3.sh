#!/usr/bin/env bash
set -u

APP_NAME="Shinobi"
APP_VERSION="3.3"
BASE_DIR="/opt/shinobi"
DATA_HOME="$BASE_DIR/data"
REPO_URL="https://gitlab.com/Shinobi-Systems/ShinobiDocker.git"
MAIN_COMPOSE="$BASE_DIR/docker-compose-main.yml"
SQL_COMPOSE="$BASE_DIR/docker-compose-sql.yml"
CONTAINER_MAIN="shinobi-shinobi-1"
HTTP_PORT="8080"
TZ="America/Santiago"
CRED_FILE="/root/shinobi-superusuario.txt"
DEFAULT_SUPER_USER="admin@shinobi.video"
DEFAULT_SUPER_PASS="admin"

RED='\e[91m'; GREEN='\e[92m'; YELLOW='\e[93m'; CYAN='\e[96m'; WHITE='\e[97m'; NC='\e[0m'

header(){ clear; echo -e "${CYAN}============================================================${NC}"; echo -e "${CYAN}                  SHINOBI MANAGER${NC}"; echo -e "${CYAN}                      Versión $APP_VERSION${NC}"; echo -e "${CYAN}============================================================${NC}"; echo; }
titulo(){ echo -e "${CYAN}============== ${YELLOW}$1${CYAN} ==============${NC}"; echo; }
pause(){ echo; echo -e "${YELLOW}Presione ENTER para continuar...${NC}"; read -r; }
need_root(){ if [[ ${EUID:-$(id -u)} -ne 0 ]]; then echo -e "${RED}Ejecute este script como root.${NC}"; exit 1; fi; }

compose(){ ( cd "$BASE_DIR" && HOME="$DATA_HOME" docker compose -f "$SQL_COMPOSE" -f "$MAIN_COMPOSE" "$@" ); }

get_port(){
  if [[ -f "$MAIN_COMPOSE" ]]; then
    local p
    p=$(grep -E '^[[:space:]]*-[[:space:]]*"?[0-9]+:8080"?' "$MAIN_COMPOSE" 2>/dev/null | head -n1 | sed -E 's/.*"?([0-9]+):8080"?.*/\1/')
    [[ -n "$p" ]] && HTTP_PORT="$p"
  fi
}

instalar_dependencias(){
  header; titulo "INSTALAR DEPENDENCIAS"
  apt-get update || { echo -e "${RED}Error ejecutando apt update.${NC}"; pause; return 1; }
  apt-get install -y ca-certificates curl gnupg git || { echo -e "${RED}Error instalando dependencias base.${NC}"; pause; return 1; }
  if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg || return 1
    chmod a+r /etc/apt/keyrings/docker.gpg
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
    apt-get update || return 1
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 1
    systemctl enable --now docker
  fi
  echo -e "${GREEN}✓ Docker, Compose y Git disponibles.${NC}"
  pause
}

preparar_repo(){
  if [[ -d "$BASE_DIR/.git" ]]; then
    git -C "$BASE_DIR" fetch --all --prune && git -C "$BASE_DIR" reset --hard origin/master
  elif [[ -e "$BASE_DIR" ]]; then
    echo -e "${RED}$BASE_DIR existe pero no es el repositorio oficial.${NC}"
    echo -e "${YELLOW}Renómbrelo o elimínelo antes de continuar para evitar borrar datos.${NC}"
    return 1
  else
    git clone "$REPO_URL" "$BASE_DIR" || return 1
  fi
  mkdir -p "$DATA_HOME/Shinobi" "$DATA_HOME/ShinobiSQL" /dev/shm/ShinobiRAM
  chown -R 999:999 "$DATA_HOME/Shinobi" "$DATA_HOME/ShinobiSQL" 2>/dev/null || true
}

ajustar_puerto_compose(){
  local nuevo="$1"
  sed -Ei "s#([\"']?)[0-9]+:8080\1#\1${nuevo}:8080\1#" "$MAIN_COMPOSE"
  HTTP_PORT="$nuevo"
}

instalar_shinobi(){
  header; titulo "INSTALAR SHINOBI"
  if [[ -f "$MAIN_COMPOSE" ]] && compose ps --status running 2>/dev/null | grep -q shinobi; then
    echo -e "${YELLOW}Shinobi ya está instalado y en ejecución.${NC}"; pause; return
  fi
  if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    instalar_dependencias
  fi
  read -rp "Puerto Web [8080]: " HTTP_PORT; HTTP_PORT=${HTTP_PORT:-8080}
  if ! [[ "$HTTP_PORT" =~ ^[0-9]+$ ]] || (( HTTP_PORT < 1 || HTTP_PORT > 65535 )); then echo -e "${RED}Puerto inválido.${NC}"; pause; return; fi
  local INSTALACION_NUEVA=0
  [[ ! -d "$BASE_DIR/.git" ]] && INSTALACION_NUEVA=1
  preparar_repo || { pause; return; }
  ajustar_puerto_compose "$HTTP_PORT"
  echo -e "${YELLOW}Validando Docker Compose oficial...${NC}"
  compose config >/dev/null || { echo -e "${RED}Error en la configuración Docker Compose.${NC}"; pause; return; }
  echo -e "${YELLOW}Construyendo e iniciando Shinobi...${NC}"
  if ! compose up -d --build; then
    echo -e "${RED}No fue posible iniciar Shinobi.${NC}"
    compose logs --tail=80
    pause; return
  fi
  local ip; ip=$(hostname -I | awk '{print $1}')
  if (( INSTALACION_NUEVA == 1 )); then
    printf "Usuario: %s\nContraseña: %s\n" "$DEFAULT_SUPER_USER" "$DEFAULT_SUPER_PASS" > "$CRED_FILE"
    chmod 600 "$CRED_FILE" 2>/dev/null || true
  fi
  echo; echo -e "${GREEN}✓ Shinobi instalado/iniciado.${NC}"
  echo "URL principal : http://${ip}:${HTTP_PORT}"
  echo "Superusuario  : http://${ip}:${HTTP_PORT}/super"
  echo "Puerto Web    : $HTTP_PORT"
  echo "Directorio    : $BASE_DIR"
  echo "Datos         : $DATA_HOME"
  if (( INSTALACION_NUEVA == 1 )); then
    echo "Usuario       : $DEFAULT_SUPER_USER"
    echo "Contraseña    : $DEFAULT_SUPER_PASS"
    echo "Credenciales  : $CRED_FILE"
  elif [[ -f "$CRED_FILE" ]]; then
    echo "Credenciales  : $CRED_FILE"
    sed 's/^/                /' "$CRED_FILE"
  else
    echo "Credenciales  : instalación existente; use Gestión de usuarios"
  fi
  echo
  echo -e "${YELLOW}IMPORTANTE:${NC} el usuario inicial oficial es admin@shinobi.video / admin únicamente en una instalación nueva."
  pause
}

estado_shinobi(){
  header; titulo "ESTADO SHINOBI"
  [[ -f "$MAIN_COMPOSE" ]] || { echo -e "${RED}Shinobi no está instalado en $BASE_DIR.${NC}"; pause; return; }
  get_port
  compose ps
  echo
  echo "Acceso Web : http://$(hostname -I | awk '{print $1}'):$HTTP_PORT"
  echo "Datos      : $DATA_HOME"
  pause
}

iniciar_shinobi(){ header; titulo "INICIAR SHINOBI"; [[ -f "$MAIN_COMPOSE" ]] || { echo -e "${RED}No instalado.${NC}"; pause; return; }; compose up -d; pause; }
detener_shinobi(){ header; titulo "DETENER SHINOBI"; [[ -f "$MAIN_COMPOSE" ]] || { echo -e "${RED}No instalado.${NC}"; pause; return; }; compose stop; pause; }
reiniciar_shinobi(){ header; titulo "REINICIAR SHINOBI"; [[ -f "$MAIN_COMPOSE" ]] || { echo -e "${RED}No instalado.${NC}"; pause; return; }; compose restart; pause; }
logs_shinobi(){ header; titulo "LOGS SHINOBI"; [[ -f "$MAIN_COMPOSE" ]] || { echo -e "${RED}No instalado.${NC}"; pause; return; }; echo -e "${CYAN}CTRL+C para volver.${NC}"; compose logs -f --tail=100; }

administrar_servicios(){
  while true; do header; titulo "ADMINISTRAR SERVICIOS"; echo -e " ${YELLOW}1)${NC} Iniciar Shinobi"; echo -e " ${YELLOW}2)${NC} Detener Shinobi"; echo -e " ${YELLOW}3)${NC} Reiniciar Shinobi"; echo -e " ${YELLOW}4)${NC} Ver estado"; echo -e " ${YELLOW}5)${NC} Ver logs"; echo -e " ${YELLOW}0)${NC} Volver"; echo; read -rp "Seleccione una opción: " o; case "$o" in 1) iniciar_shinobi;;2) detener_shinobi;;3) reiniciar_shinobi;;4) estado_shinobi;;5) logs_shinobi;;0) return;;*) sleep 1;; esac; done
}

cambiar_puerto_web(){
  header; titulo "CAMBIAR PUERTO WEB"; [[ -f "$MAIN_COMPOSE" ]] || { echo -e "${RED}No instalado.${NC}"; pause; return; }
  get_port; echo "Puerto actual: $HTTP_PORT"; read -rp "Nuevo puerto: " nuevo
  if ! [[ "$nuevo" =~ ^[0-9]+$ ]] || (( nuevo < 1 || nuevo > 65535 )); then echo -e "${RED}Puerto inválido.${NC}"; pause; return; fi
  if ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${nuevo}$"; then echo -e "${RED}El puerto $nuevo ya está en uso.${NC}"; pause; return; fi
  ajustar_puerto_compose "$nuevo"; compose up -d; echo -e "${GREEN}✓ Puerto actualizado.${NC}"; echo "http://$(hostname -I | awk '{print $1}'):$nuevo"; pause
}

actualizar_shinobi(){
  header; titulo "ACTUALIZAR SHINOBI"; [[ -d "$BASE_DIR/.git" ]] || { echo -e "${RED}No se encontró instalación oficial.${NC}"; pause; return; }
  get_port
  git -C "$BASE_DIR" fetch --all --prune || { pause; return; }
  git -C "$BASE_DIR" reset --hard origin/master || { pause; return; }
  ajustar_puerto_compose "$HTTP_PORT"
  compose up -d --build
  docker image prune -f >/dev/null 2>&1 || true
  echo -e "${GREEN}✓ Shinobi actualizado.${NC}"; pause
}

recrear_contenedor(){ header; titulo "RECREAR CONTENEDORES"; [[ -f "$MAIN_COMPOSE" ]] || { echo -e "${RED}No instalado.${NC}"; pause; return; }; compose down; compose up -d --build; pause; }

cambiar_idioma_shinobi(){
  header; titulo "CAMBIAR IDIOMA"
  local cid
  cid=$(compose ps -q shinobi 2>/dev/null)
  [[ -n "$cid" ]] || { echo -e "${RED}El contenedor Shinobi no está en ejecución.${NC}"; pause; return; }
  mapfile -t idiomas < <(docker exec "$cid" sh -c "ls /home/Shinobi/languages/*.json 2>/dev/null | xargs -n1 basename | sed 's/.json$//' | sort")
  (( ${#idiomas[@]} )) || { echo -e "${RED}No se encontraron idiomas.${NC}"; pause; return; }
  local i=1; for l in "${idiomas[@]}"; do echo -e " ${YELLOW}$i)${NC} $l"; ((i++)); done
  echo; read -rp "Seleccione idioma: " op
  [[ "$op" =~ ^[0-9]+$ ]] && (( op>=1 && op<=${#idiomas[@]} )) || { echo -e "${RED}Opción inválida.${NC}"; pause; return; }
  local lang="${idiomas[$((op-1))]}"
  docker exec -e LANG_SELECTED="$lang" "$cid" node -e 'const fs=require("fs");const p="/home/Shinobi/conf.json";let c=JSON.parse(fs.readFileSync(p));c.language=process.env.LANG_SELECTED;fs.writeFileSync(p,JSON.stringify(c,null,3));'
  docker restart "$cid" >/dev/null
  echo -e "${GREEN}✓ Idioma cambiado a $lang.${NC}"; pause
}

informacion(){ header; titulo "INFORMACIÓN"; [[ -f "$MAIN_COMPOSE" ]] || { echo -e "${RED}No instalado.${NC}"; pause; return; }; get_port; echo "Aplicación      : $APP_NAME"; echo "Versión manager : $APP_VERSION"; echo "Directorio      : $BASE_DIR"; echo "Datos           : $DATA_HOME"; echo "Puerto Web      : $HTTP_PORT"; echo "Repositorio     : $REPO_URL"; echo; compose images; pause; }

desinstalar_shinobi(){
  header; titulo "DESINSTALAR SHINOBI"
  echo -e " ${YELLOW}1)${NC} Eliminar contenedores, conservar datos y archivos"
  echo -e " ${YELLOW}2)${NC} Eliminar contenedores e imágenes, conservar datos"
  echo -e " ${YELLOW}3)${NC} Eliminación completa de $BASE_DIR"
  echo -e " ${YELLOW}0)${NC} Volver"; echo
  read -rp "Seleccione una opción: " o
  case "$o" in
    1) [[ -f "$MAIN_COMPOSE" ]] && compose down; echo -e "${GREEN}Datos conservados.${NC}";;
    2) [[ -f "$MAIN_COMPOSE" ]] && compose down --rmi local; docker image prune -f >/dev/null 2>&1 || true; echo -e "${GREEN}Datos conservados.${NC}";;
    3) read -rp "Escriba ELIMINAR para borrar Shinobi y todos sus datos: " c; [[ "$c" == "ELIMINAR" ]] || { echo "Cancelado."; pause; return; }; [[ -f "$MAIN_COMPOSE" ]] && compose down --rmi local -v || true; rm -rf "$BASE_DIR" /dev/shm/ShinobiRAM; echo -e "${GREEN}✓ Shinobi eliminado completamente.${NC}";;
    0) return;;
  esac
  pause
}


get_shinobi_cid(){
  local cid
  cid=$(compose ps -q shinobi 2>/dev/null | head -n1)
  [[ -n "$cid" ]] || return 1
  printf '%s' "$cid"
}

get_super_json_path(){
  local cid="$1" p
  p=$(docker exec "$cid" sh -c 'for f in /home/Shinobi/super.json /config/super.json; do [ -f "$f" ] && { echo "$f"; exit 0; }; done; find /home/Shinobi /config -maxdepth 3 -name super.json -type f 2>/dev/null | head -n1' 2>/dev/null)
  [[ -n "$p" ]] || return 1
  printf '%s' "$p"
}

ver_credenciales_super(){
  header; titulo "CREDENCIALES DE INICIO DE SESIÓN"
  get_port
  local ip cid sj
  ip=$(hostname -I | awk '{print $1}')
  echo "URL principal : http://${ip}:${HTTP_PORT}"
  echo "Superusuario  : http://${ip}:${HTTP_PORT}/super"
  echo "Puerto Web    : $HTTP_PORT"
  echo "Directorio    : $BASE_DIR"
  echo
  if [[ -f "$CRED_FILE" ]]; then
    echo -e "${CYAN}Credenciales guardadas por este administrador:${NC}"
    cat "$CRED_FILE"
  else
    echo -e "${YELLOW}No hay contraseña en texto claro guardada por este administrador.${NC}"
    echo "Usuario inicial conocido : $DEFAULT_SUPER_USER"
    echo "Contraseña inicial       : $DEFAULT_SUPER_PASS"
  fi
  echo
  if cid=$(get_shinobi_cid); then
    if sj=$(get_super_json_path "$cid"); then
      echo -e "${CYAN}Superusuarios registrados en super.json:${NC}"
      docker exec -e SJ="$sj" "$cid" node -e 'const fs=require("fs");const a=JSON.parse(fs.readFileSync(process.env.SJ));(Array.isArray(a)?a:[a]).forEach((u,i)=>console.log(`  ${i+1}) ${u.mail||u.email||"(sin correo)"}`));' 2>/dev/null || true
      echo
      echo -e "${YELLOW}Nota:${NC} Shinobi guarda la contraseña como hash; no se puede recuperar el texto original si fue cambiada fuera de este script."
    fi
  fi
  pause
}

cambiar_superusuario(){
  header; titulo "CAMBIAR SUPERUSUARIO / CONTRASEÑA"
  local cid sj seleccion nuevo pass pass2 actual total
  cid=$(get_shinobi_cid) || { echo -e "${RED}Shinobi no está en ejecución.${NC}"; pause; return; }
  sj=$(get_super_json_path "$cid") || { echo -e "${RED}No se encontró super.json.${NC}"; pause; return; }

  mapfile -t supers < <(docker exec -e SJ="$sj" "$cid" node -e 'const fs=require("fs");let a=JSON.parse(fs.readFileSync(process.env.SJ));if(!Array.isArray(a))a=[a];a.forEach(u=>console.log(u.mail||u.email||""));' 2>/dev/null)
  total=${#supers[@]}
  (( total > 0 )) || { echo -e "${RED}No se encontraron superusuarios.${NC}"; pause; return; }

  echo "Superusuarios actuales:"
  local i=1
  for actual in "${supers[@]}"; do
    echo -e " ${YELLOW}${i})${NC} $actual"
    ((i++))
  done
  echo
  read -rp "Seleccione superusuario [1]: " seleccion
  seleccion=${seleccion:-1}
  if ! [[ "$seleccion" =~ ^[0-9]+$ ]] || (( seleccion < 1 || seleccion > total )); then
    echo -e "${RED}Selección inválida.${NC}"; pause; return
  fi

  actual="${supers[$((seleccion-1))]}"
  read -rp "Nuevo correo [mantener $actual]: " nuevo
  nuevo=${nuevo:-$actual}
  read -rsp "Nueva contraseña: " pass; echo
  read -rsp "Repita nueva contraseña: " pass2; echo
  [[ -n "$pass" ]] || { echo -e "${RED}La contraseña no puede estar vacía.${NC}"; pause; return; }
  [[ "$pass" == "$pass2" ]] || { echo -e "${RED}Las contraseñas no coinciden.${NC}"; pause; return; }

  if docker exec -e SJ="$sj" -e OLD_MAIL="$actual" -e NEW_MAIL="$nuevo" -e NEW_PASS="$pass" "$cid" node -e '
const fs=require("fs"),crypto=require("crypto");
const p=process.env.SJ;
let a=JSON.parse(fs.readFileSync(p));
if(!Array.isArray(a))a=[a];
const i=a.findIndex(u=>(u.mail||u.email)===process.env.OLD_MAIL);
if(i<0)process.exit(4);
a[i].mail=process.env.NEW_MAIL;
delete a[i].email;
a[i].pass=crypto.createHash("md5").update(process.env.NEW_PASS).digest("hex");
fs.writeFileSync(p,JSON.stringify(a,null,3));'; then
    printf "Usuario: %s\nContraseña: %s\n" "$nuevo" "$pass" > "$CRED_FILE"
    chmod 600 "$CRED_FILE" 2>/dev/null || true
    docker restart "$cid" >/dev/null
    echo -e "${GREEN}✓ Superusuario actualizado y Shinobi reiniciado.${NC}"
    echo "Usuario: $nuevo"
    echo "Contraseña: $pass"
    echo "Login: http://$(hostname -I | awk '{print $1}'):${HTTP_PORT}/super"
  else
    echo -e "${RED}No fue posible modificar el superusuario.${NC}"
  fi
  pause
}

crear_superusuario(){
  header; titulo "CREAR SUPERUSUARIO ADICIONAL"
  local cid sj mail pass pass2
  cid=$(get_shinobi_cid) || { echo -e "${RED}Shinobi no está en ejecución.${NC}"; pause; return; }
  sj=$(get_super_json_path "$cid") || { echo -e "${RED}No se encontró super.json.${NC}"; pause; return; }
  read -rp "Correo del nuevo superusuario: " mail
  [[ "$mail" == *@*.* ]] || { echo -e "${RED}Correo inválido.${NC}"; pause; return; }
  read -rsp "Contraseña: " pass; echo
  read -rsp "Repita contraseña: " pass2; echo
  [[ -n "$pass" && "$pass" == "$pass2" ]] || { echo -e "${RED}Las contraseñas no coinciden o están vacías.${NC}"; pause; return; }
  if docker exec -e SJ="$sj" -e NEW_MAIL="$mail" -e NEW_PASS="$pass" "$cid" node -e '
const fs=require("fs"),crypto=require("crypto");const p=process.env.SJ;let a=JSON.parse(fs.readFileSync(p));if(!Array.isArray(a))a=[a];if(a.some(u=>(u.mail||u.email)===process.env.NEW_MAIL))process.exit(5);a.push({mail:process.env.NEW_MAIL,pass:crypto.createHash("md5").update(process.env.NEW_PASS).digest("hex")});fs.writeFileSync(p,JSON.stringify(a,null,3));'; then
    docker restart "$cid" >/dev/null
    echo -e "${GREEN}✓ Superusuario creado.${NC}"
    echo "Inicio de sesión: http://$(hostname -I | awk '{print $1}'):${HTTP_PORT}/super"
    echo "Usuario: $mail"
  else
    echo -e "${RED}No fue posible crear el superusuario; puede que ya exista.${NC}"
  fi
  pause
}

crear_usuario_admin_info(){
  header; titulo "CREAR USUARIO ADMINISTRADOR DE CÁMARAS"
  get_port
  local ip; ip=$(hostname -I | awk '{print $1}')
  echo "En Shinobi los usuarios que administran cámaras se guardan en la base SQL."
  echo "La forma soportada es crearlos desde el panel Superuser."
  echo
  echo "1) Abra: http://${ip}:${HTTP_PORT}/super"
  echo "2) Inicie sesión con el Superusuario."
  echo "3) Cree una cuenta Admin desde el panel."
  echo "4) El nuevo Admin inicia sesión en: http://${ip}:${HTTP_PORT}/"
  echo
  echo -e "${YELLOW}Este menú no inserta usuarios directamente en SQL para evitar dañar permisos o el esquema interno de Shinobi.${NC}"
  pause
}

menu_usuarios(){
  while true; do
    header; titulo "GESTIÓN DE USUARIOS"
    echo -e " ${YELLOW}1)${NC} Ver credenciales y URLs de inicio de sesión"
    echo -e " ${YELLOW}2)${NC} Cambiar correo/contraseña de Superusuario"
    echo -e " ${YELLOW}3)${NC} Crear Superusuario adicional"
    echo -e " ${YELLOW}4)${NC} Crear usuario Admin de cámaras (guía panel /super)"
    echo -e " ${YELLOW}0)${NC} Volver"
    echo
    read -rp "Seleccione una opción: " o
    case "$o" in
      1) ver_credenciales_super;;
      2) cambiar_superusuario;;
      3) crear_superusuario;;
      4) crear_usuario_admin_info;;
      0) return;;
      *) echo -e "${RED}Opción inválida.${NC}"; sleep 1;;
    esac
  done
}

menu_ajustes(){ while true; do header; titulo "AJUSTES SHINOBI"; echo -e " ${YELLOW}1)${NC} Cambiar puerto Web"; echo -e " ${YELLOW}2)${NC} Actualizar Shinobi"; echo -e " ${YELLOW}3)${NC} Recrear contenedores"; echo -e " ${YELLOW}4)${NC} Cambiar idioma"; echo -e " ${YELLOW}0)${NC} Volver"; echo; read -rp "Seleccione una opción: " o; case "$o" in 1)cambiar_puerto_web;;2)actualizar_shinobi;;3)recrear_contenedor;;4)cambiar_idioma_shinobi;;0)return;;*)sleep 1;; esac; done; }

menu_principal(){ while true; do header; titulo "SHINOBI MANAGER"; echo -e " ${YELLOW}1)${NC} Instalar dependencias Docker"; echo -e " ${YELLOW}2)${NC} Instalar Shinobi"; echo -e " ${YELLOW}3)${NC} Estado de Shinobi"; echo -e " ${YELLOW}4)${NC} Administrar servicios"; echo -e " ${YELLOW}5)${NC} Ajustes"; echo -e " ${YELLOW}6)${NC} Información"; echo -e " ${YELLOW}7)${NC} Gestión de usuarios"; echo -e " ${YELLOW}8)${NC} Desinstalar Shinobi"; echo -e " ${YELLOW}0)${NC} Salir"; echo; read -rp "Seleccione una opción: " o; case "$o" in 1)instalar_dependencias;;2)instalar_shinobi;;3)estado_shinobi;;4)administrar_servicios;;5)menu_ajustes;;6)informacion;;7)menu_usuarios;;8)desinstalar_shinobi;;0)clear;exit 0;;*)echo -e "${RED}Opción inválida.${NC}";sleep 1;; esac; done; }

need_root
menu_principal
