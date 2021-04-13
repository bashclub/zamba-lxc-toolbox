#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <helmke@cloudistboese.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

# configure system language
dpkg-reconfigure locales

source /root/zamba.conf

if [[ $ZMB_DNS_BACKEND == "BIND9_DLZ" ]]; then
  BINDNINE=bind9
fi

# Set Timezone
ln -sf /usr/share/zoneinfo/$LXC_TIMEZONE /etc/localtime

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

# update packages
apt update
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade
# install required packages
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" $LXC_TOOLSET acl attr ntpdate nginx-full rpl net-tools dnsutils ntp samba smbclient winbind libpam-winbind libnss-winbind krb5-user samba-dsdb-modules samba-vfs-modules lmdb-utils $BINDNINE

if [[ $ZMB_DNS_BACKEND == "BIND9_DLZ" ]]; then
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
systemctl stop smbd nmbd winbind
systemctl disable smbd nmbd winbind
rm -f /etc/samba/smb.conf
rm -f /etc/krb5.conf

# provision zamba domain
samba-tool domain provision --use-rfc2307 --realm=$ZMB_REALM --domain=$ZMB_DOMAIN --adminpass=$ZMB_ADMIN_PASS --server-role=dc --backend-store=mdb --dns-backend=$ZMB_DNS_BACKEND

cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc $BINDNINE
systemctl restart samba-ad-dc $BINDNINE

exit 0