#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/zamba.conf
source /root/constants-service.conf

MYSQL_PASSWORD="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)"

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq unzip sudo nginx-full mariadb-server mariadb-client php php-cli php-fpm php-mysql php-xml php-mbstring php-gd

cat << EOF > /etc/nginx/sites-available/default
server {
        listen 80 default_server;
        listen [::]:80 default_server;

        root /var/www/html;

        index index.php;

        server_name _;

        location ~ .php$ {
                include snippets/fastcgi-php.conf;
                fastcgi_pass unix:/var/run/php/php7.3-fpm.sock;
        }
}
EOF

mysql -uroot -e "CREATE USER 'open3a'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';
GRANT USAGE ON * . * TO 'open3a'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0 ;
CREATE DATABASE IF NOT EXISTS open3a;
GRANT ALL PRIVILEGES ON open3a . * TO 'open3a'@'localhost';"

cd /var/www/html/
wget https://www.open3a.de/download/open3A%203.4.zip -O open3a.zip
unzip open3a.zip
rm open3a.zip
chmod 666 system/DBData/Installation.pfdb.php
chmod -R 777 specifics/
chmod -R 777 system/Backup
chown -R www-data:www-data /var/www/html

echo "sudo -u www-data /usr/bin/php /var/www/html/plugins/Installation/backup.php; for backup in $(ls -r1 /var/www/html/system/Backup/*.gz | /bin/grep -v $(date +%Y%m%d)); do /bin/rm $backup;done" > /etc/cron.daily/open3a-backup
chmod +x /etc/cron.daily/open3a-backup

systemctl enable --now php7.3-fpm
systemctl restart nginx

echo -e "Your open3a installation is now complete. Please continue with setup in your Browser:\nURL:\t\thttp://$LXC_IP\nLogin:\t\tAdmin\nPassword:\tAdmin\n\nMysql-Settings:\nServer:\t\tlocalhost\nUser:\t\topen3a\nPassword:\t$MYSQL_PASSWORD\nDatabase:\topen3a"
