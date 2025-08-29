#!/bin/bash
# install.sh for netdata
# Version: 1.00.00

VERSION="1.00.00"
SERVICE="netdata"
SERVICE_USER="netdata"
SERVICE_GROUP="netdata"
SERVICE_HOME="/home/netdata"

# Pfade
CONFIG_DIR="$SERVICE_HOME/config"
LOG_DIR="/home/khryon/logs/netdata"

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

# Funktion für interaktive Konfiguration
configure_netdata() {
    log_message "Starting interactive Netdata configuration..."
    
    echo ""
    echo "================================================"
    echo "           NETDATA KONFIGURATION"
    echo "================================================"
    
    # ================= NETZWERK KONFIGURATION =================
    echo ""
    echo "🌐 NETZWERK-EINSTELLUNGEN"
    echo "----------------------------------------"
    read -p "Web Interface Port [19999]: " WEB_PORT
    WEB_PORT=${WEB_PORT:-19999}
    
    read -p "Bind Address [0.0.0.0]: " BIND_ADDRESS
    BIND_ADDRESS=${BIND_ADDRESS:-0.0.0.0}
    
    # ================= SICHERHEITSKONFIGURATION =================
    echo ""
    echo "🔐 SICHERHEITS-EINSTELLUNGEN"
    echo "----------------------------------------"
    read -p "Basic Authentication aktivieren? (j/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        read -p "Admin Username [admin]: " ADMIN_USER
        ADMIN_USER=${ADMIN_USER:-admin}
        read -sp "Admin Password: " ADMIN_PASSWORD
        echo
        while [ -z "$ADMIN_PASSWORD" ]; do
            read -sp "Password cannot be empty: " ADMIN_PASSWORD
            echo
        done
        AUTH_ENABLED="true"
    else
        AUTH_ENABLED="false"
    fi
    
    # ================= BESTÄTIGUNG =================
    echo ""
    echo "================================================"
    echo "           ZUSAMMENFASSUNG"
    echo "================================================"
    echo "🔸 Port: $WEB_PORT"
    echo "🔸 Bind Address: $BIND_ADDRESS"
    echo "🔸 Authentication: $AUTH_ENABLED"
    if [[ "$AUTH_ENABLED" == "true" ]]; then
        echo "🔸 Admin User: $ADMIN_USER"
    fi
    echo "================================================"
    echo ""
    
    read -p "Konfiguration bestätigen? (j/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        log_message "❌ Konfiguration abgebrochen"
        return 1
    fi

    if [[ "$AUTH_ENABLED" == "true" ]]; then
        store_password "netdata" "$ADMIN_USER" "$ADMIN_PASSWORD"
    fi
    
    return 0
}

log_message "=== Starting Netdata Installation ==="

# === SCHRITT 0: Firewall prüfen ===
check_firewall

# === SCHRITT 1: Verzeichnisse anlegen ===
sudo mkdir -p "$CONFIG_DIR" "$LOG_DIR"
sudo chown -R "$SERVICE_USER":"$SERVICE_GROUP" "$CONFIG_DIR"
sudo chown -R khryon:users "$LOG_DIR"
sudo chmod 755 "$LOG_DIR"

# === SCHRITT 2: Interaktive Konfiguration ===
if ! configure_netdata; then
    log_message "❌ ERROR: Configuration failed"
    exit 1
fi

# === SCHRITT 3: Docker Compose erstellen ===
log_message "Creating Docker Compose configuration..."
cat > "$(dirname "$0")/docker-compose.yml" << EOF
version: '3.8'

services:
  netdata:
    image: netdata/netdata
    container_name: netdata
    user: "\${UID}:\${GID}"
    volumes:
      - $CONFIG_DIR:/etc/netdata
      - $LOG_DIR:/var/log/netdata
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports:
      - "$BIND_ADDRESS:$WEB_PORT:19999"
    environment:
      - TZ=Europe/Berlin
      - UID=\${UID}
      - GID=\${GID}
    restart: unless-stopped
    cap_add:
      - SYS_PTRACE
    security_opt:
      - apparmor:unconfined
EOF

# === SCHRITT 4: Container starten ===
log_message "Starting Netdata container..."
if ! run_docker_compose "$SERVICE"; then
    log_message "❌ ERROR: Docker Compose failed"
    exit 1
fi

# === SCHRITT 5: Firewall Port öffnen ===
log_message "Configuring firewall..."
open_port "$WEB_PORT" "tcp" "Netdata - Monitoring"

# === SCHRITT 6: Log Rotation einrichten ===
setup_log_rotation "netdata" "$LOG_DIR"

log_message "=== Netdata Installation completed successfully ==="
echo ""
echo "✅ Netdata is now running!"
echo "   📊 Dashboard: http://$(hostname -I | awk '{print $1}'):$WEB_PORT"
if [[ "$AUTH_ENABLED" == "true" ]]; then
    echo "   🔐 Login: $ADMIN_USER (password saved)"
fi
echo "   🐳 Docker monitoring: Enabled"
echo "   📈 Real-time metrics: Enabled"
exit 0