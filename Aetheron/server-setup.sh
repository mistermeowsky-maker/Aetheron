#!/bin/bash
# server-setup.sh
# Version: 1.04.06

VERSION="1.04.06"
BASE_DIR=~/Aetheron
SERVICES_DIR=$BASE_DIR/services
SCRIPTS_DIR=$BASE_DIR/scripts
LOG_DIR=$BASE_DIR/logs
mkdir -p "$LOG_DIR" "$SCRIPTS_DIR"
LOGFILE="$LOG_DIR/server-setup.log"
SUMMARY_LOG="$LOG_DIR/summary.last.log"

DRYRUN=false

# Load common functions KORRIGIERT
if [[ -f "$SCRIPTS_DIR/common.sh" ]]; then
    source "$SCRIPTS_DIR/common.sh"
else
    echo "ERROR: common.sh not found at $SCRIPTS_DIR/common.sh"
    echo "Please run init-structure.sh first to create the base structure."
    exit 1
fi

# Arrays für die Zusammenfassung
SUCCESSFUL_SERVICES=()
FAILED_SERVICES=()
SKIPPED_SERVICES=()

log_message "=== Aetheron Setup Script started ==="
log_message "Version: $VERSION"

show_status() {
    if $DRYRUN; then
        echo "[MODE] Running in TEST MODE (--dry-run)"
    else
        echo "[MODE] Running in NORMAL MODE"
    fi
    echo "[INFO] Script Version: $VERSION"
    
    # Firewall Status anzeigen
    if command -v firewall-cmd &> /dev/null; then
        local default_zone=$(sudo firewall-cmd --get-default-zone)
        local ssh_status=$(sudo firewall-cmd --list-services | grep -q ssh && echo "✅" || echo "❌")
        echo "[FIREWALL] Default Zone: $default_zone, SSH: $ssh_status"
    fi
}

print_summary() {
    local operation=$1
    clear
    echo "=============================="
    echo "         ZUSAMMENFASSUNG"
    echo "=============================="
    echo "Operation: $operation"
    echo "Durchgeführt am: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Version: $VERSION"
    echo "=============================="
    echo ""

    if [ ${#SUCCESSFUL_SERVICES[@]} -gt 0 ]; then
        echo "✅ ERFOLGREICH:"
        for service in "${SUCCESSFUL_SERVICES[@]}"; do
            echo "   - $service"
        done
        echo ""
    fi

    if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
        echo "❌ FEHLGESCHLAGEN:"
        for service in "${FAILED_SERVICES[@]}"; do
            echo "   - $service"
            echo "     Log: $SERVICES_DIR/$service/logs/$operation.log"
        done
        echo ""
    fi

    if [ ${#SKIPPED_SERVICES[@]} -gt 0 ]; then
        echo "⚠️  ÜBERSPRUNGEN:"
        for service in "${SKIPPED_SERVICES[@]}"; do
            echo "   - $service"
        done
        echo ""
    fi

    # Firewall-Status in Zusammenfassung
    if command -v firewall-cmd &> /dev/null; then
        echo "=============================="
        echo "🔐 FIREWALL STATUS"
        echo "=============================="
        echo "Default Zone: $(sudo firewall-cmd --get-default-zone)"
        echo "Active Services: $(sudo firewall-cmd --list-services)"
        echo "=============================="
        echo ""
    fi

    # Zusammenfassung in Datei schreiben
    {
        echo "Zusammenfassung vom $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Version: $VERSION"
        echo "Operation: $operation"
        echo "Erfolgreich: ${#SUCCESSFUL_SERVICES[@]}"
        echo "Fehlgeschlagen: ${#FAILED_SERVICES[@]}"
        echo "Übersprungen: ${#SKIPPED_SERVICES[@]}"
        echo ""
        
        if [ ${#SUCCESSFUL_SERVICES[@]} -gt 0 ]; then
            echo "Erfolgreiche Dienste:"
            for service in "${SUCCESSFUL_SERVICES[@]}"; do
                echo "  - $service"
            done
            echo ""
        fi
        
        if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
            echo "Fehlerhafte Dienste:"
            for service in "${FAILED_SERVICES[@]}"; do
                echo "  - $service"
                echo "    Log: $SERVICES_DIR/$service/logs/$operation.log"
            done
            echo ""
        fi

        # Firewall-Info in Logfile
        if command -v firewall-cmd &> /dev/null; then
            echo "FIREWALL INFO:"
            echo "Default Zone: $(sudo firewall-cmd --get-default-zone)"
            echo "Services: $(sudo firewall-cmd --list-services)"
            echo "Ports: $(sudo firewall-cmd --list-ports)"
        fi
    } > "$SUMMARY_LOG"

    # Kritische Abhängigkeiten warnung
    local critical_services=("mariadb")
    local has_critical_error=0
    
    for critical_service in "${critical_services[@]}"; do
        if printf '%s\n' "${FAILED_SERVICES[@]}" | grep -q "^${critical_service}$"; then
            echo "⚠️  WARNUNG: $critical_service ist fehlgeschlagen!"
            echo "   Viele Dienste benötigen MariaDB für korrekte Funktion."
            has_critical_error=1
        fi
    done
    
    if [ $has_critical_error -eq 1 ]; then
        echo ""
        echo "ℹ️  Empfehlung: Beheben Sie zuerst die Fehler bei den kritischen Diensten."
    fi
    
    echo "=============================="
}

run_service_action() {
    local action=$1
    local service=$2
    local original_service=$service

    # Spezialfälle für Dienstgruppen
    case "$service" in
        "irc") 
            local services_to_run=("unrealircd" "anope")
            ;;
        "mail")
            local services_to_run=("postfix" "dovecot" "spamassassin")
            ;;
        "monitoring")
            local services_to_run=("cockpit" "netdata")
            ;;
        *)
            local services_to_run=("$service")
            ;;
    esac

    for target_service in "${services_to_run[@]}"; do
        SCRIPT="$SERVICES_DIR/$target_service/$action.sh"
        
        if [[ ! -f "$SCRIPT" ]]; then
            log_message "[ERROR] Script nicht gefunden: $SCRIPT"
            SKIPPED_SERVICES+=("$target_service")
            continue
        fi

        if [[ ! -x "$SCRIPT" ]]; then
            chmod +x "$SCRIPT"
        fi

        log_message "[ACTION] Starte $action für $target_service..."
        
        if $DRYRUN; then
            echo "[DRY-RUN] Würde ausführen: $SCRIPT"
            SKIPPED_SERVICES+=("$target_service (dry-run)")
        else
            # Führe Script aus und capture Exit-Code
            echo "Ausführen: $SCRIPT"
            bash "$SCRIPT"
            local exit_code=$?
            
            if [ $exit_code -eq 0 ]; then
                log_message "[SUCCESS] $action für $target_service abgeschlossen"
                SUCCESSFUL_SERVICES+=("$target_service")
            else
                log_message "[ERROR] $action für $target_service fehlgeschlagen (Exit-Code: $exit_code)"
                FAILED_SERVICES+=("$target_service")
                
                # Frage bei Fehler nach Fortsetzung für einzelne Dienste
                if [[ "$original_service" != "all" ]]; then
                    read -p "❌ Fehler bei $target_service. Trotzdem fortfahren? (j/N): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
                        log_message "[INFO] Abbruch durch Benutzer nach Fehler in $target_service"
                        return 1
                    fi
                fi
            fi
        fi
    done
    return 0
}

service_submenu() {
    local action=$1
    clear
    echo "===== $action Menu ====="
    echo "1) All services"
    echo "2) MariaDB"
    echo "3) IRC (UnrealIRCd + Anope)"
    echo "4) Quasselcore"
    echo "5) Nextcloud"
    echo "6) MediaWiki"
    echo "7) Apache"
    echo "8) Teamspeak"
    echo "9) Vsftpd"
    echo "10) Monitoring (Cockpit + Netdata)"
    echo "11) Mailserver"
    echo "0) Back"
    read -p "Select a service: " choice

    # Arrays zurücksetzen für neue Operation
    SUCCESSFUL_SERVICES=()
    FAILED_SERVICES=()
    SKIPPED_SERVICES=()

    case $choice in
        1) run_service_action "$action" "all" && print_summary "$action aller Dienste";;
        2) run_service_action "$action" "mariadb" && print_summary "$action MariaDB";;
        3) run_service_action "$action" "irc" && print_summary "$action IRC-Services";;
        4) run_service_action "$action" "quassel" && print_summary "$action Quasselcore";;
        5) run_service_action "$action" "nextcloud" && print_summary "$action Nextcloud";;
        6) run_service_action "$action" "mediawiki" && print_summary "$action MediaWiki";;
        7) run_service_action "$action" "apache" && print_summary "$action Apache";;
        8) run_service_action "$action" "teamspeak" && print_summary "$action Teamspeak";;
        9) run_service_action "$action" "vsftpd" && print_summary "$action Vsftpd";;
        10) run_service_action "$action" "monitoring" && print_summary "$action Monitoring";;
        11) run_service_action "$action" "mail" && print_summary "$action Mailserver";;
        0) main_menu ;;
        *) echo "Invalid option";;
    esac
}

main_menu() {
    # Firewall initialisieren beim Start
    if ! $DRYRUN; then
        check_firewall
    fi

    while true; do
        clear
        echo "=============================="
        echo "       Aetheron Setup"
        echo "       Version: $VERSION"
        echo "=============================="
        show_status
        echo ""
        echo "1) Install all services"
        echo "2) Install single service"
        echo "3) Reinstall service(s)"
        echo "4) Uninstall service(s)"
        echo "5) Wipe service(s)"
        echo "6) Test run (Dry-Run)"
        echo "7) Zeige letzte Zusammenfassung"
        echo "8) Script Version anzeigen"
        echo "9) Firewall Status anzeigen"
        echo "0) Exit"
        echo ""
        read -p "Select an option: " choice

        # Arrays zurücksetzen für neue Operation
        SUCCESSFUL_SERVICES=()
        FAILED_SERVICES=()
        SKIPPED_SERVICES=()

        case $choice in
            1) run_service_action "install" "all" && print_summary "Installation aller Dienste";;
            2) service_submenu "install" ;;
            3) service_submenu "reinstall" ;;
            4) service_submenu "uninstall" ;;
            5) service_submenu "wipe" ;;
            6) DRYRUN=true; 
               echo "[*] Dry-run mode enabled"; 
               read -p "Press Enter to continue..." dummy;
               DRYRUN=false;;
            7) [ -f "$SUMMARY_LOG" ] && cat "$SUMMARY_LOG" || echo "Keine Zusammenfassung verfügbar.";
               read -p "Press Enter to continue..." dummy;;
            8) echo "Aktuelle Version: $VERSION";
               read -p "Press Enter to continue..." dummy;;
            9) echo "Firewall Status:";
               sudo firewall-cmd --list-all;
               read -p "Press Enter to continue..." dummy;;
            0) echo "Exiting..."; exit 0;;
            *) echo "Invalid option";;
        esac
    done
}

# Start
main_menu