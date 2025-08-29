#!/bin/bash
# recover-mariadb-password.sh
# Version: 1.00.00

VERSION="1.00.00"
BASE_DIR=~/Aetheron
SERVICE_HOME="/home/mariadb"

# Load common functions
source "$BASE_DIR/scripts/common.sh"

echo "=== MariaDB Password Recovery ==="
echo ""

# 1. Versuche master password file
if [[ -f "$BASE_DIR/.master_passwords" ]]; then
    echo "🔍 Checking master password file..."
    password=$(get_password "mariadb" "dbadmin")
    if [[ -n "$password" ]]; then
        echo "✅ Password found in master file!"
        echo "Username: dbadmin"
        echo "Password: $password"
        exit 0
    fi
fi

# 2. Versuche lokale Passwort-Datei
if [[ -f "$SERVICE_HOME/dbadmin_password.txt" ]]; then
    echo "🔍 Checking local password file..."
    password=$(cat "$SERVICE_HOME/dbadmin_password.txt" 2>/dev/null)
    if [[ -n "$password" ]]; then
        echo "✅ Password found in local file!"
        echo "Username: dbadmin" 
        echo "Password: $password"
        exit 0
    fi
fi

# 3. Notfall-Reset
echo "❌ No password found in any location."
echo ""
echo "⚠️  EMERGENCY RESET REQUIRED"
echo "This will temporarily restart MariaDB with root access."
echo ""
read -p "Continue with emergency reset? (j/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Recovery cancelled."
    exit 1
fi

# Container stoppen
echo "Stopping MariaDB container..."
cd "$SERVICE_HOME"
docker-compose down

# Temporäre docker-compose für Reset
cat > docker-compose-reset.yml << EOF
version: '3.8'
services:
  mariadb:
    image: mariadb:10.11.7
    container_name: mariadb-reset
    command: --skip-grant-tables --skip-networking
    volumes:
      - /srv/mariadb:/var/lib/mysql
    networks:
      - internal-only
networks:
  internal-only:
    driver: bridge
    internal: true
EOF

# Starte Container im Recovery Mode
echo "Starting MariaDB in recovery mode..."
docker-compose -f docker-compose-reset.yml up -d
sleep 5

# Setze neues Passwort
echo "Resetting dbadmin password..."
NEW_PASSWORD=$(date +%s | sha256sum | base64 | head -c 20)
docker exec mariadb-reset mysql -e "FLUSH PRIVILEGES; ALTER USER 'dbadmin'@'%' IDENTIFIED BY '$NEW_PASSWORD'; FLUSH PRIVILEGES;"

# Container stoppen und normale Konfiguration wiederherstellen
echo "Restoring normal operation..."
docker-compose -f docker-compose-reset.yml down
docker-compose up -d

# Aufräumen
rm -f docker-compose-reset.yml

echo ""
echo "✅ Password reset successful!"
echo "Username: dbadmin"
echo "New Password: $NEW_PASSWORD"
echo ""
echo "⚠️  IMPORTANT: Update your application configurations with the new password!"
echo "⚠️  Consider running './server-setup.sh' to properly store this password."

exit 0