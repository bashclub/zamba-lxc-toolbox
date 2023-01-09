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
      apt-key adv --fetch-keys https://pkg.ltec.ch/public/conf/ltec-ag.gpg.key
      echo "deb https://pkg.ltec.ch/public/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/wsdd.list
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

# update packages
apt update
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade
# install required packages
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" $LXC_TOOLSET $ADDITIONAL_PACKAGES rsync acl attr ntpdate rpl net-tools dnsutils ntp cifs-utils samba smbclient winbind libpam-winbind libnss-winbind krb5-user samba-dsdb-modules samba-vfs-modules lmdb-utils

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
systemctl disable --now smbd nmbd winbind systemd-resolved
rm -f /etc/samba/smb.conf

echo -e "$ZMB_ADMIN_PASS" | kinit -V $ZMB_ADMIN_USER
samba-tool domain join $ZMB_REALM DC -k yes --backend-store=mdb

mkdir -p /mnt/sysvol

cat << EOF > /root/.smbcredentials
username=$ZMB_ADMIN_USER
password=$ZMB_ADMIN_PASS
domain=$ZMB_DOMAIN
EOF

echo "//$LXC_DNS/sysvol /mnt/sysvol cifs credentials=/root/.smbcredentials 0 0" >> /etc/fstab

mount.cifs //$LXC_DNS/sysvol /mnt/sysvol -o credentials=/root/.smbcredentials

cat > /etc/cron.d/sysvol-sync << EOF
*/15 * * * * root /usr/bin/rsync -XAavz --delete-after /mnt/sysvol/ /var/lib/samba/sysvol
EOF

/usr/bin/rsync -XAavz --delete-after /mnt/sysvol/ /var/lib/samba/sysvol

ssh-keygen -q -f "$HOME/.ssh/id_rsa" -N "" -b 4096

systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl restart samba-ad-dc $ADDITIONAL_SERVICES
