#!/bin/bash

set -euo pipefail

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

echo "ecodmsserver ecodmsserver/language string german" | debconf-set-selections
echo "ecodmsserver ecodmsserver/license string true" | debconf-set-selections

echo -e "deb http://www.ecodms.de/${ECODMS_RELEASE}/$(lsb_release -cs) /" > /etc/apt/sources.list.d/ecodms.list
wget -qO- http://www.ecodms.de/gpg/ecodms.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/ecodms.gpg

apt update
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install ecodmsserver