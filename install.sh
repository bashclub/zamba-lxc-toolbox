#!/bin/bash
set -euo pipefail

# This script will create and fire up a standard debian buster lxc container on your Proxmox VE.
# On a Proxmox cluster, the script will create the container on the local node, where it's executed.
# The container ID will be automatically assigned by increasing (+1) the highest number of
# existing LXC containers in your environment. If the assigned ID is already taken by a VM
# or no containers exist yet, the script falls back to the ID 100.

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

# IMPORTANT NOTE:
# Please adjust th settings in 'zamba.conf' to your needs before running the script

############### ZAMBA INSTALL SCRIPT ###############
prog="$(basename "$0")"

usage() {
	cat >&2 <<-EOF
	usage: $prog [-h] [-i CTID] [-s SERVICE] [-c CFGFILE]
	  installs a preconfigured lxc container on your proxmox server
    -i CTID      provide a container id instead of auto detection
    -s SERVICE   provide the service name and skip the selection dialog
    -c CFGFILE   use a different config file than 'zamba.conf'
    -h           displays this help text
  ---------------------------------------------------------------------------
    (C) 2021     zamba-lxc-toolbox by bashclub (https://github.com/bashclub)
  ---------------------------------------------------------------------------

	EOF
	exit "$1"
}

random_string() {
	LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c32
}

ctid=0
service=ask
config=$PWD/conf/zamba.conf
# TODO this appears unused
verbose=0

while getopts "hi:s:c:" opt; do
  case $opt in
    h) usage 0 ;;
    i) ctid=$OPTARG ;;
    s) service=$OPTARG ;;
    c) config=$OPTARG ;;
    *) usage 1 ;;
  esac
done
shift $((OPTIND-1))

OPTS=$(find src/ -maxdepth 1 -mindepth 1 -type d -exec basename -a {} + | sort -n)

valid=0
if [[ "$service" == "ask" ]]; then
  select svc in $OPTS quit; do
    if [[ "$svc" != "quit" ]]; then
       for line in $OPTS; do
        if [[ "$svc" == "$line" ]]; then
          service=$svc
          echo "Installation of $service selected."
          valid=1
          break
        fi
      done
    else
      echo "Selected 'quit' exiting without action..."
      exit 0
    fi
    if [[ "$valid" == "1" ]]; then
      break
    fi
  done
else
  for line in $OPTS; do
    if [[ "$service" == "$line" ]]; then
      echo "Installation of $service selected."
      valid=1
      break
    fi
  done
fi

if [[ "$valid" != "1" ]]; then
  echo "Invalid option, exiting..."
  usage 1
fi

# Load configuration file
echo "Loading config file '$config'..."
if [ ! -e "$config" ]; then
  echo "Configuration files does not exist"
  exit 1
fi

# shellcheck source=conf/zamba.conf.example
source "$config"

# shellcheck source=src/zmb-standalone/constants-service.conf
source "$PWD/src/$service/constants-service.conf"

# CHeck is the newest template available, else download it.
DEB_LOC=$(pveam list $LXC_TEMPLATE_STORAGE | grep $LXC_TEMPLATE_VERSION | cut -d'_' -f2)
DEB_REP=$(pveam available --section system | grep $LXC_TEMPLATE_VERSION | cut -d'_' -f2)

if [[ $DEB_LOC == "$DEB_REP" ]]; then
  echo "Newest Version of $LXC_TEMPLATE_VERSION $DEB_REP exists.";
else
  echo "Will now download newest $LXC_TEMPLATE_VERSION $DEB_REP.";
  pveam download $LXC_TEMPLATE_STORAGE "${LXC_TEMPLATE_VERSION}_${DEB_REP}_amd64.tar.gz"
fi

if [ "$ctid" -gt 99 ]; then
  LXC_CHK=$ctid
else
  # Get next free LXC-number
  LXC_LST=$( lxc-ls -1 | tail -1 )
  LXC_CHK=$((LXC_LST+1));
fi

if  [ $LXC_CHK -lt 100 ] || [ -f /etc/pve/qemu-server/$LXC_CHK.conf ]; then
  LXC_NBR=$(pvesh get /cluster/nextid);
else
  LXC_NBR=$LXC_CHK;
fi
echo "Will now create LXC Container $LXC_NBR!";

# Create the container
pct create $LXC_NBR -unprivileged $LXC_UNPRIVILEGED "$LXC_TEMPLATE_STORAGE:vztmpl/${LXC_TEMPLATE_VERSION}_${DEB_REP}_amd64.tar.gz" -rootfs $LXC_ROOTFS_STORAGE:$LXC_ROOTFS_SIZE;
sleep 2;

# Check vlan configuration
if [[ $LXC_VLAN != "" ]];then VLAN=",tag=$LXC_VLAN"; else VLAN=""; fi
# Reconfigure conatiner
pct set $LXC_NBR -memory $LXC_MEM -swap $LXC_SWAP -hostname "$LXC_HOSTNAME" -onboot 1 -timezone $LXC_TIMEZONE -features nesting=$LXC_NESTING;
if [ $LXC_DHCP == true ]; then
 pct set $LXC_NBR -net0 "name=eth0,bridge=$LXC_BRIDGE,ip=dhcp,type=veth$VLAN"
else
 pct set $LXC_NBR -net0 "name=eth0,bridge=$LXC_BRIDGE,firewall=1,gw=$LXC_GW,ip=$LXC_IP,type=veth$VLAN" -nameserver $LXC_DNS -searchdomain $LXC_DOMAIN;
fi
sleep 2

if [ $LXC_MP -gt 0 ]; then
  pct set $LXC_NBR -mp0 $LXC_SHAREFS_STORAGE:$LXC_SHAREFS_SIZE,mp=/$LXC_SHAREFS_MOUNTPOINT
fi
sleep 2;

PS3="Select the Server-Function: "

pct start $LXC_NBR;
sleep 5;
# Set the root password and key
echo -e "$LXC_PWD\n$LXC_PWD" | lxc-attach -n$LXC_NBR passwd;
lxc-attach -n$LXC_NBR mkdir /root/.ssh;
pct push $LXC_NBR $LXC_AUTHORIZED_KEY /root/.ssh/authorized_keys
pct push $LXC_NBR "$config" /root/zamba.conf
pct push $LXC_NBR "$PWD/src/constants.conf" /root/constants.conf
pct push $LXC_NBR "$PWD/src/lxc-base.sh" /root/lxc-base.sh
pct push $LXC_NBR "$PWD/src/$service/install-service.sh" /root/install-service.sh
pct push $LXC_NBR "$PWD/src/$service/constants-service.conf" /root/constants-service.conf

echo "Installing basic container setup..."
lxc-attach -n$LXC_NBR bash /root/lxc-base.sh
echo "Install '$service'!"
lxc-attach -n$LXC_NBR bash /root/install-service.sh

if [[ $service == "zmb-ad" ]]; then
  pct stop $LXC_NBR
  # TODO is the \ added to escape the dash?
  # shellcheck disable=SC1001
  pct set $LXC_NBR \-nameserver "$(echo $LXC_IP | cut -d'/' -f 1)"
  pct start $LXC_NBR
fi
