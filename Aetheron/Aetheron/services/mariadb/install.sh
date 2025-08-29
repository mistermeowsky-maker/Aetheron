#!/bin/bash
# install.sh for mariadb
# Version: 1.00.02

VERSION="1.00.02"
SERVICE="mariadb"
SERVICE_USER="mariadb"
SERVICE_GROUP="mariadb"
SERVICE_HOME="/home/$SERVICE_USER"

# Pfade für Daten und Konfiguration
DATA_DIR="/srv/mariadb"
CONFIG_DIR="$SERVICE_HOME/config"
LOG_DIR="/home/khryon/logs/mariadb"

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

# Funktion zur Generierung eines starken Passworts (genau 1 Sonderzeichen)
generate_strong_password() {
    local length=20
    local upper="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local lower="abcdefghijklmnopqrstuvwxyz"
    local digits="0123456789"
    local special="!@#$%^&*()_+-=[]{}|;:,.<>?~"
    
    # Garantierte Zeichen (je 1x)
    local guaranteed_chars=$( \
        echo "${upper:$((RANDOM % ${#upper})):1}" \
        "${lower:$((RANDOM % ${#lower})):1}" \
        "${digits:$((RANDOM % ${#digits})):1}" \
        "${special:$((RANDOM % ${#special})):1}" \
        | tr -d ' ' \
    )
    
    # Restliche Zeichen (nur Buchstaben und Zahlen - keine Sonderzeichen)
    local all_chars_no_special="${upper}${lower}${digits}"
    local remaining_chars=""
    for ((i=0; i<16; i++)); do
        remaining_chars+="${all_chars_no_special:$((RANDOM % ${#all_chars_no_special})):1}"
    done
    
    # Kombiniere und mische
    local combined_chars="${guaranteed_chars}${remaining_chars}"
    local password=$(echo "$combined_chars" | fold -w1 | shuf | tr -d '\n')
    
    echo "$password"
}

log_message "=== Starting MariaDB Installation ==="

# === SCHRITT 0: Firewall prüfen (inkl. SSH Access) ===
check_firewall

# === SCHRITT 1: Benutzer und Verzeichnisse anlegen ===
create_service_user "$SERVICE_USER" "$SERVICE_GROUP" "$SERVICE_HOME"
sudo mkdir -p "$DATA_DIR" "$CONFIG_DIR" "$LOG_DIR"
sudo chown -R 999:999 "$DATA_DIR"
sudo chmod 700 "$DATA_DIR"
sudo chown -R "$SERVICE_USER":"$SERVICE_GROUP" "$CONFIG_DIR"
sudo chown -R khryon:users "$LOG_DIR"
sudo chmod 755 "$LOG_DIR"

# === SCHRITT 2: Starke Passwörter generieren ===
log_message "Generating strong passwords..."
DBADMIN_PASSWORD=$(generate_strong_password)
TEMP_ROOT_PASSWORD=$(generate_strong_password)

# Passwort sicher speichern
echo "$DBADMIN_PASSWORD" | sudo tee "$SERVICE_HOME/dbadmin_password.txt" > /dev/null
sudo chmod 600 "$SERVICE_HOME/dbadmin_password.txt"
sudo chown "$SERVICE_USER":"$SERVICE_GROUP" "$SERVICE_HOME/dbadmin_password.txt"

# In Master-Passwort File speichern
store_password "mariadb" "dbadmin" "$DBADMIN_PASSWORD"

# === SCHRITT 3: Docker Compose mit fester Version erstellen ===
log_message "Creating Docker Compose configuration..."
cat > "$(dirname "$0")/docker-compose.yml" << EOF
version: '3.8'

services:
  mariadb:
    image: mariadb:10.11.7  # Feste Version für Stabilität
    container_name: mariadb
    user: "999:999"
    volumes:
      - $DATA_DIR:/var/lib/mysql
      - $CONFIG_DIR:/etc/mysql/conf.d
      - $LOG_DIR:/var/log/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=$TEMP_ROOT_PASSWORD
      - MYSQL_CHARSET=utf8mb4
      - MYSQL_COLLATION=utf8mb4_unicode_ci
    ports:
      - "127.0.0.1:3306:3306"  # Nur lokal erreichbar!
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

# === SCHRITT 4: Container starten ===
log_message "Starting MariaDB container for initial setup..."
if ! run_docker_compose "$SERVICE"; then
    log_message "❌ ERROR: Docker Compose failed. Removing container..."
    docker-compose -f "$(dirname "$0")/docker-compose.yml" down
    exit 1
fi

# Warten bis MariaDB vollständig hochgefahren ist
sleep 10

# === SCHRITT 5: Root deaktivieren und dbadmin anlegen ===
log_message "Securing MariaDB installation..."
if ! docker exec mariadb mysql -u root -p"$TEMP_ROOT_PASSWORD" << EOF
-- UTF-8 als default setzen
SET GLOBAL character_set_server = 'utf8mb4';
SET GLOBAL collation_server = 'utf8mb4_unicode_ci';

-- dbadmin User mit allen Rechten erstellen
CREATE USER 'dbadmin'@'%' IDENTIFIED BY '$DBADMIN_PASSWORD';
GRANT ALL PRIVILEGES ON *.* TO 'dbadmin'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;

-- Root User deaktivieren
DROP USER 'root'@'%';
DROP USER 'root'@'localhost';
FLUSH PRIVILEGES;
EOF
then
    log_message "❌ ERROR: Failed to secure MariaDB. Removing container..."
    docker-compose -f "$(dirname "$0")/docker-compose.yml" down
    exit 1
fi

# === SCHRITT 6: Konfiguration ohne Root-Password aktualisieren ===
log_message "Updating Docker Compose without root password..."
cat > "$(dirname "$0")/docker-compose.yml" << EOF
version: '3.8'

services:
  mariadb:
    image: mariadb:10.11.7
    container_name: mariadb
    user: "999:999"
    volumes:
      - $DATA_DIR:/var/lib/mysql
      - $CONFIG_DIR:/etc/mysql/conf.d
      - $LOG_DIR:/var/log/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=
      - MYSQL_CHARSET=utf8mb4
      - MYSQL_COLLATION=utf8mb4_unicode_ci
    ports:
      - "127.0.0.1:3306:3306"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

# Container neustarten
docker-compose -f "$(dirname "$0")/docker-compose.yml" down
docker-compose -f "$(dirname "$0")/docker-compose.yml" up -d
sleep 5

# === SCHRITT 7: Firewall und Log Rotation ===
log_message "Configuring firewall and log rotation..."
close_port 3306 "tcp" "MariaDB - Only localhost access"
setup_log_rotation "mariadb" "$LOG_DIR"

# === SCHRITT 8: Verbindungstest mit dbadmin ===
log_message "Testing connection with dbadmin user..."
if docker exec mariadb mysql -u dbadmin -p"$DBADMIN_PASSWORD" -e "SELECT 1; SHOW VARIABLES LIKE 'character_set_server';" > /dev/null 2>&1; then
    log_message "✅ MariaDB installation successful and secure."
    
    # Passwort anzeigen und loggen
    echo ""
    echo "================================================"
    echo "🔐 MARIADB SECURE CREDENTIALS"
    echo "================================================"
    echo "DB Admin User: dbadmin"
    echo "DB Admin Password: $DBADMIN_PASSWORD"
    echo ""
    echo "⚠️  This password has been saved to:"
    echo "    $SERVICE_HOME/dbadmin_password.txt"
    echo "    $BASE_DIR/.master_passwords"
    echo "================================================"
    echo ""
    
    log_message "UTF-8 Encoding: Enabled"
    
else
    log_message "❌ ERROR: Failed to connect with dbadmin user."
    docker-compose -f "$(dirname "$0")/docker-compose.yml" down
    exit 1
fi

log_message "=== MariaDB Installation completed successfully ==="
exit 0