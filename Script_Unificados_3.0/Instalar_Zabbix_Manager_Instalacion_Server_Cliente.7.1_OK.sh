#!/usr/bin/env bash
# Gestor completo Zabbix
# Instalación Server/Agente, gestión usuarios Web API, servicios y utilidades.

# ---------- Colores ----------
amarillo="\033[1;33m"
rojo="\033[1;31m"
fin="\033[0m"

# ---------- Config ----------
CONFIG_FILE="/etc/zabbix_manager.conf"
SERVICE_DIR="/usr/local/bin/script"

# ---------- Helpers ----------
pedir_mysql_root() {
  if [ -z "$MYSQL_ROOT_PASS" ]; then
    read -s -p "Ingrese la contraseña de root de MySQL/MariaDB: " MYSQL_ROOT_PASS
    echo ""
  fi
}

fix_dpkg() {
  echo -e "${amarillo}[*] Reparando paquetes...${fin}"
  sudo dpkg --configure -a || true
  sudo apt-get install -f -y || true
  sudo apt autoremove -y || true
}

ensure_root_or_sudo() {
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "${amarillo}Nota: se usarán comandos con sudo cuando sea necesario.${fin}"
  fi
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${rojo}ERROR: 'jq' no está instalado. Usa la opción 8 para configurar la API.${fin}"
    return 1
  fi
  return 0
}

load_config() { [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"; }

save_config() {
  sudo bash -c "cat > $CONFIG_FILE" <<EOF
ZBX_URL="${ZBX_URL}"
ZBX_USER="${ZBX_USER}"
ZBX_PASS="${ZBX_PASS}"
EOF
  sudo chmod 600 "$CONFIG_FILE"
}

# ---------- Habilitar ejecución de scripts ----------
habilitar_scripts() {
  echo -e "${amarillo}Habilitando ejecución remota de scripts en agente...${fin}"
  if [ -f /etc/zabbix/zabbix_agentd.conf ]; then
    sudo sed -i 's/^#*EnableRemoteCommands.*/EnableRemoteCommands=1/' /etc/zabbix/zabbix_agentd.conf || true
    if ! grep -q '^AllowKey=system.run' /etc/zabbix/zabbix_agentd.conf 2>/dev/null; then
      echo 'AllowKey=system.run[*]' | sudo tee -a /etc/zabbix/zabbix_agentd.conf >/dev/null
    fi
    echo "zabbix ALL=(ALL) NOPASSWD: $SERVICE_DIR/*" | sudo tee /etc/sudoers.d/zabbix-manager >/dev/null
    sudo chmod 440 /etc/sudoers.d/zabbix-manager
    sudo systemctl restart zabbix-agent || true
    echo -e "${amarillo}Habilitado EnableRemoteCommands y AllowKey (si corresponde).${fin}"
  else
    echo -e "${rojo}No se encontró /etc/zabbix/zabbix_agentd.conf${fin}"
  fi
  read -rp "ENTER para continuar..."
}

# ---------- Zabbix Server ----------
instalar_zabbix() {
  echo -e "${amarillo}[*] Instalando Zabbix Server + Frontend...${fin}"

  read -p "Ingrese nombre de la base de datos [zabbix]: " DB_NAME
  DB_NAME=${DB_NAME:-zabbix}
  read -p "Ingrese nombre de usuario DB [zabbix]: " DB_USER
  DB_USER=${DB_USER:-zabbix}
  read -s -p "Ingrese contraseña DB: " DB_PASS
  echo ""
  pedir_mysql_root

  sudo apt-get update -y
  sudo apt-get install -y sudo git unzip wget gnupg2 lsb-release mariadb-client

  wget -q https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_7.0-1+debian12_all.deb
  sudo dpkg -i zabbix-release_7.0-1+debian12_all.deb || fix_dpkg
  sudo apt-get update -y

  if ! sudo apt-get install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent; then
    fix_dpkg
    sudo apt-get install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent || {
      echo -e "${rojo}Error instalando paquetes.${fin}"
      return 1
    }
  fi

  mysql -uroot -p"$MYSQL_ROOT_PASS" <<MYSQL_SCRIPT
CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

  zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql -u$DB_USER -p"$DB_PASS" $DB_NAME

  sudo sed -i "s/^# DBPassword=.*/DBPassword=$DB_PASS/" /etc/zabbix/zabbix_server.conf
  sudo sed -i "s/^# DBUser=.*/DBUser=$DB_USER/" /etc/zabbix/zabbix_server.conf
  sudo sed -i "s/^# DBName=.*/DBName=$DB_NAME/" /etc/zabbix/zabbix_server.conf

  sudo systemctl restart zabbix-server zabbix-agent apache2
  sudo systemctl enable zabbix-server zabbix-agent apache2

  echo -e "${amarillo}==== Instalación completada ====${fin}"
  echo -e "${amarillo}Accede a Zabbix en: http://TU_IP/zabbix${fin}"
  echo -e "${amarillo}Usuario inicial: Admin${fin}"
  echo -e "${amarillo}Contraseña inicial: zabbix${fin}"
}

desinstalar_zabbix() {
  echo -e "${amarillo}>>> Desinstalando Zabbix${fin}"
  sudo systemctl stop zabbix-server zabbix-agent || true
  sudo apt purge -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf \
    zabbix-sql-scripts zabbix-agent || true
  sudo apt autoremove -y || true

  pedir_mysql_root
  mysql -uroot -p"$MYSQL_ROOT_PASS" <<MYSQL_SCRIPT
DROP DATABASE IF EXISTS zabbix;
DROP USER IF EXISTS 'zabbix'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

  echo -e "${amarillo}Zabbix, su base de datos y usuario han sido eliminados.${fin}"
}

# ---------- Zabbix Agent ----------
instalar_agente() {
    echo -e "\n${verde}=== Instalando y configurando cliente Zabbix ===${fin}"

    # Instalar agente
    if [ -f /etc/debian_version ]; then
        sudo apt update
        sudo apt install zabbix-agent jq curl -y
    elif [ -f /etc/redhat-release ]; then
        sudo yum install zabbix-agent jq curl -y
    fi

    # Configurar agente
    read -rp "IP o hostname del servidor Zabbix: " ZBX_SERVER
    read -rp "Nombre del host (como aparecerá en Zabbix): " ZBX_HOSTNAME
    CONF_FILE="/etc/zabbix/zabbix_agentd.conf"
    sudo sed -i "s/^Server=.*/Server=$ZBX_SERVER/" "$CONF_FILE"
    sudo sed -i "s/^ServerActive=.*/ServerActive=$ZBX_SERVER/" "$CONF_FILE"
    sudo sed -i "s/^Hostname=.*/Hostname=$ZBX_HOSTNAME/" "$CONF_FILE"

    # Permitir ejecutar scripts
    sudo mkdir -p "$SCRIPT_DIR"
    sudo chmod 755 "$SCRIPT_DIR"
    echo "zabbix ALL=(ALL) NOPASSWD: $SCRIPT_DIR/*" | sudo tee /etc/sudoers.d/zabbix >/dev/null
    sudo chmod 440 /etc/sudoers.d/zabbix

    # Habilitar servicio
    sudo systemctl enable zabbix-agent
    sudo systemctl restart zabbix-agent

    echo -e "${verde}✅ Cliente configurado${fin}"  


}

desinstalar_agente() {
  echo -e "${amarillo}>>> Desinstalando Zabbix Agent${fin}"
  sudo systemctl stop zabbix-agent || true
  sudo apt purge -y zabbix-agent || true
  sudo apt autoremove -y || true
  echo -e "${amarillo}Agente eliminado.${fin}"
}


# ---------- Servicios ----------
menu_estado_servicios() {
  clear
  echo -e "${amarillo}=== Estado Servicios ===${fin}"
  for s in zabbix-server zabbix-agent apache2 mysql mariadb; do
    if systemctl list-unit-files | grep -q "^$s"; then
      echo -e "${amarillo}$s:${fin} $(systemctl is-active $s)"
    fi
  done
  read -rp "ENTER para volver..."
}

menu_reiniciar_servicios() {
  while true; do
    clear
    echo -e "${amarillo}=== Reiniciar Servicios ===${fin}"
    echo -e " ${amarillo}1)${fin} Reiniciar Zabbix Server"
    echo -e " ${amarillo}2)${fin} Reiniciar Zabbix Agent"
    echo -e " ${amarillo}3)${fin} Reiniciar Apache2"
    echo -e " ${amarillo}4)${fin} Reiniciar MySQL/MariaDB"
    echo -e " ${amarillo}5)${fin} Reiniciar PHP-FPM"
    echo -e " ${rojo}6) Volver${fin}"
    read -rp "Seleccione: " opt
    case $opt in
      1) sudo systemctl restart zabbix-server ;;
      2) sudo systemctl restart zabbix-agent ;;
      3) sudo systemctl restart apache2 ;;
      4) sudo systemctl restart mysql 2>/dev/null || sudo systemctl restart mariadb 2>/dev/null ;;
      5) mapfile -t php_units < <(systemctl list-unit-files --type=service | awk '/php[0-9\.]+-fpm\.service|php-fpm.service/ {print $1}')
         for u in "${php_units[@]}"; do sudo systemctl restart "$u"; done ;;
      6) break ;;
      *) echo -e "${rojo}Opción inválida${fin}" ;;
    esac
    read -rp "ENTER para continuar..."
  done
}

insertar_servicios_predefinidos() {
  echo -e "${amarillo}>>> Creando scripts de servicios en $SERVICE_DIR${fin}"
  sudo mkdir -p "$SERVICE_DIR"
  declare -A svc=(
    ["apache2"]="systemctl restart apache2"
    ["mysql"]="systemctl restart mysql || systemctl restart mariadb"
    ["zabbix-server"]="systemctl restart zabbix-server"
    ["zabbix-agent"]="systemctl restart zabbix-agent"
  )
  for name in "${!svc[@]}"; do
    f="$SERVICE_DIR/$name.sh"
    echo "#!/bin/bash" | sudo tee "$f" >/dev/null
    echo "${svc[$name]}" | sudo tee -a "$f" >/dev/null
    sudo chmod +x "$f"
    echo -e "${amarillo}Creado: $f${fin}"
  done
  echo -e "${amarillo}Scripts listos para usar desde Zabbix.${fin}"
  read -rp "ENTER para continuar..."
}

instalar_en_bin() {
  destino="/usr/local/bin/zabbix"
  sudo cp "$0" "$destino"
  sudo chmod +x "$destino"
  echo -e "${amarillo}Script instalado en $destino${fin}"
  read -rp "ENTER para continuar..."
}

# ---------- Configurar API ----------
configurar_api() {
echo -e "\n=== Instalando dependencias y configurando API ==="
    sudo apt update
    sudo apt install jq curl -y
    echo "✅ jq instalado"
    read -rp "URL Zabbix API (ej: http://localhost/zabbix/api_jsonrpc.php): " ZBX_URL
    read -rp "Usuario Zabbix: " ZBX_USER
    read -s -rp "Contraseña Zabbix: " ZBX_PASS
    echo
    token=$(curl -s -X POST -H 'Content-Type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"user.login\",\"params\":{\"user\":\"$ZBX_USER\",\"password\":\"$ZBX_PASS\"},\"id\":1,\"auth\":null}" \
        "$ZBX_URL" | jq -r '.result')
    if [ "$token" != "null" ]; then
        echo "✅ API configurada correctamente"
        echo "$token" | sudo tee /etc/zabbix/api_token >/dev/null
    else
        echo "❌ Error al conectar con API"
    fi  

}

# ---------- Menú principal ----------
ensure_root_or_sudo
while true; do
  clear
  echo -e "${amarillo}===== GESTOR DE ZABBIX =====${fin}"
  echo -e " ${amarillo}1)${fin} Instalar Zabbix Server + Frontend"
  echo -e " ${amarillo}2)${fin} Desinstalar Zabbix"
  echo -e " ${amarillo}4)${fin} Instalar agente Zabbix"
  echo -e " ${amarillo}5)${fin} Desinstalar agente Zabbix"
  echo -e " ${amarillo}6)${fin} Ver estado servicios"
  echo -e " ${amarillo}7)${fin} Reiniciar servicios"
  echo -e " ${amarillo}8)${fin} Configurar API (jq + credenciales)"
  echo -e " ${amarillo}9)${fin} Insertar servicios predefinidos"
  echo -e " ${amarillo}10)${fin} Instalar este script en /usr/local/bin (zabbix)"
  echo -e " ${amarillo}11)${fin} Habilitar ejecución de scripts server y agente"
  echo -e " ${rojo}12) Salir${fin}"
  read -rp "Seleccione: " op
  case $op in
    1) instalar_zabbix ;;
    2) desinstalar_zabbix ;;
    3) gestion_usuarios_menu ;;
    4) instalar_agente ;;
    5) desinstalar_agente ;;
    6) menu_estado_servicios ;;
    7) menu_reiniciar_servicios ;;
    8) configurar_api ;;
    9) insertar_servicios_predefinidos ;;
    10) instalar_en_bin ;;
    11) habilitar_scripts ;;
    12) echo -e "${rojo}Saliendo...${fin}"; exit 0 ;;
    *) echo -e "${rojo}Opción inválida${fin}" ;;
  esac
  read -rp "ENTER para continuar..."
done
