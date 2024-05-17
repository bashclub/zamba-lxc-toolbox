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

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install --no-install-recommends postgresql-$POSTGRES_VERSION postgresql-client zabbix-proxy-pgsql zabbix-sql-scripts ssl-cert

timedatectl set-timezone ${LXC_TIMEZONE}

systemctl enable --now postgresql

su - postgres <<EOF
psql -c "CREATE USER ${ZABBIX_DB_USR} WITH PASSWORD '${ZABBIX_DB_PWD}';"
psql -c "CREATE DATABASE ${ZABBIX_DB_NAME} ENCODING UTF8 TEMPLATE template0 OWNER ${ZABBIX_DB_USR};"
echo "Postgres User ${ZABBIX_DB_USR} and database ${ZABBIX_DB_NAME} created."
EOF

cat /usr/share/zabbix-sql-scripts/postgresql/proxy.sql | sudo -u zabbix psql ${ZABBIX_DB_NAME}

echo "DBPassword=${ZABBIX_DB_PWD}" >> /etc/zabbix/zabbix_proxy.conf

$srv=$(grep -E "^Server" /etc/zabbix/zabbix_proxy.conf)
sed -i "s/$srv/Server=${ZBX_ADDR}/g" "s/# ListenPort=/ListenPort=/g" "s/Hostname=Zabbix proxy/# Hostname=${LXC_HOSTNAME}.${LXC_DOMAIN}/g" /etc/zabbix/zabbix_proxy.conf

systemctl enable zabbix-proxy 

systemctl restart zabbix-proxy