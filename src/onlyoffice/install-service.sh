source /root/zamba.conf
source /root/constants-service.conf
ONLYOFFICE_DB_PASSWORD=$(source /root/postgresql.sh 13 $ONLYOFFICE_DB_NAME $ONLYOFFICE_DB_USER)
source /root/rabbitmq-server.sh

apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys CB2DE8E5
echo "deb https://download.onlyoffice.com/repo/debian squeeze main" > /etc/apt/sources.list.d/onlyoffice.list

apt update

echo onlyoffice-documentserver onlyoffice/ds-port select 80 | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-host string $ONLYOFFICE_DB_HOST | sudo debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-user string $ONLYOFFICE_DB_NAME | sudo debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-name string $ONLYOFFICE_DB_USER | sudo debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-pwd password $ONLYOFFICE_DB_PASSWORD | debconf-set-selections

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install ttf-mscorefonts-installer onlyoffice-documentserver

cat << EOF > /root/onlyoffice.credentials
ONLYOFFICE_DB_HOST=$ONLYOFFICE_DB_HOST
ONLYOFFICE_DB_NAME=$ONLYOFFICE_DB_NAME
ONLYOFFICE_DB_USER=$ONLYOFFICE_DB_USER
ONLYOFFICE_DB_PASSWORD=$ONLYOFFICE_DB_PASSWORD
EOF

/etc/nginx/conf.d/ds.conf
cp /etc/onlyoffice/documentserver/nginx/ds-ssl.conf.tmpl /etc/onlyoffice/documentserver/nginx/ds-ssl.conf
ln -sf /etc/onlyoffice/documentserver/nginx/ds-ssl.conf /etc/nginx/conf.d/ds-ssl.conf
