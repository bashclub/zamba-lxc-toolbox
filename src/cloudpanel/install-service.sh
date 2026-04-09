#!/bin/bash

# Author:
# (C) 2024 Thorsten Spille <thorsten@spille-edv.de>

set -euo pipefail

source zamba.conf

wget -O - https://apt.bashclub.org/gpg/bashclub.pub | gpg --dearmor > /usr/share/keyrings/bashclub-keyring.gpg

curl -sS https://installer.cloudpanel.io/ce/v2/install.sh -o install.sh
DB_ENGINE=MARIADB_11.8 SWAP=false bash install.sh
