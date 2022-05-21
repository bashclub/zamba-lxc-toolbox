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
echo "deb https://pkg.ltec.ch/public/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/wsdd.list

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" acl samba winbind libpam-winbind libnss-winbind krb5-user krb5-config samba-dsdb-modules samba-vfs-modules wsdd

mv /etc/krb5.conf /etc/krb5.conf.bak
cat > /etc/krb5.conf <<EOF
[libdefaults]
	default_realm = $ZMB_REALM
    ticket_lifetime = 600
	dns_lookup_realm = true
	dns_lookup_kdc = true
	renew_lifetime = 7d
EOF

echo -e "$ZMB_ADMIN_PASS" | kinit -V $ZMB_ADMIN_USER
klist

mv /etc/samba/smb.conf /etc/samba/smb.conf.bak
cat > /etc/samba/smb.conf <<EOF
[global]
	workgroup = $ZMB_DOMAIN
	security = ADS
	realm = $ZMB_REALM
	server string = %h server

	vfs objects = acl_xattr shadow_copy2
    map acl inherit = Yes
    store dos attributes = Yes
	idmap config *:backend = tdb
	idmap config *:range = 3000000-4000000
	idmap config *:schema_mode = rfc2307

	winbind refresh tickets = Yes
	winbind use default domain = Yes
	winbind separator = /
	winbind nested groups = yes
	winbind nss info = rfc2307

	pam password change = Yes
	passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
	passwd program = /usr/bin/passwd %u

	template homedir = /home/%U
	template shell = /bin/bash
	bind interfaces only = Yes
	interfaces = lo eth0
	log file = /var/log/samba/log.%m
	logging = syslog
	max log size = 1000
	panic action = /usr/share/samba/panic-action %d

	load printers = No
	printcap name = /dev/null
	printing = bsd
	disable spoolss = Yes

	dns proxy = No
	shadow: snapdir = .zfs/snapshot
	shadow: sort = desc
	shadow: format = -%Y-%m-%d-%H%M
	shadow: snapprefix = ^zfs-auto-snap_\(frequent\)\{0,1\}\(hourly\)\{0,1\}\(daily\)\{0,1\}\(weekly\)\{0,1\}\(monthly\)\{0,1\}\(backup\)\{0,1\}\(manual\)\{0,1\}
	shadow: delimiter = -20

[$ZMB_SHARE]
	comment = Main Share
	path = /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE
	read only = No
	create mask = 0660
	directory mask = 0770
	inherit acls = Yes

EOF

systemctl restart smbd

echo -e "$ZMB_ADMIN_PASS" | net ads join -U $ZMB_ADMIN_USER createcomputer=Computers
sed -i "s|files systemd|files systemd winbind|g" /etc/nsswitch.conf
sed -i "s|#WINBINDD_OPTS=|WINBINDD_OPTS=|" /etc/default/winbind
echo -e "session optional        pam_mkhomedir.so skel=/etc/skel umask=077" >> /etc/pam.d/common-session

systemctl restart winbind nmbd
wbinfo -u
wbinfo -g

mkdir /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE

# originally 'domain users' was set, added variable for domain admins group, samba wiki recommends separate group e.g. 'unix admins'
chown "${ZMB_ADMIN_USER@L}" /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE

setfacl -Rm u:${ZMB_ADMIN_USER@L}:rwx,g::-,o::- /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE
setfacl -Rdm u:${ZMB_ADMIN_USER@L}:rwx,g::-,o::- /$LXC_SHAREFS_MOUNTPOINT/$ZMB_SHARE

systemctl restart smbd nmbd winbind wsdd
