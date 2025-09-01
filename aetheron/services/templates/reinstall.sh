#!/bin/bash
# reinstall.sh - Universeller Techniker  
# Version: 1.00.00

# Load common functions
source $(dirname "$0")/../../scripts/common.sh

SERVICE=$(get_service_name)

log_message "=== 🔧 Techniker beginnt $SERVICE Reinstallation ==="

# 1. Deinstallation mit Datenerhalt
log_message "Phase 1: Deinstallation..."
bash "$(dirname "$0")/uninstall.sh"

# 2. Neuinstallation
log_message "Phase 2: Neuinstallation..."
bash "$(dirname "$0")/install.sh"

log_message "✅ $SERVICE erfolgreich reinstalliert"