#!/bin/bash
# Version: 1.01.00
# Service: Let's Encrypt + Apache VHost Auto-Setup

SERVICE_NAME="letsencrypt"
SERVICE_DIR="$HOME/Aetheron/services/$SERVICE_NAME"
CONFIG_FILE="$SERVICE_DIR/domains.conf"
LOGFILE="$SERVICE_DIR/install.log"

mkdir -p "$SERVICE_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

progress_bar() {
    local duration=$1
    local steps=20
    local step_duration=$((duration / steps))
    for ((i=1; i<=steps; i++)); do
        printf "\r[%-*s] %d%%" $steps $(head -c $i < /dev/zero | tr '\0' '#') $((i*100/steps))
        sleep $step_duration
    done
    echo ""
}

log "===== Starting $SERVICE_NAME installation ====="

# --- Read config
if [[ ! -f "$CONFIG_FILE" ]]; then
    log "ERROR: Config file $CONFIG_FILE not found!"
    exit 1
fi

EMAIL=$(grep "^email=" "$CONFIG_FILE" | cut -d= -f2)
DOMAINS=$(grep "^domains=" "$CONFIG_FILE" | cut -d= -f2)

if [[ -z "$EMAIL" || -z "$DOMAINS" ]]; then
    log "ERROR: email or domains missing in config"
    exit 1
fi

log "Using email: $EMAIL"
log "Domains: $DOMAINS"

# --- Install certbot + Apache plugin
log "Installing certbot + apache plugin..."
sudo apt-get update -y >> "$LOGFILE" 2>&1
sudo apt-get install -y certbot python3-certbot-apache >> "$LOGFILE" 2>&1
progress_bar 5

# --- Generate certs
IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"
for DOMAIN in "${DOMAIN_ARRAY[@]}"; do
    log "Requesting certificate for $DOMAIN..."
    sudo certbot --apache -n --agree-tos --email "$EMAIL" -d "$DOMAIN" >> "$LOGFILE" 2>&1
    progress_bar 8
done

# --- Redirect HTTP -> HTTPS
for DOMAIN in "${DOMAIN_ARRAY[@]}"; do
    VHOST="/etc/apache2/sites-available/${DOMAIN}.conf"

    if ! grep -q "Redirect permanent / https://" "$VHOST"; then
        log "Adding HTTP->HTTPS redirect for $DOMAIN..."
        cat <<EOF | sudo tee "$VHOST" > /dev/null
<VirtualHost *:80>
    ServerName $DOMAIN
    Redirect permanent / https://$DOMAIN/
</VirtualHost>
EOF
    fi
done

sudo systemctl reload apache2
progress_bar 3

log "===== $SERVICE_NAME installation completed successfully ====="
