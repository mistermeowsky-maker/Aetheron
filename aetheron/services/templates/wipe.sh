#!/bin/bash
# wipe.sh - Universeller Abrissbagger
# Version: 1.00.00

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

SERVICE=$(get_service_name)
SERVICE_USER=$(get_service_user)
SERVICE_HOME=$(get_service_home)

log_message "=== 💥 Abrissbagger beginnt $SERVICE Vernichtung ==="

# 1. Sicherheitsabfrage
echo "🚨🚨🚨 ACHTUNG: ABRISSBAGGER IM EINSATZ! 🚨🚨🚨"
read -p "Soll $SERVICE KOMPLETT vernichtet werden? (j/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    log_message "❌ Abriss abgebrochen"
    exit 0
fi

# 2. Container und Volumes vernichten
log_message "Vernichte Docker Container und Volumes..."
run_docker_compose "down-volumes"

# 3. Daten und Home-Verzeichnis vernichten
log_message "Vernichte Daten..."
sudo rm -rf "$SERVICE_HOME"

# 4. Logs vernichten
log_message "Vernichte Logs..."
sudo rm -rf "/home/khryon/logs/$SERVICE"

log_message "✅ $SERVICE komplett vernichtet"