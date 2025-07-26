
source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf
source /etc/os-release

# --- Internal Helper Functions ---
_generate_local_password() {
    openssl rand -base64 "$1"
}


curl -fsSL https://packages.icinga.com/icinga.key | gpg --dearmor -o /usr/share/keyrings/icinga-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/icinga-archive-keyring.gpg] https://packages.icinga.com/debian icinga-$(lsb_release -cs) main" > /etc/apt/sources.list.d/icinga.list

curl -fsSL https://packages.netways.de/netways-repo.asc | gpg --dearmor -o /usr/share/keyrings/netways-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/netways-archive-keyring.gpg] https://packages.netways.de/extras/debian/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/netways.list

curl -fsSL https://repos.influxdata.com/influxdata-archive_compat.key | gpg --dearmor -o /usr/share/keyrings/influxdata-archive_compat-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/influxdata-archive_compat-keyring.gpg] https://repos.influxdata.com/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/influxdata.list

apt update

apt-get install -y icinga2 nginx php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql php${PHP_VERSION}-intl php${PHP_VERSION}-xml php${PHP_VERSION}-gd php${PHP_VERSION}-ldap php${PHP_VERSION}-imagick \
        mariadb-server mariadb-client influxdb2 imagemagick icingaweb2 icingacli icinga-php-library icingaweb2-module-reactbundle icinga-notifications icinga-notifications-web \
        icinga-director icingadb icingadb-redis icingadb-web icingaweb2-module-perfdatagraphs icingaweb2-module-perfdatagraphs-influxdbv2 \
        monitoring-plugins monitoring-plugins-basic monitoring-plugins-common monitoring-plugins-standard monitoring-plugins-systemd


ICINGAWEB_DB_PASS=$(_generate_local_password 24)
DIRECTOR_DB_PASS=$(_generate_local_password 24)
ICINGADB_PASS=$(_generate_local_password 24)
ICINGA_API_USER_PASS=$(_generate_local_password 24)
NOTIFICATIONS_DB_PASS=$(_generate_local_password 24)
ICINGAWEB_ADMIN_PASS=$(_generate_local_password 16)
INFLUX_ADMIN_PASS=$(_generate_local_password 16)
INFLUX_ADMIN_TOKEN=$(_generate_local_password 40)

systemctl start mariadb

mysql -e "CREATE DATABASE IF NOT EXISTS icingaweb2 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE DATABASE IF NOT EXISTS director CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE DATABASE IF NOT EXISTS icingadb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE DATABASE IF NOT EXISTS notifications CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

mysql -e "CREATE USER IF NOT EXISTS 'icingaweb2'@'localhost' IDENTIFIED BY '${ICINGAWEB_DB_PASS}';"
mysql -e "CREATE USER IF NOT EXISTS 'director'@'localhost' IDENTIFIED BY '${DIRECTOR_DB_PASS}';"
mysql -e "CREATE USER IF NOT EXISTS 'icingadb'@'localhost' IDENTIFIED BY '${ICINGADB_PASS}';"
mysql -e "CREATE USER IF NOT EXISTS 'notifications'@'localhost' IDENTIFIED BY '${NOTIFICATIONS_DB_PASS}';"

mysql -e "GRANT ALL PRIVILEGES ON icingaweb2.* TO 'icingaweb2'@'localhost';"
mysql -e "GRANT ALL PRIVILEGES ON director.* TO 'director'@'localhost';"
mysql -e "GRANT ALL PRIVILEGES ON icingadb.* TO 'icingadb'@'localhost';"
mysql -e "GRANT ALL PRIVILEGES ON notifications.* TO 'notifications'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

systemctl start influxdb
influx setup --skip-verify --username admin --password "$INFLUX_ADMIN_PASS" --org icinga --bucket icinga --token "$INFLUX_ADMIN_TOKEN" -f
INFLUX_ICINGA_TOKEN=$(influx auth create --org icinga --all-access --json | grep -oP '"token": "\K[^"]+')
if [ -z "$INFLUX_ICINGA_TOKEN" ]; then echo "[ERROR] Konnte InfluxDB Token nicht erstellen." >&2; exit 1; fi


mkdir -p "$(dirname "$CRED_FILE")" && chmod 700 "$(dirname "$CRED_FILE")"
{
    echo "# --- Icinga Monitoring Stack Credentials ---"
    echo "URL: https://${ZAMBA_HOSTNAME:-$(hostname -f)}/icingaweb2; Benutzer: icingaadmin; Passwort: ${ICINGAWEB_ADMIN_PASS}"
    echo "InfluxDB Admin Token: ${INFLUX_ADMIN_TOKEN}"
    echo "Icinga Director API: Benutzer: director; Passwort: ${ICINGA_API_USER_PASS}"
} > "$CRED_FILE" && chmod 600 "$CRED_FILE"

systemctl enable --now icingadb-redis

cat > /etc/icinga2/features-available/icingadb.conf <<EOF
library "icingadb"

object IcingaDB "icingadb" {
  host = "127.0.0.1"
  port = 6380
}
EOF

cat > /etc/icinga2/conf.d/api-users.conf <<EOF
object ApiUser "director" {
  password = "${ICINGA_API_USER_PASS}"
  permissions = [ "*" ]
}
EOF

cat > /etc/icinga2/features-available/influxdb2-writer.conf <<EOF
object Influxdb2Writer "influxdb2" {
  host = "127.0.0.1"
  port = 8086
  organization = "icinga"
  bucket = "icinga"
  auth_token = "${INFLUX_ICINGA_TOKEN}"
  
  flush_threshold = 1024
  flush_interval = 10s

  host_template = {
    measurement = "\$host.check_command\$"
    tags = {
      hostname = "\$host.name\$"
    }
  }
  service_template = {
    measurement = "\$service.check_command\$"
    tags = {
      hostname = "\$host.name\$"
      service = "\$service.name\$"
    }
  }
}
EOF
cat > /etc/icinga2/zones.conf <<EOF
object Endpoint "$(hostname -f)" { host = "127.0.0.1" }
object Zone "master" { endpoints = [ "$(hostname -f)" ] }
object Zone "global-templates" { global = true }
object Zone "director-global" { global = true }
EOF

cat > /etc/icingadb/config.yml <<EOF
database:
  type: mysql
  host: localhost
  database: icingadb
  user: icingadb
  password: ${ICINGADB_PASS}
redis:
  host: 127.0.0.1
  port: 6380
logging:
  level: info
  output: systemd-journald
EOF

mkdir -p /etc/icingaweb2/modules/icingadb
cat << EOF > /etc/icingaweb2/modules/icingadb/config.ini
[icingadb]
resource = icingadb
EOF
cat << EOF > /etc/icingaweb2/modules/icingadb/redis.ini
[redis1]
host = "localhost"
EOF

icinga2 feature enable icingadb

mkdir -p /etc/icingaweb2

cat > /etc/icingaweb2/resources.ini <<EOF
[icingaweb_db]
type = "db"
db = "mysql"
host = "localhost"
dbname = "icingaweb2"
username = "icingaweb2"
password = "${ICINGAWEB_DB_PASS}"
charset = "utf8mb4"

[director_db]
type = "db"
db = "mysql"
host = "localhost"
dbname = "director"
username = "director"
password = "${DIRECTOR_DB_PASS}"
charset = "utf8mb4"

[icingadb]
type = "db"
db = "mysql"
host = "localhost"
dbname = "icingadb"
username = "icingadb"
password = "${ICINGADB_PASS}"
charset = "utf8mb4"

[notifications]
type = "db"
db = "mysql"
host = "localhost"
dbname = "notifications"
username = "notifications"
password = "${NOTIFICATIONS_DB_PASS}"
charset = "utf8mb4"
EOF

cat << EOF > /etc/icinga2/conf.d/services.conf
apply Service "ping4" {
  import "generic-service"

  check_command = "ping4"

  assign where host.address
}

apply Service "ping6" {
  import "generic-service"

  check_command = "ping6"

  assign where host.address6
}

apply Service "ssh" {
  import "generic-service"

  check_command = "ssh"

  assign where (host.address || host.address6) && host.vars.os == "Linux"
}



apply Service for (http_vhost => config in host.vars.http_vhosts) {
  import "generic-service"

  check_command = "http"

  vars += config
}

apply Service for (disk => config in host.vars.disks) {
  import "generic-service"

  check_command = "disk"

  vars += config
}

apply Service "icinga" {
  import "generic-service"

  check_command = "icinga"

  assign where host.name == NodeName
}

apply Service "load" {
  import "generic-service"

  check_command = "load"

  assign where host.name == NodeName
}

apply Service "procs" {
  import "generic-service"

  check_command = "procs"

  assign where host.name == NodeName
}

apply Service "users" {
  import "generic-service"

  check_command = "users"

  assign where host.name == NodeName
}

apply Service "ssl" {
  import "generic-service"

  check_command = "ssl"

  assign where host.name == NodeName
}

apply Service "smtp" {
  import "generic-service"

  check_command = "smtp"

  assign where host.name == NodeName
}

EOF

mkdir -p /etc/nginx/ssl
if [ ! -L /etc/nginx/ssl/fullchain.pem ]; then
    ln -s /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/nginx/ssl/fullchain.pem
    ln -s /etc/ssl/private/ssl-cert-snakeoil.key /etc/nginx/ssl/privkey.pem
fi

cat > /etc/nginx/sites-available/icinga-stack <<EOF
server {
    listen 80;
    server_name ${ZAMBA_HOSTNAME:-$(hostname -f)};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${ZAMBA_HOSTNAME:-$(hostname -f)};
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    root /usr/share/icingaweb2/public;
    index index.php;
    location / { try_files \$uri \$uri/ /index.php\$is_args\$args; }
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param ICINGAWEB_CONFIGDIR /etc/icingaweb2;
    }
    #location /grafana {
    #    proxy_pass http://localhost:3000;
    #    proxy_set_header Host \$http_host;
    #}
    location /icingadb-web {
        proxy_pass http://localhost:8080/icingadb-web;
        proxy_set_header Host \$http_host;
    }
}
EOF

cat << EOF > /etc/icinga-notifications/config.yml
database:
  type: mysql

  host: localhost
  
  database: notifications

  user: notifications

  password: ${NOTIFICATIONS_DB_PASS}
EOF

cat << EOF > /etc/icingaweb2/modules/notifications/config.ini 
[database]
resource = "notifications"
EOF


ln -sf /etc/nginx/sites-available/icinga-stack /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' "/etc/php/${PHP_VERSION}/fpm/php.ini"
sed -i "s|;date.timezone =|date.timezone = $(cat /etc/timezone)|" "/etc/php/${PHP_VERSION}/fpm/php.ini"

icinga2 api setup
systemctl enable icinga2 mariadb nginx php${PHP_VERSION}-fpm influxdb icingadb icingadb-redis icinga-notifications

systemctl start mariadb
systemctl start icinga2 icingadb-redis nginx php${PHP_VERSION}-fpm influxdb icingadb

IWEB_SCHEMA="/usr/share/icingaweb2/schema/mysql.schema.sql"
DIRECTOR_SCHEMA="/usr/share/icingaweb2/modules/director/schema/mysql.sql"
ICINGADB_SCHEMA="/usr/share/icingadb/schema/mysql/schema.sql"
NOTIFICATIONS_SCHEMA="/usr/share/icinga-notifications/schema/mysql/schema.sql"

if [ ! -f "$IWEB_SCHEMA" ]; then echo "[ERROR] IcingaWeb-Schema nicht gefunden: $IWEB_SCHEMA" >&2; exit 1; fi
if [ ! -f "$DIRECTOR_SCHEMA" ]; then echo "[ERROR] Director-Schema nicht gefunden: $DIRECTOR_SCHEMA" >&2; exit 1; fi
if [ ! -f "$ICINGADB_SCHEMA" ]; then echo "[ERROR] IcingaDB-Schema nicht gefunden: $ICINGADB_SCHEMA" >&2; exit 1; fi
if [ ! -f "$NOTIFICATIONS_SCHEMA" ]; then echo "[ERROR] IcingaDB-Schema nicht gefunden: $NOTIFICATIONS_SCHEMA" >&2; exit 1; fi


if ! mysql -e "use icingaweb2; show tables;" | grep -q "icingaweb_user"; then
    echo "[INFO] Importiere IcingaWeb2-Schema..."
    mysql icingaweb2 < "$IWEB_SCHEMA"
fi

if ! mysql -e "use director; show tables;" | grep -q "director_datafield"; then
    echo "[INFO] Importiere Icinga Director-Schema..."
    mysql director < "$DIRECTOR_SCHEMA"
fi

if ! mysql -e "use icingadb; show tables;" | grep -q "icingadb_schema_migration"; then
    echo "[INFO] Importiere IcingaDB-Schema..."
    mysql icingadb < "$ICINGADB_SCHEMA"
fi

if ! mysql -e "use notifications; show tables;" | grep -q "icingadb_schema_migration"; then
    echo "[INFO] Importiere IcingaDB-Schema..."
    mysql notifications < "$NOTIFICATIONS_SCHEMA"
fi

cat > /etc/icingaweb2/config.ini <<EOF
[global]
show_stacktraces = "0"
config_backend = "db"
config_resource = "icingaweb_db"
[logging]
log = "file"
log_file = "/var/log/icingaweb2/icingaweb2.log"
level = "ERROR"
EOF

cat > /etc/icingaweb2/authentication.ini <<EOF
[icinga-web-admin]
backend = "db"
resource = "icingaweb_db"
EOF

cat > /etc/icingaweb2/roles.ini <<EOF
[Administrators]
users = "icingaadmin"
permissions = "*"
groups = "Administrators"
EOF
    
mkdir -p /etc/icingaweb2/modules/monitoring
cat > /etc/icingaweb2/modules/monitoring/backends.ini <<EOF
[icingadb]
backend = "icingadb"
resource = "icingadb"
EOF
    
mkdir -p /etc/icingaweb2/modules/director
cat > /etc/icingaweb2/modules/director/config.ini <<EOF
[db]
resource = "director_db"
EOF

mkdir -p /etc/icingaweb2/modules/perfdatagraphs
mkdir -p /etc/icingaweb2/modules/perfdatagraphsinfluxdbv2
cat > /etc/icingaweb2/modules/perfdatagraphsinfluxdbv2/config.ini <<EOF
[influx]
api_url = "http://127.0.0.1:8086"
api_token = "${INFLUX_ICINGA_TOKEN}"
api_org = "icinga"
api_bucket = "icinga"
api_tls_insecure = "1"
EOF

cat > /etc/icingaweb2/modules/perfdatagraphs/config.ini << EOF
[perfdatagraphs]
default_timerange = "PT12H"
default_backend = "InfluxDBv2"
EOF

icinga2 feature enable icingadb api influxdb2-writer perfdata

echo "[INFO] Icinga Web 2 Module werden in korrekter Reihenfolge aktiviert."
icingacli module enable reactbundle
icingacli module enable incubator
icingacli module enable director
icingacli module enable icingadb
icingacli module enable perfdatagraphs
icingacli module enable perfdatagraphsinfluxdbv2
icingacli module enable notifications

echo "[INFO] Alle Services werden neu gestartet, um die finale Konfiguration zu laden."
systemctl restart mariadb
systemctl restart php${PHP_VERSION}-fpm
systemctl restart nginx
systemctl restart icingadb
systemctl restart icinga-notifications

echo "[INFO] Füge Icinga Web 2 Admin-Benutzer direkt in die Datenbank ein."
PASSWORD_HASH=$(php -r "echo password_hash('${ICINGAWEB_ADMIN_PASS}', PASSWORD_BCRYPT);")
mysql icingaweb2 -e "INSERT INTO icingaweb_user (name, active, password_hash) VALUES ('icingaadmin', 1, '${PASSWORD_HASH}') ON DUPLICATE KEY UPDATE password_hash='${PASSWORD_HASH}';"

echo "[INFO] Warte auf Icinga Web 2 und API..."
counter=0
while ! icingacli director migration run >/dev/null 2>&1; do
    counter=$((counter + 1))
    if [ "$counter" -gt 15 ]; then
        echo "[ERROR] Icinga Director wurde nach 30 Sekunden nicht bereit." >&2
        exit 1
    fi
    echo "[INFO] Director ist noch nicht bereit, warte 2 Sekunden... (Versuch ${counter}/15)"
    sleep 2
done
echo "[INFO] Icinga Director ist bereit."

echo "[INFO] Icinga Director Setup wird ausgeführt."
cat > /etc/icingaweb2/modules/director/kickstart.ini <<EOF
[config]
endpoint = "$(hostname -f)"
port = "5665"
username = "director"
password = "${ICINGA_API_USER_PASS}"
EOF
systemctl restart icinga2
icingacli director kickstart run

echo "[INFO] Director Konfiguration wird angewendet."
icingacli director config deploy

echo ""
echo "================================================="
echo "  Installation des Icinga Monitoring Stacks abgeschlossen"
echo "================================================="
echo ""
echo "Die Konfiguration wurde erfolgreich abgeschlossen."
echo "Alle notwendigen Passwörter, Logins und API-Keys wurden generiert."
echo ""
echo "Sie finden alle Zugangsdaten in der folgenden Datei:"
echo "  ${CRED_FILE}"
echo ""
echo "Wichtige URLs:"
echo "  Icinga Web 2: https://${ZAMBA_HOSTNAME:-$(hostname -f)}/icingaweb2"
echo "  IcingaDB Web: https://${ZAMBA_HOSTNAME:-$(hostname -f)}/icingadb-web"
echo ""
cat ${CRED_FILE}