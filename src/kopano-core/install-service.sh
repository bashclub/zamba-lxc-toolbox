#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

HOSTNAME=$(hostname -f)

#wget -q -O - https://packages.sury.org/php/apt.gpg | apt-key add -
#echo "deb https://packages.sury.org/php/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/php.list

wget -q -O - https://nginx.org/keys/nginx_signing.key | apt-key add -
echo "deb http://nginx.org/packages/debian $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list

wget -q -O - https://mariadb.org/mariadb_release_signing_key.asc | apt-key add -
echo "deb https://mirror.wtnet.de/mariadb/repo/$MARIA_DB_VERS/debian $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/maria.list

apt update

#DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends nginx-light mariadb-server postfix postfix-ldap \
#php$KOPANO_PHP_VERSION-{cli,common,curl,fpm,gd,json,mysql,mbstring,opcache,phpdbg,readline,soap,xml,zip}
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends nginx-light mariadb-server postfix postfix-ldap \
php-{cli,common,curl,fpm,gd,json,mysql,mbstring,opcache,phpdbg,readline,soap,xml,zip}

#timedatectl set-timezone Europe/Berlin
#mkdir -p /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA /var/www
#chown -R www-data:www-data /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA /var/www

#### Secure Maria Instance ####

mysqladmin -u root password "[$MARIA_ROOT_PWD]"

mysql -uroot -p$MARIA_ROOT_PWD -e"DELETE FROM mysql.user WHERE User=''"
mysql -uroot -p$MARIA_ROOT_PWD -e"DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
#mysql -uroot -p$MARIA_ROOT_PWD -e"DROP DATABASE test;DELETE FROM mysql.db WHERE Db='test' OR Db='test_%'"
mysql -uroot -p$MARIA_ROOT_PWD -e"FLUSH PRIVILEGES"

#### Create user and DB for Kopano ####

mysql -uroot -p$MARIA_ROOT_PWD -e"CREATE USER '$MARIA_DB_USER'@'localhost' IDENTIFIED BY '$MARIA_USER_PWD'"
mysql -uroot -p$MARIA_ROOT_PWD -e"CREATE DATABASE $MARIA_DB_NAME; GRANT ALL PRIVILEGES ON $MARIA_DB_NAME.* TO '$MARIA_DB_USER'@'localhost'"
mysql -uroot -p$MARIA_ROOT_PWD -e"FLUSH PRIVILEGES"

echo "root-password: $MARIA_ROOT_PWD,\
db-user: $MARIA_DB_USER, password: $MARIA_USER_PWD" > /root/maria.log

cat > /etc/apt/sources.list.d/kopano.list << EOF

# Kopano Core
deb https://download.kopano.io/supported/core:/final/Debian_11/ ./

# Kopano WebApp
deb https://download.kopano.io/supported/webapp:/final/Debian_11/ ./

# Kopano MobileDeviceManagement
deb https://download.kopano.io/supported/mdm:/final/Debian_11/ ./

# Kopano Files
deb https://download.kopano.io/supported/files:/final/Debian_11/ ./

# Z-Push
deb https://download.kopano.io/zhub/z-push:/final/Debian_11/ ./

EOF

cat > /etc/apt/auth.conf.d/kopano.conf << EOF

machine download.kopano.io
login serial
password $KOPANO_REPKEY

EOF

curl https://serial:$KOPANO_REPKEY@download.kopano.io/supported/core:/final/Debian_11/Release.key | apt-key add -
curl https://serial:$KOPANO_REPKEY@download.kopano.io/supported/webapp:/final/Debian_11/Release.key | apt-key add -
curl https://serial:$KOPANO_REPKEY@download.kopano.io/supported/mdm:/final/Debian_11/Release.key | apt-key add -
curl https://serial:$KOPANO_REPKEY@download.kopano.io/supported/files:/final/Debian_11/Release.key | apt-key add -
curl https://serial:$KOPANO_REPKEY@download.kopano.io/zhub/z-push:/final/Debian_11/Release.key | apt-key add -

apt update && apt full-upgrade -y

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends kopano-server-packages kopano-webapp \
z-push-kopano z-push-config-nginx kopano-webapp-plugin-mdm kopano-webapp-plugin-files 

#### Adjust kopano settings ####

cat > /etc/kopano/ldap.cfg << EOF

!include /usr/share/kopano/ldap.active-directory.cfg

ldap_uri = ldap://192.168.100.100:389
ldap_bind_user = cn=zmb-ldap,cn=Users,dc=zmb,dc=rocks
ldap_bind_passwd = Start123!
ldap_search_base = dc=zmb,dc=rocks

#ldap_user_search_filter = (kopanoAccount=1)

EOF

cat > /etc/kopano/server.cfg << EOF

server_listen = *:236
local_admin_users = root kopano

#database_engine = mysql
#mysql_host = localhost
#mysql_port = 3306
mysql_user = $MARIA_DB_USER
mysql_password = $MARIA_USER_PWD
mysql_database = $MARIA_DB_NAME

#user_plugin = ldap
#user_plugin_config = /etc/kopano/ldap.cfg

EOF

#### Adjust php settings ####

sed -i "s/define('LANG', 'en_US.UTF-8')/define('LANG', 'de_DE.UTF-8')/" /etc/kopano/webapp/config.php

cat > /etc/php/7.4/fpm/pool.d/webapp.conf << EOF

[webapp]
listen = 127.0.0.1:9002
user = www-data
group = www-data
listen.allowed_clients = 127.0.0.1
pm = dynamic
pm.max_children = 150
pm.start_servers = 35
pm.min_spare_servers = 20
pm.max_spare_servers = 50
pm.max_requests = 200
listen.backlog = -1
request_terminate_timeout = 120s
rlimit_files = 131072
rlimit_core = unlimited
catch_workers_output = yes

EOF

sed -i "s/define('LANG', 'en_US.UTF-8')/define('LANG', 'de_DE.UTF-8')/" /etc/kopano/webapp/config.php

#### Adjust nginx settings ####

openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout /etc/ssl/private/kopano.key -out /etc/ssl/certs/kopano.crt -subj "/CN=$KOPANO_FQDN" -addext "subjectAltName=DNS:$KOPANO_FQDN"
openssl dhparam -dsaparam -out /etc/ssl/certs/dhparam.pem 4096

#mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak

cat > /etc/nginx/sites-available/webapp.conf << EOF
upstream php-handler {
    #server 127.0.0.1:9002;
    #server unix:/var/run/php5-fpm.sock;
    server unix:/var/run/php/php7.4-fpm.sock;
}
 
server{
    listen 80;
    charset utf-8;
    listen [::]:80;
    server_name _;
 
    location / {
        rewrite   ^(.*)   https://\$server_name\$1 permanent;
    }  
 }
 
server {
    charset utf-8;
    listen 443;
    listen [::]:443 ssl;
    server_name _;
    ssl on;
    client_max_body_size 1024m;
    ssl_certificate /etc/ssl/certs/kopano.crt;
    ssl_certificate_key /etc/ssl/private/kopano.key;
    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout 5m;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256;
    ssl_prefer_server_ciphers on;
    #
    # ssl_dhparam require you to create a dhparam.pem, this takes a long time
    ssl_dhparam /etc/ssl/certs/dhparam.pem;
    #
 
    # add headers
    server_tokens off;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
  
    location /webapp {
        alias /usr/share/kopano-webapp/;
        index index.php;
     
    location ~ /webapp/presence/ {
                rewrite ^/webapp/presence(/.*)$ \$1 break;
                proxy_pass http://localhost:1234;
                proxy_set_header Upgrade \$http_upgrade;
                proxy_set_header Connection "upgrade";
                proxy_http_version 1.1;
                }
 
    }
 
    location ~* ^/webapp/(.+\.php)$ {
        alias /usr/share/kopano-webapp/;
 
        # deny access to .htaccess files
        location ~ /\.ht {
                    deny all;
        }
  
        fastcgi_param PHP_VALUE "
            register_globals=off
            magic_quotes_gpc=off
            magic_quotes_runtime=off
            post_max_size=31M
            upload_max_filesize=30M
        ";
        fastcgi_param PHP_VALUE "post_max_size=31M
                 upload_max_filesize=30M
                 max_execution_time=3660
        ";
 
        include fastcgi_params;
        fastcgi_index index.php;
        #fastcgi_param HTTPS on;
        fastcgi_param SCRIPT_FILENAME \$document_root\$1;
        fastcgi_pass php-handler;
        access_log /var/log/nginx/kopano-webapp-access.log;
        error_log /var/log/nginx/kopano-webapp-error.log;
 
        # CSS and Javascript
        location ~* \.(?:css|js)$ {
            expires 1y;
            access_log off;
            add_header Cache-Control "public";
        }
 
        # All (static) resources set to 2 months expiration time.
        location ~* \.(?:jpg|gif|png)\$ {
            expires 2M;
            access_log off;
            add_header Cache-Control "public";
        }
 
        # enable gzip compression
        gzip on;
        gzip_min_length  1100;
        gzip_buffers  4 32k;
        gzip_types    text/plain application/x-javascript text/xml text/css application/json;
        gzip_vary on;
        }
 
}
 
map \$http_upgrade \$connection_upgrade {
        default upgrade;
        '' close;
}
EOF



ln -s /etc/nginx/sites-available/webapp.conf /etc/nginx/sites-enabled/

phpenmod kopano
systemctl restart php7.4-fpm nginx
