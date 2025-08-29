#!/bin/bash
# wipe.sh for mariadb
# Version: 1.00.00

VERSION="1.00.00"
SERVICE="mariadb"
SERVICE_USER="mariadb"
SERVICE_GROUP="mariadb"

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

log_message "=== Starting MariaDB WIPE ==="

# Bestätigung einholen
echo "❌❌❌ WARNING: COMPLETE WIPE OPERATION ❌❌❌"
echo "This will PERMANENTLY DELETE ALL MariaDB data and logs!"
echo ""
echo "The following will be deleted:"
echo "  - Docker containers and volumes"
echo "  - All database data in /srv/mariadb"
echo "  - Configuration in /home/mariadb"
echo "  - Logs in /home/khryon/logs/mariadb"
echo "  - User 'mariadb' and group 'mariadb'"
echo "  - Firewall rules for port 3306"
echo ""
read -p "Are you ABSOLUTELY SURE? (type 'WIPE' to confirm): " confirmation

if [[ "$confirmation" != "WIPE" ]]; then
    echo "Wipe operation cancelled."
    exit 1
fi

# Wipe durchführen
wipe_service "$SERVICE" "$SERVICE_USER" "$SERVICE_GROUP" \
    "/srv/mariadb,/home/mariadb,/home/khryon/logs/mariadb" \
    "3306/tcp"

log_message "=== MariaDB WIPE completed ==="
echo ""
echo "✅ MariaDB has been completely wiped from the system."
echo "📦 A final backup was created in: $BASE_DIR/backups/mariadb/FINAL_WIPE/"
exit 0