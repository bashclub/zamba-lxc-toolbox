#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/zamba.conf
source /root/constants-service.conf

HOSTNAME=$(hostname -f)

wget -q -O - https://packages.sury.org/php/apt.gpg | apt-key add -
echo "deb https://packages.sury.org/php/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/php.list

wget -q -O - https://nginx.org/keys/nginx_signing.key | apt-key add -
echo "deb http://nginx.org/packages/debian $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list

wget -q -O - https://mariadb.org/mariadb_release_signing_key.asc | apt-key add -
echo "deb https://mirror.wtnet.de/mariadb/repo/$MARIA_DB_VERS/debian $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/maria.list

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends nginx-light mariadb-server postfix postfix-ldap \
php$KOPANO_PHP_VERSION-{cli,common,curl,fpm,gd,json,mysql,mbstring,opcache,phpdbg,readline,soap,xml,zip}

#timedatectl set-timezone Europe/Berlin
#mkdir -p /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA /var/www
#chown -R www-data:www-data /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA /var/www

#### Secure Maria Instance ####

mysqladmin -u root password "[$MARIA_ROOT_PWD]"

mysql -uroot -p$MARIA_ROOT_PWD -e"DELETE FROM mysql.user WHERE User=''"
mysql -uroot -p$MARIA_ROOT_PWD -e"DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
mysql -uroot -p$MARIA_ROOT_PWD -e"DROP DATABASE test;DELETE FROM mysql.db WHERE Db='test' OR Db='test_%'"
mysql -uroot -p$MARIA_ROOT_PWD -e"FLUSH PRIVILEGES"

#### Create user and DB for Kopano ####

mysql -uroot -p$MARIA_ROOT_PWD -e"CREATE USER '$MARIA_DB_USER'@'localhost' IDENTIFIED BY '$MARIA_USER_PWD'"
mysql -uroot -p$MARIA_ROOT_PWD -e"CREATE DATABASE $MARIA_DB_NAME; GRANT ALL PRIVILEGES ON $MARIA_DB_NAME.* TO '$MARIA_DB_USER'@'localhost'"
mysql -uroot -p$MARIA_ROOT_PWD -e"FLUSH PRIVILEGES"

echo "root-password: $MARIA_ROOT_PWD,\
db-user: $MARIA_DB_USER, password: $MARIA_USER_PWD" > /root/maria.log

cat > /etc/apt/sources.list.d/kopano.list << EOF

# Kopano Core
deb https://download.kopano.io/supported/core:/final/Debian_10/ ./

# Kopano WebApp
deb https://download.kopano.io/supported/webapp:/final/Debian_10/ ./

# Kopano MobileDeviceManagement
deb https://download.kopano.io/supported/mdm:/final/Debian_10/ ./

# Kopano Files
deb https://download.kopano.io/supported/files:/final/Debian_10/ ./

# Z-Push
deb https://download.kopano.io/zhub/z-push:/final/Debian_10/ ./

EOF

cat > /etc/apt/auth.conf.d/kopano.conf << EOF

machine download.kopano.io
login serial
password $KOPANO_REPKEY

EOF

curl https://serial:$KOPANO_REPKEY@download.kopano.io/supported/core:/final/Debian_10/Release.key | apt-key add -
curl https://serial:$KOPANO_REPKEY@download.kopano.io/supported/webapp:/final/Debian_10/Release.key | apt-key add -
curl https://serial:$KOPANO_REPKEY@download.kopano.io/supported/mdm:/final/Debian_10/Release.key | apt-key add -
curl https://serial:$KOPANO_REPKEY@download.kopano.io/supported/files:/final/Debian_10/Release.key | apt-key add -
curl https://serial:$KOPANO_REPKEY@download.kopano.io/zhub/z-push:/final/Debian_10/Release.key | apt-key add -

apt update && apt full-upgrade -y

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends kopano-server-packages kopano-webapp \
z-push-kopano z-push-config-nginx kopano-webapp-plugin-mdm kopano-webapp-plugin-files 

#### Adjust nginx settings ####

openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout /etc/ssl/private/kopano.key -out /etc/ssl/certs/kopano.crt -subj "/CN=$KOPANO_FQDN" -addext "subjectAltName=DNS:$KOPANO_FQDN"
openssl dhparam -dsaparam -out /etc/ssl/certs/dhparam.pem 4096

mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak


