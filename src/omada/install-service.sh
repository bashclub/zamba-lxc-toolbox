#!/bin/bash

set -euo pipefail

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

inst_mongodb 

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install --no-install-recommends -y -qq default-jre-headless jsvc

inst_bashclub omada

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install --no-install-recommends -y -qq omadac