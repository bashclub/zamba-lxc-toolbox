#!/bin/bash

set -euo pipefail

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

BOOKSTACK_DB_PWD=$(random_password)
webroot=/var/www/bookstack/public

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends zip unzip nginx-full mariadb-server mariadb-client php php-cli php-fpm php-mysql php-xml php-mbstring php-gd php-tokenizer php-xml php-dompdf php-curl php-ldap php-tidy php-zip redis-server
curl -s https://api.github.com/repos/wkhtmltopdf/packaging/releases/latest | grep browser_download_url | cut -d '"' -f 4 | grep 'bookworm_amd64.deb$' | wget -O /opt/wkhtmltox.deb -i -
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends /opt/wkhtmltox.deb

mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout /etc/nginx/ssl/open3a.key -out /etc/nginx/ssl/open3a.crt -subj "/CN=$LXC_HOSTNAME.$LXC_DOMAIN" -addext "subjectAltName=DNS:$LXC_HOSTNAME.$LXC_DOMAIN"

PHP_VERSION=$(php -v | head -1 | cut -d ' ' -f2)

cat << EOF > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    return 301 https://$LXC_HOSTNAME.$LXC_DOMAIN;
}

server {

    client_max_body_size 100M;
    fastcgi_buffers 64 4K;
    client_body_timeout 120s;

    listen 443 http2 ssl default_server;
    listen [::]:443 http2 ssl default_server;
    server_name $LXC_HOSTNAME.$LXC_DOMAIN;

    root $webroot;

    index index.php;

    ssl_certificate /etc/nginx/ssl/open3a.crt;
    ssl_certificate_key /etc/nginx/ssl/open3a.key;

    access_log  /var/log/nginx/bookstack.access.log;
    error_log   /var/log/nginx/bookstack.error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php${PHP_VERSION:0:3}-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    location ~ /\.ht {
        deny all;
    }

    fastcgi_hide_header X-Powered-By;
    fastcgi_read_timeout 3600;
    fastcgi_send_timeout 3600;
    fastcgi_connect_timeout 3600;

    add_header Permissions-Policy                   "interest-cohort=()";
    add_header Referrer-Policy                      "no-referrer"   always;
    add_header X-Content-Type-Options               "nosniff"       always;
    add_header X-Download-Options                   "noopen"        always;
    add_header X-Frame-Options                      "SAMEORIGIN"    always;
    add_header X-Permitted-Cross-Domain-Policies    "none"          always;
    add_header X-Robots-Tag                         "none"          always;
    add_header X-XSS-Protection                     "1; mode=block" always;

    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
    gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

}

EOF

mysql -uroot -e "CREATE USER 'bookstack'@'localhost' IDENTIFIED BY '$BOOKSTACK_DB_PWD';
CREATE DATABASE IF NOT EXISTS bookstack;
GRANT ALL PRIVILEGES ON bookstack.* TO 'bookstack'@'localhost' IDENTIFIED BY '$BOOKSTACK_DB_PWD';
FLUSH PRIVILEGES;"

sed -i "s/post_max_size = 8M/post_max_size = 100M/g" /etc/php/${PHP_VERSION:0:3}/fpm/php.ini
sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 100M/g" /etc/php/${PHP_VERSION:0:3}/fpm/php.ini
sed -i "s/memory_limit = 128M/memory_limit = 512M/g" /etc/php/${PHP_VERSION:0:3}/fpm/php.ini

EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"
if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]
then
    >&2 echo 'ERROR: Invalid composer installer checksum'
    rm composer-setup.php
    exit 1
fi
php composer-setup.php --quiet
rm composer-setup.php
# Move composer to global installation
mv composer.phar /usr/local/bin/composer

cd /var/www
git clone https://github.com/BookStackApp/BookStack.git --branch release --single-branch bookstack
cd bookstack

# Install BookStack composer dependencies
export COMPOSER_ALLOW_SUPERUSER=1
php /usr/local/bin/composer install --no-dev --no-plugins


# Copy and update BookStack environment variables
cp .env.example .env
sed -i.bak "s@APP_URL=.*\$@APP_URL=https://${LXC_HOSTNAME}.${LXC_DOMAIN}@" .env
sed -i.bak 's/DB_DATABASE=.*$/DB_DATABASE=bookstack/' .env
sed -i.bak 's/DB_USERNAME=.*$/DB_USERNAME=bookstack/' .env
sed -i.bak "s/DB_PASSWORD=.*\$/DB_PASSWORD=$BOOKSTACK_DB_PWD/" .env

cat << EOF >> .env
QUEUE_CONNECTION=database
STORAGE_TYPE=local_secure
APP_LANG=de_informal
FILE_UPLOAD_SIZE_LIMIT=100
SESSION_SECURE_COOKIE=true
CACHE_DRIVER=redis
SESSION_DRIVER=redis
REDIS_SERVERS=127.0.0.1:6379:0
WKHTMLTOPDF=/usr/local/bin/wkhtmltopdf
ALLOW_UNTRUSTED_SERVER_FETCHING=true
EOF

# Generate the application key
php artisan key:generate --no-interaction --force
# Migrate the databases
php artisan migrate --no-interaction --force

php artisan bookstack:db-utf8mb4 > dbupgrade.sql
mysql -u root < dbupgrade.sql

chown www-data:www-data -R bootstrap/cache public/uploads storage && chmod -R 755 bootstrap/cache public/uploads storage

cat << EOF > /etc/systemd/system/bookstack-queue.service
[Unit]
Description=BookStack Queue Worker

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/bookstack/artisan queue:work --sleep=3 --tries=1 --max-time=3600

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now bookstack-queue php${PHP_VERSION:0:3}-fpm nginx redis-server
systemctl restart php${PHP_VERSION:0:3}-fpm nginx bookstack-queue redis-server

LXC_IP=$(ip address show dev eth0 | grep "inet " | cut -d ' ' -f6)

echo -e "Your bookstack installation is now complete. Please continue with setup in your Browser:\nURL:\t\thttp://$(echo ${LXC_IP} | cut -d'/' -f1)\nLogin:\t\tadmin@admin.com\nPassword:\tpassword\n\n"