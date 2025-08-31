#!/bin/bash
# install.sh for nextcloud
# Version: 1.00.01  # Alles im Home-Verzeichnis

VERSION="1.00.01"
SERVICE="nextcloud"
SERVICE_USER="nextcloud"
SERVICE_GROUP="nextcloud"
SERVICE_HOME="/home/nextcloud"

# Pfade - ALLES IM HOME!
DATA_DIR="$SERVICE_HOME/data"
CONFIG_DIR="$SERVICE_HOME/config"
HTML_DIR="$SERVICE_HOME/html"
LOG_DIR="$SERVICE_HOME/logs"
APPS_DIR="$SERVICE_HOME/apps"

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

# Funktion für interaktive Konfiguration
configure_nextcloud() {
    log_message "Starting interactive Nextcloud configuration..."
    
    echo ""
    echo "================================================"
    echo "           NEXTCLOUD KONFIGURATION"
    echo "================================================"
    echo "📁 All data will be stored in: $SERVICE_HOME/"
    echo ""
    
    # ================= DATENBANK KONFIGURATION =================
    echo "🗄️  DATENBANK-EINSTELLUNGEN"
    echo "----------------------------------------"
    DB_PASSWORD=$(get_password "mariadb" "nextcloud")
    if [[ -z "$DB_PASSWORD" ]]; then
        read -sp "Nextcloud Database Password: " DB_PASSWORD
        echo
        while [ -z "$DB_PASSWORD" ]; do
            read -sp "Password cannot be empty: " DB_PASSWORD
            echo
        done
        store_password "mariadb" "nextcloud" "$DB_PASSWORD"
    fi
    
    read -p "Nextcloud Database Name [nextcloud]: " DB_NAME
    DB_NAME=${DB_NAME:-nextcloud}
    
    read -p "Nextcloud Database User [nextcloud]: " DB_USER
    DB_USER=${DB_USER:-nextcloud}
    
    # ================= NEXTCLOUD KONFIGURATION =================
    echo ""
    echo "☁️  NEXTCLOUD EINSTELLUNGEN"
    echo "----------------------------------------"
    read -p "Nextcloud Port [8080]: " NEXTCLOUD_PORT
    NEXTCLOUD_PORT=${NEXTCLOUD_PORT:-8080}
    
    read -p "Nextcloud Hostname [nextcloud.aetheron.local]: " NEXTCLOUD_HOSTNAME
    NEXTCLOUD_HOSTNAME=${NEXTCLOUD_HOSTNAME:-nextcloud.aetheron.local}
    
    read -p "Admin Username [admin]: " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}
    
    read -sp "Admin Password: " ADMIN_PASSWORD
    echo
    while [ -z "$ADMIN_PASSWORD" ]; do
        read -sp "Password cannot be empty: " ADMIN_PASSWORD
        echo
    done
    
    # ================= BESTÄTIGUNG =================
    echo ""
    echo "================================================"
    echo "           ZUSAMMENFASSUNG"
    echo "================================================"
    echo "🔸 Database: $DB_NAME (User: $DB_USER)"
    echo "🔸 Port: $NEXTCLOUD_PORT"
    echo "🔸 Hostname: $NEXTCLOUD_HOSTNAME"
    echo "🔸 Admin: $ADMIN_USER"
    echo "🔸 Data Location: $SERVICE_HOME/"
    echo "================================================"
    echo ""
    
    read -p "Konfiguration bestätigen? (j/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        log_message "❌ Konfiguration abgebrochen"
        return 1
    fi

    store_password "nextcloud" "$ADMIN_USER" "$ADMIN_PASSWORD"
    return 0
}

log_message "=== Starting Nextcloud Installation ==="

# === SCHRITT 0: Firewall prüfen ===
check_firewall

# === SCHRITT 1: Benutzer und Verzeichnisse anlegen ===
create_service_user "$SERVICE_USER" "$SERVICE_GROUP" "$SERVICE_HOME"
sudo mkdir -p "$DATA_DIR" "$CONFIG_DIR" "$HTML_DIR" "$LOG_DIR" "$APPS_DIR"
sudo chown -R "$SERVICE_USER":"$SERVICE_GROUP" "$SERVICE_HOME"
sudo chmod 755 "$LOG_DIR"

# === SCHRITT 2: Interaktive Konfiguration ===
if ! configure_nextcloud; then
    log_message "❌ ERROR: Configuration failed"
    exit 1
fi

# === SCHRITT 3: Docker Compose erstellen ===
log_message "Creating Docker Compose configuration..."
cat > "$(dirname "$0")/docker-compose.yml" << EOF
version: '3.8'

services:
  nextcloud:
    image: nextcloud:latest
    container_name: nextcloud
    user: "\${UID}:\${GID}"
    volumes:
      - $DATA_DIR:/var/www/html/data
      - $CONFIG_DIR:/var/www/html/config
      - $HTML_DIR:/var/www/html
      - $LOG_DIR:/var/www/html/logs
      - $APPS_DIR:/var/www/html/apps
    ports:
      - "$NEXTCLOUD_PORT:80"
    environment:
      - TZ=Europe/Berlin
      - UID=\${UID}
      - GID=\${GID}
      - MYSQL_HOST=mariadb
      - MYSQL_DATABASE=$DB_NAME
      - MYSQL_USER=$DB_USER
      - MYSQL_PASSWORD=$DB_PASSWORD
      - NEXTCLOUD_TRUSTED_DOMAINS=$NEXTCLOUD_HOSTNAME
    restart: unless-stopped
    depends_on:
      - mariadb
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

# === SCHRITT 4: Container starten ===
log_message "Starting Nextcloud container..."
if ! run_docker_compose "$SERVICE"; then
    log_message "❌ ERROR: Docker Compose failed"
    exit 1
fi

# === SCHRITT 5: Firewall Port öffnen ===
log_message "Configuring firewall..."
open_port "$NEXTCLOUD_PORT" "tcp" "Nextcloud - Web Interface"

# === SCHRITT 6: Log Rotation einrichten ===
setup_log_rotation "nextcloud" "$LOG_DIR"

log_message "=== Nextcloud Installation completed successfully ==="
echo ""
echo "✅ Nextcloud is now running!"
echo "   🌐 URL: http://$(hostname -I | awk '{print $1}'):$NEXTCLOUD_PORT"
echo "   👤 Admin: $ADMIN_USER"
echo "   📁 Data Location: $SERVICE_HOME/"
echo "   💾 Database: $DB_NAME@mariadb"
exit 0