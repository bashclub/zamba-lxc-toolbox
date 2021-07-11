#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/zamba.conf
source /root/constants-service.conf

# add wsdd package repo
apt-key adv --fetch-keys https://pkg.ltec.ch/public/conf/ltec-ag.gpg.key
echo "deb https://pkg.ltec.ch/public/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/wsdd.list
echo "deb http://ftp.de.debian.org/debian buster-backports main contrib" > /etc/apt/sources.list.d/buster-backports.list

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" acl samba samba-dsdb-modules samba-vfs-modules wsdd
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" --no-install-recommends -t buster-backports cockpit

mkdir /usr/share/cockpit/smb
wget https://raw.githubusercontent.com/enira/cockpit-smb-plugin/master/index.html -O /usr/share/cockpit/smb/index.html
wget https://raw.githubusercontent.com/enira/cockpit-smb-plugin/master/manifest.json -O /usr/share/cockpit/smb/manifest.json
wget https://raw.githubusercontent.com/enira/cockpit-smb-plugin/master/smb.js -O /usr/share/cockpit/smb/smb.js

USER=$(echo "$ZMB_ADMIN_USER" | awk '{print tolower($0)}')
useradd --comment "Zamba fileserver admin" --create-home --shell /bin/bash $USER
echo "$USER:$ZMB_ADMIN_PASS" | chpasswd
smbpasswd -x $USER
(echo $ZMB_ADMIN_PASS; echo $ZMB_ADMIN_PASS) | smbpasswd -a $USER

cat << EOF >> /etc/samba/smb.conf
[$ZMB_SHARE]
    comment = Main Share
    path = /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE
    read only = No
    vfs objects = shadow_copy2
    shadow: snapdir = .zfs/snapshot
    shadow: sort = desc
    shadow: format = -%Y-%m-%d-%H%M
    shadow: snapprefix = ^zfs-auto-snap_\(frequent\)\{0,1\}\(hourly\)\{0,1\}\(daily\)\{0,1\}\(weekly\)\{0,1\}\(monthly\)\{0,1\}\(backup\)\{0,1\}\(manual\)\{0,1\}
    shadow: delimiter = -20
EOF

mkdir -p /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE
chmod -R 770 /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE
chown -R $USER:root /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE

systemctl restart smbd nmbd wsdd
