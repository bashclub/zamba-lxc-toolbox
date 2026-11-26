#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

set -euo pipefail

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

admin_token=$(openssl rand -base64 48)

inst_postgresql 

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq nginx git ssl-cert curl jq zstd

systemctl enable --now postgresql

# vaultwarden-update: installs and updates vaultwarden from the official image
# vaultwarden/server:alpine. The image is pulled straight from the registry and
# every blob is checked against its SHA-256 digest before anything is unpacked.
# The script lives outside of /var/lib/vaultwarden, which the service can write to.
cat << 'EOF' > /usr/local/sbin/vaultwarden-update
#!/bin/bash
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

IMAGE=${VW_IMAGE:-vaultwarden/server}
TAG=${VW_TAG:-alpine}
BIN=${VW_BIN:-/opt/vaultwarden/vaultwarden}
WEB=${VW_WEB:-/var/lib/vaultwarden/web-vault}
STATE=${VW_STATE:-/var/lib/vaultwarden-update}
HEALTH_URL=${VW_HEALTH_URL:-http://127.0.0.1:8000/alive}
SERVICE=vaultwarden.service
REGISTRY=https://registry-1.docker.io

log() { echo "vaultwarden-update: $*"; logger -t vaultwarden-update -- "$*" 2>/dev/null || true; }
die() { log "ERROR: $*"; exit 1; }

force=0
[ "${1:-}" = "--force" ] && force=1

mkdir -p "$STATE"
chmod 700 "$STATE"
exec 9> "$STATE/lock"
flock -n 9 || { log "already running"; exit 0; }

case "$(uname -m)" in
  x86_64)  arch=amd64 ;;
  aarch64) arch=arm64 ;;
  *) die "unsupported architecture $(uname -m)" ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

token=$(curl -fsS --max-time 30 "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${IMAGE}:pull" | jq -er .token) \
  || die "no registry token"

fetch() {
  curl -fsSL --retry 3 --max-time 600 -H "Authorization: Bearer ${token}" "$@"
}

# download a blob or manifest by digest and verify it
fetch_verified() {
  local digest=$1 out=$2; shift 2
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || die "invalid digest '$digest'"
  fetch "$@" -o "$out" || die "download of $digest failed"
  echo "${digest#sha256:}  $out" | sha256sum -c --quiet - || die "checksum mismatch for $digest"
}

accept_index='Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
accept_manifest='Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'

fetch -H "$accept_index" "$REGISTRY/v2/$IMAGE/manifests/$TAG" -o "$work/index.json" || die "no image index for $IMAGE:$TAG"
digest=$(jq -r --arg a "$arch" '[.manifests[] | select(.platform.os == "linux" and .platform.architecture == $a)][0].digest // empty' "$work/index.json")
[ -n "$digest" ] || die "no linux/$arch image in $IMAGE:$TAG"

if [ "$force" -eq 0 ] && [ -x "$BIN" ] && [ "$(cat "$STATE/digest" 2>/dev/null)" = "$digest" ]; then
  exit 0
fi
# an image that was rolled back is not tried again until a newer one appears
if [ "$force" -eq 0 ] && [ "$(cat "$STATE/failed" 2>/dev/null)" = "$digest" ]; then
  log "skipping $digest, it failed before (use --force to retry)"
  exit 0
fi
log "new image $IMAGE:$TAG ($digest)"

fetch_verified "$digest" "$work/manifest.json" -H "$accept_manifest" "$REGISTRY/v2/$IMAGE/manifests/$digest"

mkdir "$work/rootfs"
n=0
for layer in $(jq -r '.layers[].digest' "$work/manifest.json"); do
  n=$((n + 1))
  fetch_verified "$layer" "$work/layer" "$REGISTRY/v2/$IMAGE/blobs/$layer"
  # only take the binary and the web vault from the image
  tar -tf "$work/layer" | grep -E '^(\./)?(vaultwarden|web-vault(/.*)?)$' > "$work/members" || true
  if [ -s "$work/members" ]; then
    tar -xf "$work/layer" -C "$work/rootfs" --no-same-owner --no-recursion -T "$work/members"
  fi
  rm -f "$work/layer"
done
[ "$n" -gt 0 ] || die "image has no layers"

new_bin="$work/rootfs/vaultwarden"
new_web="$work/rootfs/web-vault"
[ -f "$new_bin" ] && [ -f "$new_web/index.html" ] || die "image does not contain vaultwarden and web-vault"
new_version=$("$new_bin" --version 2>/dev/null | head -n1) || die "new binary does not run"
old_version=$("$BIN" --version 2>/dev/null | head -n1 || true)
old_version=${old_version:-none}

mkdir -p "$(dirname "$BIN")" "$(dirname "$WEB")"
install -o root -g root -m 0755 "$new_bin" "$BIN.new"
rm -rf "$WEB.new"
cp -a "$new_web" "$WEB.new"
chown -R root:root "$WEB.new"
chmod -R u=rwX,go=rX "$WEB.new"

have_unit=0
systemctl cat "$SERVICE" > /dev/null 2>&1 && have_unit=1
was_active=0
[ "$have_unit" -eq 1 ] && systemctl is-active --quiet "$SERVICE" && was_active=1
[ "$was_active" -eq 1 ] && systemctl stop "$SERVICE"

rm -rf "$BIN.old" "$WEB.old"
[ -e "$BIN" ] && mv "$BIN" "$BIN.old"
[ -e "$WEB" ] && mv "$WEB" "$WEB.old"
mv "$BIN.new" "$BIN"
mv "$WEB.new" "$WEB"

if [ "$was_active" -eq 1 ]; then
  systemctl start "$SERVICE" || true
  ok=0
  for _ in $(seq 1 30); do
    if curl -fsS --max-time 2 "$HEALTH_URL" > /dev/null 2>&1; then ok=1; break; fi
    sleep 1
  done
  if [ "$ok" -ne 1 ]; then
    log "ERROR: $new_version does not answer on $HEALTH_URL, rolling back to $old_version"
    systemctl stop "$SERVICE" || true
    if [ -e "$BIN.old" ]; then rm -f "$BIN"; mv "$BIN.old" "$BIN"; fi
    if [ -e "$WEB.old" ]; then rm -rf "$WEB"; mv "$WEB.old" "$WEB"; fi
    systemctl start "$SERVICE" || true
    echo "$digest" > "$STATE/failed"
    exit 1
  fi
fi

echo "$digest" > "$STATE/digest"
rm -f "$STATE/failed"
log "updated from $old_version to $new_version"
EOF
chmod 0755 /usr/local/sbin/vaultwarden-update

mkdir -p /opt/vaultwarden
mkdir -p /var/lib/vaultwarden/data
useradd vaultwarden
chown -R vaultwarden:vaultwarden /var/lib/vaultwarden
/usr/local/sbin/vaultwarden-update

su - postgres <<EOF
psql -c "CREATE USER ${VAULTWARDEN_DB_USR} WITH PASSWORD '${VAULTWARDEN_DB_PWD}';"
psql -c "CREATE DATABASE ${VAULTWARDEN_DB_NAME} ENCODING UTF8 TEMPLATE template0 OWNER ${VAULTWARDEN_DB_USR};"
echo "Postgres User ${VAULTWARDEN_DB_USR} and database ${VAULTWARDEN_DB_NAME} created."
EOF

cat << EOF > /var/lib/vaultwarden/.env
DATABASE_URL=postgresql://vaultwarden:${VAULTWARDEN_DB_PWD}@localhost:5432/vaultwarden
DOMAIN=https://${LXC_HOSTNAME}.${LXC_DOMAIN}
ORG_CREATION_USERS=admin@$LXC_DOMAIN
# Use `openssl rand -base64 48` to generate
ADMIN_TOKEN=$admin_token
# Uncomment this once vaults restored
SIGNUPS_ALLOWED=$VW_SIGNUPS_ALLOWED
SMTP_HOST=$VW_SMTP_HOST
SMTP_FROM=$VW_SMTP_FROM
SMTP_FROM_NAME="$VW_SMTP_FROM_NAME"
SMTP_PORT=$VW_SMTP_PORT          # Ports 587 (submission) and 25 (smtp) are standard without encryption and with encryption via STARTTLS (Explicit TLS). Port 465 is outdated and us>
SMTP_SSL=$VW_SMTP_SSL          # (Explicit) - This variable by default configures Explicit STARTTLS, it will upgrade an insecure connection to a secure one. Unless SMTP_EXPLICIT_>
SMTP_EXPLICIT_TLS=$VW_SMTP_EXPLICIT_TLS # (Implicit) - N.B. This variable configures Implicit TLS. It's currently mislabelled (see bug #851) - SMTP_SSL Needs to be set to true for this o>
SMTP_USERNAME=$VW_SMTP_USERNAME
SMTP_PASSWORD=$VW_SMTP_PASSWORD
SMTP_TIMEOUT=15
EOF

cat << EOF > /etc/systemd/system/vaultwarden.service
[Unit]
Description=Bitwarden Server (Rust Edition)
Documentation=https://github.com/dani-garcia/vaultwarden
After=network.target

[Service]
User=vaultwarden
Group=vaultwarden
EnvironmentFile=/var/lib/vaultwarden/.env
ExecStart=/opt/vaultwarden/vaultwarden
LimitNOFILE=1048576
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
WorkingDirectory=/var/lib/vaultwarden
ReadWriteDirectories=/var/lib/vaultwarden
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# Check for a new vaultwarden image after every apt run. The image is only
# downloaded when its digest has changed; a failed check never fails apt.
cat << 'EOF' > /etc/apt/apt.conf.d/80-vaultwarden-apt-hook
DPkg::Post-Invoke {"/usr/local/sbin/vaultwarden-update || true";};
EOF

cat << EOF > /etc/nginx/conf.d/default.conf
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    server_tokens off;

    access_log /var/log/nginx/vaultwarden.access.log;
    error_log /var/log/nginx/vaultwarden.error.log;

    location /.well-known/ {
        root /var/www/html;
    }

    return 301 https://${LXC_HOSTNAME}.${LXC_DOMAIN}\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name ${LXC_HOSTNAME}.${LXC_DOMAIN};
    
    server_tokens off;
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

    ssl_protocols TLSv1.3 TLSv1.2;
    ssl_ciphers ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:EECDH+AESGCM:EDH+AESGCM;
    ssl_dhparam /etc/nginx/dhparam.pem;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 180m;

    ssl_stapling on;
    ssl_stapling_verify on;

    resolver 1.1.1.1 1.0.0.1;

    add_header Strict-Transport-Security "max-age=31536000" always;

    access_log /var/log/nginx/vaultwarden.access.log;
    error_log  /var/log/nginx/vaultwarden.error.log;

    client_max_body_size 50M;

    location / {
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:8000;
        proxy_read_timeout 90;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

EOF

generate_dhparam

unlink /etc/nginx/sites-enabled/default

systemctl daemon-reload
systemctl enable --now vaultwarden
systemctl restart nginx
