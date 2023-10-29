#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

ZMB_DNS_BACKEND="SAMBA_INTERNAL"

for f in ${OPTIONAL_FEATURES[@]}; do
  if [[ "$f" == "wsdd" ]]; then
    ADDITIONAL_PACKAGES="wsdd $ADDITIONAL_PACKAGES"
    ADDITIONAL_SERVICES="wsdd $ADDITIONAL_SERVICES"
  elif [[ "$f" == "splitdns" ]]; then
    ADDITIONAL_PACKAGES="nginx-full $ADDITIONAL_PACKAGES"
    ADDITIONAL_SERVICES="nginx $ADDITIONAL_SERVICES"
  elif [[ "$f" == "bind9dlz" ]]; then
    ZMB_DNS_BACKEND="BIND9_DLZ"
    ADDITIONAL_PACKAGES="bind9 $ADDITIONAL_PACKAGES"
    ADDITIONAL_SERVICES="bind9 $ADDITIONAL_SERVICES"
  else
    echo "Unsupported optional feature $f"
  fi
done

## configure ntp
cat << EOF > /etc/ntp.conf
# Local clock. Note that is not the "localhost" address!
server 127.127.1.0
fudge  127.127.1.0 stratum 10

# Where to retrieve the time from
server 0.de.pool.ntp.org     iburst prefer
server 1.de.pool.ntp.org     iburst prefer
server 2.de.pool.ntp.org     iburst prefer

driftfile       /var/lib/ntp/ntp.drift
logfile         /var/log/ntp
ntpsigndsocket  /usr/local/samba/var/lib/ntp_signd/

# Access control
# Default restriction: Allow clients only to query the time
restrict default kod nomodify notrap nopeer mssntp

# No restrictions for "localhost"
restrict 127.0.0.1

# Enable the time sources to only provide time to this host
restrict 0.pool.ntp.org   mask 255.255.255.255    nomodify notrap nopeer noquery
restrict 1.pool.ntp.org   mask 255.255.255.255    nomodify notrap nopeer noquery
restrict 2.pool.ntp.org   mask 255.255.255.255    nomodify notrap nopeer noquery

tinker panic 0
EOF

echo "deb http://ftp.halifax.rwth-aachen.de/debian/ bookworm-backports main contrib" >> /etc/apt/sources.list

# update packages
apt update
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade
# install required packages
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" $LXC_TOOLSET $ADDITIONAL_PACKAGES ntpdate rpl net-tools dnsutils ntp
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -t bookworm-backports -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" acl attr samba smbclient winbind libpam-winbind libnss-winbind krb5-user samba-dsdb-modules samba-vfs-modules lmdb-utils

if [[ "$ADDITIONAL_PACKAGES" == *"nginx-full"* ]]; then
  cat << EOF > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    server_name _;
    return 301 http://www.$LXC_DOMAIN\$request_uri;
}
EOF
fi

if  [[ "$ADDITIONAL_PACKAGES" == *"bind9"* ]]; then
  # configure bind dns service
  cat << EOF > /etc/default/bind9
#
# run resolvconf?
RESOLVCONF=no

# startup options for the server
OPTIONS="-4 -u bind"
EOF

  cat << EOF > /etc/bind/named.conf.local
//
// Do any local configuration here
//

// Consider adding the 1918 zones here, if they are not used in your
// organization
//include "/etc/bind/zones.rfc1918";
dlz "$LXC_DOMAIN" {
  database "dlopen /usr/lib/x86_64-linux-gnu/samba/bind9/dlz_bind9_11.so";
};
EOF

  cat << EOF > /etc/bind/named.conf.options
options {
  directory "/var/cache/bind";

  forwarders {
    $LXC_DNS;
  };

  allow-query {  any;};
  dnssec-validation no;

  auth-nxdomain no;    # conform to RFC1035
  listen-on-v6 { any; };
  listen-on { any; };

  tkey-gssapi-keytab "/var/lib/samba/bind-dns/dns.keytab";
  minimal-responses yes;
};
EOF

  mkdir -p /var/lib/samba/bind-dns/dns
fi

# stop + disable samba services and remove default config
systemctl disable --now smbd nmbd winbind systemd-resolved
rm -f /etc/samba/smb.conf
rm -f /etc/krb5.conf

# provision zamba domain
samba-tool domain provision --use-rfc2307 --realm=$ZMB_REALM --domain=$ZMB_DOMAIN --adminpass=$ZMB_ADMIN_PASS --server-role=dc --backend-store=mdb --dns-backend=$ZMB_DNS_BACKEND

ln -sf /var/lib/samba/private/krb5.conf /etc/krb5.conf

# disable password expiry for administrator
samba-tool user setexpiry Administrator --noexpiry

systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl restart samba-ad-dc $ADDITIONAL_SERVICES

# configure ad backup
cat << EOF > /usr/local/bin/smb-backup
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

rc=0
keep=$1
if \$1 ; then
  keep=\$1
fi

mkdir -p /${LXC_SHAREFS_MOUNTPOINT}/{online,offline}

prune () {
  backup_type=\$1
  if [ \$(find /${LXC_SHAREFS_MOUNTPOINT}/\$backup_type/*.tar.bz2 | wc -l) -gt \$keep ]; then
    find /${LXC_SHAREFS_MOUNTPOINT}/\$backup_type/*.tar.bz2 | head --lines=-\$keep | xargs -d '\n' rm
  fi
}

echo "\$(date) Starting samba-ad-dc online backup"
if echo -e "${LXC_ADMIN_PASS}" | samba-tool domain backup online --targetdir=/${LXC_SHAREFS_MOUNTPOINT}/online --server=${LXC_HOSTNAME}.${LXC_DOMAIN} -UAdministrator ; then
  echo "\$(date) Finished samba-ad-dc online backup. Cleaning up old online backups..."
  prune online
else
  echo "\$(date) samba-ad-dc online backup failed"
  rc=\$((\$rc + 1))
fi

echo "\$(date) Starting samba-ad-dc offline backup"
if samba-tool domain backup offline --targetdir=/${LXC_SHAREFS_MOUNTPOINT}/offline ; then 
  echo "\$(date) Finished samba-ad-dc offline backup. Cleaning up old offline backups..."
  prune offline
else
  echo "S(date) samba-ad-dc offline backup failed"
  rc=\$((\$rc + 1))
fi

exit \$rc
EOF
chmod +x /usr/local/bin/smb-backup

cat << EOF > /etc/cron.d/smb-backup
23 * * * * root /usr/local/bin/smb-backup 7 >> /var/log/smb-backup.log 2>&1
EOF

cat << EOF > /etc/logrotate.d/smb-backup
/var/log/smb-backup.log {
        weekly
        rotate 12
        compress
        delaycompress
        missingok
        notifempty
        create 644 root root
}
EOF

smb-backup 7

exit 0