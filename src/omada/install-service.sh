#!/bin/bash

set -euo pipefail

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor > /usr/share/keyrings/adoptium-keyring.gpg
wget -O - https://apt.bashclub.org/gpg/bashclub.pub | gpg --dearmor > /usr/share/keyrings/bashclub-keyring.gpg
wget -O - https://pgp.mongodb.com/server-4.4.asc | gpg --dearmor > /usr/share/keyrings/mongodb-server-4.4.gpg
echo "deb [signed-by=/usr/share/keyrings/bashclub-keyring.gpg] https://apt.bashclub.org/omada $(lsb_release -cs 2>/dev/null) main" > /etc/apt/sources.list.d/bashclub-omada.list
echo "deb [signed-by=/usr/share/keyrings/adoptium-keyring.gpg] https://packages.adoptium.net/artifactory/deb $(lsb_release -cs 2>/dev/null) main" > /etc/apt/sources.list.d/adoptium.list
echo "deb [signed-by=/usr/share/keyrings/mongodb-server-4.4.gpg] http://repo.mongodb.org/apt/debian buster/mongodb-org/4.4 main" > /etc/apt/sources.list.d/mongodb-org-7.0.list

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install --no-install-recommends -y -qq temurin-8-jre jsvc mongodb-org
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install --no-install-recommends -y -qq omadac