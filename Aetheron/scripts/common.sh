#!/bin/bash
# common.sh - Common functions for all service scripts
# Version: 1.00.03

VERSION="1.00.03"

# Funktion zum Erstellen von Service-Usern
create_service_user() {
    local user=$1
    local group=$2
    local home=$3
    
    if ! getent group "$group" > /dev/null; then
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

# Funktion zum Installieren von Paketen
install_package() {
    local name=$1
    local package=$2
    
    if ! pacman -Qi "$package" &> /dev/null; then
        sudo pacman -S --noconfirm "$package"
        log_message "Package $name installed"
    else
        log_message "Package $name already installed"
    fi
}

# Firewall-Funktionen für firewalld
open_port() {
    local port=$1
    local protocol=$2
    local description=$3
    
    # Port permanent hinzufügen
    sudo firewall-cmd --permanent --add-port=$port/$protocol
    sudo firewall-cmd --reload
    log_message "Port $port/$protocol opened for $description"
}

close_port() {
    local port=$1
    local protocol=$2
    local description=$3
    
    # Port permanent entfernen
    sudo firewall-cmd --permanent --remove-port=$port/$protocol
    sudo firewall-cmd --reload
    log_message "Port $port/$protocol closed for $description"
}

# SSH Service explizit erlauben (wichtig für Public Key Auth)
ensure_ssh_access() {
    log_message "Ensuring SSH access (port 22) is enabled..."
    sudo firewall-cmd --permanent --add-service=ssh
    sudo firewall-cmd --reload
    log_message "SSH service enabled in firewall"
}

# Service-Funktionen für firewalld
open_service() {
    local service=$1
    local description=$2
    
    sudo firewall-cmd --permanent --add-service=$service
    sudo firewall-cmd --reload
    log_message "Service $service opened for $description"
}

close_service() {
    local service=$1
    local description=$2
    
    sudo firewall-cmd --permanent --remove-service=$service
    sudo firewall-cmd --reload
    log_message "Service $service closed for $description"
}

# Firewall Status prüfen
check_firewall() {
    if ! systemctl is-active --quiet firewalld; then
        log_message "⚠️  firewalld is not active. Starting and enabling..."
        sudo systemctl enable --now firewalld
    fi
    
    # Default Zone auf 'drop' oder 'block' setzen für maximale Sicherheit
    local default_zone=$(sudo firewall-cmd --get-default-zone)
    if [[ "$default_zone" != "drop" && "$default_zone" != "block" ]]; then
        log_message "⚠️  Setting default zone to 'drop' for better security..."
        sudo firewall-cmd --set-default-zone=drop
    fi
    
    # SSH Zugang sicherstellen
    ensure_ssh_access
}

# Funktion zum Aktivieren/Starten von Services
enable_and_start_service() {
    local service=$1
    
    sudo systemctl enable "$service"
    sudo systemctl start "$service"
    log_message "Service $service enabled and started"
}

# Funktion zum Docker Compose
run_docker_compose() {
    local service=$1
    local compose_file="${2:-docker-compose.yml}"
    
    # Umgebungsvariablen für User/GID setzen
    export UID=$(id -u $SERVICE_USER 2>/dev/null || echo 1000)
    export GID=$(id -g $SERVICE_GROUP 2>/dev/null || echo 1000)
    
    docker-compose -f "$compose_file" up -d
    log_message "Docker Compose started for $service"
}

# Funktion zum Log-Rotation Setup
setup_log_rotation() {
    local service=$1
    local log_path=$2
    
    # Logrotate-Konfiguration erstellen
    sudo tee /etc/logrotate.d/aetheron-$service << EOF
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

# Logging-Funktion KORRIGIERT
log_message() {
    local message="$1"
    local script_dir="$(dirname "$0")"
    local logfile="$script_dir/../logs/$(basename "$0" .sh).log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$logfile"
}

# Funktion zur Generierung eines starken Passworts
generate_strong_password() {
    local length=20
    local upper="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local lower="abcdefghijklmnopqrstuvwxyz"
    local digits="0123456789"
    local special="!@#$%^&*()_+-=[]{}|;:,.<>?~"
    
    # Garantierte Zeichen (je 1x)
    local guaranteed_chars=$( \
        echo "${upper:$((RANDOM % ${#upper})):1}" \
        "${lower:$((RANDOM % ${#lower})):1}" \
        "${digits:$((RANDOM % ${#digits})):1}" \
        "${special:$((RANDOM % ${#special})):1}" \
        | tr -d ' ' \
    )
    
    # Restliche Zeichen (nur Buchstaben und Zahlen)
    local all_chars_no_special="${upper}${lower}${digits}"
    local remaining_chars=""
    for ((i=0; i<16; i++)); do
        remaining_chars+="${all_chars_no_special:$((RANDOM % ${#all_chars_no_special})):1}"
    done
    
    # Kombiniere und mische
    local combined_chars="${guaranteed_chars}${remaining_chars}"
    local password=$(echo "$combined_chars" | fold -w1 | shuf | tr -d '\n')
    
    echo "$password"
}