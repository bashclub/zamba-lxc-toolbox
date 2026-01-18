#!/bin/bash

# Author:
# (C) 2024 Thorsten Spille <thorsten@spille-edv.de>

set -euo pipefail

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

inst_bashclub manticore
inst_bashclub $PILER_BRANCH

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends piler

echo -e "Installation of piler finished."
echo -e "\nFor administration please visit the following Website:"
echo -e "\thttps://${LXC_HOSTNAME}.${LXC_DOMAIN}/"
echo -e "\nLogin with following credentials:"
echo -e "\tUser: admin@local"
echo -e "\tPass: pilerrocks"
echo -e "\n\nPlease have a look the the GOBD notes (in German):"
echo -e "\thttps://${LXC_HOSTNAME}.${LXC_DOMAIN}/gobd"