#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

set -euo pipefail

#### Set repo and install onlyoffice ####
inst_onlyoffice() {
    apt_repo "onlyoffice" "https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE" "https://download.onlyoffice.com/repo/debian" "squeeze" "main"
    apt update
    DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt-get install -y -qq ttf-mscorefonts-installer onlyoffice-documentserver
}

ONLYOFFICE_DB_PASS=$(random_password)

inst_postgresql

#cat > /etc/apt/preferences.d/onlyoffice << EOF
#Package: onlyoffice-documentserver
#Pin: version 7.1.1-23
#Pin-Priority: 900
#EOF


DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq rabbitmq-server libstdc++6 supervisor

su postgres <<EOF
psql -c "CREATE USER $ONLYOFFICE_DB_USER WITH PASSWORD '$ONLYOFFICE_DB_PASS';"
psql -c "CREATE DATABASE $ONLYOFFICE_DB_NAME ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' template=template0 OWNER $ONLYOFFICE_DB_USER;"
echo "Postgres User '$ONLYOFFICE_DB_USER' and database '$ONLYOFFICE_DB_NAME' created."
EOF

echo onlyoffice-documentserver onlyoffice/ds-port select 80 | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-host string $ONLYOFFICE_DB_HOST | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-user string $ONLYOFFICE_DB_NAME | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-name string $ONLYOFFICE_DB_USER | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-pwd password $ONLYOFFICE_DB_PASS | debconf-set-selections

inst_onlyoffice

cat << EOF > /root/onlyoffice.credentials
ONLYOFFICE_DB_HOST=$ONLYOFFICE_DB_HOST
ONLYOFFICE_DB_NAME=$ONLYOFFICE_DB_NAME
ONLYOFFICE_DB_USER=$ONLYOFFICE_DB_USER
ONLYOFFICE_DB_PASS=$ONLYOFFICE_DB_PASS
EOF

mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout /etc/nginx/ssl/onlyoffice.key -out /etc/nginx/ssl/onlyoffice.crt -subj "/CN=$LXC_HOSTNAME.$LXC_DOMAIN" -addext "subjectAltName=DNS:$LXC_HOSTNAME.$LXC_DOMAIN"

rm /etc/nginx/conf.d/ds.conf
cp /etc/onlyoffice/documentserver/nginx/ds-ssl.conf.tmpl /etc/onlyoffice/documentserver/nginx/ds-ssl.conf

sed -i "s|ssl_certificate {{SSL_CERTIFICATE_PATH}}|ssl_certificate /etc/nginx/ssl/onlyoffice.crt|" /etc/onlyoffice/documentserver/nginx/ds-ssl.conf
sed -i "s|ssl_certificate_key {{SSL_KEY_PATH}}|ssl_certificate_key /etc/nginx/ssl/onlyoffice.key|" /etc/onlyoffice/documentserver/nginx/ds-ssl.conf

ln -sf /etc/onlyoffice/documentserver/nginx/ds-ssl.conf /etc/nginx/conf.d/ds-ssl.conf

cat > /usr/local/bin/ods-apt-pre-hook << DFOE
#!/bin/bash
rm /etc/nginx/conf.d/ds-ssl.conf
systemctl stop nginx.service
DFOE
chmod +x /usr/local/bin/ods-apt-pre-hook

cat > /usr/local/bin/ods-apt-post-hook << DFOE
#!/bin/bash
rm /etc/nginx/conf.d/ds.conf
ln -sf /etc/onlyoffice/documentserver/nginx/ds-ssl.conf /etc/nginx/conf.d/ds-ssl.conf
systemctl restart nginx
DFOE
chmod +x /usr/local/bin/ods-apt-post-hook

cat << EOF > /etc/apt/apt.conf.d/80-ods-apt-pre-hook
DPkg::Pre-Invoke {"/usr/local/bin/ods-apt-pre-hook";};
EOF

cat << EOF > /etc/apt/apt.conf.d/80-ods-apt-post-hook
DPkg::Post-Invoke {"/usr/local/bin/ods-apt-post-hook";};
EOF

systemctl restart nginx
