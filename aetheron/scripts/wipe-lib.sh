#!/bin/bash
# wipe-lib.sh — zentrale Wipe-Logik (robust, user cleanup, DRY)
# Version: 0.05.03 (DEV)

# KEIN set -e; Niemals exit in Funktionen!
set +e

# ---- Konfiguration / Mapping -------------------------------------------------

# Datenwurzel (systemkonform). Kann via ENV übersteuert werden.
_data_root() {
  echo "${AETHERON_DATA_ROOT:-/var/lib/aetheron}"
}

# Service→User Mapping (nach Bedarf erweitern)
# Hinweis: unrealircd + anope teilen sich 'ircd'
declare -A SERVICE_USER_MAP=(
  [mariadb]="mariadb"
  [unrealircd]="ircd"
  [anope]="ircd"
  [nextcloud]="nextcloud"
  [postgresql]="postgres"
  [quasselcore]="ircd"      # falls du den auch unter 'ircd' laufen lässt
  [teamspeak]="teamspeak"
  [netdata]="netdata"
  # folgende sind Basis-/Systemdienste → kein eigener Service-User:
  # [mediawiki]=""          # i. d. R. via apache/php-fpm
  # [apache]=""             # Systemdienst; geschützt
  # [docker]=""             # Systemdienst; geschützt
  # [cockpit]=""            # Systemdienst; geschützt
  # [letsencrypt]=""        # Systemdienst; geschützt
  # [vsftpd]=""             # Systemdienst (falls nativ); sonst eigener User, wenn du willst
)

# Dienste, die beim Wipe geschützt sind (nur Container/Daten, kein User/Package)
_is_protected_service() {
  case "$1" in
    apache|docker|cockpit|letsencrypt) return 0 ;;
    *) return 1 ;;
  esac
}

# ---- Utility ----------------------------------------------------------------

_dry_echo() {
  if [[ "${AETHERON_DRYRUN:-}" == "1" ]]; then
    echo "[DRY] $*"
  else
    echo "      $*"
  fi
}

_maybe_run() {
  if [[ "${AETHERON_DRYRUN:-}" == "1" ]]; then
    return 0
  else
    "$@"
  fi
}

# Compose down -v für einen Service, falls docker-compose.yml existiert
_compose_down() {
  local svc="$1"
  local compose="$HOME/aetheron/services/$svc/docker-compose.yml"
  if [[ -f "$compose" ]]; then
    _dry_echo "docker compose -f $compose down -v"
    _maybe_run docker compose -f "$compose" down -v >/dev/null 2>&1
  fi
  return 0
}

# Ermittelt die *aktuelle* Service-Liste = (.order ∪ reale Ordner) – templates/hidden ausgeschlossen
_discover_services() {
  local services_dir="$HOME/aetheron/services"
  local order_file="$services_dir/.order"
  local -A seen=()
  local -a res=()

  # aus .order
  if [[ -f "$order_file" ]]; then
    while IFS= read -r line; do
      line="$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]\+//; s/[[:space:]]\+$//')"
      [[ -z "$line" ]] && continue
      [[ "$line" =~ ^# ]] && continue
      [[ -d "$services_dir/$line" ]] || continue
      [[ "$line" == "templates" ]] && continue
      [[ "$line" == .* ]] && continue
      if [[ -z "${seen[$line]+x}" ]]; then
        res+=("$line"); seen["$line"]=1
      fi
    done < "$order_file"
  fi

  # reale Ordner ergänzen
  while IFS= read -r d; do
    d="$(basename "$d")"
    [[ "$d" == "templates" ]] && continue
    [[ "$d" == .* ]] && continue
    if [[ -z "${seen[$d]+x}" ]]; then
      res+=("$d"); seen["$d"]=1
    fi
  done < <(find "$services_dir" -maxdepth 1 -mindepth 1 -type d | sort)

  printf "%s\n" "${res[@]}"
}

# --- User/Group helpers -------------------------------------------------------

_user_exists()   { id "$1"   >/dev/null 2>&1; }
_group_exists()  { getent group "$1" >/dev/null 2>&1; }

_remove_user_and_home() {
  local user="$1"
  if _user_exists "$user"; then
    _dry_echo "sudo userdel -r $user"
    _maybe_run sudo userdel -r "$user" >/dev/null 2>&1
  fi
}

_remove_group() {
  local grp="$1"
  if _group_exists "$grp"; then
    _dry_echo "sudo groupdel $grp"
    _maybe_run sudo groupdel "$grp" >/dev/null 2>&1
  fi
}

# Prüfen, ob ein User noch von *nicht gewipeten* Services gebraucht wird
# remaining_services = Services, die NICHT in der aktuellen Wipe-Liste sind
_user_needed_by_remaining() {
  local user="$1"; shift
  local -a remaining_services=("$@")
  local s u
  for s in "${remaining_services[@]}"; do
    [[ -z "$s" ]] && continue
    # Key existiert?
    if [[ -v SERVICE_USER_MAP[$s] ]]; then
      u="${SERVICE_USER_MAP[$s]}"
      [[ -z "$u" ]] && continue
      if [[ "$u" == "$user" ]]; then
        return 0  # ja, noch benötigt
      fi
    fi
  done
  return 1  # nein
}

# ---- Wipe Single -------------------------------------------------------------

wipe_service() {
  local svc="$1"
  [[ -z "$svc" ]] && return 0

  echo "[WIPE] $svc"

  # 1) Container/Netze/Volumes via compose
  _compose_down "$svc"

  # 2) Datenverzeichnis entfernen
  local root="$(_data_root)"
  local data_dir="$root/$svc"
  if [[ -d "$data_dir" ]]; then
    _dry_echo "sudo rm -rf $data_dir"
    _maybe_run sudo rm -rf "$data_dir"
    echo "  - removed data dir: $data_dir"
  else
    echo "  - data dir not present: $data_dir"
  fi

  # KEIN exit – nur return
  return 0
}

# ---- Wipe All (inkl. User-Aufräumen) ----------------------------------------

wipe_all_services() {
  # -> Liste aller Services (vereinigt)
  mapfile -t all_services < <(_discover_services)

  if (( ${#all_services[@]} == 0 )); then
    echo "[WIPE] Nothing to wipe (no services found)."
    return 0
  fi

  echo "[WIPE] Services: ${all_services[*]}"

  # 1) zuerst alle Services wipen (Container + Daten)
  local svc
  for svc in "${all_services[@]}"; do
    wipe_service "$svc"
  done

  # 2) User/Groups aufräumen – shared User korrekt behandeln
  #    a) Kandidaten-User aus der Wipe-Liste einsammeln (nur für ungeschützte Dienste)
  declare -A users_to_consider=()
  for svc in "${all_services[@]}"; do
    _is_protected_service "$svc" && continue
    if [[ -v SERVICE_USER_MAP[$svc] ]]; then
      local u="${SERVICE_USER_MAP[$svc]}"
      [[ -z "$u" ]] && continue
      users_to_consider["$u"]=1
    fi
  done

  #    b) remaining_services = Dienste, die NICHT in all_services stehen (also nicht gewipet werden)
  #       (Ermittlung: alle Service-Verzeichnisse minus all_services)
  mapfile -t all_dirs < <(find "$HOME/aetheron/services" -maxdepth 1 -mindepth 1 -type d -printf "%f\n")
  # filter
  declare -a cleaned_all_dirs=()
  for d in "${all_dirs[@]}"; do
    [[ "$d" == "templates" ]] && continue
    [[ "$d" == .* ]] && continue
    cleaned_all_dirs+=("$d")
  done

  # Set-Bildung: remaining = cleaned_all_dirs \ all_services
  declare -A wiped_set=()
  for s in "${all_services[@]}"; do wiped_set["$s"]=1; done

  declare -a remaining_services=()
  for d in "${cleaned_all_dirs[@]}"; do
    if [[ -z "${wiped_set[$d]+x}" ]]; then
      remaining_services+=("$d")
    fi
  done

  #    c) Für jeden Kandidaten-User prüfen, ob er noch von remaining_services genutzt wird
  local user
  for user in "${!users_to_consider[@]}"; do
    if _user_needed_by_remaining "$user" "${remaining_services[@]}"; then
      echo "  - keep user '$user' (still needed by remaining services)"
      continue
    fi
    # sonst löschen (User + Home + ggf. Gruppe gleichen Namens)
    echo "  - remove user '$user' and its home"
    _remove_user_and_home "$user"
    _remove_group "$user"
  done

  echo "[WIPE] All done."
  return 0
}

