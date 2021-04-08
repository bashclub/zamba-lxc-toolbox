#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <helmke@cloudistboese.de>
# (C) 2021 Script rework by Thorsten Spille <thorsten@spille-edv.de>

source ./zamba.conf

# Set Timezone
ln -sf /usr/share/zoneinfo/$LXC_TIMEZONE /etc/localtime

# configure system language
dpkg-reconfigure locales

MRX_PKE=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

ELE_DBNAME="synapse_db"
ELE_DBUSER="synapse_user"
ELE_DBPASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

apt update && apt full-upgrade -y

apt install -y $LXC_TOOLSET apt-transport-https gpg software-properties-common nginx postgresql python3-psycopg2

wget wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/matrix-org.list
apt update && apt install -y matrix-synapse-py3
systemctl enable matrix-synapse

ss -tulpen

mkdir /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout /etc/nginx/ssl/matrix.key -out /etc/nginx/ssl/matrix.crt -subj "/CN=$MATRIX_FQDN" -addext "subjectAltName=DNS:$MATRIX_FQDN"

cat > /etc/nginx/sites-available/$MATRIX_FQDN <<EOF
# Virtual Host configuration for example.com
#
# You can move that to a different file under sites-available/ and symlink that
# to sites-enabled/ to enable it.

server {
    listen 80;
    listen [::]:80;
    server_name $MATRIX_FQDN;

    return 301 https://$MATRIX_FQDN;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name $MATRIX_FQDN;

    ssl on;
    ssl_certificate /etc/nginx/ssl/matrix.crt;
    ssl_certificate_key /etc/nginx/ssl/matrix.key;

    location / {
      proxy_pass http://127.0.0.1:8008;
      proxy_set_header X-Forwarded-For \$remote_addr;
    }
}

server {
    listen 8448 ssl;
    listen [::]:8448 ssl;
    server_name $MATRIX_FQDN;

    ssl on;
    ssl_certificate /etc/nginx/ssl/matrix.crt;
    ssl_certificate_key /etc/nginx/ssl/matrix.key;

    # If you don't wanna serve a site, comment this out
    root /var/www/$MATRIX_FQDN;
    index index.html index.htm;

    location / {
        proxy_pass http://127.0.0.1:8008;
        proxy_set_header X-Forwarded-For \$remote_addr;
    }
}

EOF
ln -s /etc/nginx/sites-available/$MATRIX_FQDN /etc/nginx/sites-enabled/$MATRIX_FQDN

cat > /etc/nginx/sites-available/$MATRIX_ELEMENT_FQDN <<EOF
# Virtual Host configuration for example.com
#
# You can move that to a different file under sites-available/ and symlink that
# to sites-enabled/ to enable it.

server {
    listen 80;
    listen [::]:80;
    server_name $MATRIX_ELEMENT_FQDN;
    return 301 https://$MATRIX_ELEMENT_FQDN;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name $MATRIX_ELEMENT_FQDN;

    ssl on;
    ssl_certificate /etc/nginx/ssl/matrix.crt;
    ssl_certificate_key /etc/nginx/ssl/matrix.key;

    # If you don't wanna serve a site, comment this out
    root /var/www/$MATRIX_ELEMENT_FQDN/element;
    index index.html index.htm;
} 

EOF

ln -s /etc/nginx/sites-available/$MATRIX_ELEMENT_FQDN /etc/nginx/sites-enabled/$MATRIX_ELEMENT_FQDN

systemctl restart nginx

mkdir /var/www/$MATRIX_ELEMENT_FQDN
cd /var/www/$MATRIX_ELEMENT_FQDN
wget https://packages.riot.im/element-release-key.asc
gpg --import element-release-key.asc

wget https://github.com/vector-im/element-web/releases/download/$MATRIX_ELEMENT_VERSION/element-$MATRIX_ELEMENT_VERSION.tar.gz
wget https://github.com/vector-im/element-web/releases/download/$MATRIX_ELEMENT_VERSION/element-$MATRIX_ELEMENT_VERSION.tar.gz.asc
gpg --verify element-$MATRIX_ELEMENT_VERSION.tar.gz.asc

tar -xzvf element-$MATRIX_ELEMENT_VERSION.tar.gz
ln -s element-$MATRIX_ELEMENT_VERSION element
chown www-data:www-data -R element
cp ./element/config.sample.json ./element/config.json
sed -i "s|https://matrix-client.matrix.org|https://$MATRIX_FQDN|" ./element/config.json
sed -i "s|\"server_name\": \"matrix.org\"|\"server_name\": \"$MATRIX_FQDN\"|" ./element/config.json

su postgres <<EOF
psql -c "CREATE USER $ELE_DBUSER WITH PASSWORD '$ELE_DBPASS';"
psql -c "CREATE DATABASE $ELE_DBNAME ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' template=template0 OWNER $ELE_DBUSER;"
echo "Postgres User '$ELE_DBUSER' and database '$ELE_DBNAME' created."
EOF

cd /
sed -i "s|#registration_shared_secret: <PRIVATE STRING>|registration_shared_secret: \"$MRX_PKE\"|" /etc/matrix-synapse/homeserver.yaml
sed -i "s|#public_baseurl: https://example.com/|public_baseurl: https://$MATRIX_FQDN/|" /etc/matrix-synapse/homeserver.yaml
sed -i "s|#enable_registration: false|enable_registration: true|" /etc/matrix-synapse/homeserver.yaml
sed -i "s|name: sqlite3|name: psycopg2|" /etc/matrix-synapse/homeserver.yaml
sed -i "s|database: /var/lib/matrix-synapse/homeserver.db|database: $ELE_DBNAME\n    user: $ELE_DBUSER\n    password: $ELE_DBPASS\n    host: 127.0.0.1\n    cp_min: 5\n    cp_max: 10|" /etc/matrix-synapse/homeserver.yaml

systemctl restart matrix-synapse

register_new_matrix_user -c /etc/matrix-synapse/homeserver.yaml http://127.0.0.1:8008

#curl https://download.jitsi.org/jitsi-key.gpg.key | sh -c 'gpg --dearmor > /usr/share/keyrings/jitsi-keyring.gpg'
#echo 'deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/' | tee /etc/apt/sources.list.d/jitsi-stable.list > /dev/null

#apt update
#apt install -y jitsi-meet



