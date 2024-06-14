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

cat << EOF > /usr/local/bin/update-apt-mirrors
#!/bin/bash
PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

for m in $(aptly mirror list -raw); do
  aptly mirror update -keyring='/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg' \$m
done
EOF

chmod +x /usr/local/bin/update-apt-mirrors


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

cat << EOF > /root/mirror-examples
# import proxmox keyring
wget -O - http://download.proxmox.com/debian/proxmox-release-bookworm.gpg | gpg --no-default-keyring --keyring /$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg --import

# proxmox 8 no subscription mirror (about 11.5 GB)
aptly mirror create -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg pve8.pve-no-subscription http://download.proxmox.com/debian/ bookworm pve-no-suscription
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg pve8.pve-no-subscription

# import debian keyring
cat /etc/apt/trusted.gpg.d/debian-archive* | gpg --no-default-keyring --keyring /$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg --import

# debian 12 main mirror (about 87 GB)
aptly mirror create -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.main http://deb.debian.org/debian/ bookworm main
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.main

# debian 12 contrib mirror (about 600 MB)
aptly mirror create -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.contrib http://deb.debian.org/debian/ bookworm contrib
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.contrib

# debian 12 non-free mirror (about7,2 GB)
aptly mirror create -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free http://deb.debian.org/debian/ bookworm non-free
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free

# debian 12 non-free-firmware mirror (38 Packages)
aptly mirror create -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free-firmware http://deb.debian.org/debian/ bookworm non-free-firmware
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free-firmware

# debian 12 update main mirror (about 2,5 GB)
aptly mirror create -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.main.update http://deb.debian.org/debian/ bookworm-updates main
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.main.update

# debian 12 update contrib mirror (currently empty)
aptly mirror create -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.contrib.updates http://deb.debian.org/debian/ bookworm-updates contrib
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.contrib.updates

# debian 12 updates non-free mirror (about 900 MB)
aptly mirror create -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free.updates http://deb.debian.org/debian/ bookworm-updates non-free
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free.updates

# debian 12 updates non-free-firmware mirror (about 70 MB)
aptly mirror create -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free-firmware.updates http://deb.debian.org/debian/ bookworm-updates non-free-firmware
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free-firmware.updates

# debian 12 security main mirror (about 5,5 GB)
aptly mirror create -force-components -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.main.security http://security.debian.org/debian-security bookworm-security main
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.main.security

# debian 12 security contrib mirror (2 packages)
aptly mirror create -force-components -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.contrib.security http://security.debian.org/debian-security bookworm-security contrib
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.contrib.security

# debian 12 security non-free mirror (currently empty)
aptly mirror create -force-components -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free.security http://security.debian.org/debian-security bookworm-security non-free
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free.security

# debian 12 security non-free-firmware mirror (1 package)
aptly mirror create -force-components -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free-firmware.security http://security.debian.org/debian-security bookworm-security non-free-firmware
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free-firmware.security

# debian 12 backports main mirror (about 14,5 GB)
aptly mirror create -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.main.backports http://deb.debian.org/debian/ bookworm-backports main
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.main.backports

# debian 12 backports contrib mirror (about 100 MB)
aptly mirror create -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.contrib.backports http://deb.debian.org/debian/ bookworm-backports contrib
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.contrib.backports

# debian 12 backports non-free mirror (2 packages)
aptly mirror create -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free.backports http://deb.debian.org/debian/ bookworm-backports non-free
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free.backports

# debian 12 backports non-free-firmware mirror (currently empty)
aptly mirror create -architectures="amd64" -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free-firmware.backports http://deb.debian.org/debian/ bookworm-backports non-free-firmware
aptly mirror update -keyring=/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg debian12.non-free-firmware.backports
EOF

cat << EOF > /usr/local/bin/update-apt-mirrors 
#!/bin/bash
PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

for m in \$(aptly mirror list -raw); do
  aptly mirror update -keyring='/$LXC_SHAREFS_MOUNTPOINT/trustedkeys.gpg' $m
done
EOF

echo "0 4 * * * root /usr/local/bin/update-apt-mirrors" > /etc/cron.d/update-apt-mirrors

chmod +x /usr/local/bin/update-apt-mirrors 

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

echo "Apt mirror installation complete. Please look into /root/mirror-examples for mirror examples."