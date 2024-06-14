#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

set -euo pipefail

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

webroot=/var/www/html

LXC_RANDOMPWD=20
MYSQL_PASSWORD="$(random_password)"

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends unzip sudo nginx-full mariadb-server mariadb-client php php-cli php-zip php-curl php-intl php-fpm php-mysql php-imap php-xml php-mbstring php-gd ssl-cert git


echo ‘cgi.fix_pathinfo=0’ >> /etc/php/8.2/fpm/php.ini

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

    root $webroot/freescout/public;

    index index.php index.html index.htm;

    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;

    client_max_body_size 20M;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ .php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    	include fastcgi_params;
    }
    
    location ^~ /storage/app/attachment/ {
        internal;
        alias /var/www/html/storage/app/attachment/;
    }
    
    location ~* ^/storage/attachment/ {
        expires 1M;
        access_log off;
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location ~* ^/(?:css|js)/.*\.(?:css|js)$ {
        expires 2d;
        access_log off;
        add_header Cache-Control "public, must-revalidate";
    }
    
    # The list should be in sync with /storage/app/public/uploads/.htaccess and /config/app.php
    location ~* ^/storage/.*\.((?!(jpg|jpeg|jfif|pjpeg|pjp|apng|bmp|gif|ico|cur|png|tif|tiff|webp|pdf|txt|diff|patch|json|mp3|wav|ogg|wma)).)*$ {
        add_header Content-disposition "attachment; filename=\$2";
        default_type application/octet-stream;
    }	
    
    location ~* ^/(?:css|fonts|img|installer|js|modules|[^\\\\\\]+\..*)$ {
        expires 1M;
        access_log off;
        add_header Cache-Control "public";
    }
    
    location ~ /\. {
        deny  all;
    }
}

EOF

rm /var/www/html/*nginx*.html
mkdir -p /etc/nginx/ssl
ln -sf /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/nginx/ssl/fullchain.pem
ln -sf /etc/ssl/private/ssl-cert-snakeoil.key /etc/nginx/ssl/privkey.pem

mysql -uroot -e "CREATE USER 'freescout'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';
GRANT USAGE ON * . * TO 'freescout'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0 ;
CREATE DATABASE IF NOT EXISTS freescout;
GRANT ALL PRIVILEGES ON freescout . * TO 'freescout'@'localhost';"

curl -s https://api.github.com/repos/freescout-helpdesk/freescout/releases/latest | grep tarball_url | cut -d '"' -f 4 | wget -O $webroot/freescout.tar.gz -i -
cd $webroot
tar -vxf freescout.tar.gz
dir=$(ls -d freescout-helpdesk-freescout*)
mv -v $dir freescout
chown -R www-data:www-data /var/www/html
find /var/www/html -type f -exec chmod 664 {} \;    
find /var/www/html -type d -exec chmod 775 {} \;
cd $webroot/freescout
APP_KEY=$(sudo -u www-data php artisan key:generate --show)
sudo -u www-data sed -e "s|APP_URL=.*|APP_URL=https://${LXC_HOSTNAME}.${LXC_DOMAIN}|" -e "s|DB_DATABASE=|DB_DATABASE=freescout|" -e "s|DB_USERNAME=|DB_USERNAME=freescout|" -e "s|DB_PASSWORD=|DB_PASSWORD=${MYSQL_PASSWORD}|" -e "s|APP_KEY=|APP_KEY=${APP_KEY}|" .env.example > .env
sudo -u www-data php artisan freescout:clear-cache
sudo -u www-data php artisan storage:link
sudo -u www-data php artisan migrate -n --force
FS_PASSWORD=$(random_password)
sudo -u www-data php artisan freescout:create-user -n --role=admin --firstName=$FS_FIRSTNAME --lastName=$FS_LASTNAME --email=$FS_EMAIL --password=$FS_PASSWORD

cat << EOF > /etc/cron.d/freescout 
* * * * * www-data /bin/php /var/www/html/freescout/artisan schedule:run >> /dev/null 2>&1
EOF

systemctl enable --now php8.2-fpm
systemctl restart php8.2-fpm nginx

LXC_IP=$(ip address show dev eth0 | grep "inet " | cut -d ' ' -f6)

echo -e "Your freescout installation is now complete. Please continue with setup in your Browser:\nURL:\t\thttps://$(echo $LXC_IP | cut -d'/' -f1)\nLogin:\t\t$FS_EMAIL\nPassword:\t$FS_PASSWORD\n"