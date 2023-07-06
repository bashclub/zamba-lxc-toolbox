#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

cat << EOF > /etc/apt/sources.list.d/pbs-no-subscription.list 
# PBS pbs-no-subscription repository provided by proxmox.com,
# NOT recommended for production use
deb http://download.proxmox.com/debian/pbs $(lsb_release -cs) pbs-no-subscription
EOF

wget -q -O - https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg >/dev/null

apt update && apt upgrade -y
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" proxmox-backup-server

proxmox-backup-manager datastore create $PBS_DATA /$LXC_SHAREFS_MOUNTPOINT/$PBS_DATA

systemctl disable --now zfs-mount.service zfs-share.service
