#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <helmke@cloudistboese.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

dpkg-reconfigure locales

source /root/zamba.conf

# Set Timezone
ln -sf /usr/share/zoneinfo/$LXC_TIMEZONE /etc/localtime

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" $LXC_TOOLSET