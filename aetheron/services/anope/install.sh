#!/usr/bin/env bash
# install.sh for Anope IRC Services (Docker build + compose + link to UnrealIRCd)
# Version: 0.09.02  # DEV

set -euo pipefail

VERSION="0.09.02"
SERVICE="anope"
SERVICE_USER="ircd"
SERVICE_GROUP="ircd"

BASE_DIR="$HOME/aetheron"
SVC_DIR="$BASE_DIR/services/$SERVICE"
COMMON="$BASE_DIR/scripts/common.sh"

# Load shared helpers
source "$COMMON"

# --------------------------------------------------------------------
# Paths / constants (some are set later after user exists)
# --------------------------------------------------------------------
AETHERON_DATA_ROOT="${AETHERON_DATA_ROOT:-/var/lib/aetheron}"
DATA_DIR="$AETHERON_DATA_ROOT/$SERVICE"
CONF_DIR="$DATA_DIR/conf"
DATA_SUB="$DATA_DIR/data"
LOG_DIR="$DATA_DIR/logs"

UNREAL_SVC_DIR="$BASE_DIR/services/unrealircd"
UNREAL_CONT=""  # will be resolved dynamically

resolve_unreal_container() {
  # 1) Bevorzugte Kandidaten (häufige Namen)
  local candidates=("aetheron-unrealircd" "unrealircd" "unrealircd-1")
  local name
  for name in "${candidates[@]}"; do
    if docker ps --format '{{.Names}}' | grep -qx "$name"; then
      UNREAL_CONT="$name"
      log_message "Detected UnrealIRCd container: $UNREAL_CONT"
      return 0
    fi
  done
  # 2) Fallback: per Image-Erkennung
  local byimg
  byimg="$(docker ps --format '{{.Names}} {{.Image}}' | awk '/unrealircd\/unrealircd/ {print $1; exit}')"
  if [[ -n "$byimg" ]]; then
    UNREAL_CONT="$byimg"
    log_message "Detected UnrealIRCd by image: $UNREAL_CONT"
    return 0
  fi
  return 1
}

UNREAL_CONF_DIR=""  # will be set after ensure_ircd_user()

COMPOSE_FILE="$SVC_DIR/docker-compose.yml"
DOCKERFILE="$SVC_DIR/Dockerfile"
ENVFILE="$SVC_DIR/.env"

NET_NAME="aetheron_net"

# --------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------
die(){ echo "ERROR: $*" >&2; exit 1; }
ask_default(){ local p="$1" d="$2" v; read -r -p "$p [$d]: " v; echo "${v:-$d}"; }
user_exists(){ id "$1" >/dev/null 2>&1; }

ensure_ircd_user() {
  if user_exists "$SERVICE_USER"; then
    log_message "User '$SERVICE_USER' already exists."
    return 0
  fi
  log_message "Creating service user '$SERVICE_USER'..."
  create_service_user "$SERVICE_USER" "$SERVICE_GROUP" "/home/$SERVICE_USER"
}

set_unreal_conf_dir() {
  # called AFTER ensure_ircd_user
  local ircd_home
  ircd_home="$(getent passwd "$SERVICE_USER" | awk -F: '{print $6}')"
  [[ -z "$ircd_home" ]] && ircd_home="/home/$SERVICE_USER"
  UNREAL_CONF_DIR="$ircd_home/unrealircd/conf"
  log_message "Unreal conf dir resolved: $UNREAL_CONF_DIR"
}

ensure_dirs() {
  sudo mkdir -p "$CONF_DIR" "$DATA_SUB" "$LOG_DIR"
  sudo chown -R "$SERVICE_USER:$SERVICE_GROUP" "$AETHERON_DATA_ROOT" "$DATA_DIR"
  sudo chmod -R 750 "$DATA_DIR"
}

ensure_net() {
  if ! docker network inspect "$NET_NAME" >/dev/null 2>&1; then
    log_message "Creating docker network: $NET_NAME"
    docker network create "$NET_NAME"
  else
    log_message "Docker network already present: $NET_NAME"
  fi
}

connect_unreal_to_net() {
  if docker ps --format '{{.Names}}' | grep -qx "$UNREAL_CONT"; then
    if ! docker inspect -f '{{json .NetworkSettings.Networks}}' "$UNREAL_CONT" | grep -q "\"$NET_NAME\""; then
      log_message "Connecting $UNREAL_CONT to $NET_NAME"
      docker network connect "$NET_NAME" "$UNREAL_CONT" || true
      log_message "Restarting $UNREAL_CONT to apply network change"
      docker restart "$UNREAL_CONT" >/dev/null || true
    else
      log_message "UnrealIRCd already attached to $NET_NAME"
    fi
  else
    log_message "UnrealIRCd container not running (will continue)."
  fi
}

check_unreal_present_or_offer_install() {
  if resolve_unreal_container; then
    log_message "UnrealIRCd container is running: $UNREAL_CONT"
    return 0
  fi

  if [[ -x "$UNREAL_SVC_DIR/install.sh" ]]; then
    echo "⚠️  No running UnrealIRCd found."
    read -r -p "Install UnrealIRCd now? (y/N): " ans; ans="${ans:-N}"
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      log_message "Launching UnrealIRCd installer..."
      "$UNREAL_SVC_DIR/install.sh"
      # nach Installation erneut auflösen + kurz warten
      for _ in $(seq 1 10); do
        sleep 2
        if resolve_unreal_container; then
          log_message "UnrealIRCd is now running: $UNREAL_CONT"
          return 0
        fi
      done
      die "UnrealIRCd installation finished but no running container was detected."
    else
      die "Cannot continue without UnrealIRCd. Aborting Anope installation."
    fi
  else
    die "UnrealIRCd installer not found under $UNREAL_SVC_DIR/"
  fi
}

write_dockerfile() {
  cat > "$DOCKERFILE" <<'EOF'
# Build Anope from source (pinned)
FROM alpine:3.20 AS build
ARG ANOPE_VERSION=2.0.14
RUN apk add --no-cache build-base autoconf automake libtool openssl-dev pcre2-dev git zlib-dev curl
WORKDIR /src
RUN curl -fsSL -o anope.tar.gz https://github.com/anope/anope/archive/refs/tags/${ANOPE_VERSION}.tar.gz \
 && tar xzf anope.tar.gz && mv anope-${ANOPE_VERSION} anope
WORKDIR /src/anope
RUN ./configure --prefix=/opt/anope --enable-extras \
 && make -j"$(nproc)" \
 && make install

FROM alpine:3.20
RUN addgroup -S ircd && adduser -S -G ircd -H -s /bin/sh ircd
RUN apk add --no-cache openssl pcre2 zlib tzdata
COPY --from=build /opt/anope /opt/anope
USER ircd:ircd
WORKDIR /opt/anope
ENTRYPOINT ["/opt/anope/bin/services", "-nofork"]
EOF
  log_message "Dockerfile written: $DOCKERFILE"
}

write_compose() {
  cat > "$COMPOSE_FILE" <<EOF
services:
  anope:
    build:
      context: "$SVC_DIR"
      dockerfile: "$DOCKERFILE"
      args:
        ANOPE_VERSION: "2.0.14"
    container_name: aetheron-anope
    user: "\${UID}:\${GID}"
    environment:
      - TZ=Europe/Berlin
    volumes:
      - $CONF_DIR:/opt/anope/conf
      - $DATA_SUB:/opt/anope/data
      - $LOG_DIR:/opt/anope/logs
    networks:
      - $NET_NAME
    restart: unless-stopped

networks:
  $NET_NAME:
    external: true
EOF
  log_message "Compose written: $COMPOSE_FILE"
}

ensure_env() {
  local uid gid
  uid=$(id -u "$SERVICE_USER")
  gid=$(id -g "$SERVICE_GROUP")
  cat > "$ENVFILE" <<EOF
UID=$uid
GID=$gid
EOF
}

append_unreal_link_if_missing() {
  local services_host="$1" services_pass="$2" uplink_port="$3"

  [[ -z "$UNREAL_CONF_DIR" ]] && die "UNREAL_CONF_DIR not set"
  sudo mkdir -p "$UNREAL_CONF_DIR"
  sudo chown -R "$SERVICE_USER:$SERVICE_GROUP" "$UNREAL_CONF_DIR"

  local conf="$UNREAL_CONF_DIR/unrealircd.conf"
  if [[ ! -f "$conf" ]]; then
    log_message "WARN: $conf not found. Skipping link block append."
    return 0
  fi

  if ! sudo grep -q 'link services' "$conf"; then
    log_message "Appending link block to UnrealIRCd config"
    sudo tee -a "$conf" >/dev/null <<EOF

/* ---- Aetheron: link to Anope services ---- */
link services {
    username *;
    hostname $services_host;
    bind-ip *;
    port $uplink_port;
    password connect "$services_pass";
    password receive "$services_pass";
    class servers;
    options { ssl; };
};
EOF
    if docker ps --format '{{.Names}}' | grep -qx "$UNREAL_CONT"; then
      log_message "Restarting $UNREAL_CONT to apply link config"
      docker restart "$UNREAL_CONT" >/dev/null || true
    fi
  else
    log_message "UnrealIRCd link block already present"
  fi
}

generate_services_conf() {
  local netname="$1" services_name="$2" services_desc="$3" uplink_host="$4" uplink_port="$5" uplink_pass="$6"
  sudo -u "$SERVICE_USER" tee "$CONF_DIR/services.conf" >/dev/null <<EOF
# --- Minimal Anope configuration (generated) ---
# https://docs.anope.org/2.0/
services     {
    nick     "$services_name";
    user     "services";
    host     "$netname";
    gecos    "$services_desc";
    modes    "+o";
}

uplink {
    host     "$uplink_host";
    port     $uplink_port;
    password "$uplink_pass";
}

serverinfo {
    name     "$netname";
    desc     "$services_desc";
    numeric  0;
}

module { name = "enc_ssl" }
module { name = "cs_core" }
module { name = "ns_core" }
module { name = "os_core" }
module { name = "hs_core" }
module { name = "bs_core" }

database {
    file  "anope.db";
    save  10m;
    backup = yes;
}
EOF
  log_message "services.conf written"
}

start_compose() {
  export UID=$(id -u "$SERVICE_USER")
  export GID=$(id -g "$SERVICE_GROUP")

  ( cd "$SVC_DIR" && docker compose -f "$COMPOSE_FILE" build --pull )
  ( cd "$SVC_DIR" && docker compose -f "$COMPOSE_FILE" up -d )
  log_message "Anope container started"
}

wait_for_anope() {
  echo -n "Waiting for Anope to connect to Unreal"
  for _ in $(seq 1 30); do
    if docker logs aetheron-anope 2>&1 | grep -qi "Successfully connected to uplink"; then
      echo; echo "✅ Anope connected to Unreal uplink."
      return 0
    fi
    echo -n "."
    sleep 2
  done
  echo
  echo "⚠️  Anope did not confirm uplink within timeout. Check logs:"
  echo "    docker logs aetheron-anope | tail -n 200"
  return 0
}

# --------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------
log_message "=== Starting Anope Installation ==="

check_firewall
ensure_ircd_user           # <-- user is created here
set_unreal_conf_dir        # <-- only now we resolve $UNREAL_CONF_DIR

ensure_dirs
setup_log_rotation "$SERVICE" "$LOG_DIR" || true

check_unreal_present_or_offer_install
ensure_net
connect_unreal_to_net

echo "=== Anope basic configuration ==="
NETWORK_NAME=$(ask_default "IRC network name (for serverinfo.name)" "AetheronIRC")
SERVICES_NICK=$(ask_default "Services nick" "NickServ")
SERVICES_DESC=$(ask_default "Services description" "Aetheron IRC Services")
DEFAULT_UPLINK_HOST="$UNREAL_CONT"
UPLINK_HOST=$(ask_default "Uplink host (Unreal container name or host/IP)" "$DEFAULT_UPLINK_HOST")
UPLINK_PORT=$(ask_default "Uplink port" "7000")
UPLINK_PASS=$(ask_default "Shared password for link" "$(generate_strong_password)")

write_dockerfile
write_compose
ensure_env
generate_services_conf "$NETWORK_NAME" "$SERVICES_NICK" "$SERVICES_DESC" "$UPLINK_HOST" "$UPLINK_PORT" "$UPLINK_PASS"

append_unreal_link_if_missing "$UPLINK_HOST" "$UPLINK_PASS" "$UPLINK_PORT"

start_compose
wait_for_anope

echo
echo "=== DONE ==="
echo "Anope conf    : $CONF_DIR/services.conf"
echo "Anope logs    : docker logs aetheron-anope"
echo "Docker network: $NET_NAME"
echo "Unreal link   : host=$UPLINK_HOST port=$UPLINK_PORT (ssl) password=<hidden>"
echo
exit 0

