#!/bin/bash

set -euo pipefail

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

wget -O - https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor > /usr/share/keyrings/mongodb7.gpg
wget -O - https://dl.ubnt.com/unifi/unifi-repo.gpg | gpg --dearmor > /usr/share/keyrings/unifi.gpg

echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
echo "deb [ signed-by=/usr/share/keyrings/unifi.gpg ] http://www.ui.com/downloads/unifi/debian stable ubiquiti" > /etc/apt/sources.list.d/unifi.list 

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq default-jre-headless unifi