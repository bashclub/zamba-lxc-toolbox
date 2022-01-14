#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/zamba.conf
source /root/proxmox.conf

sed -i "s/^#.$HOST_LOCALE/$HOST_LOCALE/" /etc/locale.gen
locale-gen $HOST_LOCALE

sed -i "s/^#.$LXC_LOCALE/$LXC_LOCALE/" /etc/locale.gen
locale-gen $LXC_LOCALE
echo LANG=$LXC_LOCALE > /etc/default/locale
echo LANGUAGE=$LXC_LOCALE >> /etc/default/locale
export LANG=$LXC_LOCALE
export LANGUAGE=$LXC_LOCALE
export LC_CTYPE=C

apt update
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" $LXC_TOOLSET
sed -i "s|\"syntax on|syntax on|g" /etc/vim/vimrc
