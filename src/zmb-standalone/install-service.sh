#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

# add wsdd package repo
apt-key adv --fetch-keys https://pkg.ltec.ch/public/conf/ltec-ag.gpg.key
apt-key adv --fetch-keys https://repo.45drives.com/key/gpg.asc
echo "deb https://repo.45drives.com/debian focal main" > /etc/apt/sources.list.d/45drives.list
echo "deb https://pkg.ltec.ch/public/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/wsdd.list
echo "deb http://ftp.de.debian.org/debian $(lsb_release -cs)-backports main contrib" > /etc/apt/sources.list.d/$(lsb_release -cs)-backports.list

cat << EOF > /etc/apt/preferences.d/samba
Package: samba
Pin: release a=$(lsb_release -cs)-backports
Pin-Priority: 900
EOF

cat << EOF > /etc/apt/preferences.d/winbind
Package: winbind
Pin: release a=$(lsb_release -cs)-backports
Pin-Priority: 900
EOF

cat << EOF > /etc/apt/preferences.d/cockpit
Package: cockpit*
Pin: release a=$(lsb_release -cs)-backports
Pin-Priority: 900
EOF

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" -t $(lsb_release -cs)-backports acl samba samba-common samba-common-bin samba-dsdb-modules samba-vfs-modules samba-libs libwbclient0 winbind wsdd
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" --no-install-recommends cockpit cockpit-identities cockpit-file-sharing cockpit-navigator

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
    server role = standalone server
    obey pam restrictions = yes
    unix password sync = yes
    passwd program = /usr/bin/passwd %u
    passwd chat = *Enter\snew\s*\password:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
    pam password change = yes
    map to guest = bad user
    map acl inherit = yes
    acl_xattr:ignore system acls = yes
    vfs objects = shadow_copy2 acl_xattr catia fruit streams_xattr full_audit
    shadow: snapdir = .zfs/snapshot
    shadow: sort = desc
    shadow: format = -%Y-%m-%d-%H%M
    shadow: snapprefix = ^zfs-auto-snap_\(frequent\)\{0,1\}\(hourly\)\{0,1\}\(daily\)\{0,1\}\(weekly\)\{0,1\}\(monthly\)\{0,1\}
    shadow: delimiter = -20
    fruit:encoding = native
	fruit:metadata = stream
	fruit:zero_file_id = yes
	fruit:nfs_aces = no
    full_audit:priority = notice
    full_audit:facility = local5
    full_audit:success = connect disconnect mkdir rmdir read write rename
    full_audit:failure = connect
    full_audit:prefix = %u|%I|%S
EOF

net conf import /etc/samba/import.template

net conf addshare $ZMB_SHARE /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE
net conf setparm $ZMB_SHARE readonly no
net conf setparm $ZMB_SHARE createmask 0660
net conf setparm $ZMB_SHARE directorymask 0770

mkdir -p /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE
chmod -R 770 /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE
chown -R $USER:root /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE

systemctl restart smbd nmbd wsdd
