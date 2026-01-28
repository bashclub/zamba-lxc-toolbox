#!/bin/bash

# Author:
# (C) 2024 Thorsten Spille <thorsten@spille-edv.de>

set -euo pipefail

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

WAZUH_VERSION=4.14
curl -sO https://packages.wazuh.com/$WAZUH_VERSION/wazuh-install.sh && sudo bash ./wazuh-install.sh -a -i 2>/dev/null
