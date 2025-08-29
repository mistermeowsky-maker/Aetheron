#!/bin/bash
# install.sh for cockpit
# Version: 1.00.00

VERSION="1.00.00"
SERVICE="cockpit"
SERVICE_USER="cockpit"
SERVICE_GROUP="cockpit"
SERVICE_HOME="/home/cockpit"

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

log_message "=== Starting Cockpit Installation ==="

# === SCHRITT 0: Firewall prüfen ===
check_firewall

# === SCHRITT 1: Cockpit installieren (NATIV, nicht Docker!) ===
log_message "Installing Cockpit (native installation)..."
install_package "cockpit" "cockpit"
install_package "cockpit-docker" "cockpit-docker"
install_package "cockpit-storaged" "cockpit-storaged"
install_package "cockpit-networkmanager" "cockpit-networkmanager"
install_package "cockpit-podman" "cockpit-podman"

# === SCHRITT 2: Cockpit Services aktivieren ===
log_message "Enabling and starting Cockpit services..."
enable_and_start_service "cockpit.socket"

# === SCHRITT 3: Firewall Port öffnen ===
log_message "Configuring firewall..."
open_port 9090 "tcp" "Cockpit - Web Administration"

# === SCHRITT 4: Zugriff konfigurieren ===
log_message "Configuring Cockpit access..."
# Cockpit läuft nativ auf Port 9090, authentifiziert mit System-Accounts

log_message "=== Cockpit Installation completed successfully ==="
echo ""
echo "✅ Cockpit is now running!"
echo "   🌐 Web Interface: https://$(hostname -I | awk '{print $1}'):9090"
echo "   🔐 Login with your system user credentials"
echo "   🐳 Docker integration: Enabled"
exit 0