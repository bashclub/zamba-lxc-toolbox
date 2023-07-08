#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

wget -q -O - https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/nginx.key >/dev/null
echo "deb [signed-by=/etc/apt/trusted.gpg.d/nginx.key] http://nginx.org/packages/debian $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list

wget -q -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc  | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/postgresql.key >/dev/null
echo "deb [signed-by=/etc/apt/trusted.gpg.d/postgresql.key] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install --no-install-recommends -y -qq postgresql nginx git ssl-cert unzip zip ansible ansible-lint

systemctl enable --now postgresql

su - postgres <<EOF
psql -c "CREATE USER semaphore WITH PASSWORD '${SEMAPHORE_DB_PWD}';"
psql -c "CREATE DATABASE ${SEMAPHORE_DB_NAME} ENCODING UTF8 TEMPLATE template0 OWNER ${SEMAPHORE_DB_USR};"
echo "Postgres User ${SEMAPHORE_DB_USR} and database ${SEMAPHORE_DB_NAME} created."
EOF

curl -s https://api.github.com/repos/ansible-semaphore/semaphore/releases/latest | grep browser_download_url | cut -d '"' -f 4 | grep 'linux_amd64.deb$' | wget -i - -O /opt/semaphore_linux_amd64.deb

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install /opt/semaphore_linux_amd64.deb

cat << EOF > /usr/local/bin/update-semaphore
PATH="/bin:/usr/bin:/usr/local/bin"
echo "Checking github for new semaphore version"
current_version=\$(curl -s https://api.github.com/repos/ansible-semaphore/semaphore/releases/latest | grep "tag_name" | cut -d '"' -f4)
installed_version=\$(semaphore version)
echo "Installed semaphore version is \$installed_version"
if [ \$installed_version != \$current_version ]; then
  echo "New semaphore version \$current_version available. Stopping semaphore.service"
  systemctl stop semaphore.service
  echo "Downloading semaphore version \$current_version..."
  curl -s https://api.github.com/repos/ansible-semaphore/semaphore/releases/latest | grep browser_download_url | cut -d '"' -f 4 | grep 'linux_amd64.deb$' | wget -i - -O /opt/semaphore_linux_amd64.deb
  DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install /opt/semaphore_linux_amd64.deb
  echo "Starting semaphore.service..."
  systemctl start semaphore.service
  echo "semaphore update finished!"
else
  echo "semaphore version is up-to-date!"
fi
EOF
chmod +x /usr/local/bin/update-semaphore

cat << EOF > /etc/apt/apt.conf.d/80-semaphore-apt-hook
DPkg::Post-Invoke {"/usr/local/bin/update-semaphore";};
EOF
chmod +x /etc/apt/apt.conf.d/80-semaphore-apt-hook

cat << EOF > /etc/systemd/system/semaphore.service
[Unit]
Description=Semaphore Ansible
Documentation=https://github.com/ansible-semaphore/semaphore
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecReload=/bin/kill -HUP \$MAINPID
ExecStart=/usr/bin/semaphore service --config=/etc/semaphore/config.json
SyslogIdentifier=semaphore
Restart=always

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /etc/semaphore

cat << EOF > /etc/semaphore/config.json
{
 	"mysql": {
 		"host": "",
 		"user": "",
 		"pass": "",
 		"name": "",
 		"options": null
 	},
 	"bolt": {
 		"host": "",
 		"user": "",
 		"pass": "",
 		"name": "",
 		"options": null
 	},
 	"postgres": {
 		"host": "127.0.0.1:5432",
 		"user": "${SEMAPHORE_DB_USR}",
 		"pass": "${SEMAPHORE_DB_PWD}",
 		"name": "${SEMAPHORE_DB_NAME}",
 		"options": {
 			"sslmode": "disable"
 		}
 	},
 	"dialect": "postgres",
 	"port": "",
 	"interface": "",
 	"tmp_path": "/tmp/semaphore",
 	"cookie_hash": "$(head -c32 /dev/urandom | base64)",
 	"cookie_encryption": "$(head -c32 /dev/urandom | base64)",
 	"access_key_encryption": "$(head -c32 /dev/urandom | base64)",
 	"email_sender": "",
 	"email_host": "",
 	"email_port": "",
 	"email_username": "",
 	"email_password": "",
 	"web_host": "",
 	"ldap_binddn": "",
 	"ldap_bindpassword": "",
 	"ldap_server": "",
 	"ldap_searchdn": "",
 	"ldap_searchfilter": "",
 	"ldap_mappings": {
 		"dn": "",
 		"mail": "",
 		"uid": "",
 		"cn": ""
 	},
 	"telegram_chat": "",
 	"telegram_token": "",
 	"slack_url": "",
 	"max_parallel_tasks": 0,
 	"email_alert": false,
 	"email_secure": false,
 	"telegram_alert": false,
 	"slack_alert": false,
 	"ldap_enable": false,
 	"ldap_needtls": false,
 	"ssh_config_path": "~/.ssh/",
 	"demo_mode": false,
 	"git_client": ""
 }
EOF

if [ -f /etc/nginx/sites-enabled/default ]; then
  unlink /etc/nginx/sites-enabled/default
fi

cat << EOF > /etc/nginx/conf.d/default.conf
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    server_tokens off;

    access_log /var/log/nginx/semaphore.access.log;
    error_log /var/log/nginx/semaphore.error.log;

    location /.well-known/ {
        root /var/www/html;
    }

    return 301 https://${LXC_HOSTNAME}.${LXC_DOMAIN}\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

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

    access_log /var/log/nginx/semaphore.access.log;
    error_log  /var/log/nginx/semaphore.error.log;

    client_max_body_size 50M;

    location / {
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:3000;
        proxy_read_timeout 90;
    }
}
EOF

echo "source <(semaphore completion bash)" >> /root/.bashrc
semaphore user add --admin --login ${SEMAPHORE_ADMIN} --name ${SEMAPHORE_ADMIN_DISPLAY_NAME} --email ${SEMAPHORE_ADMIN_EMAIL} --password ${SEMAPHORE_ADMIN_PASSWORD} --config /etc/semaphore/config.json


openssl dhparam -out /etc/nginx/dhparam.pem 4096

systemctl daemon-reload
systemctl enable --now semaphore.service
systemctl restart nginx.service
