#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

MRX_PKE=$(random_password)

ELE_DBNAME="synapse_db"
ELE_DBUSER="synapse_user"
ELE_DBPASS=$(random_password)
ELE_PATH=/var/www/element-web
WEBROOT=/var/www

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq nginx postgresql python3-psycopg2

wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/matrix-org.list
apt update
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq matrix-synapse-py3
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
    root $ELE_PATH;
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
    server_name _;
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
    root $ELE_PATH;
    index index.html index.htm;
} 

EOF

unlink /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/$MATRIX_ELEMENT_FQDN /etc/nginx/sites-enabled/$MATRIX_ELEMENT_FQDN

systemctl restart nginx

cd /var/www

wget -O element-release-key.asc https://packages.riot.im/element-release-key.asc
gpg --import element-release-key.asc

MATRIX_ELEMENT_VERSION=$(curl -s https://api.github.com/repos/vector-im/element-web/releases/latest | grep tag_name | cut -d'"' -f4)

wget -O element-$MATRIX_ELEMENT_VERSION.tar.gz https://github.com/vector-im/element-web/releases/download/$MATRIX_ELEMENT_VERSION/element-$MATRIX_ELEMENT_VERSION.tar.gz
wget -O element-$MATRIX_ELEMENT_VERSION.tar.gz.asc https://github.com/vector-im/element-web/releases/download/$MATRIX_ELEMENT_VERSION/element-$MATRIX_ELEMENT_VERSION.tar.gz.asc
gpg --verify element-$MATRIX_ELEMENT_VERSION.tar.gz.asc

tar -xzvf element-$MATRIX_ELEMENT_VERSION.tar.gz
mv element-$MATRIX_ELEMENT_VERSION $ELE_PATH
chown www-data:www-data -R $ELE_PATH
cp $ELE_PATH/config.sample.json $ELE_PATH/config.json
sed -i "s|https://matrix-client.matrix.org|https://$MATRIX_FQDN|" $ELE_PATH/config.json
sed -i "s|\"server_name\": \"matrix.org\"|\"server_name\": \"$MATRIX_FQDN\"|" $ELE_PATH/config.json

su postgres <<EOF
psql -c "CREATE USER $ELE_DBUSER WITH PASSWORD '$ELE_DBPASS';"
psql -c "CREATE DATABASE $ELE_DBNAME ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' template=template0 OWNER $ELE_DBUSER;"
echo "Postgres User '$ELE_DBUSER' and database '$ELE_DBNAME' created."
EOF

cd /
sed -i "s|#registration_shared_secret: <PRIVATE STRING>|registration_shared_secret: \"$MRX_PKE\"|" /etc/matrix-synapse/homeserver.yaml
sed -i "s|#public_baseurl: https://example.com/|public_baseurl: https://$MATRIX_FQDN/|" /etc/matrix-synapse/homeserver.yaml
sed -i "s|server_name:|server_name: $MATRIX_FQDN|g" /etc/matrix-synapse/conf.d/server_name.yaml
sed -i "s|#enable_registration: false|enable_registration: true|" /etc/matrix-synapse/homeserver.yaml
sed -i "s|name: sqlite3|name: psycopg2|" /etc/matrix-synapse/homeserver.yaml
sed -i "s|database: /var/lib/matrix-synapse/homeserver.db|database: $ELE_DBNAME\n    user: $ELE_DBUSER\n    password: $ELE_DBPASS\n    host: 127.0.0.1\n    cp_min: 5\n    cp_max: 10|" /etc/matrix-synapse/homeserver.yaml

systemctl restart matrix-synapse

rm /var/www/element-release-key.asc /var/www/element-$MATRIX_ELEMENT_VERSION.tar.gz /var/www/element-$MATRIX_ELEMENT_VERSION.tar.gz.asc

register_new_matrix_user -a -u $MATRIX_ADMIN_USER -p \'$MATRIX_ADMIN_PASSWORD\' -c /etc/matrix-synapse/homeserver.yaml http://127.0.0.1:8008

echo -e "Your matrix installation is now complete. Please login into your element:\nLogin:\t\t$MATRIX_ADMIN_USER\nPassword:\t$MATRIX_ADMIN_PASSWORD\n\n"