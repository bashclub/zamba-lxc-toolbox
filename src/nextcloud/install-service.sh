#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

set -euo pipefail

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

NEXTCLOUD_ADMIN_PWD=$(random_password)
NEXTCLOUD_REDIS_PWD=$(random_password)
HOSTNAME=$(hostname -f)

#### Modify Nginx for Nextcloud ####
mod_nginx() {
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout /etc/ssl/private/nextcloud.key -out /etc/ssl/certs/nextcloud.crt -subj "/CN=$NEXTCLOUD_FQDN" -addext "subjectAltName=DNS:$NEXTCLOUD_FQDN"
generate_dhparam

mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak

cat > /etc/nginx/nginx.conf <<EOF
user www-data;
worker_processes auto;
pid /var/run/nginx.pid;
events {
  worker_connections 2048;
  multi_accept on;
  use epoll;
}
http {
  log_format criegerde escape=json
  '{'
    '"time_local":"\$time_local",'
    '"remote_addr":"\$remote_addr",'
    '"remote_user":"\$remote_user",'
    '"request":"\$request",'
    '"status": "\$status",'
    '"body_bytes_sent":"\$body_bytes_sent",'
    '"request_time":"\$request_time",'
    '"http_referrer":"\$http_referer",'
    '"http_user_agent":"\$http_user_agent"'
  '}';
  server_names_hash_bucket_size 64;
  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log warn;
  set_real_ip_from 127.0.0.1;
  # optional, set reverse proxy ip, if used:
  # set_real_ip_from $NEXTCLOUD_REVPROX;
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
  resolver $NEXTCLOUD_REVPROX valid=30s;
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
map \$arg_v \$asset_immutable {
  "" "";
  default "immutable";
}
server {
  listen 80 default_server;
  listen [::]:80 default_server;
  server_name $NEXTCLOUD_FQDN;
  root /var/www;
  location ^~ /.well-known/acme-challenge {
    default_type text/plain;
    root /var/www/letsencrypt;
  }
  location / {
    return 301 https://\$host\$request_uri;
  }  
}
EOF

cat > /etc/nginx/conf.d/nextcloud.conf << EOF
limit_req_zone \$binary_remote_addr zone=NextcloudRateLimit:10m rate=2r/s;
server {
  listen 443 ssl default_server;
  listen [::]:443 ssl default_server;
  http2 on;
  #listen 443 quic reuseport;
  #listen [::]:443 quic reuseport;
  #http3 on;
  #http3_hq on;
  #quic_retry on;
  server_name $NEXTCLOUD_FQDN;
  ssl_certificate /etc/ssl/certs/nextcloud.crt;
  ssl_certificate_key /etc/ssl/private/nextcloud.key;
  ssl_trusted_certificate /etc/ssl/certs/nextcloud.crt;
  #ssl_certificate /etc/letsencrypt/rsa-certs/fullchain.pem;
  #ssl_certificate_key /etc/letsencrypt/rsa-certs/privkey.pem;
  #ssl_certificate /etc/letsencrypt/ecc-certs/fullchain.pem;
  #ssl_certificate_key /etc/letsencrypt/ecc-certs/privkey.pem;
  #ssl_trusted_certificate /etc/letsencrypt/ecc-certs/chain.pem;
  ssl_dhparam /etc/nginx/dhparam.pem;
  ssl_session_timeout 1d;
  ssl_session_cache shared:SSL:50m;
  ssl_session_tickets off;
  ssl_protocols TLSv1.3 TLSv1.2;
  ssl_ciphers 'TLS-CHACHA20-POLY1305-SHA256:TLS-AES-256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384';
  ssl_prefer_server_ciphers on;
  ssl_stapling on;
  ssl_stapling_verify on;
  client_max_body_size 10G;
  client_body_timeout 3600s;
  client_body_buffer_size 512k;
  fastcgi_buffers 64 4K;
  gzip on;
  gzip_vary on;
  gzip_comp_level 4;
  gzip_min_length 256;
  gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
  gzip_types application/atom+xml text/javascript application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/wasm application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;
  add_header Strict-Transport-Security            "max-age=15768000; includeSubDomains; preload;" always;
  add_header Permissions-Policy                   "interest-cohort=()";
  add_header Referrer-Policy                      "no-referrer"   always;
  add_header X-Content-Type-Options               "nosniff"       always;
  add_header X-Download-Options                   "noopen"        always;
  add_header X-Frame-Options                      "SAMEORIGIN"    always;
  add_header X-Permitted-Cross-Domain-Policies    "none"          always;
  add_header X-Robots-Tag                         "noindex, nofollow" always;
  add_header X-XSS-Protection                     "1; mode=block" always;
  add_header Alt-Svc                              'h3=":\$server_port"; ma=86400';
  add_header x-quic                               'h3';
  add_header Alt-Svc                              'h3-29=":\$server_port"';
  fastcgi_hide_header X-Powered-By;
  include mime.types;
  types {
    text/javascript mjs;
  }
  root /var/www/nextcloud;
  index index.php index.html /index.php\$request_uri;
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
  location ^~ /.well-known {
    location = /.well-known/carddav { return 301 /remote.php/dav/; }
    location = /.well-known/caldav  { return 301 /remote.php/dav/; }
    location /.well-known/acme-challenge { try_files \$uri \$uri/ =404; }
    location /.well-known/pki-validation { try_files \$uri \$uri/ =404; }
    return 301 /index.php\$request_uri;
  }
  location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/)  { return 404; }
  location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console)                { return 404; }
  location ~ \.php(?:$|/) {
    rewrite ^/(?!index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|ocs-provider\/.+|.+\/richdocumentscode\/proxy) /index.php\$request_uri;
    fastcgi_split_path_info ^(.+?\.php)(/.*)$;
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
    fastcgi_read_timeout 3600;
    fastcgi_send_timeout 3600;
    fastcgi_connect_timeout 3600;
    fastcgi_max_temp_file_size 0;
  }
  location ~ \.(?:css|js|mjs|svg|gif|ico|jpg|png|webp|wasm|tflite|map|ogg|flac)$ {
    try_files \$uri /index.php\$request_uri;
    add_header Cache-Control                     "public, max-age=15768000, \$asset_immutable";
    add_header Permissions-Policy                "interest-cohort=()";
    add_header Referrer-Policy                   "no-referrer"       always;
    add_header X-Content-Type-Options            "nosniff"           always;
    add_header X-Frame-Options                   "SAMEORIGIN"        always;
    add_header X-Permitted-Cross-Domain-Policies "none"              always;
    add_header X-Robots-Tag                      "noindex, nofollow" always;
    add_header X-XSS-Protection                  "1; mode=block"     always;
    add_header Alt-Svc                           'h3=":\$server_port"; ma=86400';
    add_header x-quic                            'h3';
    add_header Alt-Svc                           'h3-29=":\$server_port"';
    access_log off;
    expires 6M;
    access_log off;
    location ~ \.wasm$ {
      default_type application/wasm;
    }
  }
  location ~ \.(otf|woff2?)$ {
    try_files \$uri /index.php\$request_uri;
    expires 7d;
    access_log off;
  }
  location /remote {
    return 301 /remote.php\$request_uri;
  }
  location /login {
    limit_req zone=NextcloudRateLimit burst=5 nodelay;
    limit_req_status 429;
    try_files \$uri \$uri/ /index.php\$request_uri;
  }
  location / {
    try_files \$uri \$uri/ /index.php\$request_uri;
  }
  location ^~ /push/ {
    proxy_pass http://127.0.0.1:7867/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}
EOF
}

#### Modify php settings for Nextcloud ####
mod_php() {
cp /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf.bak
cp /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini.bak
cp /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini.bak
cp /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php-fpm.conf /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php-fpm.conf.bak
cp /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/apcu.ini /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/apcu.ini.bak
cp /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/opcache.ini /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/opcache.ini.bak
cp /etc/ImageMagick-6/policy.xml /etc/ImageMagick-6/policy.xml.bak

sed -i "s/;env\[HOSTNAME\] = /env[HOSTNAME] = /" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/;env\[TMP\] = /env[TMP] = /" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/;env\[TMPDIR\] = /env[TMPDIR] = /" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/;env\[TEMP\] = /env[TEMP] = /" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/;env\[PATH\] = /env[PATH] = /" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/pm.max_children =.*/pm.max_children = 200/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/pm.start_servers =.*/pm.start_servers = 100/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/pm.min_spare_servers =.*/pm.min_spare_servers = 60/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/pm.max_spare_servers =.*/pm.max_spare_servers = 140/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/;pm.max_requests =.*/pm.max_requests = 1000/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/pool.d/www.conf
sed -i "s/allow_url_fopen =.*/allow_url_fopen = 1/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini

sed -i "s/output_buffering =.*/output_buffering = 'Off'/" /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini
sed -i "s/max_execution_time =.*/max_execution_time = 3600/" /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini
sed -i "s/max_input_time =.*/max_input_time = 3600/" /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini
sed -i "s/post_max_size =.*/post_max_size = 10G/" /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini
sed -i "s/upload_max_filesize =.*/upload_max_filesize = 10G/" /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini
sed -i "s|;date.timezone.*|date.timezone = $LXC_TIMEZONE|" /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini
sed -i "s/;cgi.fix_pathinfo.*/cgi.fix_pathinfo=0/" /etc/php/$NEXTCLOUD_PHP_VERSION/cli/php.ini

sed -i "s/memory_limit = 128M/memory_limit = 1G/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/output_buffering =.*/output_buffering = 'Off'/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/max_execution_time =.*/max_execution_time = 3600/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/max_input_time =.*/max_input_time = 3600/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/post_max_size =.*/post_max_size = 10G/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/upload_max_filesize =.*/upload_max_filesize = 10G/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s|;date.timezone.*|date.timezone = $LXC_TIMEZONE|" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;session.cookie_secure.*/session.cookie_secure = True/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.enable=.*/opcache.enable=1/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.validate_timestamps=.*/opcache.validate_timestamps=1/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.enable_cli=.*/opcache.enable_cli=1/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.memory_consumption=.*/opcache.memory_consumption=256/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=64/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=100000/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.revalidate_freq=.*/opcache.revalidate_freq=0/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.save_comments=.*/opcache.save_comments=1/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini
sed -i "s/;opcache.huge_code_pages=.*/opcache.huge_code_pages=0/" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php.ini

sed -i "s|;emergency_restart_threshold.*|emergency_restart_threshold = 10|g" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php-fpm.conf
sed -i "s|;emergency_restart_interval.*|emergency_restart_interval = 1m|g" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php-fpm.conf
sed -i "s|;process_control_timeout.*|process_control_timeout = 10|g" /etc/php/$NEXTCLOUD_PHP_VERSION/fpm/php-fpm.conf

sed -i '$aapc.enable_cli=1' /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/apcu.ini

sed -i 's/opcache.jit=off/opcache.jit=on/' /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/opcache.ini
sed -i '$aopcache.jit=1255' /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/opcache.ini
sed -i '$aopcache.jit_buffer_size=256M' /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/opcache.ini

sed -i "s/rights=\"none\" pattern=\"PS\"/rights=\"read|write\" pattern=\"PS\"/" /etc/ImageMagick-6/policy.xml
sed -i "s/rights=\"none\" pattern=\"EPS\"/rights=\"read|write\" pattern=\"EPS\"/" /etc/ImageMagick-6/policy.xml
sed -i "s/rights=\"none\" pattern=\"PDF\"/rights=\"read|write\" pattern=\"PDF\"/" /etc/ImageMagick-6/policy.xml
sed -i "s/rights=\"none\" pattern=\"XPS\"/rights=\"read|write\" pattern=\"XPS\"/" /etc/ImageMagick-6/policy.xml

sed -i '$apgsql.allow_persistent = On' /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/pgsql.ini
sed -i '$apgsql.auto_reset_persistent = Off' /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/pgsql.ini
sed -i '$apgsql.max_persistent = -1' /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/pgsql.ini
sed -i '$apgsql.max_links = -1' /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/pgsql.ini
sed -i '$apgsql.ignore_notice = 0' /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/pgsql.ini
sed -i '$apgsql.log_notice = 0' /etc/php/$NEXTCLOUD_PHP_VERSION/mods-available/pgsql.ini
}

#### Modify Postgresql for Nextcloud ####
mod_postgresql() {
su - postgres <<EOF
    psql -c "CREATE USER $NEXTCLOUD_DB_USR WITH PASSWORD '$NEXTCLOUD_DB_PWD';"
    psql -c "CREATE DATABASE $NEXTCLOUD_DB_NAME ENCODING UTF8 TEMPLATE template0 OWNER $NEXTCLOUD_DB_USR;"
    echo "Postgres User $NEXTCLOUD_DB_USR and database $NEXTCLOUD_DB_NAME created."
EOF
    cat > /etc/postgresql/$POSTGRES_VERSION/main/conf.d/nextcloud.conf <<EOF
    max_connections = 200
    shared_buffers = 1GB
    effective_cache_size = 3GB
    maintenance_work_mem = 256MB
    checkpoint_completion_target = 0.9
    wal_buffers = 16MB
    default_statistics_target = 100
    random_page_cost = 1.1
    effective_io_concurrency = 200
    work_mem = 2621kB
    min_wal_size = 1GB
    max_wal_size = 4GB
    max_worker_processes = 4
    max_parallel_workers_per_gather = 2
    max_parallel_workers = 4
    max_parallel_maintenance_workers = 2
EOF
}

#### Install and modify Redis-server ####
inst_redis() {
    apt update && DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends redis-server
}
mod_redis() {
cp /etc/redis/redis.conf /etc/redis/redis.conf.bak
sed -i "s/port 6379/port 0/" /etc/redis/redis.conf
sed -i s/\#\ unixsocket/\unixsocket/g /etc/redis/redis.conf
sed -i "s/unixsocketperm 700/unixsocketperm 770/" /etc/redis/redis.conf
sed -i "s/# maxclients 10000/maxclients 10240/" /etc/redis/redis.conf
sed -i "s/# requirepass foobared/requirepass $NEXTCLOUD_REDIS_PWD/" /etc/redis/redis.conf
usermod -aG redis www-data
cp /etc/sysctl.conf /etc/sysctl.conf.bak
sed -i '$avm.overcommit_memory = 1' /etc/sysctl.conf
}

#### Install some more packages
inst_packages() {
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends tree ldap-utils cifs-utils locate screen zip ffmpeg ghostscript libfile-fcntllock-perl libfuse2 socat imagemagick libmagickcore-6.q16-6-extra
timedatectl set-timezone $LXC_TIMEZONE
mkdir -p /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA /var/www /etc/letsencrypt
chown -R www-data:www-data /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA /var/www
}

#### Install and modify Nextcloud ####
inst_nextcloud() {
cd /usr/local/src
wget https://download.nextcloud.com/server/releases/latest.tar.bz2
wget https://download.nextcloud.com/server/releases/latest.tar.bz2.md5

md5sum -c --ignore-missing latest.tar.bz2.md5 < latest.tar.bz2
tar -xjf latest.tar.bz2 -C /var/www && chown -R www-data:www-data /var/www/ && rm -f latest.tar.bz2*

cat > /root/permissions.sh << EOF
#!/bin/bash
find /var/www/ -type f -print0 | xargs -0 chmod 0640
find /var/www/ -type d -print0 | xargs -0 chmod 0750
if [ -d "/var/www/nextcloud/apps/notify_push" ]; then
chmod ug+x /var/www/nextcloud/apps/notify_push/bin/x86_64/notify_push
fi
chmod -R 770 /etc/letsencrypt 
chown -R www-data:www-data /var/www
chown -R www-data:www-data /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA
chmod 0644 /var/www/nextcloud/.htaccess
chmod 0644 /var/www/nextcloud/.user.ini
exit 0
EOF

chmod +x /root/permissions.sh
/root/permissions.sh
}

#### Create configuration script for nextcloud, which will be executet as user www-data
mod_nextcloudconfig() {

systemctl stop nginx

sudo -u www-data /usr/bin/php /var/www/nextcloud/occ maintenance:install --database pgsql \
--database-host $NEXTCLOUD_DB_IP \
--database-port $NEXTCLOUD_DB_PORT \
--database-name $NEXTCLOUD_DB_NAME \
--database-user $NEXTCLOUD_DB_USR \
--database-pass $NEXTCLOUD_DB_PWD \
--admin-user $NEXTCLOUD_ADMIN_USR \
--admin-pass $NEXTCLOUD_ADMIN_PWD \
--data-dir /$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA

sudo -u www-data cp /var/www/nextcloud/config/config.php /var/www/nextcloud/config/config.php.bak
sed -i '/);/d' /var/www/nextcloud/config/config.php
sed -i 's/^[ ]*//' /var/www/nextcloud/config/config.php
sed -i "s/output_buffering=.*/output_buffering=0/" /var/www/nextcloud/.user.ini


cat >> /var/www/nextcloud/config/config.php << EOF
  'activity_expire_days' => 14,
  'allow_local_remote_servers' => true,
  'auth.bruteforce.protection.enabled' => true,
  'forbidden_filenames' =>
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
    0 => 'OC\\Preview\\PNG',
    1 => 'OC\\Preview\\JPEG',
    2 => 'OC\\Preview\\GIF',
    3 => 'OC\\Preview\\BMP',
    4 => 'OC\\Preview\\XBitmap',
    5 => 'OC\\Preview\\Movie',
    6 => 'OC\\Preview\\PDF',
    7 => 'OC\\Preview\\MP3',
    8 => 'OC\\Preview\\TXT',
    9 => 'OC\\Preview\\MarkDown',
    10 => 'OC\\Preview\\HEIC',
    11 => 'OC\\Preview\\Movie',
    12 => 'OC\\Preview\\MKV',
    13 => 'OC\\Preview\\MP4',
    14 => 'OC\\Preview\\AVI',
    ),
  'filesystem_check_changes' => 0,
  'filelocking.enabled' => 'true',
  'htaccess.RewriteBase' => '/',
  'integrity.check.disabled' => false,
  'knowledgebaseenabled' => false,
  'logfile' => '/$LXC_SHAREFS_MOUNTPOINT/$NEXTCLOUD_DATA/nextcloud.log',
  'loglevel' => 2,
  'logtimezone' => '$LXC_TIMEZONE',
  'log_rotate_size' => 104857600,
  'memcache.local' => '\OC\Memcache\APCu',
  'memcache.locking' => '\OC\Memcache\Redis',
  'overwriteprotocol' => 'https',
  'preview_max_x' => 1024,
  'preview_max_y' => 768,
  'preview_max_scale_factor' => 1,
  'profile.enabled' => false,
  'redis' => 
  array (
    'host' => '/run/redis/redis-server.sock',
    'port' => 0,
    'password' => '$NEXTCLOUD_REDIS_PWD',
    'timeout' => 0.0,
  ),
  'quota_include_external_storage' => false,
  'share_folder' => '/Freigaben',
  'skeletondirectory' => '',
  'theme' => '',
  'trashbin_retention_obligation' => 'auto, 7',
  'updater.release.channel' => 'stable',
  'maintenance_window_start' => 1,
  'maintenance' => false,
  'mail_smtpmode' => 'sendmail',
  'mail_sendmailmode' => 'smtp',
  'mail_from_address' => '$NEXTCLOUD_ADMIN_USR',
  'mail_domain' => '$NEXTCLOUD_FQDN',
  'overwrite.cli.url' => 'https://$NEXTCLOUD_FQDN',
  'overwritehost' => '$NEXTCLOUD_FQDN',
  'trusted_domains' => 
  array (
    0 => '$LXC_IP',
    1 => '$NEXTCLOUD_FQDN',
  ),

);
EOF

/root/permissions.sh

sudo -u www-data /usr/bin/cp /var/www/nextcloud/config/config.php /var/www/nextcloud/config/config.php.bak
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ app:disable survey_client
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ app:disable firstrunwizard
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ app:enable admin_audit
#sudo -u www-data /usr/bin/php /var/www/nextcloud/occ app:enable notify_push
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ background:cron
sudo -u www-data /usr/bin/php /var/www/nextcloud/occ db:add-missing-indices
sudo -u www-data nohup /usr/bin/php /var/www/nextcloud/occ maintenance:repair --include-expensive &
sed -i 's/^[ ]*//' /var/www/nextcloud/config/config.php
sed -i "s/output_buffering=.*/output_buffering=0/" /var/www/nextcloud/.user.ini

echo "*/5 * * * * www-data /usr/bin/php -f /var/www/nextcloud/cron.php > /dev/null 2>&1" > /etc/cron.d/nextcloud

systemctl restart php$NEXTCLOUD_PHP_VERSION-fpm
systemctl start nginx

cat > /etc/systemd/system/notify_push.service << EOF
[Unit]
Description = Push daemon for Nextcloud clients
After=nginx.service php$NEXTCLOUD_PHP_VERSION-fpm.service system-postgresql.slice redis-server.service

[Service]
Environment=PORT=7867
Environment=NEXTCLOUD_URL=https://$NEXTCLOUD_FQDN
Environment=ALLOW_SELF_SIGNED=true
ExecStart=/var/www/nextcloud/apps/notify_push/bin/x86_64/notify_push /var/www/nextcloud/config/config.php
User=www-data

[Install]
WantedBy = multi-user.target
EOF

systemctl daemon-reload
systemctl enable notify_push
}

#### Modifying Crowdsec ####
mod_crowdsec() {
cscli collections install crowdsecurity/nginx
cscli collections install crowdsecurity/nextcloud
cscli collections install crowdsecurity/sshd

cat >> /etc/crowdsec/acquis.yaml << EOF
filenames:
 - /var/log/nextcloud/nextcloud.log
labels:
  type: Nextcloud
---
EOF
systemctl reload crowdsec
}
#### Install the system !####
echo "=> Installing Nginx ..."
inst_nginx
echo "=> Modifying Nginx config for Nextcloud ..."
mod_nginx

echo "=> Installing PHP $NEXTCLOUD_PHP_VERSION ..."
inst_php
echo "=> Modifying PHP config for Nextcloud ..."
mod_php

echo "=> Installing Postgresql $POSTGRES_VERSION ..."
inst_postgresql
echo "=> Modifying Postgresql config for Nextcloud ..."
mod_postgresql

echo "=> Installing Redis-server ..."
inst_redis
echo "=> Modifying Redis-server for Nextcloud ..."
mod_redis

echo "=> Installing some more packages ..."
inst_packages

echo "=> Installing Nextcloud ..."
inst_nextcloud
echo "=> Modifying Nextcloud ..."
mod_nextcloudconfig

echo "=> Installing Crowdsec ..."
inst_crowdsec
echo "=> Modifying Crowdsec ..."
mod_crowdsec

echo -e "\n######################################################################\n\n    Please note this user and password for the nextcloud login:\n        '$NEXTCLOUD_ADMIN_USR' / '$NEXTCLOUD_ADMIN_PWD'\n                Enjoy your Nextcloud intallation.\n\n######################################################################"
shutdown -r now
