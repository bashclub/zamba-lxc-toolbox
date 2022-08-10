#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

HOSTNAME=$(hostname -f)

wget -q -O - https://nginx.org/keys/nginx_signing.key | apt-key add -
echo "deb http://nginx.org/packages/debian $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list

wget -q -O - https://mariadb.org/mariadb_release_signing_key.asc | apt-key add -
echo "deb https://mirror.wtnet.de/mariadb/repo/$MARIA_DB_VERS/debian $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/maria.list

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends nginx-light mariadb-server mariadb-client ffmpeg memcached libmemcached-dev python3 python3-{pip,pil,ldap,urllib3,setuptools,mysqldb,memcache,requests} \

pip3 install --upgrade pip
pip3 install --timeout=3600 Pillow pylibmc captcha jinja2 sqlalchemy==1.4.3
pip3 install --timeout=3600 django-pylibmc django-simple-captcha python3-ldap mysqlclient

systemctl start memcached
systemctl enable memcached

#timedatectl set-timezone Europe/Berlin
#mkdir -p /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA /var/www
#chown -R www-data:www-data /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA /var/www

#### Secure Maria Instance ####

mysqladmin -u root password "[$MARIA_ROOT_PWD]"

mysql -uroot -p$MARIA_ROOT_PWD -e"DELETE FROM mysql.user WHERE User=''"
mysql -uroot -p$MARIA_ROOT_PWD -e"DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
mysql -uroot -p$MARIA_ROOT_PWD -e"DROP DATABASE test;DELETE FROM mysql.db WHERE Db='test' OR Db='test_%'"
mysql -uroot -p$MARIA_ROOT_PWD -e"FLUSH PRIVILEGES"

#### Create user and DB for Seafile ####

mysql -uroot -p$MARIA_ROOT_PWD -e"CREATE USER '$MARIA_DB_USER'@'localhost' IDENTIFIED BY '$MARIA_USER_PWD'"
mysql -uroot -p$MARIA_ROOT_PWD -e"CREATE DATABASE $MARIA_DB_NAME; GRANT ALL PRIVILEGES ON $MARIA_DB_NAME_SEAFILE.* TO '$MARIA_DB_USER'@'localhost'"
mysql -uroot -p$MARIA_ROOT_PWD -e"CREATE DATABASE $MARIA_DB_NAME; GRANT ALL PRIVILEGES ON $MARIA_DB_NAME_CCNET.* TO '$MARIA_DB_USER'@'localhost'"
mysql -uroot -p$MARIA_ROOT_PWD -e"CREATE DATABASE $MARIA_DB_NAME; GRANT ALL PRIVILEGES ON $MARIA_DB_NAME_SEAHUB.* TO '$MARIA_DB_USER'@'localhost'"
mysql -uroot -p$MARIA_ROOT_PWD -e"FLUSH PRIVILEGES"

echo "root-password: $MARIA_ROOT_PWD,\
db-user: $MARIA_DB_USER, password: $MARIA_USER_PWD" > /root/maria.log

#### Create Systemuer Seafile ####
sudo adduser --password $UNIX_USER_SEAFILE_PWD --home  /opt/seafile   $UNIX_USER_SEAFILE
chown -R $UNIX_USER_SEAFILE: /opt/seafile

apt update && apt full-upgrade -y


#### Adjust nginx settings ####


systemctl restart nginx

