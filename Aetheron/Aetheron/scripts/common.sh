# In common.sh hinzufügen
wipe_service() {
    local service=$1
    local service_user=$2
    local service_group=$3
    local directories=$4  # Komma-getrennte Liste von Verzeichnissen
    local ports=$5        # Komma-getrennte Liste von Ports (z.B. "3306/tcp,8080/tcp")
    
    log_message "Starting WIPE operation for $service"
    
    # === 1. BACKUP ERSTELLEN (alles außer Logs) ===
    log_message "Creating final backup (excluding logs)..."
    local backup_file=""
    for dir in $(echo "$directories" | tr ',' ' '); do
        if [[ -d "$dir" ]] && [[ "$dir" != *"log"* ]]; then  # Logs nicht backupen
            backup_file=$(create_backup "$service" "$dir" "FINAL_WIPE")
        fi
    done
    
    # === 2. DOCKER CONTAINER STOPPEN & ENTFERNEN ===
    log_message "Stopping and removing Docker containers..."
    if [[ -f "docker-compose.yml" ]]; then
        docker-compose down -v --rmi all 2>/dev/null
    fi
    docker stop "$service" 2>/dev/null
    docker rm "$service" 2>/dev/null
    docker volume prune -f 2>/dev/null
    
    # === 3. VERZEICHNISSE LÖSCHEN (inkl. Logs) ===
    log_message "Removing directories (including logs)..."
    for dir in $(echo "$directories" | tr ',' ' '); do
        if [[ -d "$dir" ]]; then
            sudo rm -rf "$dir"
            log_message "Removed directory: $dir"
        fi
    done
    
    # === 4. LOGS IM HAUPTUSER LÖSCHEN ===
    local user_log_dir="/home/khryon/logs/$service"
    if [[ -d "$user_log_dir" ]]; then
        sudo rm -rf "$user_log_dir"
        log_message "Removed user log directory: $user_log_dir"
    fi
    
    # === 5. PORTS IN FIREWALL SCHLIEßEN ===
    log_message "Closing firewall ports..."
    for port_entry in $(echo "$ports" | tr ',' ' '); do
        local port=$(echo "$port_entry" | cut -d'/' -f1)
        local protocol=$(echo "$port_entry" | cut -d'/' -f2)
        close_port "$port" "$protocol" "Wiped service: $service"
    done
    
    # === 6. USER & GRUPPE ENTFERNEN ===
    log_message "Removing user and group..."
    if id "$service_user" &>/dev/null; then
        sudo userdel -r "$service_user" 2>/dev/null
        log_message "Removed user: $service_user"
    fi
    
    if getent group "$service_group" > /dev/null; then
        sudo groupdel "$service_group" 2>/dev/null
        log_message "Removed group: $service_group"
    fi
    
    # === 7. LOGROTATE KONFIG ENTFERNEN ===
    log_message "Removing logrotate configuration..."
    sudo rm -f "/etc/logrotate.d/aetheron-$service"
    
    # === 8. CRON-JOBS ENTFERNEN ===
    log_message "Removing cron jobs..."
    sudo crontab -l | grep -v "$service" | sudo crontab -
    
    log_message "✅ WIPE completed for $service"
    if [[ -n "$backup_file" ]]; then
        log_message "📦 Final backup saved: $backup_file"
    fi
}