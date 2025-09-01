#!/bin/bash
# reverse-proxy-setup-secure.sh
# Version: 1.00.01
# Installiert Nginx Reverse-Proxy - Nur Let's Encrypt auf Port 80

set -e

# Farben für die Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# === SCHRITT 1: Nginx installieren ===
log "Installing Nginx..."
sudo apt update
sudo apt install -y nginx

# === SCHRITT 2: Firewall konfigurieren ===
log "Configuring firewall..."
sudo ufw allow 443/tcp comment "HTTPS"
sudo ufw allow 22/tcp comment "SSH"
# Port 80 NUR für Let's Encrypt IPs
sudo ufw allow from 64.78.149.164/28 to any port 80 comment "Let's Encrypt"
sudo ufw allow from 66.133.109.36/28 to any port 80 comment "Let's Encrypt"

# === SCHRITT 3: Nginx Config nur für Let's Encrypt ===
log "Creating secure Nginx configuration..."

sudo tee /etc/nginx/conf.d/letsencrypt-only.conf > /dev/null << 'EOF'
# ONLY Allow Let's Encrypt Validation
server {
    listen 80;
    server_name _;
    
    # Only allow Let's Encrypt IP ranges
    allow 64.78.149.164/28;
    allow 66.133.109.36/28;
    deny all;
    
    # ACME Challenge Location
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files $uri =404;
    }
    
    # Block everything else
    location / {
        return 444;
    }
}
EOF

# === SCHRITT 4: HTTPS Config mit automatischer Umleitung ===
sudo tee /etc/nginx/conf.d/aetheron-https.conf > /dev/null << 'EOF'
# Aetheron HTTPS Configuration
server {
    listen 443 ssl http2;
    server_name nextcloud.your-domain.com;
    
    # SSL Configuration will be added by Certbot
    ssl_certificate /etc/letsencrypt/live/nextcloud.your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/nextcloud.your-domain.com/privkey.pem;
    
    location / {
        proxy_pass http://YOUR_SERVER_IP:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
    }
}

server {
    listen 443 ssl http2;
    server_name wiki.your-domain.com;
    
    ssl_certificate /etc/letsencrypt/live/wiki.your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/wiki.your-domain.com/privkey.pem;
    
    location / {
        proxy_pass http://YOUR_SERVER_IP:8081;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# === SCHRITT 5: Certbot installieren ===
log "Installing Certbot..."
sudo apt install -y certbot python3-certbot-nginx

# === SCHRITT 6: Webroot für ACME Challenges ===
sudo mkdir -p /var/www/html/.well-known/acme-challenge
sudo chown -R www-data:www-data /var/www/html

# === SCHRITT 7: Nginx starten ===
log "Starting Nginx..."
sudo systemctl enable nginx
sudo systemctl restart nginx

log "✅ Secure Reverse-Proxy Setup completed!"
log ""
log "Port 80 is ONLY accessible for Let's Encrypt validation"
log "To get SSL certificates, run:"
log "sudo certbot --webroot -w /var/www/html -d your-domain.com"
log ""
log "Firewall rules:"
sudo ufw status numbered