#!/bin/bash

# This script will create and fire up a standard debian buster lxc container on your Proxmox VE.
# On a Proxmox cluster, the script will create the container on the local node, where it's executed.
# The container ID will be automatically assigned by increasing (+1) the highest number of
# existing LXC containers in your environment. If the assigned ID is already taken by a VM
# or no containers exist yet, the script falls back to the ID 100.

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <helmke@cloudistboese.de>
# (C) 2021 Script rework by Thorsten Spille <thorsten@spille-edv.de>


#### PLEASE ADJUST THE FOLLWING VARIABLES, BEFORE RUNNING THE SCRIPT ####

# The storage, where your container tmeplates are located (in most cases: local)
LXC_TEMPLATE_STORAGE="local"

# Define the size and storage location of the container's root filesystem
LXC_ROOTFS_SIZE="100"
LXC_ROOTFS_STORAGE="local-zfs"

# Define the size, storage location and mountpoint of the container's shared filesystem (required for 'zmb_standalone' and 'zmb_member') 
LXC_FILEFS_SIZE="100"
LXC_FILEFS_STORAGE="local-zfs"
LXC_FILEFS_MOUNTPOINT="tank"

# Define whether the container will be created in unprivileged (1) or privileged (0) mode
# For 'zmb_standalone', 'zmb_pdc', 'zmb_member' and 'mailpiler' the container needs to be created with 'unprivileged=0'
LXC_UNPRIVILEGED="1"

# Size of the RAM assigned to the container
LXC_MEM="1024"

# Size of the SWAP assigned to the container
LXC_SWAP="1024"

# The hostname (eg. zamba1 or mailpiler1)
LXC_HOSTNAME="zamba"

# The domain suffix (the domain name / search domain of th container, results to the FQDN 'LXC_HOTNAME.LXC_DOMAIN')
LXC_DOMAIN="zmb.rocks"

# IP-address and subnet
LXC_IP="10.10.80.20/24"

# Gateway
LXC_GW="10.10.80.10"

# DNS-server (should be your AD DC)
LXC_DNS="10.10.80.10"

# Networkbridge for this container
LXC_BRIDGE="vmbr80"

# Optional VLAN number for this container
LXC_VLAN=""

# root password - take care to delete from this file
LXC_PWD="MYPASSWD"

LXC_AUTHORIZED_KEY="ssh-rsa xxxxxxxx"

############### Zamba-Server-Section ###############

# Domain Entries to samba/smb.conf. Will be also uses for samba domain-provisioning when zmb-pdc will choosen.
ZMB_REALM="ZMB.ROCKS"
ZMB_DOMAIN="ZMB"

# The Domain-Admin and password for zamba installation
ZMB_ADMIN_USER="Administrator"
ZMB_ADMIN_PASS="MYPASSWORD"
ZMB_DOMAIN_ADMINS_GROUP="domain admins"

# Name of the Zamba Share
ZMB_SHARE="share"

############### Mailpiler-Section ###############

# The FQDN vor the Hostname. This must be exactly the same like the LXC_HOSTNAME / LXC_DOMAIN at section above.
PILER_FQDN="piler.zmb.rocks"
PILER_SMARTHOST="10.10.80.20"
PILER_VERSION="1.3.10"
PILER_SPHINX_VERSION="3.3.1"
PILER_PHP_VERSION="7.4"

############### Matrix-Section ###############

# The FQDN vor the Hostname. This should be the same like the LXC_HOSTNAME / LXC_DOMAIN at section above.
MATRIX_FQDN="matrix.zmb.rocks"
MATRIX_ELEMENT_FQDN="element.zmb.rocks"
MATRIX_ELEMENT_VERSION="v1.7.24"
MATRIX_JITSI_FQDN="meet.zmb.rocks"

#################################

# CHeck is the newest template available, else download it.

DEB_LOC=$(pveam list $LXC_TEMPLATE_STORAGE | grep debian-10-standard | cut -d'_' -f2)

DEB_REP=$(pveam available --section system | grep debian-10-standard | cut -d'_' -f2)

if [[ $DEB_LOC == $DEB_REP ]];
then
  echo "Newest Version of Debian 10 Standard $DEP_REP exists.";
else
  echo "Will now download newest Debian 10 Standard $DEP_REP.";
  pveam download $LXC_TEMPLATE_STORAGE debian-10-standard_$DEB_REP\_amd64.tar.gz
fi

# Get next free LXC-number
LXC_LST=$( lxc-ls | egrep -o '.{1,5}$' )
LXC_CHK=$((LXC_LST+1));

if  [ $LXC_CHK -lt 100 ] || [ -f /etc/pve/qemu-server/$LXC_CHK.conf ]; then
  LXC_NBR=$(pvesh get /cluster/nextid);
else
  LXC_NBR=$LXC_CHK;
fi

echo "Will now create LXC Container $LXC_NBR!";

# Create the container
pct create $LXC_NBR -unprivileged $LXC_UNPRIVILEGED $LXC_TEMPLATE_STORAGE:vztmpl/debian-10-standard_$DEB_REP\_amd64.tar.gz -rootfs $LXC_ROOTFS_STORAGE:$LXC_ROOTFS_SIZE;
sleep 2;

if [[ $LXC_VLAN != "" ]];then
  VLAN=",vlan=$LXC_VLAN"
else
 VLAN=""
fi

pct set $LXC_NBR -memory $LXC_MEM -swap $LXC_SWAP -hostname $LXC_HOSTNAME \-nameserver $LXC_DNS -searchdomain $LXC_DOMAIN -onboot 1 -timezone Europe/Berlin -net0 name=eth0,bridge=$LXC_BRIDGE,firewall=1,gw=$LXC_GW,ip=$LXC_IP,type=veth$VLAN;
sleep 2;

PS3="Select the Server-Function: "

select opt in just_lxc zmb-standalone zmb-member zmb-pdc mailpiler matrix quit; do
  case $opt in
    just_lxc)
      lxc-start $LXC_NBR;
      sleep 5;
      # Set the root password and key
      echo -e "$LXC_PWD\n$LXC_PWD" | lxc-attach -n$LXC_NBR passwd;
      lxc-attach -n$LXC_NBR mkdir /root/.ssh;
      echo -e "$LXC_AUTHORIZED_KEY" | lxc-attach -n$LXC_NBR tee /root/.ssh/authorized_keys;
      lxc-attach -n$LXC_NBR service ssh restart;
      echo "Should be ready!"
      break
      ;;
    zmb-standalone)
      break
      ;;
    zmb-member)
      echo "Make some additions to LXC for AD-Member-Server!"
      pct set $LXC_NBR -mp0 $LXC_FILEFS_STORAGE:$LXC_FILEFS_SIZE,mp=/$LXC_FILEFS_MOUNTPOINT
      sleep 2;
      lxc-start $LXC_NBR;
      sleep 5;
      # Set the root password and key
      echo -e "$LXC_PWD\n$LXC_PWD" | lxc-attach -n$LXC_NBR passwd;
      lxc-attach -n$LXC_NBR mkdir /root/.ssh;
      echo -e "$LXC_AUTHORIZED_KEY" | lxc-attach -n$LXC_NBR tee /root/.ssh/authorized_keys;
      lxc-attach -n$LXC_NBR service ssh restart;
      cp /root/zmb_mem.orig /root/zmb_mem.sh
      sed -i "s|#ZMB_VAR|#ZMB_VAR\nLXC_FILEFS_MOUNTPOINT='$LXC_FILEFS_MOUNTPOINT'\nZMB_SHARE='$ZMB_SHARE'\nZMB_REALM='$ZMB_REALM'\nZMB_DOMAIN='$ZMB_DOMAIN'\nZMB_ADMIN_USER='$ZMB_ADMIN_USER'\nZMB_ADMIN_PASS='$ZMB_ADMIN_PASS'\nZMB_DOMAIN_ADMINS_GROUP='$ZMB_DOMAIN_ADMINS_GROUP'|" /root/zmb_mem.sh
      pct push $LXC_NBR /root/zmb_mem.sh /root/zmb_mem.sh
      echo "Install zamba as AD-Member-Server!"
      lxc-attach -n$LXC_NBR bash /root/zmb_mem.sh
      break
      ;;
    zmb-pdc)
      break
      ;;
    mailpiler)
      echo "Make some additions to LXC for Mailpiler!"
      pct set $LXC_NBR -features nesting=1
      sleep 2;
      lxc-start $LXC_NBR;
      sleep 5;
      # Set the root password and key
      echo -e "$LXC_PWD\n$LXC_PWD" | lxc-attach -n$LXC_NBR passwd;
      lxc-attach -n$LXC_NBR mkdir /root/.ssh;
      echo -e "$LXC_AUTHORIZED_KEY" | lxc-attach -n$LXC_NBR tee /root/.ssh/authorized_keys;
      lxc-attach -n$LXC_NBR service ssh restart;
      cp /root/mailpiler.orig /root/mailpiler.sh
      sed -i "s|#PILER_VAR|#PILER_VAR\nPILER_FQDN='$PILER_FQDN'\nPILER_SMARTHOST='$PILER_SMARTHOST'\nPILER_VERSION='$PILER_VERSION'\nPILER_SPHINX_VERSION='$PILER_SPHINX_VERSION'\nPILER_PHP_VERSION='$PILER_PHP_VERSION'|" /root/mailpiler.sh
      pct push $LXC_NBR /root/mailpiler.sh /root/mailpiler.sh
      echo "Install Mailpiler mailarchiv!"
      lxc-attach -n$LXC_NBR bash mailpiler.sh
      break
      ;;
    matrix)
      echo "Make some additions to LXC for Matrix!"
      lxc-start $LXC_NBR;
      sleep 5;
      # Set the root password and key
      echo -e "$LXC_PWD\n$LXC_PWD" | lxc-attach -n$LXC_NBR passwd;
      lxc-attach -n$LXC_NBR mkdir /root/.ssh;
      echo -e "$LXC_AUTHORIZED_KEY" | lxc-attach -n$LXC_NBR tee /root/.ssh/authorized_keys;
      lxc-attach -n$LXC_NBR service ssh restart;
      cp /root/matrix.orig /root/matrix.sh
      sed -i "s|#MATRIX_VAR|#Matrix_VAR\nMATRIX_FQDN='$MATRIX_FQDN'\nMATRIX_ELEMENT_FQDN='$MATRIX_ELEMENT_FQDN'\nMATRIX_ELEMENT_VERSION='$MATRIX_ELEMENT_VERSION'\nMATRIX_JITSI_FQDN='$MATRIX_JITSI_FQDN'|" /root/matrix.sh
      pct push $LXC_NBR /root/matrix.sh /root/matrix.sh
      echo "Install Matrix Chatserver!"
      lxc-attach -n$LXC_NBR bash matrix.sh
      break
      ;;
    quit)
      break
      ;;
    *)
      echo "Invalid option!"
      ;;
    esac
done

