#!/bin/bash
# install.sh for docker (Manjaro)
# Version: 1.05.01

VERSION="1.05.01"
SERVICE="docker"

# Common helpers
source "$(dirname "$0")/../../scripts/common.sh"

log_message "=== Starting Docker installation (Manjaro) ==="

# 0) Firewall check (Docker selbst braucht keine offenen Ports)
check_firewall

# 1) Pakete
install_package "docker" "docker"
install_package "docker-compose" "docker-compose"

# 2) Dienst aktivieren/gestartet
enable_and_start_service "docker.service"

# 3) Benutzer zur Gruppe 'docker' hinzufügen (SUDO_USER bevorzugt)
TARGET_USER="${SUDO_USER:-$USER}"
if getent group docker >/dev/null 2>&1; then
  if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx "docker"; then
    log_message "User '$TARGET_USER' already in group 'docker'."
  else
    log_message "Adding user '$TARGET_USER' to 'docker' group..."
    sudo usermod -aG docker "$TARGET_USER"
    ADDED_TO_GROUP=true
  fi
else
  log_message "Group 'docker' not found, creating and adding '$TARGET_USER'..."
  sudo groupadd docker
  sudo usermod -aG docker "$TARGET_USER"
  ADDED_TO_GROUP=true
fi

# 4) Statuscheck
if systemctl is-active --quiet docker; then
  log_message "Docker service is running."
else
  log_message "ERROR: docker.service failed to start. See 'journalctl -u docker'."
  exit 1
fi

# 5) Versionen ausgeben
DOCKER_VER="$(docker --version 2>/dev/null || echo 'unknown')"
DCOMPOSE_VER="$(docker-compose --version 2>/dev/null || echo 'unknown')"
log_message "Installed: ${DOCKER_VER}"
log_message "Installed: ${DCOMPOSE_VER}"

log_message "=== Docker installation completed successfully ==="
echo
echo "✅ Docker is ready."
if [[ "${ADDED_TO_GROUP:-false}" == "true" ]]; then
  echo "ℹ️  Please log out/in (or reboot) so group changes for '$TARGET_USER' take effect."
fi
echo "🐳 Test:  docker run --rm hello-world"
exit 0
