#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

echo "deb http://deb.debian.org/debian/ bookworm-backports main contrib" >> /etc/apt/sources.list

apt update

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -t bookworm-backports -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" acl cups samba winbind libpam-winbind libnss-winbind krb5-user krb5-config samba-dsdb-modules samba-vfs-modules wsdd

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

	dns proxy = No
	shadow: snapdir = .zfs/snapshot
	shadow: sort = desc
	shadow: format = -%Y-%m-%d-%H%M
	shadow: snapprefix = ^zfs-auto-snap_\(frequent\)\{0,1\}\(hourly\)\{0,1\}\(daily\)\{0,1\}\(weekly\)\{0,1\}\(monthly\)\{0,1\}\(backup\)\{0,1\}\(manual\)\{0,1\}
	shadow: delimiter = -20
	
	printing = CUPS
	rpcd_spoolss:idle_seconds=300
	rpcd_spoolss:num_workers = 10
	spoolss: architecture = Windows x64

[printers]
	path = /${LXC_SHAREFS_MOUNTPOINT}/spool
	printable = yes

[print$]
	path = /${LXC_SHAREFS_MOUNTPOINT}/printerdrivers
	read only = no

EOF

systemctl restart smbd

echo -e "$ZMB_ADMIN_PASS" | net ads join -U $ZMB_ADMIN_USER createcomputer=Computers
sed -i "s|files systemd|files systemd winbind|g" /etc/nsswitch.conf
sed -i "s|#WINBINDD_OPTS=|WINBINDD_OPTS=|" /etc/default/winbind
echo -e "session optional        pam_mkhomedir.so skel=/etc/skel umask=077" >> /etc/pam.d/common-session

systemctl restart winbind nmbd

mkdir -p /${LXC_SHAREFS_MOUNTPOINT}/{spool,printerdrivers}
cp -rv /var/lib/samba/printers/* /${LXC_SHAREFS_MOUNTPOINT}/printerdrivers
chown -R root:"domain admins" /${LXC_SHAREFS_MOUNTPOINT}/printerdrivers
chmod -R 1777 /${LXC_SHAREFS_MOUNTPOINT}/spool
chmod -R 2775 /${LXC_SHAREFS_MOUNTPOINT}/printerdrivers
setfacl -Rb /${LXC_SHAREFS_MOUNTPOINT}/printerdrivers
setfacl -Rm u:${ZMB_ADMIN_USER}:rwx,g:"domain admins":rwx,g:"NT Authority/authenticated users":r-x,o::--- /${LXC_SHAREFS_MOUNTPOINT}/printerdrivers
setfacl -Rdm u:${ZMB_ADMIN_USER}:rwx,g:"domain admins":rwx,g:"NT Authority/authenticated users":r-x,o::--- /${LXC_SHAREFS_MOUNTPOINT}/printerdrivers
echo -e "${ZMB_ADMIN_PASS}" | net rpc rights grant "${ZMB_DOMAIN}\\domain admins" SePrintOperatorPrivilege -U "${ZMB_DOMAIN}\\${ZMB_ADMIN_USER}"
systemctl disable --now cups-browsed.service

cupsctl --remote-admin

systemctl restart cups smbd nmbd winbind wsdd