#!/bin/bash
# install.sh for anope
# Version: 1.02.00  # Mit HTTPS-Webpanel und erweiterter Fehlerbehandlung

VERSION="1.02.00"
SERVICE="anope"
SERVICE_USER="ircd"
SERVICE_GROUP="ircd"
SERVICE_HOME="/home/ircd"

# Pfade für Anope
ANOPE_DIR="$SERVICE_HOME/anope"
CONFIG_DIR="$ANOPE_DIR/conf"
LOG_DIR="/home/khryon/logs/anope"
SSL_DIR="/home/khryon/ssl"

# Load common functions
if [ -f "$(dirname "$0")/../../scripts/common.sh" ]; then
    source $(dirname "$0")/../../scripts/common.sh
else
    echo "❌ ERROR: common.sh not found. Please install common scripts first."
    exit 1
fi

# Funktion für interaktive Konfiguration
configure_anope() {
    log_message "Starting interactive Anope configuration..."
    
    echo ""
    echo "================================================"
    echo "           ANOPE SERVICES KONFIGURATION"
    echo "================================================"
    
    # ================= NETZWERK KONFIGURATION =================
    echo ""
    echo "🌐 NETZWERK-EINSTELLUNGEN"
    echo "----------------------------------------"
    read -p "Netzwerk-Name [AetheronIRC]: " NETWORK_NAME
    NETWORK_NAME=${NETWORK_NAME:-AetheronIRC}
    
    read -p "Services Hostname [services.aetheron.local]: " SERVICES_HOST
    SERVICES_HOST=${SERVICES_HOST:-services.aetheron.local}
    
    # ================= UNREALIRCD UPLINK =================
    echo ""
    echo "🔗 UNREALIRCD UPLINK"
    echo "----------------------------------------"
    
    # Prüfen ob UnrealIRCd installiert ist
    if ! check_service_running "unrealircd"; then
        echo "⚠️  UnrealIRCd scheint nicht installiert oder nicht aktiv zu sein."
        read -p "Trotzdem fortfahren? (j/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Jj]$ ]]; then
            return 1
        fi
    fi
    
    read -p "UnrealIRCd Host [unrealircd]: " UPLINK_HOST
    UPLINK_HOST=${UPLINK_HOST:-unrealircd}
    
    read -p "UnrealIRCd Port [6667]: " UPLINK_PORT
    UPLINK_PORT=${UPLINK_PORT:-6667}
    
    read -sp "Uplink Passwort: " UPLINK_PASSWORD
    echo
    while [ -z "$UPLINK_PASSWORD" ]; do
        read -sp "Passwort darf nicht leer sein: " UPLINK_PASSWORD
        echo
    done
    
    # ================= SERVICES KONFIGURATION =================
    echo ""
    echo "⚙️  SERVICES-EINSTELLUNGEN"
    echo "----------------------------------------"
    read -p "NickServ Nickname [NickServ]: " NICKSERV_NICK
    NICKSERV_NICK=${NICKSERV_NICK:-NickServ}
    
    read -p "ChanServ Nickname [ChanServ]: " CHANSERV_NICK
    CHANSERV_NICK=${CHANSERV_NICK:-ChanServ}
    
    read -p "MemoServ Nickname [MemoServ]: " MEMOSERV_NICK
    MEMOSERV_NICK=${MEMOSERV_NICK:-MemoServ}
    
    read -p "OperServ Nickname [OperServ]: " OPERSERV_NICK
    OPERSERV_NICK=${OPERSERV_NICK:-OperServ}
    
    # ================= WEB PANEL KONFIGURATION =================
    echo ""
    echo "🌐 WEB PANEL"
    echo "----------------------------------------"
    read -p "Web Panel aktivieren? (j/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        WEB_PANEL="true"
        read -p "Web Panel Port [8443]: " WEB_PORT
        WEB_PORT=${WEB_PORT:-8443}
        
        read -p "Web Panel Benutzername [admin]: " WEB_USER
        WEB_USER=${WEB_USER:-admin}
        
        read -sp "Web Panel Passwort: " WEB_PASSWORD
        echo
        while [ -z "$WEB_PASSWORD" ]; do
            read -sp "Passwort darf nicht leer sein: " WEB_PASSWORD
            echo
        done
        
        # SSL Zertifikat Konfiguration
        echo ""
        echo "🔒 SSL ZERTIFIKAT"
        echo "----------------------------------------"
        if [ -f "$SSL_DIR/fullchain.pem" ] && [ -f "$SSL_DIR/privkey.pem" ]; then
            echo "✅ Vorhandene SSL Zertifikate gefunden in $SSL_DIR"
            USE_EXISTING_SSL="true"
        else
            echo "ℹ️  Keine SSL Zertifikate gefunden. Selbstsigniertes Zertifikat wird generiert."
            USE_EXISTING_SSL="false"
        fi
    else
        WEB_PANEL="false"
        WEB_PORT="8443"
        WEB_USER=""
        WEB_PASSWORD=""
        USE_EXISTING_SSL="false"
    fi
    
    # ================= BESTÄTIGUNG =================
    echo ""
    echo "================================================"
    echo "           ZUSAMMENFASSUNG"
    echo "================================================"
    echo "🔸 Netzwerk: $NETWORK_NAME"
    echo "🔸 Services Host: $SERVICES_HOST"
    echo "🔸 Uplink: $UPLINK_HOST:$UPLINK_PORT"
    echo "🔸 Services: $NICKSERV_NICK, $CHANSERV_NICK, $MEMOSERV_NICK, $OPERSERV_NICK"
    if [[ "$WEB_PANEL" == "true" ]]; then
        echo "🔸 Web Panel: HTTPS Port $WEB_PORT (User: $WEB_USER)"
        if [[ "$USE_EXISTING_SSL" == "true" ]]; then
            echo "🔸 SSL: Vorhandene Zertifikate werden verwendet"
        else
            echo "🔸 SSL: Selbstsigniertes Zertifikat wird generiert"
        fi
    else
        echo "🔸 Web Panel: Deaktiviert"
    fi
    echo "================================================"
    echo ""
    
    read -p "Konfiguration bestätigen? (j/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        log_message "❌ Konfiguration abgebrochen"
        return 1
    fi

    # ================= KONFIGURATION ERSTELLEN =================
    log_message "Creating Anope configuration..."
    sudo -u "$SERVICE_USER" tee "$CONFIG_DIR/services.conf" > /dev/null << EOF
# Anope IRC Services Configuration
# Auto-generated on $(date)

// ================= NETWORK KONFIGURATION =================
network {
    name = "$NETWORK_NAME"
    nick = "Global"
    user = "Service"
    host = "$SERVICES_HOST"
    gecos = "Aetheron IRC Services"
};

// ================= SERVER KONFIGURATION =================
server {
    name = "$SERVICES_HOST"
    pid = "/anope/data/services.pid"
    motd = "/anope/conf/motd.txt"
};

// ================= UPLINK KONFIGURATION =================
uplink {
    host = "$UPLINK_HOST"
    port = $UPLINK_PORT
    password = "$UPLINK_PASSWORD"
};

// ================= SERVICES KONFIGURATION =================
service {
    name = "NickServ"
    nick = "$NICKSERV_NICK"
    user = "service"
    host = "$SERVICES_HOST"
};

service {
    name = "ChanServ"
    nick = "$CHANSERV_NICK"
    user = "service"
    host = "$SERVICES_HOST"
};

service {
    name = "MemoServ"
    nick = "$MEMOSERV_NICK"
    user = "service"
    host = "$SERVICES_HOST"
};

service {
    name = "OperServ"
    nick = "$OPERSERV_NICK"
    user = "service"
    host = "$SERVICES_HOST"
};

// ================= MODULE KONFIGURATION =================
module {
    name = "cs_register"
    maxusers = 10
};

module {
    name = "ns_register"
    registration = "none"
};

module {
    name = "os_session"
};

module {
    name = "hs_request"
};

// ================= WEB PANEL KONFIGURATION =================
module {
    name = "webcpanel"
    port = $WEB_PORT
    user = "$WEB_USER"
    password = "$WEB_PASSWORD"
    ssl = true
    ssl_cert = "/anope/ssl/cert.pem"
    ssl_key = "/anope/ssl/key.pem"
    timeout = 30
};

// ================= LOGGING KONFIGURATION =================
log {
    target = "file"
    name = "anope.log"
    level = info
};

log {
    target = "file"
    name = "oper.log"
    level = debug
    type = "OPER"
};
EOF

    # Motd Datei erstellen
    sudo -u "$SERVICE_USER" tee "$CONFIG_DIR/motd.txt" > /dev/null << EOF
Welcome to $NETWORK_NAME IRC Services
Running on $SERVICES_HOST
Connected to $UPLINK_HOST:$UPLINK_PORT
EOF

    log_message "✅ Anope configuration created"
    return 0
}

# Funktion zur SSL Zertifikatserstellung
setup_ssl_certificates() {
    local ssl_dir="$ANOPE_DIR/ssl"
    mkdir -p "$ssl_dir"
    chown -R "$SERVICE_USER":"$SERVICE_GROUP" "$ssl_dir"
    
    if [[ "$USE_EXISTING_SSL" == "true" ]] && [ -f "$SSL_DIR/fullchain.pem" ] && [ -f "$SSL_DIR/privkey.pem" ]; then
        log_message "Using existing SSL certificates from $SSL_DIR"
        cp "$SSL_DIR/fullchain.pem" "$ssl_dir/cert.pem"
        cp "$SSL_DIR/privkey.pem" "$ssl_dir/key.pem"
    else
        log_message "Generating self-signed SSL certificate..."
        openssl req -x509 -newkey rsa:4096 -keyout "$ssl_dir/key.pem" -out "$ssl_dir/cert.pem" \
            -days 365 -nodes -subj "/CN=$SERVICES_HOST" 2>/dev/null
        
        if [ $? -ne 0 ]; then
            log_message "⚠️  SSL certificate generation failed, continuing without SSL"
            return 1
        fi
    fi
    
    chmod 600 "$ssl_dir/key.pem"
    chmod 644 "$ssl_dir/cert.pem"
    log_message "✅ SSL certificates setup completed"
    return 0
}

log_message "=== Starting Anope Installation ==="

# === SCHRITT 0: Abhängigkeiten prüfen ===
check_dependency "docker"
check_dependency "docker-compose"
check_dependency "openssl" "optional"

# === SCHRITT 1: Verzeichnisse anlegen ===
sudo mkdir -p "$ANOPE_DIR" "$CONFIG_DIR" "$LOG_DIR" "$SSL_DIR"
sudo chown -R "$SERVICE_USER":"$SERVICE_GROUP" "$ANOPE_DIR"
sudo chown -R khryon:users "$LOG_DIR" "$SSL_DIR"
sudo chmod 755 "$LOG_DIR" "$SSL_DIR"

# === SCHRITT 2: Interaktive Konfiguration ===
if ! configure_anope; then
    log_message "❌ ERROR: Configuration failed"
    exit 1
fi

# === SCHRITT 3: SSL Zertifikate einrichten (falls Web Panel aktiviert) ===
if [[ "$WEB_PANEL" == "true" ]]; then
    if ! setup_ssl_certificates; then
        log_message "⚠️  SSL setup had issues, but continuing with installation"
    fi
fi

# === SCHRITT 4: Docker Compose erstellen ===
log_message "Creating Docker Compose configuration..."

# UID und GID ermitteln
CURRENT_UID=$(id -u "$SERVICE_USER" 2>/dev/null || echo "1000")
CURRENT_GID=$(id -g "$SERVICE_GROUP" 2>/dev/null || echo "1000")

# Web Ports nur wenn aktiviert
local web_ports=""
if [[ "$WEB_PANEL" == "true" ]]; then
    web_ports="      - \"$WEB_PORT:$WEB_PORT\""
fi

cat > "$(dirname "$0")/docker-compose.yml" << EOF
version: '3.8'

services:
  anope:
    image: anope/anope:2.0.10
    container_name: anope
    user: "$CURRENT_UID:$CURRENT_GID"
    volumes:
      - $ANOPE_DIR/data:/anope/data
      - $CONFIG_DIR:/anope/conf
      - $LOG_DIR:/anope/logs
      - $ANOPE_DIR/ssl:/anope/ssl
    ports:
$web_ports
    environment:
      - TZ=Europe/Berlin
      - UID=$CURRENT_UID
      - GID=$CURRENT_GID
    restart: unless-stopped
    depends_on:
      - unrealircd
    networks:
      - irc-network

networks:
  irc-network:
    name: irc-network
    external: true
EOF

# === SCHRITT 5: Container starten ===
log_message "Starting Anope container..."
if ! run_docker_compose "$SERVICE"; then
    log_message "❌ ERROR: Docker Compose failed"
    exit 1
fi

# === SCHRITT 6: Firewall Port öffnen (falls Web Panel) ===
if [[ "$WEB_PANEL" == "true" ]]; then
    log_message "Configuring firewall for web panel..."
    open_port "$WEB_PORT" "tcp" "Anope - Web Panel (HTTPS)"
fi

# === SCHRITT 7: Log Rotation einrichten ===
setup_log_rotation "anope" "$LOG_DIR"

log_message "=== Anope Installation completed successfully ==="
echo ""
echo "✅ Anope IRC Services are now running!"
echo "   🔗 Connected to UnrealIRCd: $UPLINK_HOST:$UPLINK_PORT"
echo "   👤 Services: $NICKSERV_NICK, $CHANSERV_NICK, $MEMOSERV_NICK, $OPERSERV_NICK"
if [[ "$WEB_PANEL" == "true" ]]; then
    echo "   🌐 Web Panel: https://$(hostname -I | awk '{print $1}'):$WEB_PORT"
    echo "      User: $WEB_USER"
    echo "      🔒 HTTPS encryption enabled"
fi
echo ""
echo "ℹ️  Note: Make sure UnrealIRCd is running and configured to link with Anope"
exit 0