source /root/zamba.conf
source /root/constants-service.conf

ONLYOFFICE_DB_PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys CB2DE8E5
echo "deb https://download.onlyoffice.com/repo/debian squeeze main" > /etc/apt/sources.list.d/onlyoffice.list

apt update 

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq postgresql rabbitmq-server libstdc++6 supervisor

su postgres <<EOF
psql -c "CREATE USER $ONLYOFFICE_DB_USER WITH PASSWORD '$ONLYOFFICE_DB_PASS';"
psql -c "CREATE DATABASE $ONLYOFFICE_DB_NAME ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' template=template0 OWNER $ONLYOFFICE_DB_USER;"
echo "Postgres User '$ONLYOFFICE_DB_USER' and database '$ONLYOFFICE_DB_NAME' created."
EOF

echo onlyoffice-documentserver onlyoffice/ds-port select 80 | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-host string $ONLYOFFICE_DB_HOST | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-user string $ONLYOFFICE_DB_NAME | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-name string $ONLYOFFICE_DB_USER | debconf-set-selections
echo onlyoffice-documentserver onlyoffice/db-pwd password $ONLYOFFICE_DB_PASS | debconf-set-selections

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install ttf-mscorefonts-installer onlyoffice-documentserver

cat << EOF > /root/onlyoffice.credentials
ONLYOFFICE_DB_HOST=$ONLYOFFICE_DB_HOST
ONLYOFFICE_DB_NAME=$ONLYOFFICE_DB_NAME
ONLYOFFICE_DB_USER=$ONLYOFFICE_DB_USER
ONLYOFFICE_DB_PASS=$ONLYOFFICE_DB_PASS
EOF

/etc/nginx/conf.d/ds.conf
cp /etc/onlyoffice/documentserver/nginx/ds-ssl.conf.tmpl /etc/onlyoffice/documentserver/nginx/ds-ssl.conf
ln -sf /etc/onlyoffice/documentserver/nginx/ds-ssl.conf /etc/nginx/conf.d/ds-ssl.conf
