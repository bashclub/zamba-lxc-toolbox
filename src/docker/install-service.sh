#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

set -euo pipefail

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

inst_docker

SECRET=$(random_password)
myip=$(ip a s dev eth0 | grep -m1 inet | cut -d' ' -f6 | cut -d'/' -f1)

install_portainer_full() {
    mkdir -p /opt/portainer/data
    cd /opt/portainer
    cat << EOF > /opt/portainer/docker-compose.yml
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

case $PORTAINER in
  full) install_portainer_full ;;
  agent) install_portainer_agent ;;
  *)     echo -e "\n######################################################################\n\n   Enjoy your Docker intallation.\n\n######################################################################" ;;
esac