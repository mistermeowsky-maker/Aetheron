#!/bin/bash
# install.sh for Anope IRC Services
# Version: 1.00.02

set -euo pipefail

SERVICE="anope"
SERVICE_USER="ircd"     # gleicher User wie Unreal
SERVICE_GROUP="ircd"
SERVICE_HOME="/home/ircd"

BASE_DIR="/home/khryon/aetheron"
source "$BASE_DIR/scripts/common.sh"

log_message "=== Starting Anope Installation ==="

# 0) Firewall/sshd nur sicherstellen (keine Ports öffnen)
check_firewall

# 1) Benutzer/Verzeichnisse
create_service_user "$SERVICE_USER" "$SERVICE_GROUP" "$SERVICE_HOME"
ANOPE_DIR="$SERVICE_HOME/anope"
CONF_DIR="$ANOPE_DIR/conf"
DATA_DIR="$ANOPE_DIR/data"
sudo mkdir -p "$CONF_DIR" "$DATA_DIR"
sudo chown -R "$SERVICE_USER:$SERVICE_GROUP" "$ANOPE_DIR"

# 2) Link-Passwort aus Unreal-Secret holen (oder neu setzen)
UNREAL_SECRET="/home/khryon/.aetheron/secrets/unrealircd/secrets.env"
if [[ -f "$UNREAL_SECRET" ]] && grep -q '^UNREAL_LINK_PASSWORD=' "$UNREAL_SECRET"; then
  LINK_PASS="$(grep '^UNREAL_LINK_PASSWORD=' "$UNREAL_SECRET" | cut -d= -f2-)"
else
  LINK_PASS="$(generate_strong_password)"
  store_password "unrealircd" "UNREAL_LINK_PASSWORD" "$LINK_PASS"
fi

# 3) Minimal services.conf – erst STABIL OHNE TLS linken
log_message "Creating Anope configuration..."
sudo tee "${CONF_DIR}/services.conf" >/dev/null <<'CONF'
# --- Minimal, robust start for UnrealIRCd + Anope ---

# Hashing
module { name = "enc_sha256" }

# Für TLS (SPÄTER aktivieren, wenn Unreal-Link TLS kann)
# module { name = "m_ssl_openssl" }

# Netzwerkname
networkinfo { networkname = "AetheronIRC"; }

# Uplink (zuerst OHNE TLS stabilisieren)
uplink {
  host = "unrealircd";   # Docker-Servicename von Unreal
  port = 7000;
  password = "REPLACED_AT_INSTALL";
  ssl = no;              # später auf yes, wenn Unreal Link TLS kann
}

# Services-Server muss zum Unreal-Link-Namen passen:
serverinfo {
  name = "services.aetheron.local";
  description = "Aetheron IRC Services";
}

# Protokoll: WICHTIG für Unreal
module {
  name = "unreal";
  use_server_side_mlock = yes
  use_server_side_topiclock = no
}

# Basis-Module
module { name = "nickserv" }
module { name = "chanserv" }
module { name = "botserv" }

# Storage
database {
  engine = "db_flatfile";
  name = "anope.db";
  dir = "/anope/data";
  saveonchanges = yes;
}
CONF
sudo sed -i "s#password = \"REPLACED_AT_INSTALL\";#password = \"${LINK_PASS//\//\\/}\";#" "${CONF_DIR}/services.conf"
log_message "✅ Anope configuration created"

# 4) Docker Compose im Service-Verzeichnis
SERVICE_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${SERVICE_DIR}/docker-compose.yml"

log_message "Creating Docker Compose configuration..."
cat > "$COMPOSE_FILE" << EOF
services:
  anope:
    image: anope/anope:2.0
    container_name: aetheron-anope
    user: "\${AETHERON_PUID}:\${AETHERON_PGID}"
    environment:
      - TZ=Europe/Berlin
    volumes:
      - $CONF_DIR:/anope/conf
      - $DATA_DIR:/anope/data
    networks:
      - aetheron
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "pgrep", "-f", "anope"]
      interval: 10s
      timeout: 5s
      retries: 12
networks:
  aetheron:
    external: true
EOF

# 5) Start
ensure_docker_network "aetheron"
log_message "Starting Anope container..."
run_docker_compose "$SERVICE" "$COMPOSE_FILE" || { log_message "❌ ERROR: Docker Compose failed"; exit 1; }

# 6) Warten bis Prozess läuft (kein Port, daher Prozess-Check)
log_message "Waiting for Anope to initialize..."
ready=""
for i in {1..60}; do
  if docker exec aetheron-anope sh -lc 'ps aux | grep -q "[a]nope"'; then
    ready="yes"; break
  fi
  sleep 2
done
[[ -z "$ready" ]] && { log_message "❌ ERROR: Anope not ready after 120s."; exit 1; }

log_message "✅ Anope is running (linked to UnrealIRCd via internal port 7000)"
echo ""
echo "✅ Anope up and running."
echo "   - Container : aetheron-anope"
echo "   - Config    : ${CONF_DIR}/services.conf"
echo "   - Data dir  : ${DATA_DIR}"
echo "   - Link      : unrealircd:7000 (internal Docker network)"
echo "   - TLS       : derzeit AUS. Danach optional aktivieren (ssl = yes + Unreal link tls)"
exit 0

