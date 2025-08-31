#!/bin/bash
# common.sh - Common functions for all service scripts
# Version: 1.03.01

set -euo pipefail

VERSION="1.03.01"

# ----- Utility: service + action names -----
get_service_name() { echo "$(basename "$(dirname "$0")")"; }
get_action_name()  { echo "$(basename "$0" .sh)"; }
get_service_user() { echo "$(get_service_name)"; }
get_service_home() { echo "/home/$(get_service_name)"; }

# ----- pacman lock handling -----
_pacman_wait_unlock() {
  local lock="/var/lib/pacman/db.lck" tries=30
  while [[ -e "$lock" && $tries -gt 0 ]]; do
    log_message "pacman lock present, waiting..."
    sleep 2; ((tries--))
  done
  if [[ -e "$lock" ]]; then
    log_message "ERROR: pacman lock still present."
    return 1
  fi
  return 0
}

# ----- Logging -----
log_message() {
  local message="$1"
  local service="$(get_service_name)"
  local action="$(get_action_name)"
  local base_dir="/home/khryon/.aetheron/logs/${service}"
  local logfile="${base_dir}/${action}.log"
  mkdir -p "$base_dir"
  local lr_cfg="/etc/logrotate.d/aetheron-${service}"
  local warn_flag="${base_dir}/.logrotate_warned"
  if [[ ! -f "$lr_cfg" && ! -f "$warn_flag" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ⚠  No logrotate config for service '${service}'. Consider: /home/khryon/aetheron/utility-scripts/aetheron-logrotate" | tee -a "$logfile"
    touch "$warn_flag"
  fi
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$logfile"
}

# ----- Users/Groups -----
create_service_user() {
  local user="$1" group="$2" home="$3"
  if ! getent group "$group" >/dev/null; then
    sudo groupadd "$group"
    log_message "Group $group created"
  fi
  if ! id "$user" &>/dev/null; then
    sudo useradd -r -g "$group" -d "$home" -s /bin/bash "$user"
    sudo mkdir -p "$home"
    sudo chown "$user:$group" "$home"
    log_message "User $user created with home $home"
  fi
}

# ----- Packages -----
install_package() {
  local name="$1" pkg="$2"
  if ! pacman -Qi "$pkg" &>/dev/null; then
    _pacman_wait_unlock || return 1
    sudo pacman -S --noconfirm "$pkg"
    log_message "Package $name installed"
  else
    log_message "Package $name already installed"
  fi
}

# ----- UFW → firewalld migration -----
ufw_installed() { command -v ufw >/dev/null 2>&1; }
ufw_active()    { sudo ufw status 2>/dev/null | grep -qi "Status: active"; }

backup_ufw_rules() {
  local bkdir="/home/khryon/.aetheron/backups"; local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$bkdir"
  sudo ufw status numbered > "$bkdir/ufw-status-numbered-${ts}.txt" 2>&1 || true
  sudo ufw status          > "$bkdir/ufw-status-${ts}.txt"           2>&1 || true
  log_message "UFW rules backed up to $bkdir/ufw-status-*.txt"
}

disable_and_remove_ufw() {
  if ufw_installed; then
    if ufw_active; then
      backup_ufw_rules
      sudo ufw disable || log_message "WARN: ufw disable failed (continuing)"
    fi
    _pacman_wait_unlock || true
    sudo pacman -Rns --noconfirm ufw || log_message "WARN: pacman -Rns ufw failed (continuing)"
    log_message "UFW uninstalled"
  fi
}

# ----- firewalld helpers -----
ensure_firewalld_installed() {
  # Migrate from UFW if present
  if ufw_installed; then
    log_message "Detected UFW. Migrating to firewalld..."
    disable_and_remove_ufw
  fi

  # Install firewalld if missing
  if ! command -v firewall-cmd >/dev/null 2>&1; then
    log_message "Installing firewalld..."
    _pacman_wait_unlock || return 1
    sudo pacman -S --noconfirm firewalld || { log_message "ERROR: cannot install firewalld"; return 1; }
  fi
  return 0
}

firewall_available() { command -v firewall-cmd >/dev/null 2>&1; }

open_port() {
  local port="$1" protocol="$2" desc="${3:-}"
  firewall_available || { log_message "WARN: firewall-cmd missing; skip open_port $port/$protocol ${desc:+($desc)}"; return 0; }
  sudo firewall-cmd --permanent --add-port=${port}/${protocol}
  sudo firewall-cmd --reload
  log_message "Port ${port}/${protocol} opened${desc:+ for $desc}"
}

close_port() {
  local port="$1" protocol="$2" desc="${3:-}"
  firewall_available || { log_message "WARN: firewall-cmd missing; skip close_port $port/$protocol ${desc:+($desc)}"; return 0; }
  sudo firewall-cmd --permanent --remove-port=${port}/${protocol}
  sudo firewall-cmd --reload
  log_message "Port ${port}/${protocol} closed${desc:+ for $desc}"
}

open_service() {
  local svc="$1" desc="${2:-}"
  firewall_available || { log_message "WARN: firewall-cmd missing; skip open_service $svc ${desc:+($desc)}"; return 0; }
  sudo firewall-cmd --permanent --add-service=${svc}
  sudo firewall-cmd --reload
  log_message "Service ${svc} opened${desc:+ for $desc}"
}

close_service() {
  local svc="$1" desc="${2:-}"
  firewall_available || { log_message "WARN: firewall-cmd missing; skip close_service $svc ${desc:+($desc)}"; return 0; }
  sudo firewall-cmd --permanent --remove-service=${svc}
  sudo firewall-cmd --reload
  log_message "Service ${svc} closed${desc:+ for $desc}"
}

ensure_ssh_access() {
  firewall_available || { log_message "WARN: firewall-cmd missing; skip ensure_ssh_access"; return 0; }
  log_message "Ensuring SSH access (port 22) is enabled..."
  sudo firewall-cmd --permanent --add-service=ssh
  sudo firewall-cmd --reload
  log_message "SSH service enabled in firewall"
}

# Ensure sshd is installed/enabled/running
ensure_sshd_running() {
  if ! command -v sshd >/dev/null 2>&1; then
    log_message "OpenSSH server not found. Installing..."
    _pacman_wait_unlock || return 1
    sudo pacman -S --noconfirm openssh || { log_message "ERROR: cannot install openssh"; return 1; }
  fi
  if ! systemctl is-enabled --quiet sshd 2>/dev/null; then
    log_message "Enabling sshd.service..."
    sudo systemctl enable sshd || log_message "WARN: could not enable sshd"
  fi
  if ! systemctl is-active --quiet sshd; then
    log_message "Starting sshd.service..."
    sudo systemctl start sshd || { log_message "ERROR: could not start sshd"; return 1; }
  fi
  ensure_ssh_access
}

check_firewall() {
  ensure_firewalld_installed || { log_message "WARN: firewalld not available; skipping firewall config"; return 0; }

  if ! systemctl is-active --quiet firewalld; then
    log_message "⚠  firewalld is not active. Starting and enabling..."
    sudo systemctl enable --now firewalld || { log_message "ERROR: could not start firewalld"; return 1; }
  fi

  local default_zone
  default_zone=$(sudo firewall-cmd --get-default-zone 2>/dev/null || echo "")
  if [[ -n "$default_zone" && "$default_zone" != "drop" && "$default_zone" != "block" ]]; then
    log_message "⚠  Setting default zone to 'drop' for better security..."
    sudo firewall-cmd --set-default-zone=drop || log_message "WARN: could not set default zone"
  fi

  ensure_ssh_access
  ensure_sshd_running
}

# ----- Docker helpers -----
ensure_docker_network() {
  local net="${1:-aetheron}"
  if ! docker network ls --format '{{.Name}}' | grep -qx "$net"; then
    docker network create "$net"
    log_message "Docker network '$net' created"
  else
    log_message "Docker network '$net' already exists"
  fi
}

run_docker_compose() {
  local service="$1"
  local compose_file="${2:-docker-compose.yml}"

  # NICHT die Shell-Variable UID überschreiben – eigene Variablen verwenden
  export AETHERON_PUID="$(id -u "${SERVICE_USER:-$USER}" 2>/dev/null || echo 1000)"
  export AETHERON_PGID="$(id -g "${SERVICE_GROUP:-$USER}" 2>/dev/null || echo 1000)"

  local abs_compose
  abs_compose="$(readlink -f "$compose_file")"
  if [[ ! -f "$abs_compose" ]]; then
    log_message "ERROR: compose file not found: $compose_file"
    return 1
  fi

  docker compose -f "$abs_compose" -p "aetheron-${service}" up -d
  log_message "Docker Compose started for $service"
}

# ----- logrotate -----
setup_log_rotation() {
  local service="$1" log_path="$2"
  sudo tee /etc/logrotate.d/aetheron-$service >/dev/null << EOF
$log_path/*.log {
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
  log_message "Log rotation configured for $service (keep 10 versions)"
}

# ----- Secrets -----
store_password() {
  local service="$1" key="$2" value="$3"
  local dir="/home/khryon/.aetheron/secrets/${service}"
  local file="${dir}/secrets.env"
  mkdir -p "$dir"; chmod 700 "$dir"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s#^${key}=.*#${key}=${value//\#/\\#}#" "$file"
  else
    echo "${key}=${value}" >> "$file"
  fi
  chmod 600 "$file"
  log_message "Secret stored for ${service}: ${key}"
}

# ----- Password generator -----
generate_strong_password() {
  local upper="ABCDEFGHIJKLMNOPQRSTUVWXYZ" lower="abcdefghijklmnopqrstuvwxyz" digits="0123456789"
  local special="!@#$%^&*()_+-=[]{}|;:,.<>?~"
  local g_upper="${upper:$((RANDOM % ${#upper})):1}"
  local g_lower="${lower:$((RANDOM % ${#lower})):1}"
  local g_digit="${digits:$((RANDOM % ${#digits})):1}"
  local g_special="${special:$((RANDOM % ${#special})):1}"
  local base="${upper}${lower}${digits}" remain=""
  for ((i=0;i<16;i++)); do remain+="${base:$((RANDOM % ${#base})):1}"; done
  echo "${g_upper}${g_lower}${g_digit}${g_special}${remain}" | fold -w1 | shuf | tr -d '\n'
}

