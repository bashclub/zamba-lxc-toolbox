#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

set -euo pipefail

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

wget -O - https://apt.bashclub.org/gpg/bashclub.pub | gpg --dearmor > /usr/share/keyrings/bashclub-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/bashclub-keyring.gpg] https://apt.bashclub.org/testing $(lsb_release -cs) main" > /etc/apt/sources.list.d/bashclub.list
apt update

cd /tmp
wget https://download.checkmk.com/checkmk/$CMK_VERSION/check-mk-$CMK_EDITION-$CMK_VERSION$CMK_BUILD.$(lsb_release -cs)_amd64.deb
DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install ./check-mk-$CMK_EDITION-$CMK_VERSION$CMK_BUILD.$(lsb_release -cs)_amd64.deb
omd create --admin-password $CMK_ADMIN_PW $CMK_INSTANCE

cat << EOF > /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
	RewriteEngine On
	RewriteCond %{HTTPS} !=on
	RewriteRule ^/?(.*) https://%{SERVER_NAME}/$CMK_INSTANCE [R,L]
</VirtualHost>
EOF

cat << EOF > /etc/apache2/sites-available/default-ssl.conf
<VirtualHost *:443>
	RewriteEngine On
	RewriteCond %{REQUEST_URI} !^/$CMK_INSTANCE
	RewriteRule ^/(.*) https://%{HTTP_HOST}/$CMK_INSTANCE/\$1 [R=301,L]

	ServerAdmin webmaster@localhost

	DocumentRoot /var/www/html

	ErrorLog \${APACHE_LOG_DIR}/error.log
	CustomLog \${APACHE_LOG_DIR}/access.log combined

	SSLEngine on

	SSLCertificateFile      /etc/ssl/certs/ssl-cert-snakeoil.pem
	SSLCertificateKeyFile   /etc/ssl/private/ssl-cert-snakeoil.key

	#SSLCertificateChainFile /etc/apache2/ssl.crt/server-ca.crt

	#SSLCACertificatePath /etc/ssl/certs/
	#SSLCACertificateFile /etc/apache2/ssl.crt/ca-bundle.crt

	#SSLCARevocationPath /etc/apache2/ssl.crl/
	#SSLCARevocationFile /etc/apache2/ssl.crl/ca-bundle.crl

	#SSLVerifyClient require
	#SSLVerifyDepth  10

	#SSLOptions +FakeBasicAuth +ExportCertData +StrictRequire
	<FilesMatch "\.(?:cgi|shtml|phtml|php)\$">
		SSLOptions +StdEnvVars
	</FilesMatch>
	<Directory /usr/lib/cgi-bin>
		SSLOptions +StdEnvVars
	</Directory>

</VirtualHost>
EOF

a2enmod ssl
a2enmod rewrite
a2ensite default-ssl

systemctl restart apache2.service

omd start $CMK_INSTANCE

# install matrix notification plugin

wget -O /opt/omd/sites/$CMK_INSTANCE/local/share/check_mk/notifications/matrix.py https://github.com/bashclub/check_mk_matrix_notifications/raw/master/matrix.py
chmod +x /opt/omd/sites/$CMK_INSTANCE/local/share/check_mk/notifications/matrix.py
chown $CMK_INSTANCE /opt/omd/sites/$CMK_INSTANCE/local/share/check_mk/notifications/matrix.py


DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install cmk-push-server
