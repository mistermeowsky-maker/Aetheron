#!/bin/bash
# install.sh for vsftpd
# Version: 1.00.01  # Anonymous deaktiviert

VERSION="1.00.01"
SERVICE="vsftpd"
SERVICE_USER="vsftpd"
SERVICE_GROUP="vsftpd"
SERVICE_HOME="/home/vsftpd"

# Pfade
CONFIG_DIR="$SERVICE_HOME/config"
DATA_DIR="$SERVICE_HOME/data"
LOG_DIR="/home/khryon/logs/vsftpd"
USER_DB_DIR="$SERVICE_HOME/users"

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

# Funktion für interaktive Konfiguration
configure_vsftpd() {
    log_message "Starting interactive VSFTPD configuration..."
    
    echo ""
    echo "================================================"
    echo "           VSFTPD KONFIGURATION"
    echo "================================================"
    echo "⚠️  Anonymous access is DISABLED by default"
    echo ""
    
    # ================= NETZWERK KONFIGURATION =================
    echo "🌐 NETZWERK-EINSTELLUNGEN"
    echo "----------------------------------------"
    read -p "FTP Port [21]: " FTP_PORT
    FTP_PORT=${FTP_PORT:-21}
    
    read -p "Passive Port Range [30000-30010]: " PASSIVE_PORTS
    PASSIVE_PORTS=${PASSIVE_PORTS:-30000-30010}
    
    read -p "FTP Hostname [ftp.aetheron.local]: " FTP_HOSTNAME
    FTP_HOSTNAME=${FTP_HOSTNAME:-ftp.aetheron.local}
    
    # ================= SICHERHEITSKONFIGURATION =================
    echo ""
    echo "🔐 SICHERHEITS-EINSTELLUNGEN"
    echo "----------------------------------------"
    read -p "SSL/TLS aktivieren? (j/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        SSL_ENABLED="YES"
        read -p "SSL Zertifikat Pfad [/home/vsftpd/ssl/cert.pem]: " SSL_CERT_FILE
        SSL_CERT_FILE=${SSL_CERT_FILE:-/home/vsftpd/ssl/cert.pem}
        read -p "SSL Private Key Pfad [/home/vsftpd/ssl/key.pem]: " SSL_KEY_FILE
        SSL_KEY_FILE=${SSL_KEY_FILE:-/home/vsftpd/ssl/key.pem}
    else
        SSL_ENABLED="NO"
        SSL_CERT_FILE=""
        SSL_KEY_FILE=""
    fi
    
    # ================= USER KONFIGURATION =================
    echo ""
    echo "👤 USER-EINSTELLUNGEN"
    echo "----------------------------------------"
    read -p "Ersten FTP User erstellen? (j/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        read -p "Username: " FTP_USER
        read -sp "Password: " FTP_PASSWORD
        echo
        read -p "Root Directory [/home/vsftpd/data/$FTP_USER]: " USER_ROOT
        USER_ROOT=${USER_ROOT:-/home/vsftpd/data/$FTP_USER}
        
        # User speichern für später
        FTP_USER_CREATE="YES"
    else
        FTP_USER_CREATE="NO"
    fi
    
    # ================= BESTÄTIGUNG =================
    echo ""
    echo "================================================"
    echo "           ZUSAMMENFASSUNG"
    echo "================================================"
    echo "🔸 Port: $FTP_PORT"
    echo "🔸 Passive Ports: $PASSIVE_PORTS"
    echo "🔸 SSL: $SSL_ENABLED"
    echo "🔸 Anonymous: NO ❌"
    if [[ "$FTP_USER_CREATE" == "YES" ]]; then
        echo "🔸 User: $FTP_USER"
    fi
    echo "================================================"
    echo ""
    
    read -p "Konfiguration bestätigen? (j/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        log_message "❌ Konfiguration abgebrochen"
        return 1
    fi

    return 0
}

# Funktion zum Erstellen von FTP Usern
create_ftp_user() {
    local username=$1
    local password=$2
    local root_dir=$3
    
    # User-Datenbank erstellen falls nicht existiert
    if [[ ! -f "$USER_DB_DIR/virtual_users.txt" ]]; then
        touch "$USER_DB_DIR/virtual_users.txt"
        db_load -T -t hash -f "$USER_DB_DIR/virtual_users.txt" "$USER_DB_DIR/virtual_users.db"
    fi
    
    # User zur Datenbank hinzufügen
    echo -e "$username\n$password" >> "$USER_DB_DIR/virtual_users.txt"
    db_load -T -t hash -f "$USER_DB_DIR/virtual_users.txt" "$USER_DB_DIR/virtual_users.db"
    
    # Verzeichnis erstellen
    mkdir -p "$root_dir"
    chown -R ftp:ftp "$root_dir"
    chmod 755 "$root_dir"
    
    # User Config erstellen
    tee "$USER_DB_DIR/$username" > /dev/null << EOF
local_root=$root_dir
write_enable=YES
anon_world_readable_only=NO
anon_upload_enable=YES
anon_mkdir_write_enable=YES
anon_other_write_enable=YES
EOF

    log_message "Created FTP user: $username"
    store_password "vsftpd" "$username" "$password"
}

log_message "=== Starting VSFTPD Installation ==="

# === SCHRITT 0: Firewall prüfen ===
check_firewall

# === SCHRITT 1: Benutzer und Verzeichnisse anlegen ===
create_service_user "$SERVICE_USER" "$SERVICE_GROUP" "$SERVICE_HOME"
sudo mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" "$USER_DB_DIR"
sudo chown -R "$SERVICE_USER":"$SERVICE_GROUP" "$CONFIG_DIR" "$DATA_DIR" "$USER_DB_DIR"
sudo chown -R khryon:users "$LOG_DIR"
sudo chmod 755 "$LOG_DIR"

# === SCHRITT 2: Interaktive Konfiguration ===
if ! configure_vsftpd; then
    log_message "❌ ERROR: Configuration failed"
    exit 1
fi

# === SCHRITT 3: Konfiguration erstellen (ANONYMOUS DISABLED) ===
log_message "Creating VSFTPD configuration (anonymous disabled)..."
sudo tee "$CONFIG_DIR/vsftpd.conf" > /dev/null << EOF
# VSFTPD Configuration
# Auto-generated on $(date)
# Anonymous access: DISABLED

# Network settings
listen=YES
listen_port=$FTP_PORT
listen_address=0.0.0.0
pasv_enable=YES
pasv_min_port=$(echo $PASSIVE_PORTS | cut -d'-' -f1)
pasv_max_port=$(echo $PASSIVE_PORTS | cut -d'-' -f2)
pasv_address=$FTP_HOSTNAME

# Security settings - ANONYMOUS DISABLED
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
hide_ids=YES
seccomp_sandbox=NO

# SSL/TLS settings
ssl_enable=$SSL_ENABLED
allow_anon_ssl=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
rsa_cert_file=$SSL_CERT_FILE
rsa_private_key_file=$SSL_KEY_FILE

# Logging
xferlog_file=$LOG_DIR/vsftpd.log
log_ftp_protocol=YES
vsftpd_log_file=$LOG_DIR/vsftpd_detailed.log

# Virtual users
pam_service_name=vsftpd_virtual
guest_enable=YES
guest_username=ftp
user_config_dir=$USER_DB_DIR
virtual_use_local_privs=YES

# Performance
idle_session_timeout=600
data_connection_timeout=120
max_clients=50
max_per_ip=10
EOF

# PAM Configuration erstellen
sudo tee "/etc/pam.d/vsftpd_virtual" > /dev/null << EOF
auth required pam_userdb.so db=$USER_DB_DIR/virtual_users
account required pam_userdb.so db=$USER_DB_DIR/virtual_users
EOF

# === SCHRITT 4: FTP User erstellen falls gewünscht ===
if [[ "$FTP_USER_CREATE" == "YES" ]]; then
    log_message "Creating FTP user: $FTP_USER"
    create_ftp_user "$FTP_USER" "$FTP_PASSWORD" "$USER_ROOT"
fi

# === SCHRITT 5: Docker Compose erstellen ===
log_message "Creating Docker Compose configuration..."
cat > "$(dirname "$0")/docker-compose.yml" << EOF
version: '3.8'

services:
  vsftpd:
    image: fauria/vsftpd
    container_name: vsftpd
    user: "\${UID}:\${GID}"
    volumes:
      - $CONFIG_DIR:/etc/vsftpd
      - $DATA_DIR:/home/vsftpd
      - $LOG_DIR:/var/log/vsftpd
      - $USER_DB_DIR:/etc/vsftpd/users
    ports:
      - "$FTP_PORT:21"
      - "$(echo $PASSIVE_PORTS | cut -d'-' -f1)-$(echo $PASSIVE_PORTS | cut -d'-' -f2):$(echo $PASSIVE_PORTS | cut -d'-' -f1)-$(echo $PASSIVE_PORTS | cut -d'-' -f2)"
    environment:
      - TZ=Europe/Berlin
      - UID=\${UID}
      - GID=\${GID}
    restart: unless-stopped
    cap_add:
      - NET_BIND_SERVICE
EOF

# === SCHRITT 6: Container starten ===
log_message "Starting VSFTPD container..."
if ! run_docker_compose "$SERVICE"; then
    log_message "❌ ERROR: Docker Compose failed"
    exit 1
fi

# === SCHRITT 7: Firewall Ports öffnen ===
log_message "Configuring firewall..."
open_port "$FTP_PORT" "tcp" "VSFTPD - Control"
open_port "$(echo $PASSIVE_PORTS | cut -d'-' -f1)"-"$(echo $PASSIVE_PORTS | cut -d'-' -f2)" "tcp" "VSFTPD - Passive Data"

# === SCHRITT 8: Log Rotation einrichten ===
setup_log_rotation "vsftpd" "$LOG_DIR"

log_message "=== VSFTPD Installation completed successfully ==="
echo ""
echo "✅ VSFTPD Server is now running!"
echo "   📁 FTP: ftp://$(hostname -I | awk '{print $1}'):$FTP_PORT"
echo "   🔐 SSL: $SSL_ENABLED"
echo "   👥 Anonymous access: ❌ DISABLED"
if [[ "$FTP_USER_CREATE" == "YES" ]]; then
    echo "   👤 User: $FTP_USER"
    echo "   🔐 Password saved in master password file"
fi
echo "   📊 Passive ports: $PASSIVE_PORTS"
exit 0