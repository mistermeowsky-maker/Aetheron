#!/bin/bash
# actions-lib.sh - Fallback actions for uninstall/reinstall
# Version: 1.00.00

set -euo pipefail

# Variante 1: Einfach, reicht für lokalen Betrieb
BASE_DIR="$HOME/aetheron"

# Variante 2: Robust auch mit sudo (immer Home vom echten User)
# BASE_USER="${SUDO_USER:-$USER}"
# BASE_DIR="$(getent passwd "$BASE_USER" | cut -d: -f6)/aetheron"

SERVICES_DIR="$BASE_DIR/services"
source "$BASE_DIR/scripts/common.sh"

# Compose-Helfer
_compose_file_for() { echo "$SERVICES_DIR/$1/docker-compose.yml"; }
_project_name_for() { echo "aetheron-$1"; }

# --- Fallback: UNINSTALL ---
fallback_uninstall_service() {
  local svc="$1"
  local compose="$(_compose_file_for "$svc")"
  local proj="$(_project_name_for "$svc")"

  log_message "[uninstall:$svc] Fallback uninstall requested"
  if [[ ! -f "$compose" ]]; then
    log_message "[uninstall:$svc] No compose file at $compose -> nothing to stop"
    return 2   # SKIP
  fi

  if [[ -n "${AETHERON_DRYRUN:-}" ]]; then
    log_message "[DRY-RUN][uninstall:$svc] docker compose -f '$compose' -p '$proj' down"
    return 0
  fi

  ( cd "$(dirname "$compose")" && docker compose -f "$compose" -p "$proj" down ) || true
  log_message "[uninstall:$svc] Containers stopped (configs preserved)"
  return 0
}

# --- Fallback: REINSTALL ---
fallback_reinstall_service() {
  local svc="$1"
  local svc_dir="$SERVICES_DIR/$svc"
  local install="$svc_dir/install.sh"

  log_message "[reinstall:$svc] Fallback reinstall requested"
  # 1) Uninstall (fallback)
  if ! fallback_uninstall_service "$svc"; then
    log_message "[reinstall:$svc] fallback_uninstall failed"
    return 1
  fi

  # 2) Install (service script muss existieren)
  if [[ ! -x "$install" ]]; then
    log_message "[reinstall:$svc] install.sh not found: $install"
    return 1
  fi

  if [[ -n "${AETHERON_DRYRUN:-}" ]]; then
    log_message "[DRY-RUN][reinstall:$svc] would run: $install"
    return 0
  fi

  "$install"
  return $?
}

