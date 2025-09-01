#!/bin/bash
# install.sh for MariaDB
# Version: 1.02.00

set -euo pipefail

SERVICE="mariadb"
SERVICE_USER="mariadb"
SERVICE_GROUP="mariadb"
SERVICE_HOME="/home/mariadb"

# Load common functions (absolute safe path)
BASE_DIR="/home/khryon/aetheron"
source "$BASE_DIR/scripts/common.sh"

log_message "=== Starting MariaDB Installation ==="

# Firewall + sshd sicherstellen (inkl. UFW→firewalld)
check_firewall

# Service-User
create_service_user "$SERVICE_USER" "$SERVICE_GROUP" "$SERVICE_HOME"

# Compose/Service-Verzeichnis
SERVICE_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${SERVICE_DIR}/docker-compose.yml"
ENV_FILE="${SERVICE_DIR}/.env"
DATA_DIR="${SERVICE_DIR}/data/db"
INIT_DIR="${SERVICE_DIR}/init"

mkdir -p "$DATA_DIR" "$INIT_DIR"

# Passwörter erzeugen + speichern
log_message "Generating strong passwords..."
DB_ROOT_PASS="$(generate_strong_password)"
DB_ADMIN_PASS="$(generate_strong_password)"
store_password "$SERVICE" "MARIADB_ROOT_PASSWORD" "$DB_ROOT_PASS"
store_password "$SERVICE" "MARIADB_DBADMIN_PASSWORD" "$DB_ADMIN_PASS"

# Lokale .env erzeugen (aus Secrets)
SECRETS_DIR="/home/khryon/.aetheron/secrets/${SERVICE}"
if [[ -f "${SECRETS_DIR}/secrets.env" ]]; then
  cp "${SECRETS_DIR}/secrets.env" "$ENV_FILE"
else
  {
    echo "MARIADB_ROOT_PASSWORD=$DB_ROOT_PASS"
    echo "MARIADB_DBADMIN_PASSWORD=$DB_ADMIN_PASS"
  } > "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"

# Docker-Netz
ensure_docker_network "aetheron"

# Compose schreiben
log_message "Creating Docker Compose configuration..."
cat > "$COMPOSE_FILE" <<'YAML'
services:
  mariadb:
    image: mariadb:11.4
    container_name: aetheron-mariadb
    restart: unless-stopped
    environment:
      - MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD}
      - MARIADB_DATABASE=aetheron
      - MARIADB_USER=dbadmin
      - MARIADB_PASSWORD=${MARIADB_DBADMIN_PASSWORD}
      - TZ=Europe/Berlin
    volumes:
      - ./data/db:/var/lib/mysql
      - ./init:/docker-entrypoint-initdb.d
    networks:
      - aetheron
networks:
  aetheron:
    external: true
YAML

# Starten
log_message "Starting MariaDB container for initial setup..."
( cd "$SERVICE_DIR" && docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -p "aetheron-mariadb" up -d )

# Warten, bis der Server lauscht (TCP; nutzt mariadb-admin)
log_message "Waiting for MariaDB to become ready..."
ready=""
for i in {1..60}; do
  if docker exec aetheron-mariadb sh -lc 'mariadb-admin -uroot -p"$MARIADB_ROOT_PASSWORD" -h127.0.0.1 ping --silent'; then
    ready="yes"; break
  fi
  sleep 2
done
if [[ -z "$ready" ]]; then
  log_message "❌ ERROR: MariaDB not ready after 120s."
  exit 1
fi

# Absicherung/Hardening + UTF8 (über TCP)
log_message "Securing MariaDB installation..."
docker exec -i aetheron-mariadb sh -lc 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -h127.0.0.1' <<SQL
ALTER DATABASE aetheron CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'dbadmin'@'%' IDENTIFIED BY '${DB_ADMIN_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'dbadmin'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

log_message "✅ MariaDB secured and ready."

