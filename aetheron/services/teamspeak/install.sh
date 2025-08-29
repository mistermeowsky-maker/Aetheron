#!/bin/bash
# install.sh for teamspeak
# Version: 1.00.00

VERSION="1.00.00"
SERVICE="teamspeak"
SERVICE_USER="teamspeak"
SERVICE_GROUP="teamspeak"
SERVICE_HOME="/home/teamspeak"

# Pfade
DATA_DIR="$SERVICE_HOME/data"
LOG_DIR="/home/khryon/logs/teamspeak"

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

# Funktion für interaktive Konfiguration
configure_teamspeak() {
    log_message "Starting interactive TeamSpeak configuration..."
    
    echo ""
    echo "================================================"
    echo "           TEAMSPEAK KONFIGURATION"
    echo "================================================"
    
    # ================= NETZWERK KONFIGURATION =================
    echo ""
    echo "🌐 NETZWERK-EINSTELLUNGEN"
    echo "----------------------------------------"
    read -p "Server Query Port [10011]: " QUERY_PORT
    QUERY_PORT=${QUERY_PORT:-10011}
    
    read -p "File Transfer Port [30033]: " FILE_TRANSFER_PORT
    FILE_TRANSFER_PORT=${FILE_TRANSFER_PORT:-30033}
    
    read -p "Voice Port [9987]: " VOICE_PORT
    VOICE_PORT=${VOICE_PORT:-9987}
    
    read -p "Voice IP [0.0.0.0]: " VOICE_IP
    VOICE_IP=${VOICE_IP:-0.0.0.0}
    
    # ================= SERVER KONFIGURATION =================
    echo ""
    echo "⚙️  SERVER-EINSTELLUNGEN"
    echo "----------------------------------------"
    read -p "Max Clients [32]: " MAX_CLIENTS
    MAX_CLIENTS=${MAX_CLIENTS:-32}
    
    read -p "Server Name [Aetheron Voice]: " SERVER_NAME
    SERVER_NAME=${SERVER_NAME:-Aetheron Voice}
    
    read -p "Welcome Message [Willkommen auf Aetheron]: " WELCOME_MESSAGE
    WELCOME_MESSAGE=${WELCOME_MESSAGE:-Willkommen auf Aetheron}
    
    # ================= ADMIN KONFIGURATION =================
    echo ""
    echo "👮 ADMIN-KONFIGURATION"
    echo "----------------------------------------"
    read -p "Server Admin Benutzername [serveradmin]: " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-serveradmin}
    
    read -sp "Server Admin Passwort: " ADMIN_PASSWORD
    echo
    while [ -z "$ADMIN_PASSWORD" ]; do
        read -sp "Passwort darf nicht leer sein: " ADMIN_PASSWORD
        echo
    done
    
    # ================= BESTÄTIGUNG =================
    echo ""
    echo "================================================"
    echo "           ZUSAMMENFASSUNG"
    echo "================================================"
    echo "🔸 Server: $SERVER_NAME"
    echo "🔸 Ports: Voice $VOICE_PORT, Query $QUERY_PORT, File $FILE_TRANSFER_PORT"
    echo "🔸 Max Clients: $MAX_CLIENTS"
    echo "🔸 Admin: $ADMIN_USER"
    echo "================================================"
    echo ""
    
    read -p "Konfiguration bestätigen? (j/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        log_message "❌ Konfiguration abgebrochen"
        return 1
    fi

    # Passwort speichern
    store_password "teamspeak" "$ADMIN_USER" "$ADMIN_PASSWORD"
    
    return 0
}

log_message "=== Starting TeamSpeak Installation ==="

# === SCHRITT 0: Firewall prüfen ===
check_firewall

# === SCHRITT 1: Benutzer und Verzeichnisse anlegen ===
create_service_user "$SERVICE_USER" "$SERVICE_GROUP" "$SERVICE_HOME"
sudo mkdir -p "$DATA_DIR" "$LOG_DIR"
sudo chown -R "$SERVICE_USER":"$SERVICE_GROUP" "$DATA_DIR"
sudo chown -R khryon:users "$LOG_DIR"
sudo chmod 755 "$LOG_DIR"

# === SCHRITT 2: Interaktive Konfiguration ===
if ! configure_teamspeak; then
    log_message "❌ ERROR: Configuration failed"
    exit 1
fi

# === SCHRITT 3: Docker Compose erstellen ===
log_message "Creating Docker Compose configuration..."
cat > "$(dirname "$0")/docker-compose.yml" << EOF
version: '3.8'

services:
  teamspeak:
    image: teamspeak:latest
    container_name: teamspeak
    user: "\${UID}:\${GID}"
    volumes:
      - $DATA_DIR:/var/ts3server
      - $LOG_DIR:/var/log/ts3server
    ports:
      - "$VOICE_IP:$VOICE_PORT:$VOICE_PORT/udp"
      - "$QUERY_PORT:$QUERY_PORT"
      - "$FILE_TRANSFER_PORT:$FILE_TRANSFER_PORT"
    environment:
      - TS3SERVER_LICENSE=accept
      - TS3SERVER_MAX_CLIENTS=$MAX_CLIENTS
      - TS3SERVER_SERVER_NAME=$SERVER_NAME
      - TS3SERVER_WELCOME_MESSAGE=$WELCOME_MESSAGE
      - TS3SERVER_SERVERADMIN_PASSWORD=$ADMIN_PASSWORD
      - TZ=Europe/Berlin
      - UID=\${UID}
      - GID=\${GID}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "10011"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

# === SCHRITT 4: Container starten ===
log_message "Starting TeamSpeak container..."
if ! run_docker_compose "$SERVICE"; then
    log_message "❌ ERROR: Docker Compose failed"
    exit 1
fi

# === SCHRITT 5: Firewall Ports öffnen ===
log_message "Configuring firewall..."
open_port "$VOICE_PORT" "udp" "TeamSpeak - Voice"
open_port "$QUERY_PORT" "tcp" "TeamSpeak - Query"
open_port "$FILE_TRANSFER_PORT" "tcp" "TeamSpeak - File Transfer"

# === SCHRITT 6: Log Rotation einrichten ===
setup_log_rotation "teamspeak" "$LOG_DIR"

log_message "=== TeamSpeak Installation completed successfully ==="
echo ""
echo "✅ TeamSpeak Server is now running!"
echo "   🎤 Voice: udp://$(hostname -I | awk '{print $1}'):$VOICE_PORT"
echo "   🔧 Query: $QUERY_PORT"
echo "   📁 File Transfer: $FILE_TRANSFER_PORT"
echo "   👮 Admin: $ADMIN_USER"
echo "   🔐 Password saved in master password file"
exit 0