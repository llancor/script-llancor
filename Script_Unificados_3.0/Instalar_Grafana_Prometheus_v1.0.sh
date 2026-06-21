#!/bin/bash

GRAFANA_DIR="/opt/monitoring"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

instalar_monitoring() {

    echo
    echo -e "${CYAN}Instalando Grafana + Prometheus + cAdvisor${NC}"
    echo

    mkdir -p $GRAFANA_DIR/prometheus

    cat > $GRAFANA_DIR/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
EOF

    cat > $GRAFANA_DIR/docker-compose.yml <<EOF
services:

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    ports:
      - "8080:8080"
    privileged: true
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro

volumes:
  grafana_data:
EOF

    cd $GRAFANA_DIR || exit

    docker compose up -d

    echo
    echo -e "${GREEN}✅ Instalación completada${NC}"
    echo
    echo "Grafana:    http://IP:3000"
    echo "Prometheus: http://IP:9090"
    echo "cAdvisor:   http://IP:8080"
    echo
    echo "Usuario Grafana: admin"
    echo "Clave Grafana: admin"
    echo
}

desinstalar_monitoring() {

    echo
    echo -e "${RED}⚠️ ATENCIÓN${NC}"
    echo
    echo "Se eliminará:"
    echo " - Grafana"
    echo " - Prometheus"
    echo " - Node Exporter"
    echo " - cAdvisor"
    echo " - Volúmenes"
    echo

    read -rp "Escriba ELIMINAR para continuar: " CONFIRMAR

    [ "$CONFIRMAR" != "ELIMINAR" ] && return

    cd $GRAFANA_DIR 2>/dev/null && docker compose down -v

    rm -rf $GRAFANA_DIR

    docker rm -f grafana prometheus node-exporter cadvisor 2>/dev/null

    echo
    echo -e "${GREEN}✅ Monitoring eliminado${NC}"
    echo
}

estado_monitoring() {

    echo
    echo -e "${CYAN}Estado de servicios${NC}"
    echo

    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E \
    "grafana|prometheus|node-exporter|cadvisor"

    echo
}
instalar_node_exporter() {

    echo
    echo -e "${CYAN}Instalando Node Exporter${NC}"
    echo

    if docker ps -a --format "{{.Names}}" | grep -q "^node-exporter$"; then
        echo -e "${YELLOW}Node Exporter ya existe${NC}"
        echo
        read -rp "ENTER para continuar..."
        return
    fi

    docker run -d \
        --name node-exporter \
        --restart unless-stopped \
        --network host \
        prom/node-exporter:latest

    IP_SERVIDOR=$(hostname -I | awk '{print $1}')

    echo
    echo -e "${GREEN}✅ Node Exporter instalado${NC}"
    echo
    echo -e "${WHITE}Servidor:${NC} $IP_SERVIDOR"
    echo -e "${WHITE}Puerto:${NC} 9100"
    echo
    echo -e "${CYAN}URL de métricas:${NC}"
    echo "http://$IP_SERVIDOR:9100/metrics"
    echo
    echo -e "${YELLOW}Agregar en Prometheus:${NC}"
    echo
    cat <<EOF
- job_name: '$(hostname)'
  static_configs:
    - targets:
        - '$IP_SERVIDOR:9100'
EOF
    echo
    read -rp "ENTER para continuar..."
}

desinstalar_node_exporter() {

    echo
    echo -e "${RED}⚠️ ATENCIÓN${NC}"
    echo
    echo "Se eliminará Node Exporter"
    echo

    read -rp "Escriba ELIMINAR para continuar: " CONFIRMAR

    [ "$CONFIRMAR" != "ELIMINAR" ] && return

    docker rm -f node-exporter 2>/dev/null

    echo
    echo -e "${GREEN}✅ Node Exporter eliminado${NC}"
    echo
    read -rp "ENTER para continuar..."
}
ver_urls_puertos() {

    clear

    echo
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}      URLS Y PUERTOS DEL SERVIDOR       ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo

    IP=$(hostname -I | awk '{print $1}')

    echo -e "${WHITE}IP del servidor:${NC} ${GREEN}$IP${NC}"
    echo

    if [ -z "$(docker ps -q)" ]; then
        echo -e "${YELLOW}No hay contenedores en ejecución${NC}"
        echo
        read -rp "ENTER para continuar..."
        return
    fi

    printf "%-30s %-30s\n" "CONTENEDOR" "ACCESO"
    echo "---------------------------------------------------------------------"

    docker ps --format "{{.Names}}" | while read -r CONT; do

        PUERTOS=$(docker port "$CONT" 2>/dev/null)

        if [ -n "$PUERTOS" ]; then

            while read -r LINEA; do

                PUERTO=$(echo "$LINEA" | awk -F':' '{print $NF}')

                printf "%-30s http://%s:%s\n" \
                    "$CONT" \
                    "$IP" \
                    "$PUERTO"

            done <<< "$PUERTOS"

        else

            printf "%-30s Sin puertos publicados\n" "$CONT"

        fi

    done

    echo
    read -rp "ENTER para continuar..."
}
menu_monitoring() {

    while true; do

        clear

echo
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}      GRAFANA MONITORING MANAGER        ${NC}"
echo -e "${CYAN}========================================${NC}"
echo

echo -e " ${YELLOW}1)${NC} Instalar Monitoring Completo"
echo -e " ${YELLOW}2)${NC} Instalar Node Exporter Cliente"
echo -e " ${YELLOW}3)${NC} Estado Servicios"
echo -e " ${YELLOW}4)${NC} Desinstalar Monitoring"
echo -e " ${YELLOW}5)${NC} Desinstalar Node Exporter"
echo -e " ${YELLOW}6)${NC} Ver URLs y Puertos"
echo -e " ${YELLOW}0)${NC} Salir"

echo

        read -rp "Seleccione una opción: " OPCION

case "$OPCION" in

    1) instalar_monitoring ;;
    2) instalar_node_exporter ;;
    3) estado_monitoring ; read -rp "ENTER..." ;;
    4) desinstalar_monitoring ;;
    5) desinstalar_node_exporter ;;
	6) ver_urls_puertos ;;
    0) break ;;

esac

    done
}

menu_monitoring
