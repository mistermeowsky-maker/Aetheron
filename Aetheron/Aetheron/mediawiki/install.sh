#!/bin/bash
# install.sh for mediawiki
# Version: 1.00.01

VERSION="1.00.01"
SERVICE="mediawiki"
SERVICE_USER="mediawiki"
SERVICE_GROUP="mediawiki"
SERVICE_HOME="/home/$SERVICE_USER"

# Pfade für Daten und Konfiguration
DB_DIR="/srv/mediawiki/db"                    # Datenbank auf großem Volume
UPLOAD_DIR="/srv/www/mediawiki/images"        # Uploads auf großem Volume
CONFIG_DIR="$SERVICE_HOME/config"             # Konfiguration im Home
LOG_DIR="/home/khryon/logs/mediawiki"         # Logs beim Hauptuser

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

log_message "=== Starting MediaWiki Installation ==="

# === SCHRITT 1: Benutzer und Verzeichnisse anlegen ===
create_service_user "$SERVICE_USER" "$SERVICE_GROUP" "$SERVICE_HOME"

# Verzeichnisse anlegen
sudo mkdir -p "$DB_DIR" "$UPLOAD_DIR" "$CONFIG_DIR" "$LOG_DIR"

# Berechtigungen setzen
sudo chown -R 999:999 "$DB_DIR"                     # MySQL User
sudo chmod 700 "$DB_DIR"
sudo chown -R "$SERVICE_USER":"$SERVICE_GROUP" "$UPLOAD_DIR" "$CONFIG_DIR"
sudo chown -R khryon:users "$LOG_DIR"

# === SCHRITT 2: Docker Compose Konfiguration erstellen (OHNE Port-Exposure) ===
log_message "Creating Docker Compose configuration..."

cat > "$(dirname "$0")/docker-compose.yml" << EOF
version: '3.8'

services:
  mediawiki:
    image: mediawiki:1.39
    container_name: mediawiki
    user: "\${UID}:\${GID}"
    volumes:
      - $UPLOAD_DIR:/var/www/html/images
      - $CONFIG_DIR:/var/www/html/config
      - $LOG_DIR:/var/log/apache2
    environment:
      - MEDIAWIKI_DB_HOST=mediawiki-db
      - MEDIAWIKI_DB_NAME=mediawiki
      - MEDIAWIKI_DB_USER=mediawiki_user
      - MEDIAWIKI_DB_PASSWORD=\${MEDIAWIKI_DB_PASSWORD}
    restart: unless-stopped
    networks:
      - mediawiki-internal

  mediawiki-db:
    image: mariadb:10.11.7
    container_name: mediawiki-db
    user: "999:999"
    volumes:
      - $DB_DIR:/var/lib/mysql
    environment:
      - MYSQL_DATABASE=mediawiki
      - MYSQL_USER=mediawiki_user
      - MYSQL_PASSWORD=\${MEDIAWIKI_DB_PASSWORD}
      - MYSQL_RANDOM_ROOT_PASSWORD=yes
    restart: unless-stopped
    networks:
      - mediawiki-internal

networks:
  mediawiki-internal:
    internal: true  # Nur interne Container-Kommunikation
EOF

# === SCHRITT 3: Datenbank-Passwort setzen ===
log_message "Generating database password..."
MEDIAWIKI_DB_PASSWORD=$(generate_strong_password)
export MEDIAWIKI_DB_PASSWORD

# Passwort sicher speichern
echo "$MEDIAWIKI_DB_PASSWORD" | sudo tee "$SERVICE_HOME/db_password.txt" > /dev/null
sudo chmod 600 "$SERVICE_HOME/db_password.txt"
sudo chown "$SERVICE_USER":"$SERVICE_GROUP" "$SERVICE_HOME/db_password.txt"

# === SCHRITT 4: Container starten ===
log_message "Starting MediaWiki containers..."
run_docker_compose "$SERVICE"

# === SCHRITT 5: Log Rotation einrichten ===
setup_log_rotation "mediawiki" "$LOG_DIR"

# === SCHRITT 6: Installation testen (intern im Docker Network) ===
log_message "Testing MediaWiki installation..."
sleep 15  # Warten bis Container ready

# Teste ob MediaWiki innerhalb des Docker Networks erreichbar ist
if docker exec mediawiki curl -s http://mediawiki | grep -q "MediaWiki"; then
    log_message "✅ MediaWiki installation successful"
    log_message "   Database password saved: $SERVICE_HOME/db_password.txt"
    log_message "   Ready for Reverse-Proxy setup"
else
    log_message "❌ MediaWiki installation failed"
    docker-compose -f "$(dirname "$0")/docker-compose.yml" logs
    exit 1
fi

# === SCHRITT 7: Reverse-Proxy Hinweis ===
log_message "=== MediaWiki Installation completed ==="
log_message "Next steps:"
log_message "1. Configure Reverse-Proxy on your Raspberry Pi"
log_message "2. Point to this server's internal Docker network"
log_message "3. Setup SSL certificates for HTTPS"
log_message "4. Access via https://your-domain.com"

exit 0