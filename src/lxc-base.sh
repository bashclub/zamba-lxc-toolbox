#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

# load configuration
echo "Loading configuration..."
source /root/zamba.conf
source /root/constants.conf

echo "Updating locales"
# update locales
sed -i "s|# $LXC_LOCALE|$LXC_LOCALE|" /etc/locale.gen
cat << EOF > /etc/default/locale
LANG="$LXC_LOCALE"
LANGUAGE=$LXC_LOCALE
EOF
locale-gen $LXC_LOCALE

# update package lists
echo "Updating package database..."
apt update

# install latest packages
echo "Installing latest updates"
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq dist-upgrade

# install toolset
echo "Installing preconfigured toolset..."
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" $LXC_TOOLSET_BASE $LXC_TOOLSET

echo "Enabling vim syntax highlighting..."
sed -i "s|\"syntax on|syntax on|g" /etc/vim/vimrc
if [ $LXC_VIM_BG_DARK -gt 0 ]; then
    sed -i "s|\"set background=dark|set background=dark|g" /etc/vim/vimrc
fi

echo "Basic container setup finished, continuing with service installation..."