#!/bin/bash

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <helmke@cloudistboese.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

# configure system language
dpkg-reconfigure locales

source /root/zamba.conf

# Set Timezone
ln -sf /usr/share/zoneinfo/$LXC_TIMEZONE /etc/localtime

HOSTNAME=$(hostname -f)

echo "Ensure your Hostname is set to your Piler FQDN!"

echo $HOSTNAME

if 
    [ "$HOSTNAME" != "$PILER_FQDN" ]
then
        echo "Hostname doesn't match PILER_FQDNain! Check install.sh, /etc/hosts, /etc/hostname." && exit
else
        echo "Hostname matches PILER_FQDNAIN, so starting installation."
fi

apt update && apt full-upgrade -y

apt install -y $LXC_TOOLSET build-essential libwrap0-dev libpst-dev tnef libytnef0-dev unrtf catdoc libtre-dev tre-agrep poppler-utils libzip-dev unixodbc libpq5 software-properties-common libpoppler-dev openssl libssl-dev memcached telnet nginx mariadb-server default-libmysqlclient-dev python-mysqldb gcc libwrap0 libzip4 latex2rtf latex2html catdoc tnef zipcmp zipmerge ziptool libsodium23

# install php
wget -q https://packages.sury.org/php/apt.gpg -O- | apt-key add -
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list

apt update && apt install -y php$PILER_PHP_VERSION-{fpm,common,ldap,mysql,cli,opcache,phpdbg,gd,memcache,json,readline,zip}

apt purge -y postfix

cat > /etc/mysql/conf.d/mailpiler.conf <<EOF
innodb_buffer_pool_size=256M
innodb_flush_log_at_trx_commit=1
innodb_log_buffer_size=64M
innodb_log_file_size=16M
query_cache_size=0
query_cache_type=0
query_cache_limit=2M
EOF

systemctl restart mariadb

cd /tmp
wget https://download.mailpiler.com/generic-local/sphinx-$PILER_SPHINX_VERSION-bin.tar.gz
tar -xvzf sphinx-$PILER_SPHINX_VERSION-bin.tar.gz -C /

groupadd piler
useradd -g piler -m -s /bin/bash -d /var/piler piler
usermod -L piler
chmod 755 /var/piler

wget https://bitbucket.org/jsuto/piler/downloads/piler-$PILER_VERSION.tar.gz
tar -xvzf piler-$PILER_VERSION.tar.gz
cd piler-$PILER_VERSION/
./configure --localstatedir=/var --with-database=mysql --enable-tcpwrappers --enable-memcached
make
make install
ldconfig

cp util/postinstall.sh util/postinstall.sh.bak
sed -i "s/   PILER_SMARTHOST=.*/   PILER_SMARTHOST="\"$PILER_SMARTHOST\""/" util/postinstall.sh
sed -i 's/   WWWGROUP=.*/   WWWGROUP="www-data"/' util/postinstall.sh

make postinstall

cp /usr/local/etc/piler/piler.conf /usr/local/etc/piler/piler.conf.bak
sed -i "s/hostid=.*/hostid=$PILER_FQDN/" /usr/local/etc/piler/piler.conf
sed -i "s/update_counters_to_memcached=.*/update_counters_to_memcached=1/" /usr/local/etc/piler/piler.conf

su piler -c "indexer --all --config /usr/local/etc/piler/sphinx.conf"

/etc/init.d/rc.piler start
/etc/init.d/rc.searchd start

update-rc.d rc.piler defaults
update-rc.d rc.searchd defaults

mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout /etc/nginx/ssl/piler.key -out /etc/nginx/ssl/piler.crt -subj "/CN=$PILER_FQDN" -addext "subjectAltName=DNS:$PILER_FQDN"

cd /etc/nginx/sites-available
cp /tmp/piler-$PILER_VERSION/contrib/webserver/piler-nginx.conf /etc/nginx/sites-available/
ln -s /etc/nginx/sites-available/piler-nginx.conf /etc/nginx/sites-enabled/piler-nginx.conf

sed -i "s|PILER_HOST|$PILER_FQDN|g" /etc/nginx/sites-available/piler-nginx.conf
sed -i "s|/var/run/php/php7.4-fpm.sock|/var/run/php/php$PILER_PHP_VERSION-fpm.sock|g" /etc/nginx/sites-available/piler-nginx.conf

sed -i "/server_name.*/a \\
        listen 443 ssl http2;\n\n\
        ssl_certificate /etc/nginx/ssl/piler.crt;\n\
        ssl_certificate_key /etc/nginx/ssl/piler.key;\n\n\
        ssl_session_timeout 1d;\n\
        ssl_session_cache shared:SSL:15m;\n\
        ssl_session_tickets off;\n\n\
        # modern configuration of Mozilla SSL configurator. Tweak to your needs.\n\
        ssl_protocols TLSv1.2 TLSv1.3;\n\
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;\n\
        ssl_prefer_server_ciphers off;\n\n\
        add_header X-Frame-Options SAMEORIGIN;\n\
        add_header X-Content-Type-Options nosniff;" /etc/nginx/sites-available/piler-nginx.conf

sed -i "/^server {.*/i\
server {\n\
        listen 80;\n\
        server_name $PILER_FQDN;\n\
        server_tokens off;\n\
        # HTTP to HTTPS redirect.\n\
        return 301 https://$PILER_FQDN;\n\
}" /etc/nginx/sites-available/piler-nginx.conf

cp /usr/local/etc/piler/config-site.php /usr/local/etc/piler/config-site.php.bak
sed -i "s|\$config\['SITE_URL'\] = .*|\$config\['SITE_URL'\] = 'https://$PILER_FQDN/';|" /usr/local/etc/piler/config-site.php
cat >> /usr/local/etc/piler/config-site.php <<EOF

// CUSTOM
\$config['PROVIDED_BY'] = '$PILER_FQDN';
\$config['SUPPORT_LINK'] = 'https://$PILER_FQDN';
\$config['COMPATIBILITY'] = '';

// fancy features.
\$config['ENABLE_INSTANT_SEARCH'] = 1;
\$config['ENABLE_TABLE_RESIZE'] = 1;

\$config['ENABLE_DELETE'] = 1;
\$config['ENABLE_ON_THE_FLY_VERIFICATION'] = 1;

// general settings.
\$config['TIMEZONE'] = 'Europe/Berlin';

// authentication
// Enable authentication against an imap server
//\$config['ENABLE_IMAP_AUTH'] = 1;
//\$config['RESTORE_OVER_IMAP'] = 1;
//\$config['IMAP_RESTORE_FOLDER_INBOX'] = 'INBOX';
//\$config['IMAP_RESTORE_FOLDER_SENT'] = 'Sent';
//\$config['IMAP_HOST'] = '$PILER_SMARTHOST';
//\$config['IMAP_PORT'] =  993;
//\$config['IMAP_SSL'] = true;

// authentication against an ldap directory (disabled by default)
//\$config['ENABLE_LDAP_AUTH'] = 1;
//\$config['LDAP_HOST'] = '$PILER_SMARTHOST';
//\$config['LDAP_PORT'] = 389;
//\$config['LDAP_HELPER_DN'] = 'cn=administrator,cn=users,dc=mydomain,dc=local';
//\$config['LDAP_HELPER_PASSWORD'] = 'myxxxxpasswd';
//\$config['LDAP_MAIL_ATTR'] = 'mail';
//\$config['LDAP_AUDITOR_MEMBER_DN'] = '';
//\$config['LDAP_ADMIN_MEMBER_DN'] = '';
//\$config['LDAP_BASE_DN'] = 'ou=Benutzer,dc=krs,dc=local';

// authentication against an Uninvention based ldap directory 
//\$config['ENABLE_LDAP_AUTH'] = 1;
//\$config['LDAP_HOST'] = '$PILER_SMARTHOST';
//\$config['LDAP_PORT'] = 7389;
//\$config['LDAP_HELPER_DN'] = 'uid=ldap-search-user,cn=users,dc=mydomain,dc=local';
//\$config['LDAP_HELPER_PASSWORD'] = 'myxxxxpasswd';
//\$config['LDAP_AUDITOR_MEMBER_DN'] = '';
//\$config['LDAP_ADMIN_MEMBER_DN'] = '';
//\$config['LDAP_BASE_DN'] = 'cn=users,dc=mydomain,dc=local';
//\$config['LDAP_MAIL_ATTR'] = 'mailPrimaryAddress';
//\$config['LDAP_ACCOUNT_OBJECTCLASS'] = 'person';
//\$config['LDAP_DISTRIBUTIONLIST_OBJECTCLASS'] = 'person';
//\$config['LDAP_DISTRIBUTIONLIST_ATTR'] = 'mailAlternativeAddress';

// special settings.
\$config['MEMCACHED_ENABLED'] = 1;
\$config['SPHINX_STRICT_SCHEMA'] = 1; // required for Sphinx $PILER_SPHINX_VERSION, see https://bitbucket.org/jsuto/piler/issues/1085/sphinx-331.
EOF

nginx -t && systemctl restart nginx

apt autoremove -y
apt clean -y


