#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

# Add Docker's official GPG key:
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources:
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin jq
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt-get purge -y -qq postfix

SECRET=$(random_password)
myip=$(ip a s dev eth0 | grep -m1 inet | cut -d' ' -f6 | cut -d'/' -f1)

install_portainer_full() {
    mkdir -p /opt/portainer/data
    cd /opt/portainer
    cat << EOF > /opt/portainer/docker-compose.yml
version: "3.4"

services:
  portainer:
    restart: always
    image: portainer/portainer:latest
    volumes:
      - ./data:/data
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - "8000:8000"
      - "9443:9443"
    command: --admin-password-file=/data/admin_password
EOF
    echo -n "$SECRET" > ./data/admin_password

    docker compose pull
    docker compose up -d
    echo -e "\n######################################################################\n\n    You can access Portainer with your browser at https://${myip}:9443\n\n    Please note the following admin password to access the portainer:\n    '$SECRET'\n    Enjoy your Docker intallation.\n\n######################################################################"

}

install_portainer_agent() {
    mkdir -p /opt/portainer-agent/data
    cd /opt/portainer-agent
    cat << EOF > /opt/portainer-agent/docker-compose.yml
version: "3.4"

services:
  portainer:
    restart: always  
    image: portainer/agent:latest
    volumes:
      - /var/lib/docker/volumes:/var/lib/docker/volumes
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - "9001:9001"
EOF

    docker compose pull
    docker compose up -d

    echo -e "\n######################################################################\n\n    Please enter the following data into the Portainer "Add environment" wizard:\n\tEnvironment address: ${myip}:9001\n\n    Enjoy your Docker intallation.\n\n######################################################################"

}

# fix docker errors for slow machines
cat << EOF > /etc/docker/daemon.json
{
  "default-ulimits": {
    "nproc": {
      "name": "nproc",
      "soft": -1,
      "hard": -1
    }
  }
}
EOF
systemctl restart docker


cd /opt
git clone https://github.com/mailcow/mailcow-dockerized
cd mailcow-dockerized

cat << EOF > mailcow.conf
# ------------------------------
# mailcow web ui configuration
# ------------------------------
# example.org is _not_ a valid hostname, use a fqdn here.
# Default admin user is "admin"
# Default password is "moohoo"

MAILCOW_HOSTNAME=${LXC_HOSTNAME}.${LXC_DOMAIN}

# Password hash algorithm
# Only certain password hash algorithm are supported. For a fully list of supported schemes,
# see https://docs.mailcow.email/models/model-passwd/
MAILCOW_PASS_SCHEME=BLF-CRYPT

# ------------------------------
# SQL database configuration
# ------------------------------

DBNAME=mailcow
DBUSER=mailcow

# Please use long, random alphanumeric strings (A-Za-z0-9)

DBPASS=$(LC_ALL=C </dev/urandom tr -dc A-Za-z0-9 2> /dev/null | head -c 28)
DBROOT=$(LC_ALL=C </dev/urandom tr -dc A-Za-z0-9 2> /dev/null | head -c 28)

REDISPASS=$(LC_ALL=C </dev/urandom tr -dc A-Za-z0-9 2> /dev/null | head -c 28)

# ------------------------------
# HTTP/S Bindings
# ------------------------------

# You should use HTTPS, but in case of SSL offloaded reverse proxies:
# Might be important: This will also change the binding within the container.
# If you use a proxy within Docker, point it to the ports you set below.
# Do _not_ use IP:PORT in HTTP(S)_BIND or HTTP(S)_PORT
# IMPORTANT: Do not use port 8081, 9081 or 65510!
# Example: HTTP_BIND=1.2.3.4
# For IPv4 leave it as it is: HTTP_BIND= & HTTPS_PORT=
# For IPv6 see https://docs.mailcow.email/post_installation/firststeps-ip_bindings/

HTTP_PORT=80
HTTP_BIND=

HTTPS_PORT=443
HTTPS_BIND=

# ------------------------------
# Other bindings
# ------------------------------
# You should leave that alone
# Format: 11.22.33.44:25 or 12.34.56.78:465 etc.

SMTP_PORT=25
SMTPS_PORT=465
SUBMISSION_PORT=587
IMAP_PORT=143
IMAPS_PORT=993
POP_PORT=110
POPS_PORT=995
SIEVE_PORT=4190
DOVEADM_PORT=127.0.0.1:19991
SQL_PORT=127.0.0.1:13306
SOLR_PORT=127.0.0.1:18983
REDIS_PORT=127.0.0.1:7654

# Your timezone
# See https://en.wikipedia.org/wiki/List_of_tz_database_time_zones for a list of timezones
# Use the column named 'TZ identifier' + pay attention for the column named 'Notes'

TZ=${LXC_TIMEZONE}

# Fixed project name
# Please use lowercase letters only

COMPOSE_PROJECT_NAME=mailcowdockerized

# Used Docker Compose version
# Switch here between native (compose plugin) and standalone
# For more informations take a look at the mailcow docs regarding the configuration options.
# Normally this should be untouched but if you decided to use either of those you can switch it manually here.
# Please be aware that at least one of those variants should be installed on your machine or mailcow will fail.

DOCKER_COMPOSE_VERSION=native

# Set this to "allow" to enable the anyone pseudo user. Disabled by default.
# When enabled, ACL can be created, that apply to "All authenticated users"
# This should probably only be activated on mail hosts, that are used exclusivly by one organisation.
# Otherwise a user might share data with too many other users.
ACL_ANYONE=disallow

# Garbage collector cleanup
# Deleted domains and mailboxes are moved to /var/vmail/_garbage/timestamp_sanitizedstring
# How long should objects remain in the garbage until they are being deleted? (value in minutes)
# Check interval is hourly

MAILDIR_GC_TIME=7200

# Additional SAN for the certificate
#
# You can use wildcard records to create specific names for every domain you add to mailcow.
# Example: Add domains "example.com" and "example.net" to mailcow, change ADDITIONAL_SAN to a value like:
#ADDITIONAL_SAN=imap.*,smtp.*
# This will expand the certificate to "imap.example.com", "smtp.example.com", "imap.example.net", "smtp.example.net"
# plus every domain you add in the future.
#
# You can also just add static names...
#ADDITIONAL_SAN=srv1.example.net
# ...or combine wildcard and static names:
#ADDITIONAL_SAN=imap.*,srv1.example.com
#

ADDITIONAL_SAN=

# Additional server names for mailcow UI
#
# Specify alternative addresses for the mailcow UI to respond to
# This is useful when you set mail.* as ADDITIONAL_SAN and want to make sure mail.maildomain.com will always point to the mailcow UI.
# If the server name does not match a known site, Nginx decides by best-guess and may redirect users to the wrong web root.
# You can understand this as server_name directive in Nginx.
# Comma separated list without spaces! Example: ADDITIONAL_SERVER_NAMES=a.b.c,d.e.f

ADDITIONAL_SERVER_NAMES=

# Skip running ACME (acme-mailcow, Let's Encrypt certs) - y/n

SKIP_LETS_ENCRYPT=y

# Create seperate certificates for all domains - y/n
# this will allow adding more than 100 domains, but some email clients will not be able to connect with alternative hostnames
# see https://doc.dovecot.org/admin_manual/ssl/sni_support
ENABLE_SSL_SNI=n

# Skip IPv4 check in ACME container - y/n

SKIP_IP_CHECK=n

# Skip HTTP verification in ACME container - y/n

SKIP_HTTP_VERIFICATION=n

# Skip ClamAV (clamd-mailcow) anti-virus (Rspamd will auto-detect a missing ClamAV container) - y/n

SKIP_CLAMD=n

# Skip SOGo: Will disable SOGo integration and therefore webmail, DAV protocols and ActiveSync support (experimental, unsupported, not fully implemented) - y/n

SKIP_SOGO=n

# Skip Solr on low-memory systems or if you do not want to store a readable index of your mails in solr-vol-1.

SKIP_SOLR=n

# Solr heap size in MB, there is no recommendation, please see Solr docs.
# Solr is a prone to run OOM and should be monitored. Unmonitored Solr setups are not recommended.

SOLR_HEAP=1024

# Allow admins to log into SOGo as email user (without any password)

ALLOW_ADMIN_EMAIL_LOGIN=n

# Enable watchdog (watchdog-mailcow) to restart unhealthy containers

USE_WATCHDOG=y

# Send watchdog notifications by mail (sent from watchdog@MAILCOW_HOSTNAME)
# CAUTION:
# 1. You should use external recipients
# 2. Mails are sent unsigned (no DKIM)
# 3. If you use DMARC, create a separate DMARC policy ("v=DMARC1; p=none;" in _dmarc.MAILCOW_HOSTNAME)
# Multiple rcpts allowed, NO quotation marks, NO spaces

#WATCHDOG_NOTIFY_EMAIL=a@example.com,b@example.com,c@example.com
#WATCHDOG_NOTIFY_EMAIL=

# Send notifications to a webhook URL that receives a POST request with the content type "application/json".
# You can use this to send notifications to services like Discord, Slack and others.
#WATCHDOG_NOTIFY_WEBHOOK=https://discord.com/api/webhooks/XXXXXXXXXXXXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# JSON body included in the webhook POST request. Needs to be in single quotes.
# Following variables are available: SUBJECT, BODY
#WATCHDOG_NOTIFY_WEBHOOK_BODY='{"username": "mailcow Watchdog", "content": "**${SUBJECT}**\n${BODY}"}'

# Notify about banned IP (includes whois lookup)
WATCHDOG_NOTIFY_BAN=n

# Send a notification when the watchdog is started.
WATCHDOG_NOTIFY_START=y

# Subject for watchdog mails. Defaults to "Watchdog ALERT" followed by the error message.
#WATCHDOG_SUBJECT=

# Checks if mailcow is an open relay. Requires a SAL. More checks will follow.
# https://www.servercow.de/mailcow?lang=en
# https://www.servercow.de/mailcow?lang=de
# No data is collected. Opt-in and anonymous.
# Will only work with unmodified mailcow setups.
WATCHDOG_EXTERNAL_CHECKS=n

# Enable watchdog verbose logging
WATCHDOG_VERBOSE=n

# Max log lines per service to keep in Redis logs

LOG_LINES=9999

# Internal IPv4 /24 subnet, format n.n.n (expands to n.n.n.0/24)
# Use private IPv4 addresses only, see https://en.wikipedia.org/wiki/Private_network#Private_IPv4_addresses

IPV4_NETWORK=172.22.1

# Internal IPv6 subnet in fc00::/7
# Use private IPv6 addresses only, see https://en.wikipedia.org/wiki/Private_network#Private_IPv6_addresses

IPV6_NETWORK=fd4d:6169:6c63:6f77::/64

# Use this IPv4 for outgoing connections (SNAT)

#SNAT_TO_SOURCE=

# Use this IPv6 for outgoing connections (SNAT)

#SNAT6_TO_SOURCE=

# Create or override an API key for the web UI
# You _must_ define API_ALLOW_FROM, which is a comma separated list of IPs
# An API key defined as API_KEY has read-write access
# An API key defined as API_KEY_READ_ONLY has read-only access
# Allowed chars for API_KEY and API_KEY_READ_ONLY: a-z, A-Z, 0-9, -
# You can define API_KEY and/or API_KEY_READ_ONLY

#API_KEY=
#API_KEY_READ_ONLY=
#API_ALLOW_FROM=172.22.1.1,127.0.0.1

# mail_home is ~/Maildir
MAILDIR_SUB=Maildir

# SOGo session timeout in minutes
SOGO_EXPIRE_SESSION=480

# DOVECOT_MASTER_USER and DOVECOT_MASTER_PASS must both be provided. No special chars.
# Empty by default to auto-generate master user and password on start.
# User expands to DOVECOT_MASTER_USER@mailcow.local
# LEAVE EMPTY IF UNSURE
DOVECOT_MASTER_USER=
# LEAVE EMPTY IF UNSURE
DOVECOT_MASTER_PASS=

# Let's Encrypt registration contact information
# Optional: Leave empty for none
# This value is only used on first order!
# Setting it at a later point will require the following steps:
# https://docs.mailcow.email/troubleshooting/debug-reset_tls/
ACME_CONTACT=

# WebAuthn device manufacturer verification
# After setting WEBAUTHN_ONLY_TRUSTED_VENDORS=y only devices from trusted manufacturers are allowed
# root certificates can be placed for validation under mailcow-dockerized/data/web/inc/lib/WebAuthn/rootCertificates
WEBAUTHN_ONLY_TRUSTED_VENDORS=n

# Spamhaus Data Query Service Key
# Optional: Leave empty for none
# Enter your key here if you are using a blocked ASN (OVH, AWS, Cloudflare e.g) for the unregistered Spamhaus Blocklist. 
# If empty, it will completely disable Spamhaus blocklists if it detects that you are running on a server using a blocked AS.
# Otherwise it will work normally.
SPAMHAUS_DQS_KEY=

EOF

cat << EOF > /etc/cron.daily/mailcowbackup
#!/bin/sh

# Backup mailcow data
# https://docs.mailcow.email/backup_restore/b_n_r-backup/

set -e

OUT="\$(mktemp)"
export MAILCOW_BACKUP_LOCATION="/$LXC_SHAREFS_MOUNTPOINT/backup"
SCRIPT="/opt/mailcow-dockerized/helper-scripts/backup_and_restore.sh"
PARAMETERS="backup all"
OPTIONS="--delete-days 7"
mkdir -p \$MAILCOW_BACKUP_LOCATION

# run command
set +e
"\${SCRIPT}" \${PARAMETERS} \${OPTIONS} 2>&1 > "\$OUT"
RESULT=\$?

if [ \$RESULT -ne 0 ]
    then
            echo "\${SCRIPT} \${PARAMETERS} \${OPTIONS} encounters an error:"
            echo "RESULT=\$RESULT"
            echo "STDOUT / STDERR:"
            cat "\$OUT"
fi
EOF

chmod +x /etc/cron.daily/mailcowbackup

cat << EOF > /etc/cron.daily/checkmk-mailcow-update-check
#!/bin/bash
if ! which check_mk_agent ; then
  cd /opt/mailcow-dockerized/ && ./update.sh -c >/dev/null
  status=\$?
  if [ \$status -eq 3 ]; then
    state="0 \"mailcow_update\" mailcow_update=0;1;;0;1 No updates available."
  elif [ \$status -eq 0 ]; then
    state="1 \"mailcow_update\" mailcow_update=1;1;;0;1 Updated code is available.\nThe changes can be found here: https://github.com/mailcow/mailcow-dockerized/commits/master"
  else
    state="3 \"mailcow_update\" - Unknown output from update script ..."
  fi
  echo -e "<<<local>>>\n$\state" > /tmp/87000_mailcowupdate
  mv /tmp/87000_mailcowupdate /var/lib/check_mk_agent/spool/
fi
exit
EOF
chmod +x /etc/cron.daily/checkmk-mailcow-update-check

chmod 600 mailcow.conf

mkdir -p data/assets/ssl

openssl req -x509 -newkey rsa:4096 -keyout data/assets/ssl/key.pem -out data/assets/ssl/cert.pem -days 365 -subj "/C=DE/ST=NRW/L=Willich/O=mailcow/OU=mailcow/CN=${LXC_HOSTNAME}.${LXC_DOMAIN}" -sha256 -nodes

openssl dhparam -out data/assets/ssl/dhparams.pem 2048
cat << EOF > /etc/cron.monthly/generate-dhparams
#!/bin/bash
openssl dhparam -out data/assets/ssl/dhparams.gen 4096 > /dev/null 2>&1
mv data/assets/ssl/dhparams.gen data/assets/ssl/dhparams.pem
systemctl restart nginx
EOF
chmod +x /etc/cron.monthly/generate-dhparams

docker compose pull
docker compose up -d

case $PORTAINER in
  full) install_portainer_full ;;
  agent) install_portainer_agent ;;
  *)     echo -e "\n######################################################################\n\n   Enjoy your Docker intallation.\n\n######################################################################" ;;
esac