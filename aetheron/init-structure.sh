#!/bin/bash
# init-structure.sh
# Version: 1.00.02

BASE_DIR="$HOME/Aetheron"
SERVICES_DIR="$BASE_DIR/services"

echo "[*] Initializing directory structure under $BASE_DIR ..."

# Hauptverzeichnisse
mkdir -p "$SERVICES_DIR"

# Services
services=(mariadb unrealircd anope nextcloud mediawiki vsftpd teamspeak)

for svc in "${services[@]}"; do
    mkdir -p "$SERVICES_DIR/$svc"
    touch "$SERVICES_DIR/$svc/install.sh"
    touch "$SERVICES_DIR/$svc/reinstall.sh"
    touch "$SERVICES_DIR/$svc/uninstall.sh"
    touch "$SERVICES_DIR/$svc/wipe.sh"
done

echo "[+] Structure initialized at $BASE_DIR"

