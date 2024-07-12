#!/bin/bash

# Author:
# (C) 2024 Thorsten Spille <thorsten@spille-edv.de>

set -euo pipefail

source zamba.conf

wget -O - https://apt.bashclub.org/gpg/bashclub.pub | gpg --dearmor > /usr/share/keyrings/bashclub-keyring.gpg

curl -sS https://installer.cloudpanel.io/ce/v2/install.sh -o install.sh
echo "2aefee646f988877a31198e0d84ed30e2ef7a454857b606608a1f0b8eb6ec6b6 install.sh" | sha256sum -c
DB_ENGINE=MARIADB_10.11 SWAP=false bash install.sh
