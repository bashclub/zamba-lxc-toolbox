#!/bin/bash

# Author:
# (C) 2024 Thorsten Spille <thorsten@spille-edv.de>

source zamba.conf

wget -O - https://apt.bashclub.org/gpg/bashclub.pub | gpg --dearmor > /usr/share/keyrings/bashclub-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/bashclub-keyring.gpg] https://apt.bashclub.org/manticore bookworm main" > /etc/apt/sources.list.d/bashclub-manticore.list
echo "deb [signed-by=/usr/share/keyrings/bashclub-keyring.gpg] https://apt.bashclub.org/$PILER_BRANCH bookworm main" > /etc/apt/sources.list.d/bashclub-testing.list
apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends piler

echo -e "Installation of piler finished."
echo -e "\nFor administration please visit the following Website:"
echo -e "\thttps://${LXC_HOSTNAME}.${LXC_DOMAIN}/"
echo -e "\nLogin with following credentials:"
echo -e "\tUser: admin@local"
echo -e "\tPass: pilerrocks"
echo -e "\n\nPlease have a look the the GOBD notes (in German):"
echo -e "\thttps://${LXC_HOSTNAME}.${LXC_DOMAIN}/gobd"