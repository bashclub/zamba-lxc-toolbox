#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf
source /etc/os-release

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install --no-install-recommends -y -qq aptly python3-aptly nginx graphviz gnupg2 apt-transport-https bc

# Create gpg key for apt repo signing
gpg --batch --gen-key <<EOF
Key-Type: 1
Key-Length: 4096
Subkey-Type: 1
Subkey-Length: 4096
Name-Real: ${AM_COMPANY_NAME}
Name-Email: ${AM_COMPANY_EMAIL}
Expire-Date: 0
%no-protection
EOF

if [ -f /etc/nginx/sites-enabled/default ]; then
  unlink /etc/nginx/sites-enabled/default
fi

cat << EOF > /etc/aptly.conf
{
  "rootDir": "/$LXC_SHAREFS_MOUNTPOINT",
  "downloadConcurrency": 4,
  "downloadSpeedLimit": 0,
  "architectures": [
        "amd64",
        "armhf"
  ],
  "dependencyFollowSuggests": false,
  "dependencyFollowRecommends": false,
  "dependencyFollowAllVariants": false,
  "dependencyFollowSource": false,
  "dependencyVerboseResolve": true,
  "gpgDisableSign": false,
  "gpgDisableVerify": false,
  "gpgProvider": "gpg",
  "downloadSourcePackages": false,
  "skipLegacyPool": true,
  "ppaDistributorID": "$AM_COMPANY_NAME",
  "ppaCodename": ""
}
EOF

cat << EOF > /etc/nginx/conf.d/default.conf
server {
        listen 80 default_server;
        listen [::]:80 default_server;

        # Force HTTPS connection. This rules is domain agnostic
        if (\$scheme != "https") {
                rewrite ^ https://\$host\$uri permanent;
        }

        # SSL configuration
        #
        listen 443 ssl http2 default_server;
        listen [::]:443 ssl http2 default_server;

        ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
        ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

        ssl_protocols TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_dhparam /etc/nginx/dhparam.pem;
        ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
        ssl_ecdh_curve secp384r1; # Requires nginx >= 1.1.0
        ssl_session_timeout  10m;
        ssl_session_cache shared:SSL:10m;
        ssl_session_tickets off; # Requires nginx >= 1.5.9
        ssl_stapling on; # Requires nginx >= 1.3.7
        ssl_stapling_verify on; # Requires nginx => 1.3.7
        resolver 15.137.208.11 15.137.209.11 valid=300s;
        resolver_timeout 5s;
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";

        root /var/www/html;
        index index.html index.htm;

        server_name _;

        location /gpg {
                autoindex on;
        }

        location /graph {
                autoindex on;
        }

        location / {
                # First attempt to serve request as file, then
                # as directory, then fall back to displaying a 404.
                #try_files \$uri \$uri/ =404;
                proxy_set_header Host \$host;
                proxy_set_header X-Real-IP \$remote_addr;
                proxy_pass http://localhost:8080;

        }

        location /api {
                proxy_pass http://localhost:8000/api;
        }

        location /api/graph {
                return 403;
        }
}
EOF

cat << EOF > /etc/systemd/system/aptly.service
[Unit]
Description=Aptly Repository service

[Service]
User=root
ExecStart=/usr/bin/aptly serve -listen="localhost:8080"
KillSignal=SIGTERM
KillMode=process
TimeoutStopSec=15s

[Install]
WantedBy=multi-user.target

EOF

cat << EOF > /etc/systemd/system/aptly-api.service
[Unit]
Description=Aptly REST API service

[Service]
User=root
ExecStart=/usr/bin/aptly api serve -listen=unix:///var/run/aptly-api.sock -no-lock
KillSignal=SIGTERM
KillMode=process
TimeoutStopSec=15s

[Install]
WantedBy=multi-user.target
EOF

chown -R www-data:www-data /$LXC_SHAREFS_MOUNTPOINT

chown -R www-data:www-data /var/www

# Create required webserver folders
sudo -u www-data mkdir -p /var/www/html/{gpg,graph}

# Export gpg key
sudo -u www-data gpg --export --armor > /var/www/html/gpg/$AM_COMPANY_NAME.pub

generate_dhparam

systemctl daemon-reload
systemctl enable --now aptly aptly-api
systemctl restart nginx
