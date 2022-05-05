#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/zamba.conf
source /root/constants-service.conf

apt-key adv --fetch https://dl.packager.io/srv/zammad/zammad/key
apt-key adv --fetch https://artifacts.elastic.co/GPG-KEY-elasticsearch
wget -O /etc/apt/sources.list.d/zammad.list https://dl.packager.io/srv/zammad/zammad/stable/installer/debian/11.repo
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" > /etc/apt/sources.list.d/elastic-7.x.list
apt update
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install ssl-cert zammad

# configurwe nginx
rm -f /etc/nginx/sites-enabled/default

cat << EOF > /etc/nginx/sites-available/zammad.conf
upstream zammad-railsserver {
  server 127.0.0.1:3000;
}

upstream zammad-websocket {
  server 127.0.0.1:6042;
}

server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    server_tokens off;

    access_log /var/log/nginx/zammad.access.log;
    error_log /var/log/nginx/zammad.error.log;

    location /.well-known/ {
        root /var/www/html;
    }

    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name _;
    
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

    location = /robots.txt  {
    access_log off; log_not_found off;
    }

    location = /favicon.ico {
    access_log off; log_not_found off;
    }

    root /opt/zammad/public;

    access_log /var/log/nginx/zammad.access.log;
    error_log  /var/log/nginx/zammad.error.log;

    client_max_body_size 50M;

    location ~ ^/(assets/|robots.txt|humans.txt|favicon.ico|apple-touch-icon.png) {
    expires max;
    }

    location /ws {
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_set_header CLIENT_IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto	\$scheme;
    proxy_read_timeout 86400;
    proxy_pass http://zammad-websocket;
    }

    location / {
    proxy_set_header Host \$http_host;
    proxy_set_header CLIENT_IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto	\$scheme;

    # change this line in an SSO setup
    proxy_set_header X-Forwarded-User "";

    proxy_read_timeout 180;
    proxy_pass http://zammad-railsserver;

    gzip on;
    gzip_types text/plain text/xml text/css image/svg+xml application/javascript application/x-javascript application/json application/xml;
    gzip_proxied any;
    }
}
EOF

openssl dhparam -out /etc/nginx/dhparam.pem 4096

systemctl restart nginx