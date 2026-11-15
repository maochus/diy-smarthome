#!/bin/bash
# One-step installer: Immich photo backup (lite, no AI) + shared folder (Samba)
# Usage:  curl -sL s.mwxw.com/home | sudo bash
# Messages are in English on purpose: the Linux text console cannot show Chinese.

set -u
BASE=/opt/homeserver/immich
PHOTOS=/srv/photos
SHARE=/srv/share
TZ_NAME=Asia/Shanghai

# Mirrors that work from mainland China. Tried in order; first one that works wins.
HUB_MIRRORS="docker.1ms.run docker.m.daocloud.io docker.xuanyuan.me hub.rat.dev dockerproxy.net"
GHCR_MIRRORS="ghcr.nju.edu.cn ghcr.1ms.run ghcr.m.daocloud.io"

IMG_SERVER=ghcr.io/immich-app/immich-server:v3
IMG_DB=ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
IMG_REDIS=docker.io/valkey/valkey:9

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

[ "$(id -u)" = 0 ] || die "Please run with sudo:  curl -sL s.mwxw.com/home | sudo bash"
command -v apt-get >/dev/null || die "This script is for Ubuntu / Debian only."
USER_NAME=${SUDO_USER:-}
[ -n "$USER_NAME" ] && [ "$USER_NAME" != root ] || die "Please run it from your normal login user with sudo."

# ---------------------------------------------------------------- 0. Ask for the share password first
say "Shared folder password"
echo "Your shared folder will use the user name:  $USER_NAME"
echo "Type a password for it (tip: use the same one as your login). Nothing shows while typing."
while :; do
  read -r -s -p "Password: " P1 </dev/tty; echo
  read -r -s -p "Again:    " P2 </dev/tty; echo
  [ -n "$P1" ] && [ "$P1" = "$P2" ] && break
  warn "The two passwords are empty or different, please try again."
done

# ---------------------------------------------------------------- 1. Packages
say "Step 1/4  Installing Docker and the shared folder service"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q || die "apt update failed. Check the network and try again."
PKGS="samba"
command -v docker >/dev/null && docker compose version >/dev/null 2>&1 || PKGS="$PKGS docker.io docker-compose-v2"
apt-get install -y -q $PKGS || die "Package install failed."
apt-get install -y -q wsdd >/dev/null 2>&1   # lets Windows see this computer under "Network"; optional
systemctl enable --now docker >/dev/null 2>&1
usermod -aG docker "$USER_NAME"
timedatectl set-timezone "$TZ_NAME" 2>/dev/null

# ---------------------------------------------------------------- 2. Shared folder
say "Step 2/4  Setting up the shared folder"
mkdir -p "$SHARE"
chown "$USER_NAME:$USER_NAME" "$SHARE"
if ! grep -q '^\[share\]' /etc/samba/smb.conf; then
  cat >> /etc/samba/smb.conf <<EOF

[share]
   path = $SHARE
   browseable = yes
   read only = no
   valid users = $USER_NAME
   force user = $USER_NAME
   create mask = 0664
   directory mask = 0775
EOF
fi
printf '%s\n%s\n' "$P1" "$P1" | smbpasswd -s -a "$USER_NAME" >/dev/null || die "Could not set the share password."
unset P1 P2
systemctl restart smbd
systemctl enable --now wsdd >/dev/null 2>&1

# ---------------------------------------------------------------- 3. Immich images
say "Step 3/4  Downloading Immich (about 600 MB, please wait)"
promo
HUB_MIRRORS=$(rank_mirrors $HUB_MIRRORS);   [ -n "$HUB_MIRRORS" ]  || HUB_MIRRORS="docker.1ms.run"
GHCR_MIRRORS=$(rank_mirrors $GHCR_MIRRORS); [ -n "$GHCR_MIRRORS" ] || GHCR_MIRRORS="ghcr.nju.edu.cn"
echo "Mirror order: $GHCR_MIRRORS| $HUB_MIRRORS"
pull_via() {   # pull_via <image> <registry-host-to-strip> <mirror list>
  local img=$1 reg=$2 mirrors=$3 path m round
  if docker image inspect "$img" >/dev/null 2>&1; then echo "$img already downloaded."; return 0; fi
  path=${img#"$reg"/}
  # Finished layers are kept, so switching mirror after a stall loses almost nothing.
  for round in 1 2 3; do
    for m in $mirrors; do
      echo "Trying mirror $m (round $round) ..."
      if timeout 300 docker pull "$m/$path"; then
        docker tag "$m/$path" "$img" && docker rmi "$m/$path" >/dev/null 2>&1
        return 0
      fi
      warn "Mirror $m is slow or not working, switching to the next one."
    done
  done
  echo "Trying the original address ..."
  timeout 600 docker pull "$img"
}
pull_via "$IMG_SERVER" ghcr.io   "$GHCR_MIRRORS" || die "Could not download Immich. Run the same command again later."
pull_via "$IMG_DB"     ghcr.io   "$GHCR_MIRRORS" || die "Could not download the database. Run the same command again later."
pull_via "$IMG_REDIS"  docker.io "$HUB_MIRRORS"  || die "Could not download Redis. Run the same command again later."

# ---------------------------------------------------------------- 4. Start Immich
say "Step 4/4  Starting Immich"
mkdir -p "$BASE" "$PHOTOS"
if [ ! -f "$BASE/.env" ]; then
  cat > "$BASE/.env" <<EOF
UPLOAD_LOCATION=$PHOTOS
DB_DATA_LOCATION=$BASE/postgres
TZ=$TZ_NAME
DB_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
# Lite mode: no face recognition / smart search, so it runs well on old computers.
IMMICH_MACHINE_LEARNING_ENABLED=false
EOF
  chmod 600 "$BASE/.env"
fi
cat > "$BASE/docker-compose.yml" <<EOF
name: immich
services:
  immich-server:
    container_name: immich_server
    image: $IMG_SERVER
    volumes:
      - \${UPLOAD_LOCATION}:/data
      - /etc/localtime:/etc/localtime:ro
    env_file: .env
    ports:
      - '2283:2283'
    depends_on: [redis, database]
    restart: always

  redis:
    container_name: immich_redis
    image: $IMG_REDIS
    restart: always

  database:
    container_name: immich_postgres
    image: $IMG_DB
    environment:
      POSTGRES_PASSWORD: \${DB_PASSWORD}
      POSTGRES_USER: \${DB_USERNAME}
      POSTGRES_DB: \${DB_DATABASE_NAME}
      POSTGRES_INITDB_ARGS: '--data-checksums'
    volumes:
      - \${DB_DATA_LOCATION}:/var/lib/postgresql/data
    shm_size: 128mb
    restart: always
EOF
docker compose --project-directory "$BASE" up -d || die "Immich failed to start."

echo "Waiting for Immich to finish its first start (about 1 minute) ..."
for i in $(seq 1 60); do
  curl -s -o /dev/null --max-time 3 "http://127.0.0.1:2283/api/server/ping" && break
  printf '.'; sleep 5
done
echo

IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="src"){print $(i+1); exit}}')
[ -n "$IP" ] || IP=$(hostname -I | awk '{print $1}')

cat <<EOF

  ==========================================================
    All done!

    Photos (Immich) :  http://$IP:2283
        Phone app: install "Immich", server address is the line above.

    Shared folder   :  \\\\$IP\\share
        User name: $USER_NAME   Password: the one you just typed
        Windows: type the line above into the File Explorer address bar.
        TV / phone players: add an SMB server with this IP.

    More videos & help:  mwxw.com
  ==========================================================

EOF
