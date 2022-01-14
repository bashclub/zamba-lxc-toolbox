#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/zamba.conf
source /root/constants-service.conf

mkdir /$LXC_SHAREFS_MOUNTPOINT/$URBACKUP_DATA
mkdir /etc/urbackup
echo "/$LXC_SHAREFS_MOUNTPOINT/$URBACKUP_DATA" > /etc/urbackup/backupfolder

echo 'deb http://download.opensuse.org/repositories/home:/uroni/Debian_10/ /' | tee /etc/apt/sources.list.d/home:uroni.list
curl -fsSL https://download.opensuse.org/repositories/home:uroni/Debian_10/Release.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/home_uroni.gpg > /dev/null

apt update
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y --no-install-recommends -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" urbackup-server
chown urbackup:urbackup /$LXC_SHAREFS_MOUNTPOINT/$URBACKUP_DATA