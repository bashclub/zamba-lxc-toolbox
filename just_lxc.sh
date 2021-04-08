#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <helmke@cloudistboese.de>
# (C) 2021 Script rework by Thorsten Spille <thorsten@spille-edv.de>

# Set Timezone
ln -sf /usr/share/zoneinfo/$LXC_TIMEZONE /etc/localtime

dpkg-reconfigure locales