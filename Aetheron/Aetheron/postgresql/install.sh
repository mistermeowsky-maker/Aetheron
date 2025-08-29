#!/bin/bash
# install.sh for postgresql
# Version: 1.00.00

VERSION="1.00.00"
SERVICE="postgresql"
SERVICE_USER="postgres"
SERVICE_GROUP="postgres"
SERVICE_HOME="/home/ircd"  # Wichtig: Kommt in IRC-Block!

# Pfade für Daten und Konfiguration
DATA_DIR="$SERVICE_HOME/postgresql/data"
CONFIG_DIR="$SERVICE_HOME/postgresql/config"
LOG_DIR="/home/khryon/logs/postgresql"

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

# Funktion zur Generierung eines starken Passworts
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

log_message "=== Starting PostgreSQL Installation ==="

# === SCHRITT 0: Firewall prüfen ===
check_firewall

# === SCHRITT 1: Verzeichnisse anlegen ===
log_message "Creating directories..."
sudo mkdir -p "$DATA_DIR" "$CONFIG_DIR" "$LOG_DIR"
sudo chown -R 999:999 "$DATA_DIR"  # PostgreSQL Container User
sudo chmod 700 "$DATA_DIR"
sudo chown -R khryon:users "$LOG_DIR"
sudo chmod 755 "$LOG_DIR"

# === SCHRITT 2: Starke Passwörter generieren ===
log_message "Generating strong passwords..."
POSTGRES_PASSWORD=$(generate_strong_password)
QUASSEL_PASSWORD=$(generate_strong_password)

# Passwörter sicher speichern
store_password "postgresql" "postgres" "$POSTGRES_PASSWORD"
store_password "postgresql" "quassel" "$QUASSEL_PASSWORD"

# === SCHRITT 3: Docker Compose erstellen ===
log_message "Creating Docker Compose configuration..."
cat > "$(dirname "$0")/docker-compose.yml" << EOF
version: '3.8'

services:
  postgresql:
    image: postgres:15.4  # Feste Version für Stabilität
    container_name: postgresql
    user: "999:999"
    volumes:
      - $DATA_DIR:/var/lib/postgresql/data
      - $CONFIG_DIR:/etc/postgresql/config
      - $LOG_DIR:/var/log/postgresql
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=$POSTGRES_PASSWORD
      - POSTGRES_DB=quassel
      - POSTGRES_INITDB_ARGS=--encoding=UTF-8
      - TZ=Europe/Berlin
    ports:
      - "127.0.0.1:5432:5432"  # Nur lokal erreichbar!
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

# === SCHRITT 4: Container starten ===
log_message "Starting PostgreSQL container..."
if ! run_docker_compose "$SERVICE"; then
    log_message "❌ ERROR: Docker Compose failed. Removing container..."
    docker-compose -f "$(dirname "$0")/docker-compose.yml" down
    exit 1
fi

# Warten bis PostgreSQL ready ist
sleep 10

# === SCHRITT 5: Quassel Database & User anlegen ===
log_message "Creating Quassel database and user..."
docker exec postgresql psql -U postgres -c "
CREATE USER quassel WITH PASSWORD '$QUASSEL_PASSWORD';
CREATE DATABASE quassel OWNER quassel;
GRANT ALL PRIVILEGES ON DATABASE quassel TO quassel;
\c quassel
GRANT ALL ON SCHEMA public TO quassel;
"

# === SCHRITT 6: Firewall konfigurieren ===
log_message "Configuring firewall..."
close_port 5432 "tcp" "PostgreSQL - Only localhost access"

# === SCHRITT 7: Log Rotation einrichten ===
setup_log_rotation "postgresql" "$LOG_DIR"

# === SCHRITT 8: Verbindungstest ===
log_message "Testing connection..."
if docker exec postgresql psql -U quassel -d quassel -c "SELECT 1;" > /dev/null 2>&1; then
    log_message "✅ PostgreSQL installation successful"
    
    echo ""
    echo "================================================"
    echo "🔐 POSTGRESQL CREDENTIALS"
    echo "================================================"
    echo "Admin User: postgres"
    echo "Admin Password: $POSTGRES_PASSWORD"
    echo ""
    echo "App User: quassel"  
    echo "App Password: $QUASSEL_PASSWORD"
    echo "Database: quassel"
    echo ""
    echo "⚠️  Passwords saved in master password file"
    echo "================================================"
    
else
    log_message "❌ ERROR: Connection test failed"
    docker-compose -f "$(dirname "$0")/docker-compose.yml" down
    exit 1
fi

log_message "=== PostgreSQL Installation completed successfully ==="
exit 0