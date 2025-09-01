#!/bin/bash
# aetheron-logrotate - setup log rotation for all Aetheron services
# Version: 1.00.00

BASE_DIR="/home/khryon/aetheron"
LOG_DIR="$BASE_DIR/logs"
ROTATE_DIR="/etc/logrotate.d"

set -euo pipefail

echo "[aetheron-logrotate] Setting up logrotate configs..."

# Stelle sicher, dass das globale Log-Verzeichnis existiert
mkdir -p "$LOG_DIR"

# Alle Service-Verzeichnisse durchgehen
for service in "$BASE_DIR/services"/*; do
    [ -d "$service" ] || continue
    sname=$(basename "$service")

    # Templates/Utility-Scripts überspringen
    case "$sname" in
        templates|cert-update.sh) continue ;;
    esac

    slogdir="$LOG_DIR/$sname"
    mkdir -p "$slogdir"

    config_file="$ROTATE_DIR/aetheron-$sname"
    echo "  -> $sname"

    sudo tee "$config_file" >/dev/null <<EOF
$slogdir/*.log {
    daily
    missingok
    rotate 10
    compress
    delaycompress
    notifempty
    create 0640 khryon users
    sharedscripts
}
EOF
done

echo "[aetheron-logrotate] Done. Run 'sudo logrotate -f /etc/logrotate.conf' to force a test run."

