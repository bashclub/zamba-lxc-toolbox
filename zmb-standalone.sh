#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <helmke@cloudistboese.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

# configure system language
dpkg-reconfigure locales

source /root/zamba.conf

# Set Timezone
ln -sf /usr/share/zoneinfo/$LXC_TIMEZONE /etc/localtime

apt update
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" $LXC_TOOLSET acl samba samba-dsdb-modules samba-vfs-modules 

USER=$(echo "$ZMB_ADMIN_USER" | awk '{print tolower($0)}')
useradd --comment "Zamba fileserver admin" --create-home --shell /bin/bash $USER
echo "$USER:$ZMB_ADMIN_PASS" | chpasswd
smbpasswd -x $USER
(echo $ZMB_ADMIN_PASS; echo $ZMB_ADMIN_PASS) | smbpasswd -a $USER

cat << EOF >> /etc/samba/smb.conf
[share]
    comment = Main Share
    path = /tank/share
    read only = No
    vfs objects = shadow_copy2
    shadow: snapdir = .zfs/snapshot
    shadow: sort = desc
    shadow: format = -%Y-%m-%d-%H%M
    shadow: snapprefix = ^zfs-auto-snap_\(frequent\)\{0,1\}\(hourly\)\{0,1\}\(daily\)\{0,1\}\(monthly\)\{0,1\}
    shadow: delimiter = -20
EOF

chmod -R 770 /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE
chown -R '$ZMB_ADMIN_USER':root /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE

systemctl restart smbd nmbd 
