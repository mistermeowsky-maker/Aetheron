#!/bin/bash
# add-subdomain.sh
# Version: 1.00.00

VERSION="1.00.00"
SERVICE_HOME="/home/apache"
VHOST_DIR="$SERVICE_HOME/vhosts"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <subdomain> [port] [document_root]"
    echo "Example: $0 wiki.aetheron.local 80 /home/apache/html/wiki"
    exit 1
fi

SUBDOMAIN=$1
PORT=${2:-80}
DOC_ROOT=${3:-"$SERVICE_HOME/html/$(echo $SUBDOMAIN | cut -d'.' -f1)"}

# Load common functions
source /home/khryon/Aetheron/scripts/common.sh

log_message "Adding subdomain: $SUBDOMAIN"

# Subdomain erstellen
mkdir -p "$VHOST_DIR/$SUBDOMAIN" "$DOC_ROOT"

# Virtual Host Konfiguration
tee "$VHOST_DIR/$SUBDOMAIN/$SUBDOMAIN.conf" > /dev/null << EOF
<VirtualHost *:$PORT>
    ServerName $SUBDOMAIN
    DocumentRoot "$DOC_ROOT"
    
    <Directory "$DOC_ROOT">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog ${SERVICE_HOME}/logs/${SUBDOMAIN}_error.log
    CustomLog ${SERVICE_HOME}/logs/${SUBDOMAIN}_access.log combined
</VirtualHost>
EOF

# Apache neuladen
docker exec apache apachectl graceful

log_message "✅ Subdomain added: $SUBDOMAIN (Port: $PORT)"
echo "🌐 Subdomain available at: http://$SUBDOMAIN:$PORT"