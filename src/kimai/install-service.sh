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

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq zip unzip sudo nginx-full mariadb-server mariadb-client php8.1 php8.1-intl php8.1-cli php8.1-fpm php8.1-mysql php8.1-xml php8.1-mbstring php8.1-gd php8.1-tokenizer php8.1-zip

mkdir /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout /etc/nginx/ssl/kimai.key -out /etc/nginx/ssl/kimai.crt -subj "/CN=$LXC_HOSTNAME.$LXC_DOMAIN" -addext "subjectAltName=DNS:$LXC_HOSTNAME.$LXC_DOMAIN"

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

    ssl_certificate /etc/nginx/ssl/kimai.crt;
    ssl_certificate_key /etc/nginx/ssl/kimai.key;

    access_log  /var/log/nginx/kimai.access.log;
    error_log   /var/log/nginx/kimai.error.log;

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

mysql -uroot -e "CREATE USER 'kimai'@'localhost' IDENTIFIED BY '$KIMAI_DB_PWD';
CREATE DATABASE IF NOT EXISTS kimai;
GRANT ALL PRIVILEGES ON kimai.* TO 'kimai'@'localhost' IDENTIFIED BY '$KIMAI_DB_PWD';
FLUSH PRIVILEGES;"

sed -i "s/post_max_size = 8M/post_max_size = 100M/g" /etc/php/8.1/fpm/php.ini
sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 100M/g" /etc/php/8.1/fpm/php.ini
sed -i "s/memory_limit = 128M/memory_limit = 512M/g" /etc/php/8.1/fpm/php.ini

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
#================================================================================
# Configure your database connection and set the correct server version.
#
# You have to replace the following values with your defaults:
# - the version "5.7"
# - the database username "user"
# - the database password "password"
# - the database schema name "database"
# - you might have to adapt port "3306" and server IP "127.0.0.1" as well
#
# For MySQL that would be "serverVersion=5.7" as in:
#    DATABASE_URL=mysql://user:password@127.0.0.1:3306/database?charset=utf8&serverVersion=5.7
#
# For MariaDB it would be "serverVersion=mariadb-10.5.8":
#    DATABASE_URL=mysql://user:password@127.0.0.1:3306/database?charset=utf8&serverVersion=mariadb-10.5.8
#
DATABASE_URL=mysql://kimai:$KIMAI_DB_PWD@localhost:3306/kimai?charset=utf8&serverVersion=5.7

#================================================================================
# The full documentation can be found at https://www.kimai.org/documentation/emails.html
#
# Email will be sent with this address as sender:
MAILER_FROM=kimai@example.com
# Email connection (disabled by default) - see documentation for the format
MAILER_URL=null://null

#================================================================================
# Running behind reverse proxies? Try these:
# TRUSTED_PROXIES=127.0.0.1,127.0.0.2
# TRUSTED_HOSTS=localhost,example.com

#================================================================================
# do not change, unless you are developing for Kimai
APP_ENV=prod

#================================================================================
# should be changed to a unique character sequence, used for hashing cookies
APP_SECRET=$(random_password)

#================================================================================
# unlikely, that you need to change this one
CORS_ALLOW_ORIGIN=^https?://localhost(:[0-9]+)?$
EOF

chown -R www-data:www-data .
chmod -R g+r .
chmod -R g+rw var/

bin/console kimai:install -n

bin/console kimai:user:create admin admin@$LXC_DOMAIN ROLE_SUPER_ADMIN $LXC_PWD

systemctl daemon-reload
systemctl enable --now php8.1-fpm nginx
systemctl restart php8.1-fpm nginx

echo -e "Your kimai installation is now complete. Please continue with setup in your Browser:\nURL:\t\thttp://$(echo ${LXC_IP} | cut -d'/' -f1)\nLogin:\t\tadmin@${LXC_DOMAIN}\n\nPassword:\t${LXC_PWD}\n\n"