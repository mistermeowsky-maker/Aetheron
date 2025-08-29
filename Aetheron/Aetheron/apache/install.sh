#!/bin/bash
# install.sh for apache
# Version: 1.03.00  # SSL Focus, Port 80 nur für Let's Encrypt

VERSION="1.03.00"
SERVICE="apache"
SERVICE_USER="apache"
SERVICE_GROUP="apache"
SERVICE_HOME="/home/apache"

# Pfade
HTML_DIR="$SERVICE_HOME/html"
CONFIG_DIR="$SERVICE_HOME/config"
VHOST_DIR="$SERVICE_HOME/vhosts"
LOG_DIR="$SERVICE_HOME/logs"
SSL_DIR="$SERVICE_HOME/ssl"

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

# Funktion zum Anlegen von Subdomains
create_subdomain() {
    local subdomain=$1
    local port=$2
    local document_root=$3
    local description=$4
    
    log_message "Creating subdomain: $subdomain ($description)"
    
    # Verzeichnis erstellen
    local vhost_path="$VHOST_DIR/$subdomain"
    local html_path="$document_root"
    mkdir -p "$vhost_path" "$html_path"
    
    # Virtual Host Konfiguration (MIT SSL REDIRECT)
    tee "$vhost_path/$subdomain.conf" > /dev/null << EOF
# HTTP → HTTPS Redirect für $subdomain
<VirtualHost *:80>
    ServerName $subdomain
    ServerAdmin webmaster@$subdomain
    Redirect permanent / https://$subdomain/
    
    ErrorLog ${LOG_DIR}/${subdomain}_redirect_error.log
    CustomLog ${LOG_DIR}/${subdomain}_redirect_access.log combined
</VirtualHost>

# HTTPS Configuration für $subdomain
<VirtualHost *:443>
    ServerName $subdomain
    ServerAdmin webmaster@$subdomain
    DocumentRoot "$html_path"
    
    # SSL Configuration
    SSLEngine on
    SSLCertificateFile /usr/local/apache2/ssl/cert.pem
    SSLCertificateKeyFile /usr/local/apache2/ssl/key.pem
    SSLProtocol all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256
    SSLHonorCipherOrder on
    SSLCompression off
    SSLSessionTickets off
    
    # Security Headers
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains"
    Header always set X-Frame-Options DENY
    Header always set X-Content-Type-Options nosniff
    Header always set X-XSS-Protection "1; mode=block"
    
    <Directory "$html_path">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog ${LOG_DIR}/${subdomain}_error.log
    CustomLog ${LOG_DIR}/${subdomain}_access.log combined
    LogLevel warn
</VirtualHost>
EOF

    # Beispiel Index Datei
    tee "$html_path/index.html" > /dev/null << EOF
<!DOCTYPE html>
<html>
<head>
    <title>$subdomain - $description</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; }
        h1 { color: #2c5282; border-bottom: 2px solid #e2e8f0; padding-bottom: 10px; }
        .status { color: #38a169; font-weight: bold; }
        .ssl { color: #d69e2e; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌐 $subdomain</h1>
        <p class="status">✅ $description is running successfully!</p>
        <p class="ssl">🔐 SSL Encryption: ACTIVE</p>
        <p><strong>📁 Document Root:</strong> $html_path</p>
        <p><strong>🖥️ Server:</strong> $(hostname)</p>
        <p><strong>🔒 Access:</strong> <a href="https://$subdomain">https://$subdomain</a></p>
    </div>
</body>
</html>
EOF

    log_message "✅ Subdomain created: $subdomain (HTTPS only)"
}

# Funktion für interaktive Konfiguration
configure_apache() {
    log_message "Starting interactive Apache configuration..."
    
    echo ""
    echo "================================================"
    echo "           APACHE WEBSERVER KONFIGURATION"
    echo "================================================"
    echo "🔒 SSL FIRST - Port 80 only for Let's Encrypt"
    echo "🌐 All traffic forced to HTTPS"
    echo ""
    
    # ================= DOMAIN KONFIGURATION =================
    echo "🌐 DOMAIN-EINSTELLUNGEN"
    echo "----------------------------------------"
    read -p "Primary Domain [homeofkhryon.de]: " PRIMARY_DOMAIN
    PRIMARY_DOMAIN=${PRIMARY_DOMAIN:-homeofkhryon.de}
    
    # ================= SSL KONFIGURATION =================
    echo ""
    echo "🔐 SSL/TLS KONFIGURATION (PFLICHT)"
    echo "----------------------------------------"
    echo "SSL ist verpflichtend für maximale Sicherheit"
    echo ""
    
    read -p "SSL Zertifikat Pfad [/home/apache/ssl/cert.pem]: " SSL_CERT_FILE
    SSL_CERT_FILE=${SSL_CERT_FILE:-/home/apache/ssl/cert.pem}
    
    read -p "SSL Private Key Pfad [/home/apache/ssl/key.pem]: " SSL_KEY_FILE
    SSL_KEY_FILE=${SSL_KEY_FILE:-/home/apache/ssl/key.pem}
    
    # ================= VORKONFIGURIERTE SUBDOMAINS =================
    echo ""
    echo "🏗️  VORKONFIGURIERTE SUBDOMAINS"
    echo "----------------------------------------"
    echo "Folgende Subdomains werden automatisch erstellt:"
    echo "  🌐 cloud.$PRIMARY_DOMAIN - Nextcloud"
    echo "  📚 novasimwiki.$PRIMARY_DOMAIN - MediaWiki"
    echo "  🏠 www.$PRIMARY_DOMAIN - Hauptseite"
    echo ""
    
    read -p "Zusätzliche Subdomains erstellen? (j/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        read -p "Weitere Subdomains (comma separated): " EXTRA_SUBDOMAINS
        IFS=',' read -ra EXTRA_SUBS <<< "$EXTRA_SUBDOMAINS"
        CREATE_EXTRA_SUBS="true"
    else
        CREATE_EXTRA_SUBS="false"
    fi
    
    # ================= BESTÄTIGUNG =================
    echo ""
    echo "================================================"
    echo "           ZUSAMMENFASSUNG"
    echo "================================================"
    echo "🔐 SSL: AKTIVIERT"
    echo "🌐 Primary Domain: $PRIMARY_DOMAIN"
    echo "🔧 Automatische Subdomains:"
    echo "   - cloud.$PRIMARY_DOMAIN (Nextcloud)"
    echo "   - novasimwiki.$PRIMARY_DOMAIN (MediaWiki)" 
    echo "   - www.$PRIMARY_DOMAIN (Hauptseite)"
    if [[ "$CREATE_EXTRA_SUBS" == "true" ]]; then
        echo "   - ${EXTRA_SUBS[*]}"
    fi
    echo "🔒 Alle Verbindungen: HTTPS ONLY"
    echo "📁 Data Location: $SERVICE_HOME/"
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

log_message "=== Starting Apache Installation (SSL Focus) ==="

# === SCHRITT 0: Firewall prüfen ===
check_firewall

# === SCHRITT 1: Benutzer und Verzeichnisse anlegen ===
create_service_user "$SERVICE_USER" "$SERVICE_GROUP" "$SERVICE_HOME"
sudo mkdir -p "$HTML_DIR" "$CONFIG_DIR" "$VHOST_DIR" "$LOG_DIR" "$SSL_DIR"
sudo chown -R "$SERVICE_USER":"$SERVICE_GROUP" "$SERVICE_HOME"
sudo chmod 755 "$LOG_DIR"

# === SCHRITT 2: Interaktive Konfiguration ===
if ! configure_apache; then
    log_message "❌ ERROR: Configuration failed"
    exit 1
fi

# === SCHRITT 3: VORKONFIGURIERTE SUBDOMAINS ERSTELLEN ===
log_message "Creating pre-configured subdomains..."

# Deine gewünschten Subdomains
create_subdomain "cloud.$PRIMARY_DOMAIN" 443 "$HTML_DIR/cloud" "Nextcloud Cloud"
create_subdomain "novasimwiki.$PRIMARY_DOMAIN" 443 "$HTML_DIR/novasimwiki" "NovaSim Wiki"
create_subdomain "www.$PRIMARY_DOMAIN" 443 "$HTML_DIR/www" "Main Website"

# Zusätzliche Subdomains falls gewünscht
if [[ "$CREATE_EXTRA_SUBS" == "true" ]]; then
    for subdomain in "${EXTRA_SUBS[@]}"; do
        create_subdomain "$subdomain.$PRIMARY_DOMAIN" 443 "$HTML_DIR/$subdomain" "Custom Site"
    done
fi

# === SCHRITT 4: Hauptkonfiguration erstellen ===
log_message "Creating main Apache configuration..."
sudo tee "$CONFIG_DIR/httpd.conf" > /dev/null << EOF
# Apache Hauptkonfiguration - SSL FOCUS
ServerRoot "/usr/local/apache2"

# Ports
Listen 80
Listen 443

# Module
LoadModule mpm_event_module modules/mod_mpm_event.so
LoadModule authn_core_module modules/mod_authn_core.so
LoadModule authz_core_module modules/mod_authz_core.so
LoadModule unixd_module modules/mod_unixd.so
LoadModule dir_module modules/mod_dir.so
LoadModule mime_module modules/mod_mime.so
LoadModule log_config_module modules/mod_log_config.so
LoadModule headers_module modules/mod_headers.so
LoadModule vhost_alias_module modules/mod_vhost_alias.so
LoadModule ssl_module modules/mod_ssl.so
LoadModule rewrite_module modules/mod_rewrite.so
LoadModule socache_shmcb_module modules/mod_socache_shmcb.so

# SSL Global Einstellungen
SSLRandomSeed startup builtin
SSLRandomSeed connect builtin
SSLSessionCache shmcb:/usr/local/apache2/logs/ssl_scache(512000)
SSLSessionCacheTimeout 300

# Include Virtual Hosts
IncludeOptional $VHOST_DIR/*/*.conf

# Globaler HTTP → HTTPS Redirect (Fallback)
<VirtualHost *:80>
    ServerName default-redirect
    Redirect permanent / https://www.$PRIMARY_DOMAIN/
    
    ErrorLog ${LOG_DIR}/global_redirect_error.log
    CustomLog ${LOG_DIR}/global_redirect_access.log combined
</VirtualHost>

# Security Einstellungen
ServerTokens Prod
ServerSignature Off
TraceEnable Off
FileETag None

<Directory "$HTML_DIR">
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

ErrorLog ${LOG_DIR}/error.log
CustomLog ${LOG_DIR}/access.log combined
EOF

# === SCHRITT 5: Docker Compose erstellen ===
log_message "Creating Docker Compose configuration..."

cat > "$(dirname "$0")/docker-compose.yml" << EOF
version: '3.8'

services:
  apache:
    image: httpd:2.4
    container_name: apache
    user: "\${UID}:\${GID}"
    volumes:
      - $HTML_DIR:/usr/local/apache2/htdocs
      - $CONFIG_DIR:/usr/local/apache2/conf
      - $VHOST_DIR:/usr/local/apache2/conf/vhosts
      - $LOG_DIR:/usr/local/apache2/logs
      - $SSL_DIR:/usr/local/apache2/ssl
    ports:
      - "80:80"    # Nur für Let's Encrypt
      - "443:443"  # Haupt-Port für HTTPS
    environment:
      - TZ=Europe/Berlin
      - UID=\${UID}
      - GID=\${GID}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "https://localhost:443", "-k"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

# === SCHRITT 6: Container starten ===
log_message "Starting Apache container..."
if ! run_docker_compose "$SERVICE"; then
    log_message "❌ ERROR: Docker Compose failed"
    exit 1
fi

# === SCHRITT 7: Firewall Ports öffnen ===
log_message "Configuring firewall..."
open_port 80 "tcp" "Apache - HTTP (Let's Encrypt only)"
open_port 443 "tcp" "Apache - HTTPS (Main traffic)"

# === SCHRITT 8: Log Rotation einrichten ===
setup_log_rotation "apache" "$LOG_DIR"

log_message "=== Apache Installation completed successfully ==="
echo ""
echo "✅ Apache Web Server is now running - SSL FIRST!"
echo "   🔐 HTTPS ONLY: All traffic forced to encryption"
echo "   🌐 Primary Domain: $PRIMARY_DOMAIN"
echo "   🏗️  Pre-configured subdomains:"
echo "      🔐 https://cloud.$PRIMARY_DOMAIN - Nextcloud"
echo "      🔐 https://novasimwiki.$PRIMARY_DOMAIN - Wiki"
echo "      🔐 https://www.$PRIMARY_DOMAIN - Main site"
echo ""
echo "🔧 Port 80 remains open ONLY for Let's Encrypt"
echo "🚀 All user traffic is redirected to HTTPS"
exit 0