#!/bin/bash
# One-step installer: Docker + Home Assistant + ESPHome
# Usage:  curl -sL s.mwxw.com/ha | sudo bash
# Source code: https://github.com/maochus/diy-smarthome
# Messages are in English on purpose: the Linux text console cannot show Chinese.

set -u
BASE=/opt/homeserver
TZ_NAME=Asia/Shanghai

# Docker Hub mirrors that work from mainland China. Tried in order; first one that works wins.
MIRRORS="docker.1ms.run docker.m.daocloud.io docker.xuanyuan.me hub.rat.dev dockerproxy.net docker.1panel.live"
IMAGES="homeassistant/home-assistant:stable esphome/esphome:stable"

# Put the fastest-answering mirrors first. Measured on this computer only; nothing is sent anywhere else.
rank_mirrors() {
  local m t
  for m in "$@"; do
    t=$(curl -s -o /dev/null -w '%{time_total}' --max-time 5 "https://$m/v2/" 2>/dev/null) || t=99
    [ -z "$t" ] && t=99
    echo "$t $m"
  done | sort -n | awk '$1 < 99 {print $2}' | tr '\n' ' '
}

say()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31mXX  %s\033[0m\n\n' "$*"; exit 1; }
promo() {
  printf '\n    While you wait - more DIY smart home videos:\n'
  printf '      Bilibili :  s.mwxw.com/bili\n'
  printf '      YouTube  :  youtube.com/@erictinkers\n'
  printf '      Website  :  mwxw.com\n\n'
}

[ "$(id -u)" = 0 ] || die "Please run with sudo:  curl -sL s.mwxw.com/ha | sudo bash"
command -v apt-get >/dev/null || die "This script is for Ubuntu / Debian only."

# ---------------------------------------------------------------- 1. Docker
say "Step 1/4  Installing Docker"
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
  echo "Docker is already installed, skipping."
else
  # docker.io comes from Ubuntu's own archive, so it uses the same (domestic) mirror as the system.
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q || die "apt update failed. Check the network and try again."
  apt-get install -y -q docker.io docker-compose-v2 || die "Docker install failed."
fi
systemctl enable --now docker >/dev/null 2>&1
[ -n "${SUDO_USER:-}" ] && usermod -aG docker "$SUDO_USER"
timedatectl set-timezone "$TZ_NAME" 2>/dev/null

# ---------------------------------------------------------------- 2. Images
say "Step 2/4  Downloading Home Assistant and ESPHome (about 1 GB, please wait)"
promo
MIRRORS=$(rank_mirrors $MIRRORS)
[ -n "$MIRRORS" ] || MIRRORS="docker.1ms.run"
echo "Mirror order: $MIRRORS"
pull_one() {
  local img=$1 m round
  if docker image inspect "$img" >/dev/null 2>&1; then echo "$img already downloaded."; return 0; fi
  # Finished layers are kept, so switching mirror after a stall loses almost nothing.
  for round in 1 2 3; do
    for m in $MIRRORS; do
      echo "Trying mirror $m (round $round) ..."
      if timeout 300 docker pull "$m/$img"; then
        docker tag "$m/$img" "$img" && docker rmi "$m/$img" >/dev/null 2>&1
        return 0
      fi
      warn "Mirror $m is slow or not working, switching to the next one."
    done
  done
  echo "Trying Docker Hub directly ..."
  timeout 600 docker pull "$img"
}
for img in $IMAGES; do
  pull_one "$img" || die "Could not download $img. Run the same command again later."
done

# ---------------------------------------------------------------- 3. Start
say "Step 3/4  Starting Home Assistant and ESPHome"
mkdir -p "$BASE/homeassistant" "$BASE/esphome"
cat > "$BASE/docker-compose.yml" <<EOF
services:
  homeassistant:
    image: homeassistant/home-assistant:stable
    container_name: homeassistant
    network_mode: host
    privileged: true
    restart: unless-stopped
    environment:
      - TZ=$TZ_NAME
    volumes:
      - $BASE/homeassistant:/config
      - /etc/localtime:/etc/localtime:ro
      - /run/dbus:/run/dbus:ro

  esphome:
    image: esphome/esphome:stable
    container_name: esphome
    network_mode: host
    restart: unless-stopped
    environment:
      - TZ=$TZ_NAME
    volumes:
      - $BASE/esphome:/config
      - /etc/localtime:/etc/localtime:ro
EOF
docker compose -f "$BASE/docker-compose.yml" up -d || die "Containers failed to start."

# ---------------------------------------------------------------- 4. Wait
say "Step 4/4  Waiting for Home Assistant to finish its first start (1-3 minutes)"
IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="src"){print $(i+1); exit}}')
[ -n "$IP" ] || IP=$(hostname -I | awk '{print $1}')
for i in $(seq 1 60); do
  curl -s -o /dev/null --max-time 3 "http://127.0.0.1:8123" && break
  printf '.'; sleep 5
done
echo

cat <<EOF

  ==========================================================
    All done!  Open these on any computer or phone at home:

    Home Assistant :  http://$IP:8123
    ESPHome        :  http://$IP:6052

    More videos & help:  mwxw.com
  ==========================================================

EOF
