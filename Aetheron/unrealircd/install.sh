#!/bin/bash
# install.sh for unrealircd
# Version: 1.01.03  # Mit komplettem interaktivem Dialog

VERSION="1.01.03"
SERVICE="unrealircd"
SERVICE_USER="ircd"
SERVICE_GROUP="ircd"
SERVICE_HOME="/home/ircd"

# Pfade für UnrealIRCd
UNREAL_DIR="$SERVICE_HOME/unrealircd"
CONFIG_DIR="$UNREAL_DIR/conf"
SSL_DIR="$UNREAL_DIR/ssl"
LOG_DIR="/home/khryon/logs/unrealircd"

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

# Funktion für interaktive Konfiguration
configure_unrealircd() {
    log_message "Starting interactive UnrealIRCd configuration..."
    
    echo ""
    echo "================================================"
    echo "           UNREALIRCD KONFIGURATION"
    echo "================================================"
    
    # ================= NETZWERK KONFIGURATION =================
    echo ""
    echo "🌐 NETZWERK-EINSTELLUNGEN"
    echo "----------------------------------------"
    read -p "Netzwerk-Name [AetheronIRC]: " NETWORK_NAME
    NETWORK_NAME=${NETWORK_NAME:-AetheronIRC}
    
    read -p "Standard-Server [irc.aetheron.local]: " DEFAULT_SERVER
    DEFAULT_SERVER=${DEFAULT_SERVER:-irc.aetheron.local}
    
    read -p "Services-Server [services.aetheron.local]: " SERVICES_SERVER
    SERVICES_SERVER=${SERVICES_SERVER:-services.aetheron.local}
    
    # ================= OPERATOR KONFIGURATION =================
    echo ""
    echo "👮 OPERATOR-KONFIGURATION"
    echo "----------------------------------------"
    read -p "Operator Benutzername [admin]: " OPER_USER
    OPER_USER=${OPER_USER:-admin}
    
    read -sp "Operator Passwort: " OPER_PASSWORD
    echo
    while [ -z "$OPER_PASSWORD" ]; do
        read -sp "Passwort darf nicht leer sein: " OPER_PASSWORD
        echo
    done
    
    read -p "Operator Hostmask [*]: " OPER_MASK
    OPER_MASK=${OPER_MASK:-*}
    
    read -p "Maximale gleichzeitige Logins [5]: " MAX_LOGINS
    MAX_LOGINS=${MAX_LOGINS:-5}
    
    # ================= SSL/TLS KONFIGURATION =================
    echo ""
    echo "🔐 SSL/TLS KONFIGURATION (PFLICHT!)"
    echo "----------------------------------------"
    echo "SSL ist verpflichtend für maximale Sicherheit"
    echo ""
    
    read -p "SSL Zertifikat Pfad [/home/ircd/ssl/cert.pem]: " SSL_CERT_FILE
    SSL_CERT_FILE=${SSL_CERT_FILE:-/home/ircd/ssl/cert.pem}
    
    read -p "SSL Private Key Pfad [/home/ircd/ssl/key.pem]: " SSL_KEY_FILE
    SSL_KEY_FILE=${SSL_KEY_FILE:-/home/ircd/ssl/key.pem}
    
    # ================= NETZWERK-ZUGRIFF =================
    echo ""
    echo "🌍 NETZWERK-ZUGRIFF"
    echo "----------------------------------------"
    echo "Welche Netzwerke dürfen verbinden?"
    echo "(Leer lassen für keine Einschränkung)"
    echo ""
    
    read -p "Lokales Netzwerk [192.168.1.0/24]: " LOCAL_NETWORK
    LOCAL_NETWORK=${LOCAL_NETWORK:-192.168.1.0/24}
    
    read -p "VPN Netzwerk [10.0.0.0/24]: " VPN_NETWORK
    VPN_NETWORK=${VPN_NETWORK:-10.0.0.0/24}
    
    read -p "Max Verbindungen pro IP [3]: " MAX_CONN_PER_IP
    MAX_CONN_PER_IP=${MAX_CONN_PER_IP:-3}
    
    # ================= ERWEITERTE EINSTELLUNGEN =================
    echo ""
    echo "⚙️  ERWEITERTE EINSTELLUNGEN"
    echo "----------------------------------------"
    read -p "Maximale Useranzahl [5000]: " MAX_USERS
    MAX_USERS=${MAX_USERS:-5000}
    
    read -p "Max Channels pro User [20]: " MAX_CHANNELS_PER_USER
    MAX_CHANNELS_PER_USER=${MAX_CHANNELS_PER_USER:-20}
    
    read -p "Anti-Flood Modus [strict]: " ANTIFLOOD_MODE
    ANTIFLOOD_MODE=${ANTIFLOOD_MODE:-strict}
    
    read -p "Default Channel Modes [+nt]: " DEFAULT_CHANMODES
    DEFAULT_CHANMODES=${DEFAULT_CHANMODES:-+nt}
    
    # ================= BESTÄTIGUNG =================
    echo ""
    echo "================================================"
    echo "           ZUSAMMENFASSUNG"
    echo "================================================"
    echo "🔸 Netzwerk: $NETWORK_NAME"
    echo "🔸 Operator: $OPER_USER (max $MAX_LOGINS Logins)"
    echo "🔸 SSL: $SSL_CERT_FILE"
    echo "🔸 Max User: $MAX_USERS"
    echo "🔸 Max Channels/User: $MAX_CHANNELS_PER_USER"
    echo "🔸 Netzwerke: $LOCAL_NETWORK, $VPN_NETWORK"
    echo "================================================"
    echo ""
    
    read -p "Konfiguration bestätigen? (j/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        log_message "❌ Konfiguration abgebrochen"
        return 1
    fi

    # ================= KONFIGURATION ERSTELLEN =================
    log_message "Creating UnrealIRCd configuration..."
    sudo -u "$SERVICE_USER" tee "$CONFIG_DIR/unrealircd.conf" > /dev/null << EOF
// ================= UNREALIRCD KOMPLETTE KONFIGURATION =================
include "default.conf";
include "tls.conf";

// ================= NETZWERK GRUNDEINSTELLUNGEN =================
set {
    network-name = "$NETWORK_NAME";
    default-server = "$DEFAULT_SERVER";
    services-server = "$SERVICES_SERVER";
    help-channel = "#help";
    hiddenhost-prefix = "user";
    modes-on-connect = "+ix";
    modes-on-oper = "+xwgs";
    oper-auto-join = "#opers";
    maxchannelsperuser = $MAX_CHANNELS_PER_USER;
    anti-flood { unknown-flood-amount = 10; unknown-flood-period = 10s; };
    options { identd-check; hide-ulines; show-connect-info; flat-map; no-stealth; };
};

// ================= LISTEN PORTS (NUR SSL/TLS!) =================
listen { ip *; port 6697; options { ssl; } };
listen { ip *; port 6997; options { tls; } };

// ================= KLASSEN DEFINITION =================
class clients { pingfreq 90s; connfreq 15s; maxclients $MAX_USERS; sendq 1M; recvq 8192; };
class opers { pingfreq 90s; connfreq 15s; maxclients 100; sendq 10M; recvq 32768; options { nofakelag; }; };
class servers { pingfreq 90s; connfreq 15s; maxclients 10; sendq 20M; recvq 65536; };
class limusers { pingfreq 90s; connfreq 15s; maxclients 30; sendq 1M; recvq 8192; };

// ================= OPERATOR KONFIGURATION =================
oper $OPER_USER {
    class opers; mask $OPER_MASK; password "$OPER_PASSWORD"; operclass netadmin;
    swhois "Network Administrator"; modes +xwgs; snomask +cFfkoO; maxlogins $MAX_LOGINS;
};

// ================= SSL/TLS KONFIGURATION =================
ssl {
    certificate = "$SSL_CERT_FILE";
    key = "$SSL_KEY_FILE";
    options {
        no_plaintext; no_tlsv1; no_tlsv1_1;
        cipherlist "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
    };
};

// ================= ZUGRIFFSREGELN =================
allow { ip *; class clients; maxperip $MAX_CONN_PER_IP; };
allow { ip $LOCAL_NETWORK; class clients; maxperip 10; password "lan123"; };
allow { ip $VPN_NETWORK; class clients; maxperip 8; password "vpn123"; };

// ================= FLOOD PROTECTION =================
set {
    anti-flood {
        connect-flood 5:60; nick-flood 5:60; away-flood 5:120;
        invite-flood 3:60; knock-flood 3:60; max-concurrent-conversations 5;
        unknown-flood-amount 10; unknown-flood-period 10s;
    };
};

// ================= CHANNEL EINSTELLUNGEN =================
set {
    default-channel { modes = "$DEFAULT_CHANMODES"; topic = "Welcome to $NETWORK_NAME"; };
    channel { use-exempt = yes; use-invite = yes; use-forward = yes; use-knock = yes; };
    max-ban-entries = 200; max-join-entries = 200; max-watch-entries = 200;
};

// ================= CLIENT LIMITS =================
set {
    max-users = $MAX_USERS; nick-length = 30; topic-length = 390;
    away-length = 390; kick-length = 390; max-list-size = 100000;
};

// ================= WHOWAS EINSTELLUNGEN =================
whowas { entries = 32768; duration = 30d; };

// ================= LOGGING KONFIGURATION =================
log { destination file "$LOG_DIR/unrealircd.log"; flags { connect; oper; kills; errors; server-connects; chg-commands; }; };
log { destination file "$LOG_DIR/oper.log"; flags { oper; }; };

// ================= BLOCKIERE PLAIN TEXT PORT =================
deny { mask *; port 6667; reason "Use SSL/TLS on port 6697 or 6997"; };
EOF

    log_message "✅ UnrealIRCd configuration created"
    return 0
}

log_message "=== Starting UnrealIRCd Installation ==="

# === SCHRITT 0: Firewall prüfen ===
check_firewall

# === SCHRITT 1: Benutzer und Verzeichnisse anlegen ===
create_service_user "$SERVICE_USER" "$SERVICE_GROUP" "$SERVICE_HOME"
sudo mkdir -p "$UNREAL_DIR" "$CONFIG_DIR" "$SSL_DIR" "$LOG_DIR"
sudo chown -R "$SERVICE_USER":"$SERVICE_GROUP" "$UNREAL_DIR"
sudo chown -R khryon:users "$LOG_DIR"
sudo chmod 755 "$LOG_DIR"

# === SCHRITT 2: Interaktive Konfiguration ===
if ! configure_unrealircd; then
    log_message "❌ ERROR: Configuration failed"
    exit 1
fi

# === SCHRITT 3: Docker Compose erstellen ===
log_message "Creating Docker Compose configuration..."
cat > "$(dirname "$0")/docker-compose.yml" << EOF
version: '3.8'

services:
  unrealircd:
    image: unrealircd/unrealircd:6.1.0
    container_name: unrealircd
    user: "\${UID}:\${GID}"
    volumes:
      - $UNREAL_DIR/data:/home/ircd/unrealircd/data
      - $CONFIG_DIR:/home/ircd/unrealircd/conf
      - $SSL_DIR:/home/ircd/unrealircd/ssl
      - $LOG_DIR:/home/ircd/unrealircd/logs
    ports:
      - "6697:6697"
      - "6997:6997"
    environment:
      - TZ=Europe/Berlin
      - UID=\${UID}
      - GID=\${GID}
    restart: unless-stopped
EOF

# === SCHRITT 4: Container starten ===
log_message "Starting UnrealIRCd container..."
if ! run_docker_compose "$SERVICE"; then
    log_message "❌ ERROR: Docker Compose failed"
    exit 1
fi

# === SCHRITT 5: Firewall Ports öffnen ===
log_message "Configuring firewall..."
open_port 6697 "tcp" "UnrealIRCd - SSL IRC"
open_port 6997 "tcp" "UnrealIRCd - TLS IRC"
close_port 6667 "tcp" "UnrealIRCd - Plain text blocked"

# === SCHRITT 6: Log Rotation einrichten ===
setup_log_rotation "unrealircd" "$LOG_DIR"

log_message "=== UnrealIRCd Installation completed successfully ==="
echo ""
echo "✅ UnrealIRCd is now running - SSL/TLS ONLY!"
echo "   🔒 Connect on port 6697 (SSL) or 6997 (TLS)"
echo "   ❌ Port 6667 (plain text) is BLOCKED"
echo "   👤 Operator: $OPER_USER ($MAX_LOGINS simultaneous logins)"
echo "   👥 Max Users: $MAX_USERS"
exit 0