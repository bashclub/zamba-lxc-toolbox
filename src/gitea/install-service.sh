#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

wget -q -O - https://nginx.org/keys/nginx_signing.key | apt-key add -
echo "deb http://nginx.org/packages/debian $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list

wget -q -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq postgresql nginx git ssl-cert unzip zip

systemctl enable --now postgresql

su - postgres <<EOF
psql -c "CREATE USER gitea WITH PASSWORD '${GITEA_DB_PWD}';"
psql -c "CREATE DATABASE ${GITEA_DB_NAME} ENCODING UTF8 TEMPLATE template0 OWNER ${GITEA_DB_USR};"
echo "Postgres User ${GITEA_DB_USR} and database ${GITEA_DB_NAME} created."
EOF

adduser  --system  --shell /bin/bash --gecos 'Git Version Control' --group --disabled-password --home /home/git git

curl -s https://api.github.com/repos/go-gitea/gitea/releases/latest | grep browser_download_url | cut -d '"' -f 4 | grep '\linux-amd64$' | wget -O /usr/local/bin/gitea -i -
chmod +x /usr/local/bin/gitea
mkdir -p /etc/gitea
mkdir -p /${LXC_SHAREFS_MOUNTPOINT}/
chown -R git:git /${LXC_SHAREFS_MOUNTPOINT}/
chmod -R 750 /${LXC_SHAREFS_MOUNTPOINT}/

cat << EOF > /etc/systemd/system/gitea.service
[Unit]
Description=Gitea
After=syslog.target
After=network.target
After=postgresql.service

[Service]
RestartSec=2s
Type=simple
User=git
Group=git
WorkingDirectory=/${LXC_SHAREFS_MOUNTPOINT}/
ExecStart=/usr/local/bin/gitea web -c /etc/gitea/app.ini
Restart=always
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=/${LXC_SHAREFS_MOUNTPOINT}/

[Install]
WantedBy=multi-user.target
EOF

cat << EOF > /etc/gitea/app.ini
RUN_MODE = prod
RUN_USER = git

[repository]
ROOT = /${LXC_SHAREFS_MOUNTPOINT}/git/repositories

[repository.local]
LOCAL_COPY_PATH = /${LXC_SHAREFS_MOUNTPOINT}/gitea/tmp/local-repo

[repository.upload]
TEMP_PATH = /${LXC_SHAREFS_MOUNTPOINT}/gitea/uploads

[database]
DB_TYPE=postgres
HOST=localhost
NAME=${GITEA_DB_NAME}
USER=${GITEA_DB_USR}
PASSWD=${GITEA_DB_PWD}
SSL_MODE=disable

[server]
APP_DATA_PATH    = /${LXC_SHAREFS_MOUNTPOINT}/gitea
DOMAIN           = ${LXC_HOSTNAME}.${LXC_DOMAIN}
SSH_DOMAIN       = ${LXC_HOSTNAME}.${LXC_DOMAIN}
HTTP_HOST        = localhost
HTTP_PORT        = 3000
ROOT_URL         = http://${LXC_HOSTNAME}.${LXC_DOMAIN}/
DISABLE_SSH      = false
SSH_PORT         = 22
SSH_LISTEN_PORT  = 22
EOF

chown -R root:git /etc/gitea
chmod 770 /etc/gitea
chmod 770 /etc/gitea/app.ini

cat << EOF > /etc/nginx/conf.d/default.conf
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    server_tokens off;

    access_log /var/log/nginx/gitea.access.log;
    error_log /var/log/nginx/gitea.error.log;

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

    access_log /var/log/nginx/gitea.access.log;
    error_log  /var/log/nginx/gitea.error.log;

    client_max_body_size 50M;

    location / {
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:3000;
        proxy_read_timeout 90;
    }
}

EOF
openssl dhparam -out /etc/nginx/dhparam.pem 4096

systemctl daemon-reload
systemctl enable --now gitea
systemctl restart nginx
