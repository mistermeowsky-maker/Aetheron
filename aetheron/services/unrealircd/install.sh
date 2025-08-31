#!/bin/bash
# install.sh for UnrealIRCd
# Version: 1.02.03

set -euo pipefail

SERVICE="unrealircd"
SERVICE_USER="ircd"              # ganzer IRC-Block unter 'ircd'
SERVICE_GROUP="ircd"
SERVICE_HOME="/home/ircd"

# Verzeichnisse (nach deinem Schema)
UNREAL_DIR="$SERVICE_HOME/unrealircd"
CONFIG_DIR="$UNREAL_DIR/conf"
SSL_DIR="$UNREAL_DIR/ssl"
DATA_DIR="$UNREAL_DIR/data"
LOG_DIR="/home/khryon/.aetheron/logs/unrealircd"

BASE_DIR="/home/khryon/aetheron"
source "$BASE_DIR/scripts/common.sh"

# ---------------- Interaktive Konfiguration ----------------
configure_unrealircd() {
  log_message "Starting interactive UnrealIRCd configuration..."
  echo ""
  echo "================================================"
  echo "           UNREALIRCD KONFIGURATION"
  echo "================================================"

  # Netzwerk
  echo ""
  echo "🌐 NETZWERK-EINSTELLUNGEN"
  echo "----------------------------------------"
  read -p "Netzwerk-Name [AetheronIRC]: " NETWORK_NAME
  NETWORK_NAME=${NETWORK_NAME:-AetheronIRC}

  read -p "Standard-Server [irc.aetheron.local]: " DEFAULT_SERVER
  DEFAULT_SERVER=${DEFAULT_SERVER:-irc.aetheron.local}

  read -p "Services-Server [services.aetheron.local]: " SERVICES_SERVER
  SERVICES_SERVER=${SERVICES_SERVER:-services.aetheron.local}

  # Operator
  echo ""
  echo "👮 OPERATOR-KONFIGURATION"
  echo "----------------------------------------"
  read -p "Operator Benutzername [admin]: " OPER_USER
  OPER_USER=${OPER_USER:-admin}

  read -sp "Operator Passwort: " OPER_PASSWORD; echo
  while [[ -z "${OPER_PASSWORD}" ]]; do
    read -sp "Passwort darf nicht leer sein: " OPER_PASSWORD; echo
  done

  read -p "Operator Hostmask [*]: " OPER_MASK
  OPER_MASK=${OPER_MASK:-*}

  read -p "Maximale gleichzeitige Logins [5]: " MAX_LOGINS
  MAX_LOGINS=${MAX_LOGINS:-5}

  # SSL/TLS
  echo ""
  echo "🔐 SSL/TLS KONFIGURATION (Pflicht)"
  echo "----------------------------------------"
  read -p "SSL Zertifikat Pfad [/home/ircd/ssl/cert.pem]: " SSL_CERT_FILE
  SSL_CERT_FILE=${SSL_CERT_FILE:-/home/ircd/ssl/cert.pem}

  read -p "SSL Private Key Pfad [/home/ircd/ssl/key.pem]: " SSL_KEY_FILE
  SSL_KEY_FILE=${SSL_KEY_FILE:-/home/ircd/ssl/key.pem}

  # Netzwerkzugriff
  echo ""
  echo "🌍 NETZWERK-ZUGRIFF"
  echo "----------------------------------------"
  read -p "Lokales Netzwerk [192.168.1.0/24]: " LOCAL_NETWORK
  LOCAL_NETWORK=${LOCAL_NETWORK:-192.168.1.0/24}

  read -p "VPN Netzwerk [10.0.0.0/24]: " VPN_NETWORK
  VPN_NETWORK=${VPN_NETWORK:-10.0.0.0/24}

  read -p "Max Verbindungen pro IP [3]: " MAX_CONN_PER_IP
  MAX_CONN_PER_IP=${MAX_CONN_PER_IP:-3}

  # Erweitert
  echo ""
  echo "⚙  ERWEITERTE EINSTELLUNGEN"
  echo "----------------------------------------"
  read -p "Maximale Useranzahl [5000]: " MAX_USERS
  MAX_USERS=${MAX_USERS:-5000}

  read -p "Max Channels pro User [20]: " MAX_CHANNELS_PER_USER
  MAX_CHANNELS_PER_USER=${MAX_CHANNELS_PER_USER:-20}

  read -p "Default Channel Modes [+nt]: " DEFAULT_CHANMODES
  DEFAULT_CHANMODES=${DEFAULT_CHANMODES:-+nt}

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

  read -p "Konfiguration bestätigen? (j/N): " -n 1 -r; echo
  if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    log_message "❌ Konfiguration abgebrochen"
    return 1
  fi

  # Link-Passwort für Anope (Secret persistieren)
  LINK_PASS="$(generate_strong_password)"
  store_password "unrealircd" "UNREAL_LINK_PASSWORD" "$LINK_PASS"

  # Konfiguration schreiben (erst erstellen, dann chown)
  log_message "Creating UnrealIRCd configuration..."
  sudo tee "$CONFIG_DIR/unrealircd.conf" >/dev/null << EOF
// ================= UNREALIRCD KOMPLETTE KONFIGURATION =================
include "default.conf";
include "tls.conf";

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

    // ein paar solide Defaults
    options { identd-check; hide-ulines; show-connect-info; flat-map; no-stealth; };
};

// ================= LISTEN PORTS (SSL/TLS für Clients) =================
listen { ip *; port 6697; options { ssl; } };
listen { ip *; port 6997; options { tls; } };

// Interner Link-Port für Services (Anope) – nur im Docker-Netz
listen { ip *; port 7000; options { serversonly; } };

// ================= KLASSEN =================
class clients { pingfreq 90s; connfreq 15s; maxclients $MAX_USERS; sendq 1M; recvq 8192; };
class opers   { pingfreq 90s; connfreq 15s; maxclients 100; sendq 10M; recvq 32768; options { nofakelag; }; };
class servers { pingfreq 90s; connfreq 15s; maxclients 10; sendq 20M; recvq 65536; };

// ================= OPERATOR =================
oper $OPER_USER {
    class opers; mask $OPER_MASK; password "$OPER_PASSWORD"; operclass netadmin;
    swhois "Network Administrator"; modes +xwgs; snomask +cFfkoO; maxlogins $MAX_LOGINS;
};

// ================= SSL/TLS =================
ssl {
    certificate = "$SSL_CERT_FILE";
    key = "$SSL_KEY_FILE";
    options {
        no_plaintext; no_tlsv1; no_tlsv1_1;
        cipherlist "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
    };
};

// ================= ZUGRIFF =================
allow { ip *; class clients; maxperip $MAX_CONN_PER_IP; };
allow { ip $LOCAL_NETWORK; class clients; maxperip 10; password "lan123"; };
allow { ip $VPN_NETWORK; class clients; maxperip 8; password "vpn123"; };

// ================= DEFAULT CHANNEL MODES =================
set { default-channel { modes = "$DEFAULT_CHANMODES"; topic = "Welcome to $NETWORK_NAME"; }; };

// ================= LOGGING (Dateien liegen außerhalb des Containers) =================
log { destination file "$LOG_DIR/unrealircd.log"; flags { connect; oper; kills; errors; server-connects; chg-commands; }; };
log { destination file "$LOG_DIR/oper.log";      flags { oper; }; };

// ================= BLOCK PLAIN TEXT =================
deny { mask *; port 6667; reason "Use SSL/TLS on port 6697 or 6997"; };

// ================= LINK ZU SERVICES (ANOPE) =================
// Erst OHNE TLS stabilisieren – danach TLS aktivieren.
link services.aetheron.local {
    incoming { mask *; };
    outgoing {
        hostname anope;   // Docker-Service-Name
        port 7000;
        // options { tls; };  // später aktivieren
    };
    password {
        connect "LINKPASS_REPLACED";
        receive "LINKPASS_REPLACED";
        class servers;
    };
};
ulines { services.aetheron.local; };
EOF
  sudo chown -R "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_DIR"
  sudo chmod 640 "$CONFIG_DIR/unrealircd.conf"

  # Link-Passwort injizieren
  sudo sed -i "s/LINKPASS_REPLACED/${LINK_PASS//\//\\/}/g" "$CONFIG_DIR/unrealircd.conf"

  log_message "✅ UnrealIRCd configuration created"
  return 0
}

log_message "=== Starting UnrealIRCd Installation ==="

# 0) Firewall + sshd
check_firewall

# 1) Benutzer/Verzeichnisse
create_service_user "$SERVICE_USER" "$SERVICE_GROUP" "$SERVICE_HOME"
sudo mkdir -p "$CONFIG_DIR" "$SSL_DIR" "$DATA_DIR" "$LOG_DIR"
sudo chown -R "$SERVICE_USER:$SERVICE_GROUP" "$UNREAL_DIR"
sudo chown -R khryon:users "$LOG_DIR"
sudo chmod 755 "$LOG_DIR"

# 2) Interaktive Konfiguration
if ! configure_unrealircd; then
  log_message "❌ ERROR: Configuration failed"
  exit 1
fi

# 3) Docker-Compose im Service-Verzeichnis erzeugen
SERVICE_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${SERVICE_DIR}/docker-compose.yml"

log_message "Creating Docker Compose configuration..."
cat > "$COMPOSE_FILE" << EOF
services:
  unrealircd:
    image: unrealircd/unrealircd:6.1.0
    container_name: aetheron-unrealircd
    user: "\${AETHERON_PUID}:\${AETHERON_PGID}"
    volumes:
      - $DATA_DIR:/home/ircd/unrealircd/data
      - $CONFIG_DIR:/home/ircd/unrealircd/conf
      - $SSL_DIR:/home/ircd/unrealircd/ssl
      - $LOG_DIR:/home/ircd/unrealircd/logs
    ports:
      - "6697:6697/tcp"
      - "6997:6997/tcp"
    environment:
      - TZ=Europe/Berlin
    networks:
      - aetheron
    restart: unless-stopped
networks:
  aetheron:
    external: true
EOF

# 4) Start
ensure_docker_network "aetheron"
log_message "Starting UnrealIRCd container..."
run_docker_compose "$SERVICE" "$COMPOSE_FILE" || { log_message "❌ ERROR: Docker Compose failed"; exit 1; }

# 5) Firewall
open_port 6697 tcp "UnrealIRCd - SSL IRC"
open_port 6997 tcp "UnrealIRCd - TLS IRC"
close_port 6667 tcp "UnrealIRCd - Plain text blocked"

# 6) Logrotate
setup_log_rotation "unrealircd" "$LOG_DIR"

log_message "=== UnrealIRCd Installation completed successfully ==="
echo ""
echo "✅ UnrealIRCd is now running - SSL/TLS ONLY!"
echo "   🔒 Connect on 6697 (SSL) or 6997 (TLS)"
echo "   ❌ Port 6667 (plain text) is BLOCKED"
exit 0

