#!/bin/bash
# uninstall.sh - Universeller Hausmeister
# Version: 1.00.00

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

SERVICE=$(get_service_name)
SERVICE_USER=$(get_service_user)
SERVICE_HOME=$(get_service_home)

log_message "=== 🧹 Hausmeister beginnt $SERVICE Deinstallation ==="

# 1. Docker Container stoppen (Daten bleiben erhalten)
log_message "Stoppe Docker Container..."
run_docker_compose "down"

# 2. Temporäre Dateien bereinigen
log_message "Räume temporäre Dateien auf..."
sudo rm -rf "$SERVICE_HOME/tmp" "$SERVICE_HOME/cache" "$SERVICE_HOME/logs/*.tmp"

# 3. Logs rotieren
log_message "Rotiere Logs..."
sudo logrotate -f /etc/logrotate.d/aetheron-$SERVICE 2>/dev/null || true

log_message "✅ $SERVICE deinstalliert (Daten erhalten)"