#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

mkdir /opt/rei3
wget -c https://rei3.de/downloads/REI3_3.4.2_x64_linux.tar.gz -O - | tar -zx -C /opt/rei3

wget -q -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | sudo tee /usr/share/keyrings/postgres.gpg
echo "deb [signed-by=/usr/share/keyrings/postgres.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install --no-install-recommends postgresql imagemagick ghostscript postgresql-client

timedatectl set-timezone ${LXC_TIMEZONE}

systemctl enable --now postgresql

su - postgres <<EOF
psql -c "CREATE USER ${REI3_DB_USR} WITH PASSWORD '${REI3_DB_PWD}';"
psql -c "CREATE DATABASE ${REI3_DB_NAME} ENCODING UTF8 TEMPLATE template0 OWNER ${REI3_DB_USR};"
psql -c "GRANT ALL PRIVILEGES ON DATABASE ${REI3_DB_NAME} TO ${REI3_DB_USR};"
echo "Postgres User ${REI3_DB_USR} and database ${REI3_DB_NAME} created."
EOF

cp /opt/rei3/config_template.json /opt/rei3/config.json
chmod u+x /opt/rei3/r3

sed -i 's/"user": "app",/"user": "'${REI3_DB_USR}'",/g' /opt/rei3/config.json 
sed -i 's/"pass": "app",/"pass": "'${REI3_DB_PWD}'",/g' /opt/rei3/config.json 

/opt/rei3/r3 -install
#/opt/rei/r3 -newadmin
systemctl start rei3
