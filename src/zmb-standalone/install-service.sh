#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

apt-key adv --fetch-keys https://repo.45drives.com/key/gpg.asc
echo "deb https://repo.45drives.com/debian focal main" > /etc/apt/sources.list.d/45drives.list

echo "deb http://ftp.halifax.rwth-aachen.de/debian/ bookworm-backports main contrib" >> /etc/apt/sources.list

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -t bookworm-backports -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" acl samba samba-common samba-common-bin samba-dsdb-modules samba-vfs-modules samba-libs libwbclient0 winbind wsdd
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -t bookworm-backports -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" --no-install-recommends cockpit cockpit-identities cockpit-file-sharing cockpit-navigator

USER=$(echo "$ZMB_ADMIN_USER" | awk '{print tolower($0)}')
useradd --comment "Zamba fileserver admin" --create-home --shell /bin/bash $USER
echo "$USER:$ZMB_ADMIN_PASS" | chpasswd
smbpasswd -x $USER
(echo $ZMB_ADMIN_PASS; echo $ZMB_ADMIN_PASS) | smbpasswd -a $USER

usermod -aG sudo $USER

cat << EOF | sudo tee -i /etc/samba/smb.conf
[global]
    include = registry
EOF

cat << EOF | sudo tee -i /etc/samba/import.template
[global]
    workgroup = WORKGROUP
    log file = /var/log/samba/log.%m
    max log size = 1000
    logging = file
    panic action = /usr/share/samba/panic-action %d
    log level = 3
    server role = standalone server
    obey pam restrictions = yes
    unix password sync = yes
    passwd program = /usr/bin/passwd %u
    passwd chat = *Enter\snew\s*\password:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
    pam password change = yes
    map to guest = bad user
    vfs objects = shadow_copy2 acl_xattr catia fruit streams_xattr
    map acl inherit = yes
    acl_xattr:ignore system acls = yes
    shadow: snapdir = .zfs/snapshot
    shadow: sort = desc
    shadow: format = -%Y-%m-%d-%H%M
    shadow: snapprefix = ^zfs-auto-snap_\(frequent\)\{0,1\}\(hourly\)\{0,1\}\(daily\)\{0,1\}\(weekly\)\{0,1\}\(monthly\)\{0,1\}
    shadow: delimiter = -20
    fruit:encoding = native
    fruit:metadata = stream
    fruit:zero_file_id = yes
    fruit:nfs_aces = no
EOF

net conf import /etc/samba/import.template

mkdir -p /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE
chmod -R 770 /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE
chown -R $USER:root /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE

net conf addshare $ZMB_SHARE /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE
net conf setparm $ZMB_SHARE readonly no
net conf setparm $ZMB_SHARE browseable yes
net conf setparm $ZMB_SHARE createmask 0660
net conf setparm $ZMB_SHARE directorymask 0770

systemctl restart smbd nmbd wsdd
