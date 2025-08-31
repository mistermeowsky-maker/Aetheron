#!/bin/bash
# install.sh for quasselcore
# Version: 1.00.00

VERSION="1.00.00"
SERVICE="quasselcore"
SERVICE_USER="ircd"
SERVICE_GROUP="ircd"
SERVICE_HOME="/home/ircd"

# Pfade
QUASSEL_DIR="$SERVICE_HOME/quasselcore"
CONFIG_DIR="$QUASSEL_DIR/config"
LOG_DIR="/home/khryon/logs/quasselcore"

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

# Funktion für interaktive Konfiguration
configure_quasselcore() {
    log_message "Starting interactive QuasselCore configuration..."
    
    echo ""
    echo "=== QuasselCore Configuration ==="
    
    # Datenbank-Passwort abrufen
    DB_PASSWORD=$(get_password "postgresql" "quassel")
    if [[ -z "$DB_PASSWORD" ]]; then
        log_message "❌ ERROR: Could not retrieve database password"
        return 1
    fi

    # Netzwerk-Konfiguration
    read -p "Listen address [0.0.0.0]: " LISTEN_ADDRESS
    LISTEN_ADDRESS=${LISTEN_ADDRESS:-0.0.0.0}
    
    read -p "Listen port [4242]: " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-4242}
    
    read -p "Max simultaneous connections [50]: " MAX_CONNECTIONS
    MAX_CONNECTIONS=${MAX_CONNECTIONS:-50}

    # SSL Konfiguration
    read -p "Enable SSL? (j/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        SSL_ENABLED="true"
        read -p "SSL certificate file: " SSL_CERT_FILE
        read -p "SSL private key file: " SSL_KEY_FILE
    else
        SSL_ENABLED="false"
        SSL_CERT_FILE=""
        SSL_KEY_FILE=""
    fi

    # Config File erstellen
    log_message "Creating QuasselCore configuration..."
    sudo -u "$SERVICE_USER" tee "$CONFIG_DIR/quasselcore.conf" > /dev/null << EOF
# QuasselCore Configuration
# Auto-generated on $(date)

[Database]
StorageType=PostgreSQL
DatabaseName=quassel
UserName=quassel
Password=$DB_PASSWORD
Host=postgresql
Port=5432
ConnectionTimeout=30

[Authentication]
Method=Database

[Network]
Listen=$LISTEN_ADDRESS:$LISTEN_PORT
Timeout=120
MaxBufferSize=65536
MaxConnections=$MAX_CONNECTIONS
LocalHostname=quassel.aetheron.local

[Core]
SessionTimeout=1800
BacklogLimit=500
BacklogAge=30
MaxLogAge=90
BacklogRequiresAuthentication=true

[SSL]
UseSSL=$SSL_ENABLED
CertificateFile=$SSL_CERT_FILE
PrivateKeyFile=$SSL_KEY_FILE

[Logging]
LogLevel=Info
LogFile=$LOG_DIR/quasselcore.log
EOF

    # Docker Compose Config aktualisieren
    cat > "$(dirname "$0")/docker-compose.yml" << EOF
version: '3.8'

services:
  quasselcore:
    image: quassel/quassel-core:0.14.0
    container_name: quasselcore
    user: "\${UID}:\${GID}"
    volumes:
      - $CONFIG_DIR:/var/lib/quassel
      - $LOG_DIR:/var/log/quassel
    ports:
      - "$LISTEN_ADDRESS:$LISTEN_PORT:$LISTEN_PORT"
    environment:
      - TZ=Europe/Berlin
      - UID=\${UID}
      - GID=\${GID}
    restart: unless-stopped
    depends_on:
      - postgresql
    healthcheck:
      test: ["CMD", "pg_isready", "-h", "postgresql", "-U", "quassel"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

    log_message "✅ Configuration completed"
    return 0
}

log_message "=== Starting QuasselCore Installation ==="

# === SCHRITT 0: Firewall prüfen ===
check_firewall

# === SCHRITT 1: Verzeichnisse anlegen ===
log_message "Creating directories..."
sudo mkdir -p "$QUASSEL_DIR" "$CONFIG_DIR" "$LOG_DIR"
sudo chown -R "$SERVICE_USER":"$SERVICE_GROUP" "$QUASSEL_DIR"
sudo chown -R khryon:users "$LOG_DIR"
sudo chmod 755 "$LOG_DIR"

# === SCHRITT 2: Interaktive Konfiguration ===
if ! configure_quasselcore; then
    log_message "❌ ERROR: Configuration failed"
    exit 1
fi

# === SCHRITT 3: Container starten ===
log_message "Starting QuasselCore container..."
if ! run_docker_compose "$SERVICE"; then
    log_message "❌ ERROR: Docker Compose failed"
    exit 1
fi

# === SCHRITT 4: Firewall Port öffnen ===
log_message "Configuring firewall..."
open_port "$LISTEN_PORT" "tcp" "QuasselCore - IRC Client"

# === SCHRITT 5: Log Rotation einrichten ===
setup_log_rotation "quasselcore" "$LOG_DIR"

# === SCHRITT 6: Verbindungstest ===
log_message "Testing connection..."
sleep 5
if docker logs quasselcore 2>&1 | grep -q "Database connection established"; then
    log_message "✅ QuasselCore installation successful"
    
    echo ""
    echo "================================================"
    echo "🎯 QUASSELCORE INSTALLATION COMPLETE"
    echo "================================================"
    echo "Connect to: $LISTEN_ADDRESS:$LISTEN_PORT"
    echo "Config: $CONFIG_DIR/quasselcore.conf"
    echo "Logs: $LOG_DIR/"
    echo "================================================"
    
else
    log_message "❌ ERROR: QuasselCore startup failed"
    docker-compose -f "$(dirname "$0")/docker-compose.yml" down
    exit 1
fi

log_message "=== QuasselCore Installation completed successfully ==="
exit 0