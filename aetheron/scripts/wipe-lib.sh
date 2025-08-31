#!/bin/bash
# wipe-lib.sh - Centralized wipe helpers for Aetheron
# Version: 1.00.00

set -euo pipefail

BASE_DIR="/home/khryon/aetheron"
SERVICES_DIR="$BASE_DIR/services"
BACKUP_ROOT="$BASE_DIR/backups"
SCRIPTS_DIR="$BASE_DIR/scripts"

# Common helpers (log_message, etc.)
source "$SCRIPTS_DIR/common.sh"

# == intern: util ==
_ts() { date +%Y%m%d-%H%M%S; }

_list_services() {
  # alle Unterordner unter services/, offensichtliche Nicht-Services filtern
  local s
  for s in "$SERVICES_DIR"/*; do
    [[ -d "$s" ]] || continue
    case "$(basename "$s")" in
      templates|lets*|cert-update.sh|cert-update|certs) continue ;;
    esac
    echo "$(basename "$s")"
  done | sort
}

_compose_file_for() {
  local svc="$1"
  echo "$SERVICES_DIR/$svc/docker-compose.yml"
}

_project_name_for() {
  local svc="$1"
  echo "aetheron-$svc"
}

_backup_dir_for() {
  local svc="$1"
  echo "$BACKUP_ROOT/wipe-${svc}-$(_ts)"
}

# Parse host-Volume-Pfade aus docker-compose.yml (links der Doppelpunkte)
# und klassifiziere: "config-like" vs "data-like"
_parse_volumes_host_paths() {
  local compose="$1"
  # einfache YAML-Linienanalyse:  - /host/path:/container/path
  # gibt nur den linken Teil aus
  awk '
    /^\s*-\s*[^#]*:\/\// { next }  # URLs ignorieren
    /^\s*-\s*[^#]*:[^#]*$/ {
      line=$0
      sub(/^\s*-\s*/, "", line)
      split(line, a, ":")
      print a[1]
    }
  ' "$compose"
}

_is_data_path() {
  # Heuristik: alles mit /data, /db, /mysql, /mariadb, /postgres, /var/lib
  local p="$1"
  [[ "$p" =~ /data($|/) || "$p" =~ /(db|mysql|mariadb|postgres)($|/) || "$p" =~ /var/lib/ ]]
}

# == Aktionen ==
stop_service_compose() {
  local svc="$1"
  local compose="$(_compose_file_for "$svc")"
  local proj="$(_project_name_for "$svc")"

  if [[ -f "$compose" ]]; then
    log_message "[wipe:$svc] Stopping containers (compose down, keep volumes)..."
    if [[ -n "${AETHERON_DRYRUN:-}" ]]; then
      log_message "[DRY-RUN] docker compose -f '$compose' -p '$proj' down"
    else
      ( cd "$(dirname "$compose")" && docker compose -f "$compose" -p "$proj" down ) || true
    fi
  else
    log_message "[wipe:$svc] No compose file at $compose"
  fi
}

backup_service_configs() {
  local svc="$1"
  local compose="$(_compose_file_for "$svc")"
  local bdir="$(_backup_dir_for "$svc")"
  local sdir="$SERVICES_DIR/$svc"
  local secrets_dir="/home/khryon/.aetheron/secrets/$svc"

  mkdir -p "$bdir"
  log_message "[wipe:$svc] Backing up configs to $bdir"

  # 1) docker-compose.yml
  if [[ -f "$compose" ]]; then
    cp -a "$compose" "$bdir/"
  fi

  # 2) .env / weitere top-level-Dateien, außer data/
  find "$sdir" -maxdepth 1 -type f -name ".env" -exec cp -a {} "$bdir/" \; 2>/dev/null || true

  # 3) komplette service-Struktur TARen – aber data/ & logs/ ausschließen
  if command -v tar >/dev/null 2>&1; then
    ( cd "$SERVICES_DIR" && tar czf "$bdir/service-tree.tgz" \
        --exclude="$svc/data" \
        --exclude="$svc/*/data" \
        --exclude="$svc/logs" \
        "$svc" )
  fi

  # 4) Secrets sichern
  if [[ -d "$secrets_dir" ]]; then
    mkdir -p "$bdir/secrets"
    cp -a "$secrets_dir" "$bdir/secrets/"
  fi

  log_message "[wipe:$svc] Backup completed"
}

remove_service_configs() {
  local svc="$1"
  local compose="$(_compose_file_for "$svc")"
  local sdir="$SERVICES_DIR/$svc"
  local secrets_dir="/home/khryon/.aetheron/secrets/$svc"

  log_message "[wipe:$svc] Removing configuration files (preserving data)..."

  # 1) Host-Volumes aus compose parsen und configartige Pfade löschen (data-Pfade auslassen)
  if [[ -f "$compose" ]]; then
    while IFS= read -r host; do
      [[ -e "$host" ]] || continue
      if _is_data_path "$host"; then
        log_message "[wipe:$svc] keeping data path: $host"
      else
        if [[ -n "${AETHERON_DRYRUN:-}" ]]; then
          log_message "[DRY-RUN] rm -rf '$host'"
        else
          sudo rm -rf "$host"
          log_message "[wipe:$svc] removed: $host"
        fi
      fi
    done < <(_parse_volumes_host_paths "$compose")
  fi

  # 2) compose & .env entfernen
  if [[ -n "${AETHERON_DRYRUN:-}" ]]; then
    [[ -f "$compose" ]] && log_message "[DRY-RUN] rm -f '$compose'"
    [[ -f "$sdir/.env" ]] && log_message "[DRY-RUN] rm -f '$sdir/.env'"
  else
    [[ -f "$compose" ]] && rm -f "$compose"
    [[ -f "$sdir/.env" ]] && rm -f "$sdir/.env"
  fi

  # 3) typische config-Verzeichnisse im Service-Ordner (conf/, config/) löschen, data/ NICHT
  for d in conf config etc; do
    if [[ -d "$sdir/$d" ]]; then
      if [[ -n "${AETHERON_DRYRUN:-}" ]]; then
        log_message "[DRY-RUN] rm -rf '$sdir/$d'"
      else
        rm -rf "$sdir/$d"
        log_message "[wipe:$svc] removed: $sdir/$d"
      fi
    fi
  done

  # 4) Secrets entfernen
  if [[ -d "$secrets_dir" ]]; then
    if [[ -n "${AETHERON_DRYRUN:-}" ]]; then
      log_message "[DRY-RUN] rm -rf '$secrets_dir'"
    else
      rm -rf "$secrets_dir"
      log_message "[wipe:$svc] removed secrets"
    fi
  fi

  log_message "[wipe:$svc] Configuration removal done"
}

wipe_service() {
  local svc="$1"
  log_message "---- WIPING service: $svc ----"
  stop_service_compose "$svc"
  backup_service_configs "$svc"
  remove_service_configs "$svc"
  log_message "---- DONE: $svc (data preserved) ----"
}

wipe_all_services() {
  local svc
  for svc in $(_list_services); do
    wipe_service "$svc"
  done
}

# ===== Menü für server-setup.sh =====
run_wipe_menu() {
  while true; do
    echo ""
    echo "==== WIPE MENU (configs only; data preserved) ===="
    echo "A) ALL services"
    local i=1
    mapfile -t SVC_ARR < <(_list_services)
    for s in "${SVC_ARR[@]}"; do
      printf "%2d) %s\n" "$i" "$s"
      ((i++))
    done
    echo " 0) Back"
    echo "-----------------------------------------------"
    read -rp "Select: " sel

    if [[ "$sel" == "A" || "$sel" == "a" ]]; then
      wipe_all_services
    elif [[ "$sel" == "0" ]]; then
      return 0
    elif [[ "$sel" =~ ^[0-9]+$ && "$sel" -ge 1 && "$sel" -le "${#SVC_ARR[@]}" ]]; then
      local svc="${SVC_ARR[$((sel-1))]}"
      wipe_service "$svc"
    else
      echo "Invalid choice."
    fi
  done
}

