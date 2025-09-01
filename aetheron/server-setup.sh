#!/bin/bash
# server-setup.sh — Aetheron Orchestrator (portable $HOME version)
# Version: 0.05.00   # DEV phase (0.xx.xx). Central wipe via wipe-lib.

# === IMPORTS (vor set -euo pipefail laden) ===
source "$HOME/aetheron/scripts/common.sh"
source "$HOME/aetheron/scripts/wipe-lib.sh"
source "$HOME/aetheron/scripts/actions-lib.sh" 2>/dev/null || true   # optional, falls vorhanden

set -euo pipefail

# === BASISPFAD / LOGS / ORDER ===
BASE_DIR="$HOME/aetheron"
SERVICES_DIR="$BASE_DIR/services"

ORCH_LOG_DIR="$HOME/.aetheron/logs/_orchestrator"
SUMMARY_LOG="$ORCH_LOG_DIR/summary.log"
ORCH_LOG="$ORCH_LOG_DIR/server-setup.log"

DRYRUN=false
STRICT_MODE=false   # true => bei .order-Abweichungen abbrechen statt auto-fix
ORDER_FILE="$SERVICES_DIR/.order"

mkdir -p "$ORCH_LOG_DIR"

ts(){ date '+%Y-%m-%d %H:%M:%S'; }
log(){ echo "[$(ts)] $*" | tee -a "$ORCH_LOG"; }
summary_append(){ echo "[$(ts)] $*" | tee -a "$SUMMARY_LOG"; }
show_status(){
  echo "Mode: $([[ "$DRYRUN" == true ]] && echo "DRY-RUN" || echo "NORMAL")  |  Strict: $([[ "$STRICT_MODE" == true ]] && echo "ON" || echo "OFF")"
}
pause(){ read -rp "Weiter mit [Enter] ... " _; }

progress_bar(){
  local steps=${1:-30} delay=${2:-0.03}
  for ((i=1;i<=steps;i++)); do
    printf "\r[%-*s] %3d%%" "$steps" "$(printf '#%.0s' $(seq 1 $i))" $(( i*100/steps ))
    sleep "$delay"
  done
  echo
}

# --------- Preflight ---------
check_space(){
  local path="$1" min_mb="$2"
  local avail
  avail=$(df -Pm "$path" | awk 'NR==2{print $4}')
  if (( avail < min_mb )); then
    echo "WARN: Low disk space on $path (available ${avail}MB, need >= ${min_mb}MB)." >&2
  fi
}

preflight_checks(){
  echo "=== Preflight checks ==="

  # sudo
  if ! sudo -v >/dev/null 2>&1; then
    echo "ERROR: sudo not available / password required." >&2
    exit 1
  fi

  # Internet (DNS + HTTPS)
  if ! getent hosts archlinux.org >/dev/null; then
    echo "ERROR: DNS seems down (archlinux.org not resolvable)." >&2
    exit 1
  fi
  if ! curl -fsS --max-time 5 https://www.google.com >/dev/null; then
    echo "ERROR: No outbound HTTPS connectivity." >&2
    exit 1
  fi

  # Zeit/Sync (optional)
  if command -v timedatectl >/dev/null 2>&1; then
    if ! timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -qi yes; then
      echo "WARN: NTP not synchronized. TLS/LetsEncrypt may fail." >&2
    fi
  fi

  # Diskplatz (rudimentär): $HOME und /srv
  check_space "$HOME" 1024  # 1GB
  check_space "/srv"  1024  # nur Hinweis

  echo "Preflight OK."
  echo
}

# --------- Order helpers ---------
init_order_file_if_missing(){
  if [[ ! -f "$ORDER_FILE" ]]; then
    log "No .order file found. Creating initial order from existing service directories..."
    find "$SERVICES_DIR" -maxdepth 1 -mindepth 1 -type d -printf "%f\n" \
      | grep -viE 'templates|^\.|cert|letsencrypt' | sort > "$ORDER_FILE"
    log "Created $ORDER_FILE"
  fi
}

read_services_order(){ mapfile -t SERVICES_ORDER < <(grep -v '^\s*$' "$ORDER_FILE" | sed 's/\r$//'); }
write_services_order(){ printf "%s\n" "${SERVICES_ORDER[@]}" > "$ORDER_FILE"; }

autofix_order_or_abort(){
  local -A seen=()
  local -a current_dirs=() new_order=() missing=() added=()

  mapfile -t current_dirs < <(find "$SERVICES_DIR" -maxdepth 1 -mindepth 1 -type d -printf "%f\n" | sort) || true
  read_services_order

  for s in "${SERVICES_ORDER[@]}"; do
    if [[ -d "$SERVICES_DIR/$s" ]]; then new_order+=("$s"); seen["$s"]=1; else missing+=("$s"); fi
  done
  for d in "${current_dirs[@]}"; do
    if [[ -z "${seen[$d]+x}" ]]; then new_order+=("$d"); added+=("$d"); fi
  done

  local changed=false
  (( ${#missing[@]} > 0 || ${#added[@]} > 0 )) && changed=true

  if $changed; then
    if $STRICT_MODE; then
      echo "ERROR: .order inconsistent."
      (( ${#missing[@]} > 0 )) && echo "Missing (in .order but no dir): ${missing[*]}"
      (( ${#added[@]}   > 0 )) && echo "Extra (dir not in .order): ${added[*]}"
      echo "Strict mode is ON → abort."
      exit 1
    else
      printf "%s\n" "${new_order[@]}" > "$ORDER_FILE"
      (( ${#missing[@]} > 0 )) && log "Auto-fix: removed from .order (no dir): ${missing[*]}"
      (( ${#added[@]}   > 0 )) && log "Auto-fix: added to .order (new dir): ${added[*]}"
    fi
  else
    log "Order OK: .order matches existing service directories."
  fi
}

script_path_for(){ local service="$1"; local action="$2"; echo "$SERVICES_DIR/$service/${action}.sh"; }

# --- DRY-RUN Binder (für Libs) ---
_bind_dryrun(){ if [[ "${DRYRUN:-false}" == "true" ]]; then export AETHERON_DRYRUN=1; else unset AETHERON_DRYRUN; fi; }

# --- Wipe glue (direkt nutzbar, falls benötigt) ---
_run_wipe_single(){ _bind_dryrun; wipe_service "$1"; }
_run_wipe_all(){ _bind_dryrun; wipe_all_services; }

# --------- Run service actions (zentral) ---------
do_action_one(){
  local action="$1"; local service="$2"
  _bind_dryrun

  # --- Wipe: immer zentrale Lib, NIE service/wipe.sh erwarten ---
  if [[ "$action" == "wipe" ]]; then
    log "RUN: $service – wipe (central wipe-lib)"
    if wipe_service "$service"; then
      summary_append "OK: $service (wipe)"; progress_bar; return 0
    else
      summary_append "FAIL: $service (wipe)"; return 1
    fi
  fi

  # --- Uninstall: prefer service/uninstall.sh, sonst Fallback ---
  if [[ "$action" == "uninstall" ]]; then
    local script; script="$(script_path_for "$service" uninstall)"
    if [[ -x "$script" ]]; then
      log "RUN: $service – uninstall.sh"
      [[ "$DRYRUN" == true ]] && { summary_append "DRY-RUN: $service (uninstall)"; progress_bar; return 0; }
      "$script" && { summary_append "OK: $service (uninstall)"; progress_bar; return 0; }
      summary_append "FAIL: $service (uninstall)"; return 1
    else
      log "RUN: $service – uninstall (fallback)"
      if type -t fallback_uninstall_service >/dev/null 2>&1 && fallback_uninstall_service "$service"; then
        summary_append "OK: $service (uninstall-fallback)"; progress_bar; return 0
      else
        summary_append "FAIL: $service (uninstall-fallback)"; return 1
      fi
    fi
  fi

  # --- Reinstall: prefer service/reinstall.sh, sonst Fallback (down + install) ---
  if [[ "$action" == "reinstall" ]]; then
    local script; script="$(script_path_for "$service" reinstall)"
    if [[ -x "$script" ]]; then
      log "RUN: $service – reinstall.sh"
      [[ "$DRYRUN" == true ]] && { summary_append "DRY-RUN: $service (reinstall)"; progress_bar; return 0; }
      "$script" && { summary_append "OK: $service (reinstall)"; progress_bar; return 0; }
      summary_append "FAIL: $service (reinstall)"; return 1
    else
      log "RUN: $service – reinstall (fallback)"
      if type -t fallback_reinstall_service >/dev/null 2>&1 && fallback_reinstall_service "$service"; then
        summary_append "OK: $service (reinstall-fallback)"; progress_bar; return 0
      else
        summary_append "FAIL: $service (reinstall-fallback)"; return 1
      fi
    fi
  fi

  # --- Install: nur via service/install.sh ---
  local script; script="$(script_path_for "$service" install)"
  if [[ ! -f "$script" ]]; then
    log "SKIP: $service – install.sh not found: $script"
    summary_append "SKIP: $service (install) – script missing"
    return 2
  fi
  [[ -x "$script" ]] || chmod +x "$script"
  log "RUN: $service – install"
  if [[ "$DRYRUN" == true ]]; then
    summary_append "DRY-RUN: $service (install)"; progress_bar; return 0
  fi
  "$script" && { summary_append "OK: $service (install)"; progress_bar; return 0; }
  summary_append "FAIL: $service (install)"; return 1
}

do_action_many(){
  local action="$1"; shift; local items=("$@")
  local ok=0 fail=0 skip=0 rc=0
  for svc in "${items[@]}"; do
    do_action_one "$action" "$svc"; rc=$?
    case "$rc" in 0) ((ok++));; 1) ((fail++));; 2) ((skip++));; esac
  done
  log "Summary: OK=$ok FAIL=$fail SKIP=$skip ($action)"
  echo; echo "=== SUMMARY ($action) ==="; echo "OK: $ok"; echo "FAIL: $fail"; echo "SKIP: $skip"
  echo "(Detail: $SUMMARY_LOG)"; echo; pause
}

# --------- Manage services (Add/Remove/Rename/Reorder) ---------
sanitize_name(){ echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g'; }

ensure_templates(){
  local TEMPLATES_DIR="$SERVICES_DIR/templates"
  [[ -d "$TEMPLATES_DIR" ]] || mkdir -p "$TEMPLATES_DIR"
  for f in install.sh reinstall.sh uninstall.sh wipe.sh; do
    [[ -f "$TEMPLATES_DIR/$f" ]] && continue
    cat > "$TEMPLATES_DIR/$f" <<'EOF'
#!/bin/bash
# template
# Version: 0.01.00
SERVICE="$(basename "$(dirname "$0")")"
BASE_DIR="$HOME/aetheron"
source "$BASE_DIR/scripts/common.sh"
log_message "Template script for $SERVICE ($0) — please implement."
exit 0
EOF
    chmod +x "$TEMPLATES_DIR/$f"
  done
}

add_service(){
  ensure_templates
  read -rp "New service name (folder): " raw
  local name; name="$(sanitize_name "$raw")"
  [[ -z "$name" ]] && { echo "Abort."; return; }
  if [[ -d "$SERVICES_DIR/$name" ]]; then echo "Service '$name' exists."; return; fi

  mkdir -p "$SERVICES_DIR/$name/logs"
  for f in install.sh reinstall.sh uninstall.sh wipe.sh; do
    cp -n "$SERVICES_DIR/templates/$f" "$SERVICES_DIR/$name/$f"
    sed -i "s/^# Version: .*/# Version: 0.01.00/" "$SERVICES_DIR/$name/$f"
    chmod +x "$SERVICES_DIR/$name/$f"
  done

  read_services_order; SERVICES_ORDER+=("$name"); write_services_order
  echo "Added service '$name' and appended to .order."
  pause
}

remove_service(){
  read_services_order
  echo "Which service to remove?"
  select svc in "${SERVICES_ORDER[@]}" "Cancel"; do
    (( REPLY == ${#SERVICES_ORDER[@]}+1 )) && return
    (( REPLY < 1 || REPLY > ${#SERVICES_ORDER[@]} )) && { echo "Invalid."; continue; }
    local name="${SERVICES_ORDER[REPLY-1]}"

    read -rp "Create backup before removing? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      local ts="$(date +%Y%m%d-%H%M%S)"
      local bk="$HOME/.aetheron/backups"
      mkdir -p "$bk"
      tar czf "$bk/service-${name}-${ts}.tar.gz" -C "$SERVICES_DIR" "$name"
      echo "Backup: $bk/service-${name}-${ts}.tar.gz"
    fi

    read -rp "Really delete services/$name ? (scripts only, no app data) [type YES]: " conf
    [[ "$conf" == "YES" ]] || { echo "Abort."; return; }
    rm -rf "$SERVICES_DIR/$name"

    local new=(); for x in "${SERVICES_ORDER[@]}"; do [[ "$x" != "$name" ]] && new+=("$x"); done
    SERVICES_ORDER=("${new[@]}"); write_services_order
    echo "Removed '$name' and updated .order."
    pause
    return
  done
}

rename_service(){
  read_services_order
  echo "Which service to rename?"
  select svc in "${SERVICES_ORDER[@]}" "Cancel"; do
    (( REPLY == ${#SERVICES_ORDER[@]}+1 )) && return
    (( REPLY < 1 || REPLY > ${#SERVICES_ORDER[@]} )) && { echo "Invalid."; continue; }
    local old="$svc"
    read -rp "New name for '$old': " raw
    local new; new="$(sanitize_name "$raw")"
    [[ -z "$new" ]] && { echo "Abort."; return; }
    [[ -d "$SERVICES_DIR/$new" ]] && { echo "Target '$new' exists."; return; }

    mv "$SERVICES_DIR/$old" "$SERVICES_DIR/$new"
    for i in "${!SERVICES_ORDER[@]}"; do [[ "${SERVICES_ORDER[$i]}" == "$old" ]] && SERVICES_ORDER[$i]="$new"; done
    write_services_order
    echo "Renamed '$old' -> '$new' and updated .order."
    pause
    return
  done
}

reorder_services(){
  read_services_order
  echo "Current order:"; nl -ba "$ORDER_FILE"; echo
  echo "Commands:  m <name> up|down|top|bottom    |    done"
  while true; do
    read -rp "> " cmd a b
    case "$cmd" in
      m)
        local name="$a" dir="$b" idx=-1 tmp
        for i in "${!SERVICES_ORDER[@]}"; do [[ "${SERVICES_ORDER[$i]}" == "$name" ]] && idx=$i; done
        (( idx == -1 )) && { echo "Unknown '$name'"; continue; }
        case "$dir" in
          up)     (( idx>0 )) && { tmp="${SERVICES_ORDER[idx-1]}"; SERVICES_ORDER[idx-1]="$name"; SERVICES_ORDER[idx]="$tmp"; } ;;
          down)   (( idx<${#SERVICES_ORDER[@]}-1 )) && { tmp="${SERVICES_ORDER[idx+1]}"; SERVICES_ORDER[idx+1]="$name"; SERVICES_ORDER[idx]="$tmp"; } ;;
          top)    SERVICES_ORDER=("$name" "${SERVICES_ORDER[@]/$name}");;
          bottom) SERVICES_ORDER=("${SERVICES_ORDER[@]/$name}"); SERVICES_ORDER+=("$name");;
          *) echo "Use up|down|top|bottom";;
        esac
        write_services_order; nl -ba "$ORDER_FILE"
        ;;
      done) break ;;
      *) echo "Unknown command";;
    esac
  done
}

manage_services_menu(){
  while true; do
    clear
    echo "========= Manage services ========="
    echo "1) Add service"
    echo "2) Remove service"
    echo "3) Rename service"
    echo "4) Reorder services"
    echo "5) Show current order"
    echo "6) Toggle Strict Mode"
    echo "0) Back"
    echo
    read -rp "Select: " c
    case "$c" in
      1) add_service ;;
      2) remove_service ;;
      3) rename_service ;;
      4) reorder_services ;;
      5) echo; nl -ba "$ORDER_FILE"; echo; pause ;;
      6) STRICT_MODE=$([[ "$STRICT_MODE" == true ]] && echo false || echo true) ;;
      0) return ;;
      *) echo "Invalid"; sleep 1 ;;
    esac
  done
}

# --------- Submenu for actions ---------
service_submenu() {
  local action="$1"
  read_services_order
  while true; do
    clear
    echo "============== $action MENU =============="
    echo "Mode: $([[ "$DRYRUN" == true ]] && echo "DRY-RUN" || echo "NORMAL")  |  Strict: $([[ "$STRICT_MODE" == true ]] && echo "ON" || echo "OFF")"
    echo
    echo " 1) All services (per .order / central for wipe)"
    local i=2
    for svc in "${SERVICES_ORDER[@]}"; do printf " %d) %s\n" "$i" "$svc"; ((i++)); done
    echo " 0) Back"
    echo
    read -rp "Select: " choice

    # --- NEU: für wipe immer zentral alles wipen ---
    if [[ "$action" == "wipe" && "$choice" == "1" ]]; then
      log "RUN: Wipe – ALL services (central wipe-lib)"
      _run_wipe_all
      summary_append "OK: wipe (all)"
      progress_bar
      continue
    fi

    if [[ "$choice" == "1" ]]; then
      do_action_many "$action" "${SERVICES_ORDER[@]}"
    elif [[ "$choice" == "0" ]]; then
      return
    else
      local idx=$(( choice - 2 ))
      if (( idx >= 0 && idx < ${#SERVICES_ORDER[@]} )); then
        do_action_many "$action" "${SERVICES_ORDER[$idx]}"
      else
        echo "Invalid option"; sleep 1
      fi
    fi
  done
}

main_menu(){
  preflight_checks
  init_order_file_if_missing
  autofix_order_or_abort
  read_services_order

  while true; do
    clear
    echo "=============================="
    echo "       Aetheron Setup"
    echo "       Version: 0.05.00  (central wipe via wipe-lib)"
    echo "=============================="
    show_status
    echo
    echo "1) Install single service"
    echo "2) Reinstall service(s)"
    echo "3) Uninstall service(s)"
    echo "4) Wipe service(s)"
    echo "5) Test run (Dry-Run) toggle"
    echo "6) Show last summary"
    echo "7) Manage services (Add/Remove/Rename/Reorder/Strict)"
    echo "8) Show current service order (.order)"
    echo "9) Exit"
    echo
    read -rp "Select: " choice

    case "$choice" in
      1) service_submenu "install" ;;
      2) service_submenu "reinstall" ;;
      3) service_submenu "uninstall" ;;
      4) service_submenu "wipe" ;;
      5) DRYRUN=$([[ "$DRYRUN" == true ]] && echo false || echo true) ;;
      6) [[ -f "$SUMMARY_LOG" ]] && { echo; cat "$SUMMARY_LOG"; echo; pause; } || { echo "No summary yet."; sleep 1; } ;;
      7) manage_services_menu ;;
      8) echo; nl -ba "$ORDER_FILE"; echo; pause ;;
      9) echo "Bye."; exit 0 ;;
      *) echo "Invalid option"; sleep 1 ;;
    esac
  done
}

main_menu

