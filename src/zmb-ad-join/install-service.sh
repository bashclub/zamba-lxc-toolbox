#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

set -euo pipefail

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

# echo "deb http://deb.debian.org/debian/ bookworm-backports main contrib" >> /etc/apt/sources.list

# update packages
apt update
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade
# install required packages
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" $LXC_TOOLSET ntpsec-ntpdate rpl net-tools dnsutils chrony sipcalc
# DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -t bookworm-backports -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" acl attr samba smbclient winbind libpam-winbind libnss-winbind krb5-user samba-dsdb-modules samba-vfs-modules lmdb-utils rsync cifs-utils
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" acl attr samba samba-ad-dc smbclient winbind libpam-winbind libnss-winbind krb5-user samba-dsdb-modules samba-vfs-modules lmdb-utils rsync cifs-utils ldb-tools ldap-utils

mkdir -p /etc/chrony/conf.d
mkdir -p /etc/systemd/system/chrony.service.d

cat << EOF > /etc/default/chrony
# This is a configuration file for /etc/init.d/chrony and
# /lib/systemd/system/chrony.service; it allows you to pass various options to
# the chrony daemon without editing the init script or service file.

# Options to pass to chrony.
DAEMON_OPTS="-x -F 1"
EOF

cat << EOF > /etc/systemd/system/chrony.service.d/override.conf
[Unit]
ConditionCapability=
EOF

cat << EOF > /etc/chrony/conf.d/samba.conf
bindcmdaddress $(sipcalc ${LXC_IP} | grep -m1 "Host address" | rev | cut -d' ' -f1 | rev)
server de.pool.ntp.org iburst
server europe.pool.ntp.org iburst
allow $(sipcalc ${LXC_IP} | grep -m1 "Network address" | rev | cut -d' ' -f1 | rev)/$(sipcalc ${LXC_IP} | grep -m1 "Network mask (bits)" | rev | cut -d' ' -f1 | rev)
ntpsigndsocket /var/lib/samba/ntp_signd
EOF

mv /etc/krb5.conf /etc/krb5.conf.bak
cat > /etc/krb5.conf <<EOF
[libdefaults]
	default_realm = $ZMB_REALM
	ticket_lifetime = 600
	dns_lookup_realm = true
	dns_lookup_kdc = true
	renew_lifetime = 7d
EOF

# stop + disable samba services and remove default config
systemctl disable --now smbd nmbd winbind > /dev/null 2>&1
rm -f /etc/samba/smb.conf

echo "fixing samba service to wait for lxc being online"

install -d -m 0755 /etc/systemd/system/samba-ad-dc.service.d

cat <<'EOF' > /etc/systemd/system/samba-ad-dc.service.d/wait-net.conf
[Unit]
After=networking.service
Wants=networking.service

[Service]
# Wait up to 30s for eth0 to get an IPv4 address
ExecStartPre=/bin/sh -c 'for i in $(seq 1 30); do ip -4 addr show dev eth0 scope global | grep -q inet && exit 0; sleep 1; done; echo "Network not ready" >&2; exit 1'

Restart=on-failure
RestartSec=3
EOF

systemctl daemon-reload

echo -e "$ZMB_ADMIN_PASS" | kinit -V $ZMB_ADMIN_USER
samba-tool domain join $ZMB_REALM DC --use-kerberos=required --backend-store=mdb


rm /etc/krb5.conf
ln -sf /var/lib/samba/private/krb5.conf /etc/krb5.conf

mkdir -p /mnt/sysvol

cat << EOF > /root/.smbcredentials
username=$ZMB_ADMIN_USER
password=$ZMB_ADMIN_PASS
domain=$ZMB_DOMAIN
EOF

echo "//$LXC_DNS/sysvol /mnt/sysvol cifs credentials=/root/.smbcredentials 0 0" >> /etc/fstab

mount.cifs //$LXC_DNS/sysvol /mnt/sysvol -o credentials=/root/.smbcredentials

cat > /etc/cron.d/sysvol-sync << EOF
*/15 * * * * root /usr/bin/rsync -XAavz --delete-after /mnt/sysvol/ /var/lib/samba/sysvol; if ! /usr/bin/samba-tool ntacl sysvolcheck > /dev/null 2>&1 ; then /usr/bin/samba-tool ntacl sysvolreset ; fi
EOF

/usr/bin/rsync -XAavz --delete-after /mnt/sysvol/ /var/lib/samba/sysvol

if ! samba-tool ntacl sysvolcheck > /dev/null 2>&1 ; then
  samba-tool ntacl sysvolreset
fi

ssh-keygen -q -f "$HOME/.ssh/id_rsa" -N "" -b 4096

systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl restart samba-ad-dc

bash /root/zmb-ad_auto-map-root.sh
chmod +x /usr/bin/create-service-account

# configure ad backup
inst_smb_backup
