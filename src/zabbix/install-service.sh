#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

set -euo pipefail

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

apt_repo "zabbix" "https://repo.zabbix.com/zabbix-official-repo.key" "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/debian/ $(lsb_release -cs) main"
apt_repo "postgresql" "https://www.postgresql.org/media/keys/ACCC4CF8.asc" "http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main"
apt_repo "timescaledb" "https://packagecloud.io/timescale/timescaledb/gpgkey" "https://packagecloud.io/timescale/timescaledb/debian/ $(lsb_release -c -s) main"

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install --no-install-recommends postgresql-$POSTGRES_VERSION timescaledb-2-oss-$TS_VERSION-postgresql-$POSTGRES_VERSION postgresql-client timescaledb-tools nginx php$PHP_VERSION-pgsql php$PHP_VERSION-fpm zabbix-server-pgsql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent ssl-cert

unlink /etc/nginx/sites-enabled/default

cat << EOF > /etc/zabbix/nginx.conf
server {
        listen          80 default_server;
        listen          [::]:80 default_server;
        server_name _;

        server_tokens off;

        access_log /var/log/nginx/zabbix.access.log;
        error_log /var/log/nginx/zabbix.error.log;

        location /.well-known/ {
        }

        return 301 https://${LXC_HOSTNAME}.${LXC_DOMAIN}\$request_uri;
        }

server {
        listen 443 ssl http2 default_server;
        listen [::]:443 ssl http2 default_server;

        server_name ${LXC_HOSTNAME}.${LXC_DOMAIN};

        server_tokens off;
        ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
        ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

        ssl_protocols TLSv1.3 TLSv1.2;
        ssl_ciphers ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:EECDH+AESGCM:EDH+AESGCM;
        ssl_dhparam /etc/nginx/dhparam.pem;
        ssl_prefer_server_ciphers on;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 180m;

        ssl_stapling on;
        ssl_stapling_verify on;

        resolver 1.1.1.1 1.0.0.1;

        add_header Strict-Transport-Security "max-age=31536000" always;

        root    /usr/share/zabbix;

        index   index.php;

        location = /favicon.ico {
                log_not_found   off;
        }

        location / {
                try_files       \$uri \$uri/ =404;
        }

        location /assets {
                access_log      off;
                expires         10d;
        }

        location ~ /\.ht {
                deny            all;
        }

        location ~ /(api\/|conf[^\.]|include|locale) {
                deny            all;
                return          404;
        }

        location /vendor {
                deny            all;
                return          404;
        }

        location ~ [^/]\.php(/|$) {
                fastcgi_pass    unix:/var/run/php/zabbix.sock;
                fastcgi_split_path_info ^(.+\.php)(/.+)$;
                fastcgi_index   index.php;

                fastcgi_param   DOCUMENT_ROOT   /usr/share/zabbix;
                fastcgi_param   SCRIPT_FILENAME /usr/share/zabbix\$fastcgi_script_name;
                fastcgi_param   PATH_TRANSLATED /usr/share/zabbix\$fastcgi_script_name;

                include fastcgi_params;
                fastcgi_param   QUERY_STRING    \$query_string;
                fastcgi_param   REQUEST_METHOD  \$request_method;
                fastcgi_param   CONTENT_TYPE    \$content_type;
                fastcgi_param   CONTENT_LENGTH  \$content_length;

                fastcgi_intercept_errors        on;
                fastcgi_ignore_client_abort     off;
                fastcgi_connect_timeout         60;
                fastcgi_send_timeout            180;
                fastcgi_read_timeout            180;
                fastcgi_buffer_size             128k;
                fastcgi_buffers                 4 256k;
                fastcgi_busy_buffers_size       256k;
                fastcgi_temp_file_write_size    256k;
        }
}
EOF

cat << EOF > /etc/php/$PHP_VERSION/fpm/pool.d/zabbix-php-fpm.conf
[zabbix]
user = www-data
group = www-data

listen = /var/run/php/zabbix.sock
listen.owner = www-data
listen.allowed_clients = 127.0.0.1

pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.max_requests = 200

php_value[session.save_handler] = files
php_value[session.save_path]    = /var/lib/php/sessions/

php_value[max_execution_time] = 300
php_value[memory_limit] = 128M
php_value[post_max_size] = 16M
php_value[upload_max_filesize] = 2M
php_value[max_input_time] = 300
php_value[max_input_vars] = 10000
EOF

cat << EOF > /etc/zabbix/web/zabbix.conf.php 
<?php
// Zabbix GUI configuration file.

\$DB['TYPE']				= 'POSTGRESQL';
\$DB['SERVER']			= 'localhost';
\$DB['PORT']				= '0';
\$DB['DATABASE']			= '${ZABBIX_DB_NAME}';
\$DB['USER']				= '${ZABBIX_DB_USR}';
\$DB['PASSWORD']			= '${ZABBIX_DB_PWD}';

// Schema name. Used for PostgreSQL.
\$DB['SCHEMA']			= '';

// Used for TLS connection.
\$DB['ENCRYPTION']		= true;
\$DB['KEY_FILE']			= '';
\$DB['CERT_FILE']		= '';
\$DB['CA_FILE']			= '';
\$DB['VERIFY_HOST']		= false;
\$DB['CIPHER_LIST']		= '';

// Vault configuration. Used if database credentials are stored in Vault secrets manager.
\$DB['VAULT_URL']		= '';
\$DB['VAULT_DB_PATH']	= '';
\$DB['VAULT_TOKEN']		= '';

// Use IEEE754 compatible value range for 64-bit Numeric (float) history values.
// This option is enabled by default for new Zabbix installations.
// For upgraded installations, please read database upgrade notes before enabling this option.
\$DB['DOUBLE_IEEE754']	= true;

// Uncomment and set to desired values to override Zabbix hostname/IP and port.
// \$ZBX_SERVER			= '';
// \$ZBX_SERVER_PORT		= '';

\$ZBX_SERVER_NAME		= '${LXC_HOSTNAME}';

\$IMAGE_FORMAT_DEFAULT	= IMAGE_FORMAT_PNG;

// Uncomment this block only if you are using Elasticsearch.
// Elasticsearch url (can be string if same url is used for all types).
//\$HISTORY['url'] = [
//	'uint' => 'http://localhost:9200',
//	'text' => 'http://localhost:9200'
//];
// Value types stored in Elasticsearch.
//\$HISTORY['types'] = ['uint', 'text'];

// Used for SAML authentication.
// Uncomment to override the default paths to SP private key, SP and IdP X.509 certificates, and to set extra settings.
//\$SSO['SP_KEY']			= 'conf/certs/sp.key';
//\$SSO['SP_CERT']			= 'conf/certs/sp.crt';
//\$SSO['IDP_CERT']		= 'conf/certs/idp.crt';
//\$SSO['SETTINGS']		= [];
EOF

timedatectl set-timezone ${LXC_TIMEZONE}

systemctl enable --now postgresql

su - postgres <<EOF
psql -c "CREATE USER ${ZABBIX_DB_USR} WITH PASSWORD '${ZABBIX_DB_PWD}';"
psql -c "CREATE DATABASE ${ZABBIX_DB_NAME} ENCODING UTF8 TEMPLATE template0 OWNER ${ZABBIX_DB_USR};"
echo "Postgres User ${ZABBIX_DB_USR} and database ${ZABBIX_DB_NAME} created."
EOF

sed -i "s/false/true/g" /usr/share/zabbix/include/locales.inc.php

zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u zabbix psql ${ZABBIX_DB_NAME}

timescaledb-tune --quiet --yes >> /etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf

systemctl restart postgresql

echo "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;" | sudo -u postgres psql zabbix
cat /usr/share/zabbix-sql-scripts/postgresql/timescaledb/schema.sql | sudo -u zabbix psql ${ZABBIX_DB_NAME}

echo "DBPassword=${ZABBIX_DB_PWD}" >> /etc/zabbix/zabbix_server.conf

generate_dhparam

systemctl enable nginx php$PHP_VERSION-fpm zabbix-server zabbix-agent 

systemctl restart nginx php$PHP_VERSION-fpm zabbix-server zabbix-agent > /dev/null 2>&1