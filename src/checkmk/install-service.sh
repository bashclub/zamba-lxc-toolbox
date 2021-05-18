#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/zamba.conf
source /root/constants-service.conf

wget https://download.checkmk.com/checkmk/$CMK_VERSION/check-mk-$CMK_EDITION-$CMK_VERSION$CMK_BUILD.buster_amd64.deb
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install ./check-mk-$CMK_EDITION-$CMK_VERSION$CMK_BUILD.buster_amd64.deb

omd create --admin-password $CMK_ADMIN_PW $CMK_INSTANCE

omd start $CMK_INSTANCE
