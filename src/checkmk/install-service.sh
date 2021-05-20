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

cat << EOF > /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
	RewriteEngine On
	RewriteCond %{HTTPS} !=on
	RewriteRule ^/?(.*) https://%{SERVER_NAME}/$CMK_INSTANCE [R,L]
</VirtualHost>
EOF

a2enmod ssl
a2enmod rewrite
a2ensite default-ssl

systemctl restart apache2.service

omd start $CMK_INSTANCE

# install matrix notification plugin
su - $CMK_INSTANCE
cd ~/local/share/check_mk/notifications/
wget https://github.com/bashclub/check_mk_matrix_notifications/raw/master/matrix.py
chmod +x ./matrix.py
exit