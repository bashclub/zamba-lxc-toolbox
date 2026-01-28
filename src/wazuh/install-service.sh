#!/bin/bash

# Author:
# (C) 2024 Thorsten Spille <thorsten@spille-edv.de>

set -euo pipefail

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

WAZUH_VERSION=4.14
REG_PASS=$(random_password)

curl -sO https://packages.wazuh.com/$WAZUH_VERSION/wazuh-install.sh && sudo bash ./wazuh-install.sh -a -i 2>/dev/null


sed -i "s|<use_password>no</use_password>|<use_password>yes</use_password>|" /var/ossec/etc/ossec.conf
echo "$REG_PASS" > /var/ossec/etc/authd.pass
chmod 640 /var/ossec/etc/authd.pass
chown root:wazuh /var/ossec/etc/authd.pass
systemctl restart wazuh-manager

echo "Please use the following password for agent registration: $REG_PASS"