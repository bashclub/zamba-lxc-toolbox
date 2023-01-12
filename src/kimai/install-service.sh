#!/bin/bash

set -euo pipefail

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

KIMAI_DB_PWD=$(random_password)
webroot=/var/www/kimai/public

wget -q -O - https://packages.sury.org/php/apt.gpg | apt-key add -
echo "deb https://packages.sury.org/php/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/php.list

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq zip unzip sudo nginx-full mariadb-server mariadb-client php8.1 php8.1-intl php8.1-cli php8.1-fpm php8.1-mysql php8.1-xml php8.1-mbstring php8.1-gd php8.1-tokenizer php8.1-zip php8.1-opcache php8.1-curl

mkdir /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout /etc/nginx/ssl/kimai.key -out /etc/nginx/ssl/kimai.crt -subj "/CN=$LXC_HOSTNAME.$LXC_DOMAIN" -addext "subjectAltName=DNS:$LXC_HOSTNAME.$LXC_DOMAIN"

PHP_VERSION=$(php -v | head -1 | cut -d ' ' -f2)
PHP_VERSION=${PHP_VERSION:0:3}

cat << EOF > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    return 301 https://$LXC_HOSTNAME.$LXC_DOMAIN;
}

server {

    client_max_body_size 2M;
    fastcgi_buffers 64 4K;
    client_body_timeout 120s;

    listen 443 http2 ssl default_server;
    listen [::]:443 http2 ssl default_server;
    server_name $LXC_HOSTNAME.$LXC_DOMAIN;

    root $webroot;

    index index.php;

    ssl_certificate /etc/nginx/ssl/kimai.crt;
    ssl_certificate_key /etc/nginx/ssl/kimai.key;

    access_log  /var/log/nginx/kimai.access.log;
    error_log   /var/log/nginx/kimai.error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
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

mysql -uroot -e "CREATE USER 'kimai'@'localhost' IDENTIFIED BY '$KIMAI_DB_PWD';
CREATE DATABASE IF NOT EXISTS kimai;
GRANT ALL PRIVILEGES ON kimai.* TO 'kimai'@'localhost' IDENTIFIED BY '$KIMAI_DB_PWD';
FLUSH PRIVILEGES;"

sed -i "s/post_max_size = 8M/post_max_size = 2M/g" /etc/php/${PHP_VERSION}/fpm/php.ini
sed -i "s/memory_limit = 128M/memory_limit = 512M/g" /etc/php/${PHP_VERSION}/fpm/php.ini
sed -i "s/;opcache.enable=1/opcache.enable=1/g" /etc/php/${PHP_VERSION}/fpm/php.ini
sed -i "s/;opcache.memory_consumption=128/opcache.memory_consumption=256/g" /etc/php/${PHP_VERSION}/fpm/php.ini
sed -i "s/opcache.interned_strings_buffer=8/opcache.interned_strings_buffer=24/g" /etc/php/${PHP_VERSION}/fpm/php.ini
sed -i "s/;opcache.max_accelerated_files=10000/opcache.max_accelerated_files=100000/g" /etc/php/${PHP_VERSION}/fpm/php.ini
sed -i "s/;opcache.validate_timestamps=1/opcache.validate_timestamps=0/g" /etc/php/${PHP_VERSION}/fpm/php.ini
sed -i "s/session.gc_maxlifetime = 1440/session.gc_maxlifetime = 604800/g" /etc/php/${PHP_VERSION}/fpm/php.ini

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
git clone https://github.com/kimai/kimai.git --branch $KIMAI_VERSION --depth 1
cd kimai

# Install kimai composer dependencies
export COMPOSER_ALLOW_SUPERUSER=1
/usr/local/bin/composer install --optimize-autoloader -n

# Copy and update kimai environment variables
cat << EOF >> .env
# For more infos about the variables, see .env.dist
DATABASE_URL=mysql://kimai:$KIMAI_DB_PWD@localhost:3306/kimai?charset=utf8&serverVersion=mariadb-10.5.8
MAILER_FROM=admin@$LXC_DOMAIN
MAILER_URL=null://null
APP_ENV=prod
APP_SECRET=$(random_password)
CORS_ALLOW_ORIGIN=^https?://localhost(:[0-9]+)?$
EOF

chown -R www-data:www-data .
chmod -R g+r .
chmod -R g+rw var/

bin/console kimai:install -n

bin/console kimai:user:create admin admin@$LXC_DOMAIN ROLE_SUPER_ADMIN $LXC_PWD

systemctl daemon-reload
systemctl enable --now php${PHP_VERSION}-fpm nginx
systemctl restart php${PHP_VERSION}-fpm nginx

echo -e "Your kimai installation is now complete. Please continue with setup in your Browser:\nURL:\t\thttp://$(echo ${LXC_IP} | cut -d'/' -f1)\nLogin:\t\tadmin@${LXC_DOMAIN}\n\nPassword:\t${LXC_PWD}\n\n"
