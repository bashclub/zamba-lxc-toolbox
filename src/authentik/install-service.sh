#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

set -euo pipefail

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

# Add Docker's official GPG key:
inst_docker

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt-get install -y -qq pwgen

myip=$(ip a s dev eth0 | grep -m1 inet | cut -d' ' -f6 | cut -d'/' -f1)

mkdir -p /opt/authentik
wget -O /opt/authentik/docker-compose.yml https://goauthentik.io/docker-compose.yml
cd /opt/authentik
cat << EOF > .env
PG_PASS=$(pwgen -s 40 1)
AUTHENTIK_SECRET_KEY=$(pwgen -s 50 1)
AUTHENTIK_DISABLE_UPDATE_CHECK=false
AUTHENTIK_ERROR_REPORTING__ENABLED=false
AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true
AUTHENTIK_AVATARS=initials
COMPOSE_PORT_HTTP=80
COMPOSE_PORT_HTTPS=443
AUTHENTIK_EMAIL__HOST=
AUTHENTIK_EMAIL__PORT=
AUTHENTIK_EMAIL__USERNAME=
AUTHENTIK_EMAIL__PASSWORD=
# Use StartTLS
AUTHENTIK_EMAIL__USE_TLS=false
# Use SSL
AUTHENTIK_EMAIL__USE_SSL=false
AUTHENTIK_EMAIL__TIMEOUT=10
# Email address authentik will send from, should have a correct @domain
AUTHENTIK_EMAIL__FROM=
AUTHENTIK_REDIS__DB=1
EOF

docker compose pull
docker compose up -d

echo -e "\n######################################################################\n\n   Enjoy your authentik intallation.\n\n######################################################################\n\n    Setup your authentik instance by entering https://${myip}/if/flow/initial-setup/ into your browser.\n\n######################################################################"
