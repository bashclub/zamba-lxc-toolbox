#!/bin/bash

set -euo pipefail

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

wget -O /etc/apt/trusted.gpg.d/mongodb-3.6.asc https://www.mongodb.org/static/pgp/server-3.6.asc
wget -O /etc/apt/trusted.gpg.d/unifi.gpg https://dl.ubnt.com/unifi/unifi-repo.gpg

echo "deb http://repo.mongodb.org/apt/debian stretch/mongodb-org/3.6 main" > /etc/apt/sources.list.d/mongodb.list
echo "deb http://www.ui.com/downloads/unifi/debian stable ubiquiti" > /etc/apt/sources.list.d/unifi.list 

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq sudo unifi