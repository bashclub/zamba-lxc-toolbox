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

# IMPORTANT NOTE:
# Please adjust th settings in 'zamba.conf' to your needs before running the script

############### ZAMBA INSTALL SCRIPT ###############

# Load configuration file
source ./zamba.conf

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

