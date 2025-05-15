#!/bin/bash

# Author:
# (C) 2024 Thorsten Spille <thorsten@spille-edv.de>

set -euo pipefail

source zamba.conf

wget -O - https://apt.bashclub.org/gpg/bashclub.pub | gpg --dearmor > /usr/share/keyrings/bashclub-keyring.gpg

curl -sS https://installer.cloudpanel.io/ce/v2/install.sh -o install.sh
echo "a3ba69a8102345127b4ae0e28cfe89daca675cbc63cd39225133cdd2fa02ad36 install.sh" | sha256sum -c
DB_ENGINE=MARIADB_11.4 SWAP=false bash install.sh
