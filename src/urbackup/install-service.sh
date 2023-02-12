#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

mkdir -p /$LXC_SHAREFS_MOUNTPOINT/tmp
mkdir -p /$LXC_SHAREFS_MOUNTPOINT/$URBACKUP_DATA
mkdir /etc/urbackup
echo "/$LXC_SHAREFS_MOUNTPOINT/$URBACKUP_DATA" > /etc/urbackup/backupfolder

echo "deb http://download.opensuse.org/repositories/home:/uroni/$REPO_CODENAME/ /" | tee /etc/apt/sources.list.d/urbackup.list
curl -fsSL https://download.opensuse.org/repositories/home:uroni/$REPO_CODENAME/Release.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/home_uroni.gpg > /dev/null

apt update
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y --no-install-recommends -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" urbackup-server nginx

mkdir /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout /etc/nginx/ssl/urbackup.key -out /etc/nginx/ssl/urbackup.crt -subj "/CN=$LXC_HOSTNAME.$LXC_DOMAIN" -addext "subjectAltName=DNS:$LXC_HOSTNAME.$LXC_DOMAIN"

ln -s /usr/share/urbackup/www /var/www/urbackup

cat << EOF > /etc/nginx/sites-available/default
server {
    listen 80;
    listen [::]:80;
    server_name _;

    return 301 https://$LXC_HOSTNAME.$LXC_DOMAIN;
}


server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name $LXC_HOSTNAME.$LXC_DOMAIN;

    root /var/www/urbackup;

    index index.htm;

    ssl on;
    ssl_certificate /etc/nginx/ssl/urbackup.crt;
    ssl_certificate_key /etc/nginx/ssl/urbackup.key;

    location /x {
        include /etc/nginx/fastcgi_params;
        fastcgi_pass 127.0.0.1:55413;
    }
}

EOF

sed -i "s/DAEMON_TMPDIR=\"\/tmp\"/DAEMON_TMPDIR=\"\/$LXC_SHAREFS_MOUNTPOINT\/tmp\"/g" /etc/default/urbackupsrv
sed -i "s/HTTP_SERVER=\"true\"/HTTP_SERVER=\"false\"/g" /etc/default/urbackupsrv
chown urbackup:urbackup /$LXC_SHAREFS_MOUNTPOINT/tmp
chown urbackup:urbackup /$LXC_SHAREFS_MOUNTPOINT/$URBACKUP_DATA

systemctl restart urbackupsrv nginx