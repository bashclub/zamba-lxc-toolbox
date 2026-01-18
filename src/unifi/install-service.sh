#!/bin/bash

set -euo pipefail

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

inst_unifi() {
    apt_repo "unifi" "https://dl.ubnt.com/unifi/unifi-repo.gpg" "http://www.ui.com/downloads/unifi/debian" "stable" "ubiquiti"
    apt update 
    DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends unifi
}

inst_mongodb

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq default-jre-headless

inst_unifi