#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

admin_token=$(openssl rand -base64 48)

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq postgresql nginx git ssl-cert

systemctl enable --now postgresql

wget https://raw.githubusercontent.com/jjlin/docker-image-extract/main/docker-image-extract
chmod +x docker-image-extract
./docker-image-extract vaultwarden/server:alpine
mkdir -p /opt/vaultwarden
mkdir -p /var/lib/vaultwarden/data
useradd vaultwarden
chown -R vaultwarden:vaultwarden /var/lib/vaultwarden
mv output/vaultwarden /opt/vaultwarden
mv output/web-vault /var/lib/vaultwarden/
rm -Rf output
rm -Rf docker-image-extract

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

cat << EOF > /etc/apt/apt.conf.d/80-vaultwarden-apt-hook
DPkg::Post-Invoke {"/var/lib/vaultwarden/update.sh";};
EOF

cat << EOF > /var/lib/vaultwarden/update.sh
PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"
wget https://raw.githubusercontent.com/jjlin/docker-image-extract/main/docker-image-extract
chmod +x docker-image-extract
./docker-image-extract vaultwarden/server:alpine
mv output/vaultwarden /opt/vaultwarden
systemctl stop vaultwarden.service
cp -rlf output/web-vault /var/lib/vaultwarden/
rm -Rf output
rm -Rf docker-image-extract
systemctl start vaultwarden.service
EOF

chmod +x /etc/apt/apt.conf.d/80-vaultwarden-apt-hook
chmod +x /var/lib/vaultwarden/update.sh

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
    }
}

EOF

generate_dhparam

unlink /etc/nginx/sites-enabled/default

systemctl daemon-reload
systemctl enable --now vaultwarden
systemctl restart nginx
