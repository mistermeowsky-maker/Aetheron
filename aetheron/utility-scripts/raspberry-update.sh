#!/bin/bash
# Auto-Update Script für Raspberry Pi
# Version: 1.00.00

LOG_FILE="/var/log/raspberry-update.log"

echo "=== Raspberry Pi Auto-Update $(date) ===" | tee -a "$LOG_FILE"

# System Updates
echo "System updates..." | tee -a "$LOG_FILE"
sudo apt update 2>&1 | tee -a "$LOG_FILE"
sudo apt upgrade -y 2>&1 | tee -a "$LOG_FILE"

# Nginx Updates
echo "Nginx updates..." | tee -a "$LOG_FILE"
sudo apt install --only-upgrade nginx -y 2>&1 | tee -a "$LOG_FILE"

# Certbot Updates
echo "Certbot updates..." | tee -a "$LOG_FILE"
sudo apt install --only-upgrade certbot python3-certbot-nginx -y 2>&1 | tee -a "$LOG_FILE"

# Cleanup
echo "Cleaning up..." | tee -a "$LOG_FILE"
sudo apt autoremove -y 2>&1 | tee -a "$LOG_FILE"
sudo apt autoclean 2>&1 | tee -a "$LOG_FILE"

echo "=== Update completed ===" | tee -a "$LOG_FILE"