#!/bin/bash

set -euo pipefail

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

wget -qO - https://adoptopenjdk.jfrog.io/adoptopenjdk/api/gpg/key/public | apt-key add -
add-apt-repository --yes https://adoptopenjdk.jfrog.io/adoptopenjdk/deb/

wget -O /etc/apt/trusted.gpg.d/mongodb-4.4.asc https://www.mongodb.org/static/pgp/server-4.4.asc

echo "deb http://repo.mongodb.org/apt/debian buster/mongodb-org/4.4 main" > /etc/apt/sources.list.d/mongodb.list

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq adoptopenjdk-8-hotspot jsvc mongodb-org

DL=$(wget -O - -q  https://www.tp-link.com/de/support/download/omada-software-controller/ 2>/dev/null | grep Download-Detail-Software_Omada-Software-Controller | grep "Linux_x64.deb" | head -1 | cut -d'"' -f6)

wget -O /tmp/omada.deb -q $DL

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq /tmp/omada.deb