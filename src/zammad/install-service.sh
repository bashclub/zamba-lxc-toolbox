#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

curl -fsSL https://dl.packager.io/srv/zammad/zammad/key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/pkgr-zammad.gpg > /dev/null
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor | tee /etc/apt/trusted.gpg.d/elasticsearch.gpg> /dev/null
echo "deb [signed-by=/etc/apt/trusted.gpg.d/elasticsearch.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main"| tee -a /etc/apt/sources.list.d/elastic-7.x.list > /dev/null
echo "deb [signed-by=/etc/apt/trusted.gpg.d/pkgr-zammad.gpg] https://dl.packager.io/srv/deb/zammad/zammad/stable/debian 12 main"| tee /etc/apt/sources.list.d/zammad.list > /dev/null

apt update
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install ssl-cert nginx-full postgresql zammad


# Java set startup environment 
mkdir -p /etc/elasticsearch/jvm.options.d
cat << EOF >>/etc/elasticsearch/jvm.options.d/msmx-size.options
# INFO: https://www.elastic.co/guide/en/elasticsearch/reference/master/advanced-configuration.html#set-jvm-heap-size
# max 50% of total RAM - 2G Ram then set Xms and Xmx 1g
-Xms1g
-Xmx1g
EOF

# configure nginx
generate_dhparam

unlink /etc/nginx/sites-enabled/default
unlink /etc/nginx/sites-enabled/zammad.conf

mkdir -p /etc/nginx/ssl
ln -sf /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/nginx/ssl/fullchain.pem
ln -sf /etc/ssl/private/ssl-cert-snakeoil.key /etc/nginx/ssl/privkey.pem
ln -sf /etc/nginx/dhparam.pem /etc/nginx/ssl/dhparam.pem

echo "Customizing nginx configuration..."
sed -e "s|$(grep -m1 server_name /etc/nginx/sites-available/zammad_ssl.conf)|server_name ${LXC_HOSTNAME}.${LXC_DOMAIN};|g" \
 -e "s|$(grep -m1 ssl_certificate /etc/nginx/sites-available/zammad_ssl.conf)|ssl_certificate /etc/nginx/ssl/fullchain.pem;|g" \
 -e "s|$(grep -m1 ssl_certificate_key /etc/nginx/sites-available/zammad_ssl.conf)|ssl_certificate_key /etc/nginx/ssl/privkey.pem;|g" \
 -e "s|$(grep -m1 ssl_protocols /etc/nginx/sites-available/zammad_ssl.conf)|ssl_protocols TLSv1.2 TLSv1.3;|g" \
 -e "s|$(grep -m1 ssl_trusted_certificate /etc/nginx/sites-available/zammad_ssl.conf)|#  ssl_trusted_certificate /etc/nginx/ssl/lets-encrypt-x3-cross-signed.pem;|g" \
 /opt/zammad/contrib/nginx/zammad_ssl.conf > /etc/nginx/sites-available/zammad_ssl.conf
echo "Linking nginx configuration..."
ln -sf /etc/nginx/sites-available/zammad_ssl.conf /etc/nginx/sites-enabled/


# configure elasticsearch
/usr/share/elasticsearch/bin/elasticsearch-plugin install -b ingest-attachment

systemctl enable elasticsearch.service
systemctl restart nginx elasticsearch.service

# Elasticsearch conntact to Zammad
zammad run rails r "Setting.set('es_url', 'http://127.0.0.1:9200')"
zammad run rails r "Setting.set('es_index', Socket.gethostname.downcase + '_zammad')"
zammad run rails r "User.find_by(email: 'nicole.braun@zammad.org').destroy"
systemctl restart elasticsearch.service
zammad run rake zammad:searchindex:rebuild[$(nproc)]