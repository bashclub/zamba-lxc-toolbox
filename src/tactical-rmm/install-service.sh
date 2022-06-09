#!/bin/bash

set -euo pipefail

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

codename=$(lsb_release -cs)

useradd -m -G sudo -s /bin/bash ${RMMUSER}

echo "deb https://repo.mongodb.org/apt/$osname buster/mongodb-org/4.4 main" > /etc/apt/sources.list.d/mongodb.list
echo "deb https://apt.postgresql.org/pub/repos/apt/ $codename-pgdg main" > /etc/apt/sources.list.d/postgres.list
echo "deb https://deb.nodesource.com/node_16.x $codename main" > /etc/apt/sources.list.d/nodejs.list
echo "deb https://dl.yarnpkg.com/debian stable main" > tee /etc/apt/sources.list.d/yarn.list

apt-key adv --fetch https://pgp.mongodb.com/server-4.4.pub
apt-key adv --fetch https://deb.nodesource.com/gpgkey/nodesource.gpg.key
apt-key adv --fetch https://dl.yarnpkg.com/debian/yarnkey.gpg
apt-key adv --fetch https://www.postgresql.org/media/keys/ACCC4CF8.asc


apt update
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq sudo ssl-cert nginx mongodb-org gcc g++ make build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev libbz2-dev ca-certificates redis git postgresql-14 rpl
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq nodejs

echo "${RMMUSER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${RMMUSER}

npm install --no-fund --location=global npm

openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout /etc/ssl/private/${frontenddomain}.key -out /etc/ssl/certs/${frontenddomain}.pem -subj "/CN=$frontenddomain" -addext "subjectAltName=DNS:*.${frontenddomain}"
chown root:ssl-cert /etc/ssl/private/${frontenddomain}.key
chmod 640 /etc/ssl/private/${frontenddomain}.key
usermod -aG ssl-cert ${RMMUSER}

update-ca-certificates

systemctl enable mongod.service postgresql.service

# configure hosts file
echo "127.0.1.1 ${rmmdomain} ${frontenddomain} ${meshdomain}" | tee --append /etc/hosts > /dev/null

# set global nginx vars
sed -i 's/worker_connections.*/worker_connections 2048;/g' /etc/nginx/nginx.conf
sed -i 's/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/g' /etc/nginx/nginx.conf

# compile python3
su - ${RMMUSER} << EOF
cd ~
wget https://www.python.org/ftp/python/${PYTHON_VER}/Python-${PYTHON_VER}.tgz
tar -xf Python-${PYTHON_VER}.tgz
cd Python-${PYTHON_VER}
./configure --enable-optimizations
make -j $(nproc)
sudo make altinstall
cd ~
sudo rm -rf Python-${PYTHON_VER} Python-${PYTHON_VER}.tgz
EOF


systemctl restart mongod postgresql
systemctl stop nginx

# configure postgresql
cd /var/lib/postgresql
sudo -u postgres psql -c "CREATE DATABASE tacticalrmm;"
sudo -u postgres psql -c "CREATE USER ${pgusername} WITH PASSWORD '${pgpw}';"
sudo -u postgres psql -c "ALTER ROLE ${pgusername} SET client_encoding TO 'utf8';"
sudo -u postgres psql -c "ALTER ROLE ${pgusername} SET default_transaction_isolation TO 'read committed';"
sudo -u postgres psql -c "ALTER ROLE ${pgusername} SET timezone TO 'UTC';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE tacticalrmm TO ${pgusername};"

# clone tacticalrmm
mkdir /rmm
chown ${RMMUSER}:${RMMUSER} /rmm
mkdir -p /var/log/celery
chown ${RMMUSER}:${RMMUSER} /var/log/celery
mkdir -p ${SCRIPTS_DIR}
chown ${RMMUSER}:${RMMUSER} ${SCRIPTS_DIR}
su - ${RMMUSER} << EOF
cd /rmm
git clone -b master https://github.com/amidaware/tacticalrmm.git /rmm
git config user.email "admin@example.com"
git config user.name "Bob"
cd ${SCRIPTS_DIR} 
git clone -b main https://github.com/amidaware/community-scripts.git ${SCRIPTS_DIR}/
git config user.email "admin@example.com"
git config user.name "Bob"
EOF

# configure NATS server
NATS_SERVER_VER=$(grep "^NATS_SERVER_VER" /rmm/api/tacticalrmm/tacticalrmm/settings.py | awk -F'[= "]' '{print $5}')
nats_tmp=$(mktemp -d -t nats-server-XXXXXXXXXXXXX)
wget https://github.com/nats-io/nats-server/releases/download/v${NATS_SERVER_VER}/nats-server-v${NATS_SERVER_VER}-linux-amd64.tar.gz -O ${nats_tmp}/nats-server-v${NATS_SERVER_VER}-linux-amd64.tar.gz
tar -xzf ${nats_tmp}/nats-server-v${NATS_SERVER_VER}-linux-amd64.tar.gz -C ${nats_tmp}
mv ${nats_tmp}/nats-server-v${NATS_SERVER_VER}-linux-amd64/nats-server /usr/local/bin/
chmod +x /usr/local/bin/nats-server
chown ${RMMUSER}:${RMMUSER} /usr/local/bin/nats-server
rm -rf ${nats_tmp}

# fix cert in nats-rmm.conf
rpl "/etc/letsencrypt/live/${frontenddomain}/fullchain.pem" "/etc/ssl/certs/${frontenddomain}.pem" /rmm/api/tacticalrmm/nats-rmm.conf
rpl "/etc/letsencrypt/live/${frontenddomain}/privkey.pem" "/etc/ssl/private/${frontenddomain}.key" /rmm/api/tacticalrmm/nats-rmm.conf

# install meshcentral
MESH_VER=$(grep "^MESH_VER" /rmm/api/tacticalrmm/tacticalrmm/settings.py | awk -F'[= "]' '{print $5}')

mkdir -p /meshcentral/meshcentral-data
chown ${RMMUSER}:${RMMUSER} -R /meshcentral

su  - ${RMMUSER} << EOF
cd /meshcentral
npm install meshcentral@${MESH_VER}
EOF

chown ${RMMUSER}:${RMMUSER} -R /meshcentral

meshcfg="$(cat << EOF
{
  "settings": {
    "Cert": "${meshdomain}",
    "MongoDb": "mongodb://127.0.0.1:27017",
    "MongoDbName": "meshcentral",
    "WANonly": true,
    "Minify": 1,
    "Port": 4430,
    "AliasPort": 443,
    "RedirPort": 800,
    "AllowLoginToken": true,
    "AllowFraming": true,
    "_AgentPing": 60,
    "AgentPong": 300,
    "AllowHighQualityDesktop": true,
    "TlsOffload": "127.0.0.1",
    "agentCoreDump": false,
    "Compression": true,
    "WsCompression": true,
    "AgentWsCompression": true,
    "MaxInvalidLogin": { "time": 5, "count": 5, "coolofftime": 30 }
  },
  "domains": {
    "": {
      "Title": "Tactical RMM",
      "Title2": "Tactical RMM",
      "NewAccounts": false,
      "CertUrl": "https://${meshdomain}:443/",
      "GeoLocation": true,
      "CookieIpCheck": false,
      "mstsc": true,
      "force2factor": false
    }
  }
}
EOF
)"
sudo -u ${RMMUSER} echo "${meshcfg}" > /meshcentral/meshcentral-data/config.json

localvars="$(cat << EOF
SECRET_KEY = "${DJANGO_SEKRET}"

DEBUG = False

ALLOWED_HOSTS = ['${rmmdomain}']

ADMIN_URL = "${ADMINURL}/"

CORS_ORIGIN_WHITELIST = [
    "https://${frontenddomain}"
]

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'tacticalrmm',
        'USER': '${pgusername}',
        'PASSWORD': '${pgpw}',
        'HOST': 'localhost',
        'PORT': '5432',
    }
}

MESH_USERNAME = "${meshusername}"
MESH_SITE = "https://${meshdomain}"
REDIS_HOST    = "localhost"
ADMIN_ENABLED = True
EOF
)"
sudo -u ${RMMUSER} echo "${localvars}" > /rmm/api/tacticalrmm/tacticalrmm/local_settings.py

cp /rmm/natsapi/bin/nats-api /usr/local/bin
chown ${RMMUSER}:${RMMUSER} /usr/local/bin/nats-api
chmod +x /usr/local/bin/nats-api

SETUPTOOLS_VER=$(grep "^SETUPTOOLS_VER" /rmm/api/tacticalrmm/tacticalrmm/settings.py | awk -F'[= "]' '{print $5}')
WHEEL_VER=$(grep "^WHEEL_VER" /rmm/api/tacticalrmm/tacticalrmm/settings.py | awk -F'[= "]' '{print $5}')

su - ${RMMUSER} << EOF
cd /rmm/api/
/usr/local/bin/python3.10 -m venv env
source /rmm/api/env/bin/activate
cd /rmm/api/tacticalrmm
pip install --no-cache-dir --upgrade pip
pip install --no-cache-dir setuptools==${SETUPTOOLS_VER} wheel==${WHEEL_VER}
pip install --no-cache-dir -r /rmm/api/tacticalrmm/requirements.txt
python manage.py migrate
python manage.py collectstatic --no-input
python manage.py create_natsapi_conf
python manage.py load_chocos
python manage.py load_community_scripts
python manage.py create_installer_user
deactivate
EOF

# install backend
echo 'Optimizing for number of processors'
uwsgiprocs=4
if [[ "$(nproc)" == "1" ]]; then
  uwsgiprocs=2
else
  uwsgiprocs=$(nproc)
fi

uwsgini="$(cat << EOF
[uwsgi]
chdir = /rmm/api/tacticalrmm
module = tacticalrmm.wsgi
home = /rmm/api/env
master = true
processes = ${uwsgiprocs}
threads = ${uwsgiprocs}
enable-threads = true
socket = /rmm/api/tacticalrmm/tacticalrmm.sock
harakiri = 300
chmod-socket = 660
buffer-size = 65535
vacuum = true
die-on-term = true
max-requests = 500
disable-logging = true
EOF
)"
sudo -u ${RMMUSER} echo "${uwsgini}" > /rmm/api/tacticalrmm/app.ini

# create systemd services

rmmservice="$(cat << EOF
[Unit]
Description=tacticalrmm uwsgi daemon
After=network.target postgresql.service

[Service]
User=${RMMUSER}
Group=www-data
WorkingDirectory=/rmm/api/tacticalrmm
Environment="PATH=/rmm/api/env/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/rmm/api/env/bin/uwsgi --ini app.ini
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
)"
echo "${rmmservice}" | sudo tee /etc/systemd/system/rmm.service > /dev/null

daphneservice="$(cat << EOF
[Unit]
Description=django channels daemon
After=network.target

[Service]
User=${RMMUSER}
Group=www-data
WorkingDirectory=/rmm/api/tacticalrmm
Environment="PATH=/rmm/api/env/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/rmm/api/env/bin/daphne -u /rmm/daphne.sock tacticalrmm.asgi:application
Restart=always
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
)"
echo "${daphneservice}" | sudo tee /etc/systemd/system/daphne.service > /dev/null

natsservice="$(cat << EOF
[Unit]
Description=NATS Server
After=network.target

[Service]
PrivateTmp=true
Type=simple
ExecStart=/usr/local/bin/nats-server -c /rmm/api/tacticalrmm/nats-rmm.conf
ExecReload=/usr/bin/kill -s HUP \$MAINPID
ExecStop=/usr/bin/kill -s SIGINT \$MAINPID
User=${RMMUSER}
Group=www-data
Restart=always
RestartSec=5s
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
)"
echo "${natsservice}" | sudo tee /etc/systemd/system/nats.service > /dev/null

natsapi="$(cat << EOF
[Unit]
Description=TacticalRMM Nats Api v1
After=nats.service

[Service]
Type=simple
ExecStart=/usr/local/bin/nats-api
User=${RMMUSER}
Group=${RMMUSER}
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
)"
echo "${natsapi}" | sudo tee /etc/systemd/system/nats-api.service > /dev/null

celeryservice="$(cat << EOF
[Unit]
Description=Celery Service V2
After=network.target redis-server.service postgresql.service

[Service]
Type=forking
User=${RMMUSER}
Group=${RMMUSER}
EnvironmentFile=/etc/conf.d/celery.conf
WorkingDirectory=/rmm/api/tacticalrmm
ExecStart=/bin/sh -c '\${CELERY_BIN} -A \$CELERY_APP multi start \$CELERYD_NODES --pidfile=\${CELERYD_PID_FILE} --logfile=\${CELERYD_LOG_FILE} --loglevel="\${CELERYD_LOG_LEVEL}" \$CELERYD_OPTS'
ExecStop=/bin/sh -c '\${CELERY_BIN} multi stopwait \$CELERYD_NODES --pidfile=\${CELERYD_PID_FILE} --loglevel="\${CELERYD_LOG_LEVEL}"'
ExecReload=/bin/sh -c '\${CELERY_BIN} -A \$CELERY_APP multi restart \$CELERYD_NODES --pidfile=\${CELERYD_PID_FILE} --logfile=\${CELERYD_LOG_FILE} --loglevel="\${CELERYD_LOG_LEVEL}" \$CELERYD_OPTS'
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
)"
echo "${celeryservice}" | sudo tee /etc/systemd/system/celery.service > /dev/null

celerybeatservice="$(cat << EOF
[Unit]
Description=Celery Beat Service V2
After=network.target redis-server.service postgresql.service

[Service]
Type=simple
User=${RMMUSER}
Group=${RMMUSER}
EnvironmentFile=/etc/conf.d/celery.conf
WorkingDirectory=/rmm/api/tacticalrmm
ExecStart=/bin/sh -c '\${CELERY_BIN} -A \${CELERY_APP} beat --pidfile=\${CELERYBEAT_PID_FILE} --logfile=\${CELERYBEAT_LOG_FILE} --loglevel=\${CELERYD_LOG_LEVEL}'
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
)"
echo "${celerybeatservice}" | sudo tee /etc/systemd/system/celerybeat.service > /dev/null

meshservice="$(cat << EOF
[Unit]
Description=MeshCentral Server
After=network.target mongod.service nginx.service
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/node node_modules/meshcentral
Environment=NODE_ENV=production
WorkingDirectory=/meshcentral
User=${RMMUSER}
Group=${RMMUSER}
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
)"
echo "${meshservice}" | sudo tee /etc/systemd/system/meshcentral.service > /dev/null


# create nginx config

nginxrmm="$(cat << EOF
server_tokens off;

upstream tacticalrmm {
    server unix:////rmm/api/tacticalrmm/tacticalrmm.sock;
}

map \$http_user_agent \$ignore_ua {
    "~python-requests.*" 0;
    "~go-resty.*" 0;
    default 1;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${rmmdomain};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${rmmdomain};
    client_max_body_size 300M;
    access_log /rmm/api/tacticalrmm/tacticalrmm/private/log/access.log combined if=\$ignore_ua;
    error_log /rmm/api/tacticalrmm/tacticalrmm/private/log/error.log;
    ssl_certificate /etc/ssl/certs/${frontenddomain}.pem;
    ssl_certificate_key /etc/ssl/private/${frontenddomain}.key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
    ssl_ecdh_curve secp384r1;
    ssl_stapling on;
    ssl_stapling_verify on;
    add_header X-Content-Type-Options nosniff;
    
    location /static/ {
        root /rmm/api/tacticalrmm;
    }

    location /private/ {
        internal;
        add_header "Access-Control-Allow-Origin" "https://${frontenddomain}";
        alias /rmm/api/tacticalrmm/tacticalrmm/private/;
    }

    location ~ ^/(natsapi) {
        allow 127.0.0.1;
        deny all;
        uwsgi_pass tacticalrmm;
        include     /etc/nginx/uwsgi_params;
        uwsgi_read_timeout 500s;
        uwsgi_ignore_client_abort on;
    }

    location ~ ^/ws/ {
        proxy_pass http://unix:/rmm/daphne.sock;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_redirect     off;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Host \$server_name;
    }

    location / {
        uwsgi_pass  tacticalrmm;
        include     /etc/nginx/uwsgi_params;
        uwsgi_read_timeout 9999s;
        uwsgi_ignore_client_abort on;
    }
}
EOF
)"
echo "${nginxrmm}" | sudo tee /etc/nginx/sites-available/rmm.conf > /dev/null


nginxmesh="$(cat << EOF
server {
  listen 80;
  listen [::]:80;
  server_name ${meshdomain};
  return 301 https://\$server_name\$request_uri;
}

server {

    listen 443 ssl;
    listen [::]:443 ssl;
    proxy_send_timeout 330s;
    proxy_read_timeout 330s;
    server_name ${meshdomain};
    ssl_certificate /etc/ssl/certs/${frontenddomain}.pem;
    ssl_certificate_key /etc/ssl/private/${frontenddomain}.key;

    ssl_session_cache shared:WEBSSL:10m;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
    ssl_ecdh_curve secp384r1;
    ssl_stapling on;
    ssl_stapling_verify on;
    add_header X-Content-Type-Options nosniff;

    location / {
        proxy_pass http://127.0.0.1:4430/;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Forwarded-Host \$host:\$server_port;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
)"
echo "${nginxmesh}" | sudo tee /etc/nginx/sites-available/meshcentral.conf > /dev/null

ln -s /etc/nginx/sites-available/rmm.conf /etc/nginx/sites-enabled/rmm.conf
ln -s /etc/nginx/sites-available/meshcentral.conf /etc/nginx/sites-enabled/meshcentral.conf

# configure celery
mkdir /etc/conf.d

celeryconf="$(cat << EOF
CELERYD_NODES="w1"

CELERY_BIN="/rmm/api/env/bin/celery"

CELERY_APP="tacticalrmm"

CELERYD_MULTI="multi"

CELERYD_OPTS="--time-limit=86400 --autoscale=20,2"

CELERYD_PID_FILE="/rmm/api/tacticalrmm/%n.pid"
CELERYD_LOG_FILE="/var/log/celery/%n%I.log"
CELERYD_LOG_LEVEL="ERROR"

CELERYBEAT_PID_FILE="/rmm/api/tacticalrmm/beat.pid"
CELERYBEAT_LOG_FILE="/var/log/celery/beat.log"
EOF
)"
echo "${celeryconf}" | sudo tee /etc/conf.d/celery.conf > /dev/null

chown ${RMMUSER}:${RMMUSER} -R /etc/conf.d/

systemctl daemon-reload

# install frontend

su - ${RMMUSER} << EOF

if [ -d ~/.npm ]; then
  chown -R $RMMUSER:$RMMUSER ~/.npm
fi

if [ -d ~/.config ]; then
  chown -R $RMMUSER:$RMMUSER ~/.config
fi

echo -e "PROD_URL = \"https://${rmmdomain}\"\nDEV_URL = \"https://${rmmdomain}\"" > /rmm/web/.env

cd /rmm/web
npm install
npm audit fix
npm run build
EOF

mkdir -p /var/www/rmm
cp -pvr /rmm/web/dist /var/www/rmm/
chown www-data:www-data -R /var/www/rmm/dist

nginxfrontend="$(cat << EOF
server {
    server_name ${frontenddomain};
    charset utf-8;
    location / {
        root /var/www/rmm/dist;
        try_files \$uri \$uri/ /index.html;
        add_header Cache-Control "no-store, no-cache, must-revalidate";
        add_header Pragma "no-cache";
    }
    error_log  /var/log/nginx/frontend-error.log;
    access_log /var/log/nginx/frontend-access.log;

    listen 443 ssl;
    listen [::]:443 ssl;
    ssl_certificate /etc/ssl/certs/${frontenddomain}.pem;
    ssl_certificate_key /etc/ssl/private/${frontenddomain}.key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
    ssl_ecdh_curve secp384r1;
    ssl_stapling on;
    ssl_stapling_verify on;
    add_header X-Content-Type-Options nosniff;
}

server {
    if (\$host = ${frontenddomain}) {
        return 301 https://\$host\$request_uri;
    }

    listen 80;
    listen [::]:80;
    server_name ${frontenddomain};
    return 404;
}
EOF
)"
echo "${nginxfrontend}" | tee /etc/nginx/sites-available/frontend.conf > /dev/null

ln -s /etc/nginx/sites-available/frontend.conf /etc/nginx/sites-enabled/frontend.conf


for i in rmm.service daphne.service celery.service celerybeat.service nginx
do
  systemctl enable ${i}
  systemctl stop ${i}
  systemctl start ${i}
done
sleep 5
systemctl enable meshcentral

systemctl restart meshcentral

CHECK_MESH_READY=1
while ! [[ $CHECK_MESH_READY ]]; do
  CHECK_MESH_READY=$(sudo journalctl -u meshcentral.service -b --no-pager | grep "MeshCentral HTTP server running on port")
  echo -ne "Mesh Central not ready yet...\n"
  sleep 3
done

node /meshcentral/node_modules/meshcentral --logintokenkey

MESHTOKENKEY=$(node /meshcentral/node_modules/meshcentral --logintokenkey)
sudo -u ${USER} echo "MESH_TOKEN_KEY = \"$MESHTOKENKEY\"" >> /rmm/api/tacticalrmm/tacticalrmm/local_settings.py

systemctl stop meshcentral
sleep 1
cd /meshcentral

sudo -u ${RMMUSER} node node_modules/meshcentral --createaccount ${meshusername} --pass ${MESHPASSWD} --email ${adminemail}
sleep 1
sudo -u ${RMMUSER} node node_modules/meshcentral --adminaccount ${meshusername}

systemctl start meshcentral
sleep 5


sudo -u ${RMMUSER} node node_modules/meshcentral/meshctrl.js --url wss://${meshdomain}:443 --loginuser ${meshusername} --loginpass ${MESHPASSWD} AddDeviceGroup --name TacticalRMM
sleep 1

systemctl enable nats.service
su - ${RMMUSER} <<EOF
cd /rmm/api/tacticalrmm
source /rmm/api/env/bin/activate
python manage.py initial_db_setup
python manage.py reload_nats
deactivate
EOF

systemctl start nats.service

sleep 1
systemctl enable nats-api.service
systemctl start nats-api.service

## disable django admin
sudo -u ${RMMUSER} sed -i 's/ADMIN_ENABLED = True/ADMIN_ENABLED = False/g' /rmm/api/tacticalrmm/tacticalrmm/local_settings.py

echo 'Restarting services'
for i in rmm.service daphne.service celery.service celerybeat.service
do
  systemctl stop ${i}
  systemctl start ${i}
done

cat << EOF > /usr/local/bin/register-rmm-admin
cd /rmm/api
source /rmm/api/env/bin/activate
cd /rmm/api/tacticalrmm
printf >&2 "Please create your login for the RMM website and django admin\n"
printf >&2 "\n"
echo -ne "Username: "
read djangousername
python manage.py createsuperuser --username \${djangousername} --email ${adminemail}
#RANDBASE=\$(python manage.py generate_totp)
#python manage.py generate_barcode \${RANDBASE} \${djangousername} ${frontenddomain}
deactivate
EOF
chmod +x /usr/local/bin/register-rmm-admin

printf >&2 "Installation complete!\n\n"
printf >&2 "Access your rmm at: https://${frontenddomain}\n\n"
printf >&2 "Django admin url (disabled by default): https://${rmmdomain}/${ADMINURL}/\n\n"
printf >&2 "MeshCentral username: ${meshusername}\n"
printf >&2 "MeshCentral password: ${MESHPASSWD}\n\n"

printf >&2 "Please run 'register-rmm-admin' to create an administrative rmm user.\n\n"