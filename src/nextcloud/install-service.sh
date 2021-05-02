#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/zamba.conf
source /root/constants-service.conf

HOSTNAME=$(hostname -f)

wget -q -O - https://packages.sury.org/php/apt.gpg | apt-key add -
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list

wget -q -O - https://nginx.org/keys/nginx_signing.key | apt-key add -
echo "deb http://nginx.org/packages/debian $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list

wget -q -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq tree locate screen zip ffmpeg ghostscript libfile-fcntllock-perl libfuse2 socat fail2ban ldap-utils nfs-common cifs-utils redis-server imagemagick \
postgresql-13 nginx php$NEXTCLOUD_PHP_VERSION-{fpm,gd,mysql,pgsql,curl,xml,zip,intl,mbstring,bz2,ldap,apcu,bcmath,gmp,imagick,igbinary,redis,dev,smbclient,cli,common,opcache,readline}

timedatectl set-timezone Europe/Berlin
mkdir -p /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA /var/www
chown -R www-data:www-data /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA /var/www

#### Create database for nextcloud ####

su - postgres <<EOF
psql -c "CREATE USER $NEXTCLOUD_DB_USR WITH PASSWORD '$NEXTCLOUD_DB_PWD';"
psql -c "CREATE DATABASE $NEXTCLOUD_DB_NAME ENCODING UTF8 TEMPLATE template0 OWNER $NEXTCLOUD_DB_USR;"
echo "Postgres User $NEXTCLOUD_DB_USR and database $NEXTCLOUD_DB_NAME created."
EOF

#### Adjust php settings ####

cp /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf.bak
cp /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini.bak
cp /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini.bak
cp /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php-fpm.conf /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php-fpm.conf.bak
cp /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/apcu.ini /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/apcu.ini.bak
cp /etc/ImageMagick-6/policy.xml /etc/ImageMagick-6/policy.xml.bak
sed -i "s/;env\[HOSTNAME\] = /env[HOSTNAME] = /" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/;env\[TMP\] = /env[TMP] = /" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/;env\[TMPDIR\] = /env[TMPDIR] = /" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/;env\[TEMP\] = /env[TEMP] = /" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/;env\[PATH\] = /env[PATH] = /" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/pm.max_children =.*/pm.max_children = 120/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/pm.start_servers =.*/pm.start_servers = 12/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/pm.min_spare_servers =.*/pm.min_spare_servers = 6/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/pm.max_spare_servers =.*/pm.max_spare_servers = 18/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/;pm.max_requests =.*/pm.max_requests = 1000/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/allow_url_fopen =.*/allow_url_fopen = 1/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/output_buffering =.*/output_buffering = 'Off'/" /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini
sed -i "s/max_execution_time =.*/max_execution_time = 3600/" /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini
sed -i "s/max_input_time =.*/max_input_time = 3600/" /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini
sed -i "s/post_max_size =.*/post_max_size = 10240M/" /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini
sed -i "s/upload_max_filesize =.*/upload_max_filesize = 10240M/" /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini
sed -i "s/;date.timezone.*/date.timezone = Europe\/\Berlin/" /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini
sed -i "s/memory_limit = 128M/memory_limit = 1024M/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/output_buffering =.*/output_buffering = 'Off'/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/max_execution_time =.*/max_execution_time = 3600/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/max_input_time =.*/max_input_time = 3600/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/post_max_size =.*/post_max_size = 10240M/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/upload_max_filesize =.*/upload_max_filesize = 10240M/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;date.timezone.*/date.timezone = Europe\/\Berlin/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;session.cookie_secure.*/session.cookie_secure = True/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.enable=.*/opcache.enable=1/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.enable_cli=.*/opcache.enable_cli=1/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.memory_consumption=.*/opcache.memory_consumption=128/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=8/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=10000/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.revalidate_freq=.*/opcache.revalidate_freq=1/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.save_comments=.*/opcache.save_comments=1/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i '\$aapc.enable_cli=1' /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/apcu.ini
sed -i "s/rights=\"none\" pattern=\"PS\"/rights=\"read|write\" pattern=\"PS\"/" /etc/ImageMagick-6/policy.xml
sed -i "s/rights=\"none\" pattern=\"EPS\"/rights=\"read|write\" pattern=\"EPS\"/" /etc/ImageMagick-6/policy.xml
sed -i "s/rights=\"none\" pattern=\"PDF\"/rights=\"read|write\" pattern=\"PDF\"/" /etc/ImageMagick-6/policy.xml
sed -i "s/rights=\"none\" pattern=\"XPS\"/rights=\"read|write\" pattern=\"XPS\"/" /etc/ImageMagick-6/policy.xml

#### Adjust nginx settings ####

mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout /etc/ssl/private/nextcloud.key -out /etc/ssl/certs/nextcloud.crt -subj "/CN=$NEXTCLOUD_FQDN" -addext "subjectAltName=DNS:$NEXTCLOUD_FQDN"
openssl dhparam -dsaparam -out /etc/ssl/certs/dhparam.pem 4096

mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak


cat > /etc/nginx/nginx.conf <<EOF
user www-data;
worker_processes auto;
pid /var/run/nginx.pid;
events {
worker_connections 1024;
multi_accept on; use epoll;
}
http {
server_names_hash_bucket_size 64;
access_log /var/log/nginx/access.log;
error_log /var/log/nginx/error.log warn;
set_real_ip_from 127.0.0.1;
#optional, Sie können das eigene Subnetz ergänzen, bspw.:
# set_real_ip_from $LXC_IP;
real_ip_header X-Forwarded-For;
real_ip_recursive on;
include /etc/nginx/mime.types;
default_type application/octet-stream;
sendfile on;
send_timeout 3600;
tcp_nopush on;
tcp_nodelay on;
open_file_cache max=500 inactive=10m;
open_file_cache_errors on;
keepalive_timeout 65;
reset_timedout_connection on;
server_tokens off;
resolver 127.0.0.53 valid=30s;
resolver_timeout 5s;
include /etc/nginx/conf.d/*.conf;
}
EOF

[ -f /etc/nginx/conf.d/default.conf ] && mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
touch /etc/nginx/conf.d/default.conf

cat > /etc/nginx/conf.d/http.conf << EOF
upstream php-handler {
server unix:/run/php/php$NEXTCLOUD_PHP_VERSION-fpm.sock;
}
server {
listen 80 default_server;
listen [::]:80 default_server;
server_name $NEXTCLOUD_FQDN;
root /var/www;
location / {
return 301 https://\$host\$request_uri;
}
}
EOF

cat > /etc/nginx/conf.d/nextcloud.conf << EOF
server {
listen 443      ssl http2;
listen [::]:443 ssl http2;
server_name $NEXTCLOUD_FQDN;
ssl_certificate /etc/ssl/certs/nextcloud.crt;
ssl_certificate_key /etc/ssl/private/nextcloud.key;
ssl_trusted_certificate /etc/ssl/certs/nextcloud.crt;
#ssl_certificate /etc/letsencrypt/rsa-certs/fullchain.pem;
#ssl_certificate_key /etc/letsencrypt/rsa-certs/privkey.pem;
#ssl_certificate /etc/letsencrypt/ecc-certs/fullchain.pem;
#ssl_certificate_key /etc/letsencrypt/ecc-certs/privkey.pem;
#ssl_trusted_certificate /etc/letsencrypt/ecc-certs/chain.pem;
ssl_dhparam /etc/ssl/certs/dhparam.pem;
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:50m;
ssl_session_tickets off;
ssl_protocols TLSv1.3 TLSv1.2;
ssl_ciphers 'TLS-CHACHA20-POLY1305-SHA256:TLS-AES-256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384';
ssl_ecdh_curve X448:secp521r1:secp384r1;
ssl_prefer_server_ciphers on;
ssl_stapling on;
ssl_stapling_verify on;
client_max_body_size 5120M;
fastcgi_buffers 64 4K;
gzip on;
gzip_vary on;
gzip_comp_level 4;
gzip_min_length 256;
gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;
add_header Strict-Transport-Security            "max-age=15768000; includeSubDomains; preload;" always;
add_header Permissions-Policy                   "interest-cohort=()";
add_header Referrer-Policy                      "no-referrer"   always;
add_header X-Content-Type-Options               "nosniff"       always;
add_header X-Download-Options                   "noopen"        always;
add_header X-Frame-Options                      "SAMEORIGIN"    always;
add_header X-Permitted-Cross-Domain-Policies    "none"          always;
add_header X-Robots-Tag                         "none"          always;
add_header X-XSS-Protection                     "1; mode=block" always;
fastcgi_hide_header X-Powered-By;
fastcgi_read_timeout 3600;
fastcgi_send_timeout 3600;
fastcgi_connect_timeout 3600;
root /var/www/nextcloud;
index index.php index.html /index.php\$request_uri;
expires 1m;
location = / {
if ( \$http_user_agent ~ ^DavClnt ) {
return 302 /remote.php/webdav/\$is_args\$args;
}
}
location = /robots.txt {
allow all;
log_not_found off;
access_log off;
}
location ^~ /apps/rainloop/app/data {
deny all;
}
location ^~ /.well-known {
location = /.well-known/carddav     { return 301 /remote.php/dav/; }
location = /.well-known/caldav      { return 301 /remote.php/dav/; }
location ^~ /.well-known            { return 301 /index.php/\$uri; }
try_files \$uri \$uri/ =404;
}
location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:\$|/)  { return 404; }
location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console)                { return 404; }
location ~ \.php(?:\$|/) {
rewrite ^/(?!index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|oc[ms]-provider\/.+|.+\/richdocumentscode\/proxy) /index.php$request_uri;
fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
set \$path_info \$fastcgi_path_info;
try_files \$fastcgi_script_name =404;
include fastcgi_params;
fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
fastcgi_param PATH_INFO \$path_info;
fastcgi_param HTTPS on;
fastcgi_param modHeadersAvailable true;
fastcgi_param front_controller_active true;
fastcgi_pass php-handler;
fastcgi_intercept_errors on;
fastcgi_request_buffering off;
}
location ~ \.(?:css|js|svg|gif)\$ {
try_files \$uri /index.php\$request_uri;
expires 6M;
access_log off;
}
location ~ \.woff2?\$ {
try_files \$uri /index.php\$request_uri;
expires 7d;
access_log off;
}
location / {
try_files \$uri \$uri/ /index.php\$request_uri;
}
}
EOF

systemctl restart php$NEXTCLOUD_PHP_VERSION-fpm nginx

#### Adjust redis settings ####

cp /etc/redis/redis.conf /etc/redis/redis.conf.bak
sed -i "s/port 6379/port 0/" /etc/redis/redis.conf
sed -i s/\#\ unixsocket/\unixsocket/g /etc/redis/redis.conf
sed -i "s/unixsocketperm 700/unixsocketperm 770/" /etc/redis/redis.conf
sed -i "s/# maxclients 10000/maxclients 512/" /etc/redis/redis.conf
usermod -aG redis www-data

#### Adjust sysctl.conf settings ####

cp /etc/sysctl.conf /etc/sysctl.conf.bak
echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
systemctl restart redis

#### HIER MÜSSTE EIN REBOOT REIN ####


#### Install nextcloud ####

cd /usr/local/src

wget https://download.nextcloud.com/server/releases/latest.tar.bz2
wget https://download.nextcloud.com/server/releases/latest.tar.bz2.md5

md5sum -c latest.tar.bz2.md5 < latest.tar.bz2

tar -xjf latest.tar.bz2 -C /var/www && chown -R www-data:www-data /var/www/ && rm -f latest.tar.bz2

cat > /root/permissions.sh << EOF
#!/bin/bash
find /var/www/ -type f -print0 | xargs -0 chmod 0640
find /var/www/ -type d -print0 | xargs -0 chmod 0750
chown -R www-data:www-data /var/www 
chown -R www-data:www-data /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA
chmod 0644 /var/www/nextcloud/.htaccess
chmod 0644 /var/www/nextcloud/.user.ini
exit 0
EOF

chmod +x /root/permissions.sh
/root/permissions.sh

#### install fail2ban ####

cat <<EOF >/etc/fail2ban/filter.d/nextcloud.conf
[Definition]
_groupsre = (?:(?:,?\s*"\w+":(?:"[^"]+"|\w+))*)
failregex = ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Login failed:
            ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Trusted domain error.
datepattern = ,?\s*"time"\s*:\s*"%%Y-%%m-%%d[T ]%%H:%%M:%%S(%%z)?"
EOF

cat > /etc/fail2ban/jail.d/nextcloud.local << EOF
[nextcloud]
backend = auto
enabled = true
port = 80,443
protocol = tcp
filter = nextcloud
maxretry = 5
bantime = 3600
findtime = 36000
logpath = /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA/nextcloud.log 
EOF

systemctl restart fail2ban

#### Create configuration script for nextcloud, which will be executet as user www-data

cat > /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA/config_nextcloud.sh << DFOE

#!/bin/bash 

php /var/www/nextcloud/occ maintenance:install --database pgsql \
--database-host $NEXTCLOUD_DB_IP \
--database-port $NEXTCLOUD_DB_PORT \
--database-name $NEXTCLOUD_DB_NAME \
--database-user $NEXTCLOUD_DB_USR \
--database-pass $NEXTCLOUD_DB_PWD \
--admin-user $NEXTCLOUD_ADMIN_USR \
--admin-pass $NEXTCLOUD_ADMIN_PWD \
--data-dir /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA

php /var/www/nextcloud/occ config:system:set trusted_domains 0 --value=$NEXTCLOUD_FQDN
php /var/www/nextcloud/occ config:system:set overwrite.cli.url --value=https://$NEXTCLOUD_FQDN

cp /var/www/nextcloud/config/config.php /var/www/nextcloud/config/config.php.bak
sed -i 's/^[ ]*//' /var/www/nextcloud/config/config.php
sed -i '/);/d' /var/www/nextcloud/config/config.php

cat >> /var/www/nextcloud/config/config.php << EOF
'activity_expire_days' => 14,
'auth.bruteforce.protection.enabled' => true,
'blacklisted_files' => 
array (
0 => '.htaccess',
1 => 'Thumbs.db',
2 => 'thumbs.db',
),
'cron_log' => true,
'default_phone_region' => 'DE',
'enable_previews' => true,
'enabledPreviewProviders' => 
array (
0 => 'OC\Preview\PNG',
1 => 'OC\Preview\JPEG',
2 => 'OC\Preview\GIF',
3 => 'OC\Preview\BMP',
4 => 'OC\Preview\XBitmap',
5 => 'OC\Preview\Movie',
6 => 'OC\Preview\PDF',
7 => 'OC\Preview\MP3',
8 => 'OC\Preview\TXT',
9 => 'OC\Preview\MarkDown',
),
'filesystem_check_changes' => 0,
'filelocking.enabled' => 'true',
'htaccess.RewriteBase' => '/',
'integrity.check.disabled' => false,
'knowledgebaseenabled' => false,
'logfile' => '/var/$NEXTCLOUD_DATA/nextcloud.log',
'loglevel' => 2,
'logtimezone' => 'Europe/Berlin',
'log_rotate_size' => 104857600,
'maintenance' => false,
'memcache.local' => '\OC\Memcache\APCu',
'memcache.locking' => '\OC\Memcache\Redis',
'overwriteprotocol' => 'https',
'preview_max_x' => 1024,
'preview_max_y' => 768,
'preview_max_scale_factor' => 1,
'redis' => 
array (
'host' => '/var/run/redis/redis-server.sock',
'port' => 0,
'timeout' => 0.0,
),
'quota_include_external_storage' => false,
'share_folder' => '/Freigaben',
'skeletondirectory' => '',
'theme' => '',
'trashbin_retention_obligation' => 'auto, 7',
'updater.release.channel' => 'stable',
);
EOF

sed -i "s/output_buffering=.*/output_buffering=0/" /var/www/nextcloud/.user.ini
php /var/www/nextcloud/occ app:disable survey_client
php /var/www/nextcloud/occ app:disable firstrunwizard
php /var/www/nextcloud/occ app:enable admin_audit
php /var/www/nextcloud/occ app:enable files_pdfviewer
php /var/www/nextcloud/occ background:cron
DFOE

/root/permissions.sh

su -s /bin/bash www-data <<EOF
bash /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA/config_nextcloud.sh
EOF
echo "*/5 * * * * www-data php -f /var/www/nextcloud/cron.php > /dev/null 2>&1" > /etc/cron.d/nextcloud

echo -e "\n######################################################################\n\n    Please note this user and password for the nextcloud login:\n        '$NEXTCLOUD_ADMIN_USR' / '$NEXTCLOUD_ADMIN_PWD'\n                Enjoy your Nextcloud intallation.\n\n######################################################################"
systemctl stop nginx php$NEXTCLOUD_PHP_VERSION-fpm
systemctl restart postgresql php$NEXTCLOUD_PHP_VERSION-fpm redis-server nginx

exit 0
