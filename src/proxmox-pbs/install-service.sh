#!/bin/bash

set -euo pipefail

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

#### Set repo and install onlyoffice ####
inst_pbs() {
    apt_repo "proxmox" "https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg" "http://download.proxmox.com/debian/pbs" "trixie" "pbs-no-subscription"
apt update && apt upgrade -y
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" proxmox-backup-server
}

inst_pbs

proxmox-backup-manager datastore create $PBS_DATA /$LXC_SHAREFS_MOUNTPOINT/$PBS_DATA

systemctl disable --now zfs-mount.service zfs-share.service
