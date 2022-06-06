#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf
LXC_IP=$(hostname -I)
webroot=/var/www/html

MYSQL_PASSWORD="$(random_password_open3a)"

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq unzip sudo nginx-full mariadb-server mariadb-client php php-cli php-fpm php-mysql php-xml php-mbstring php-gd

mkdir /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout /etc/nginx/ssl/open3a.key -out /etc/nginx/ssl/open3a.crt -subj "/CN=$LXC_HOSTNAME.$LXC_DOMAIN" -addext "subjectAltName=DNS:$LXC_HOSTNAME.$LXC_DOMAIN"

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

    root $webroot;

    index index.php;

    ssl on;
    ssl_certificate /etc/nginx/ssl/open3a.crt;
    ssl_certificate_key /etc/nginx/ssl/open3a.key;

    location ~ .php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
    }
}

EOF

mysql -uroot -e "CREATE USER 'open3a'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';
GRANT USAGE ON * . * TO 'open3a'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0 ;
CREATE DATABASE IF NOT EXISTS open3a;
GRANT ALL PRIVILEGES ON open3a . * TO 'open3a'@'localhost';"

cd $webroot
wget https://www.open3a.de/download/open3A%203.5.zip -O $webroot/open3a.zip
unzip open3a.zip
rm open3a.zip
chmod 666 system/DBData/Installation.pfdb.php
chmod -R 777 specifics/
chmod -R 777 system/Backup
chown -R www-data:www-data $webroot

echo "sudo -u www-data /usr/bin/php $webroot/plugins/Installation/backup.php; for backup in \$(ls -r1 $webroot/system/Backup/*.gz | /bin/grep -v \$(date +%Y%m%d)); do /bin/rm \$backup;done" > /etc/cron.daily/open3a-backup
chmod +x /etc/cron.daily/open3a-backup

systemctl enable --now php7.4-fpm
systemctl restart php7.4-fpm nginx

cat << EOF >/var/www/html/system/DBData/Installation.pfdb.php
<?php echo "This is a database-file."; /*
host&%%%&user&%%%&password&%%%&datab&%%%&httpHost
varchar(40)&%%%&varchar(20)&%%%&varchar(20)&%%%&varchar(30)&%%%&varchar(40)                                                                                         
localhost                               &%%%&open3a              &%%%&$MYSQL_PASSWORD&%%%&open3a                        &%%%&*                                       %%&&&
*/ ?>
EOF

echo -e "Your open3a installation is now complete. Please continue with setup in your Browser:\nURL:\t\thttp://$(echo $LXC_IP | cut -d'/' -f1)\nLogin:\t\tAdmin\nPassword:\tAdmin\n\nMysql-Settings:\nServer:\t\tlocalhost\nUser:\t\topen3a\nPassword:\t$MYSQL_PASSWORD\nDatabase:\topen3a"
