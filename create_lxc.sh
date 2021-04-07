#!/bin/bash

# This script wil create and fire up a standard debian buster lxc container on your proxmox pve.
# The Script will look for the next free lxc number and take the next free and use it. So take
# care that behind your last number is place for it. 

#### SOME VARIABLES TO ADJUST ####

# Storage with templates
LXC_TMP="local"

# Size and pool of rootfs / in GB
SIZ_ROT="100"
S_ROT_P="local-zfs"

# Size and pool of Filestorage in GB will mounted to /share
SIZ_FIL="100"
S_FIL_P="local-zfs"

#Weather or not (1 and 0) the container will createt as unpriviliged LXC
LXC_UNP="1"

# Size of the RAM assigned to the LXC
LXC_MEM="1024"

# Size of the SWAP assigned to the LXC
LXC_SWA="1024"

# The hostname (eq. zamba1 or mailpiler1)
LXC_HOST="zamba"

# The domainname (searchdomain /etc/resolf.conf & hosts)
LXC_SDN="zmb.local"

# IP-address and subnet
LXC_IP="10.10.80.20/24"

# Gateway
LXC_GW="10.10.80.10"

# DNS-server and here shoud be your AD-DC
LXC_DNS="10.10.80.10"

# Networkbridge for this machine
LXC_BRD="vmbr80"

# root password - take care to delete from this file
LXC_PWD="MYPASSWD"

LXC_KEY="ssh-rsa xxxxxxxx"

############### Zamba-Server-Section ###############

# Domain Entries to samba/smb.conf. Will be also uses for samba domain-provisioning when zmb-pdc will choosen.
ZMB_REA="ZMB.LOCAL"
ZMB_DOM="ZMB"

# THE Domain-Admin and passwd for zamba-install
ZMB_ADA="Administrator"
ZMB_APW="MYPASSWORD"

############### Mailpiler-Section ###############

# The FQDN vor the Hostname. This must be exactly the same like the LXC_HOST / LXC_SDN at section above.
PILER_DOM="piler.zmb.rocks"
SMARTHOST="10.10.80.20"
PILER_VER="1.3.10"
SPHINX_VER="3.3.1"
PHP_VER="7.4"

############### Matrix-Section ###############

# The FQDN vor the Hostname. This should be the same like the LXC_HOST / LXC_SDN at section above.
MRX_DOM="matrix.zmb.rocks"
ELE_DOM="element.zmb.rocks"
ELE_VER="v1.7.21"
JIT_DOM="meet.zmb.rocks"

#################################

# CHeck is the newest template available, else download it.

DEB_LOC=$(pveam list $LXC_TMP | grep debian-10-standard | cut -d'_' -f2)

DEB_REP=$(pveam available --section system | grep debian-10-standard | cut -d'_' -f2)

if [[ $DEB_LOC == $DEB_REP ]];
then
  echo "Newest Version of Debian 10 Standard $DEP_REP exists.";
else
  echo "Will now download newest Debian 10 Standard $DEP_REP.";
  pveam download $LXC_TMP debian-10-standard_$DEB_REP\_amd64.tar.gz
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
pct create $LXC_NBR -unprivileged $LXC_UNP $LXC_TMP:vztmpl/debian-10-standard_$DEB_REP\_amd64.tar.gz -rootfs $S_ROT_P:$SIZ_ROT;
sleep 2;

pct set $LXC_NBR -memory $LXC_MEM -swap $LXC_SWA -hostname $LXC_HOST \-nameserver $LXC_DNS -searchdomain $LXC_SDN -onboot 1 -timezone Europe/Berlin -net0 name=eth0,bridge=$LXC_BRD,firewall=1,gw=$LXC_GW,ip=$LXC_IP,type=veth;
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
      echo -e "$LXC_KEY" | lxc-attach -n$LXC_NBR tee /root/.ssh/authorized_keys;
      lxc-attach -n$LXC_NBR service ssh restart;
      echo "Should be ready!"
      break
      ;;
    zmb-standalone)
      break
      ;;
    zmb-member)
      echo "Make some additions to LXC for AD-Member-Server!"
      pct set $LXC_NBR -mp0 $S_FIL_P:$SIZ_FIL,mp=/tank
      sleep 2;
      lxc-start $LXC_NBR;
      sleep 5;
      # Set the root password and key
      echo -e "$LXC_PWD\n$LXC_PWD" | lxc-attach -n$LXC_NBR passwd;
      lxc-attach -n$LXC_NBR mkdir /root/.ssh;
      echo -e "$LXC_KEY" | lxc-attach -n$LXC_NBR tee /root/.ssh/authorized_keys;
      lxc-attach -n$LXC_NBR service ssh restart;
      cp /root/zmb_mem.orig /root/zmb_mem.sh
      sed -i "s|#ZMB_VAR|#ZMB_VAR\nZMB_REA='$ZMB_REA'\nZMB_DOM='$ZMB_DOM'\nZMB_ADA='$ZMB_ADA'\nZMB_APW='$ZMB_APW'|" /root/zmb_mem.sh
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
      echo -e "$LXC_KEY" | lxc-attach -n$LXC_NBR tee /root/.ssh/authorized_keys;
      lxc-attach -n$LXC_NBR service ssh restart;
      cp /root/mailpiler.orig /root/mailpiler.sh
      sed -i "s|#PILER_VAR|#PILER_VAR\nPILER_DOM='$PILER_DOM'\nSMARTHOST='$SMARTHOST'\nPILER_VER='$PILER_VER'\nSPHINX_VER='$SPHINX_VER'\nPHP_VER='$PHP_VER'|" /root/mailpiler.sh
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
      echo -e "$LXC_KEY" | lxc-attach -n$LXC_NBR tee /root/.ssh/authorized_keys;
      lxc-attach -n$LXC_NBR service ssh restart;
      cp /root/matrix.orig /root/matrix.sh
      sed -i "s|#MATRIX_VAR|#Matrix_VAR\nMRX_DOM='$MRX_DOM'\nELE_DOM='$ELE_DOM'\nELE_VER='$ELE_VER'\nJIT_DOM='$JIT_DOM'|" /root/matrix.sh
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

