#!/bin/bash
#
# Zamba LXC Toolbox - Service Installer
# Service: icinga-stack
#
# Description: Führt die Installation und Konfiguration des Icinga2 Stacks durch.
# Dieses Skript ist eigenständig und verwendet nur Standard-OS-Befehle.
#

# --- Internal Helper Functions ---
# Diese Funktion ist skript-spezifisch und nicht Teil eines Frameworks.
_generate_local_password() {
    # Erzeugt eine sichere, zufällige Zeichenkette.
    # $1: Länge der Zeichenkette
    openssl rand -base64 "$1"
}


# --- Service Functions (_install, _configure, _setup, _info) ---

_install() {
    echo ""
    echo "================================================="
    echo "  Phase 1: Installation der Pakete"
    echo "================================================="
    echo ""
    
    echo "[INFO] System wird aktualisiert und Basispakete werden installiert."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y wget gpg apt-transport-https curl sudo lsb-release

    echo "[INFO] Repositories für Icinga, InfluxDB und Grafana werden hinzugefügt."
    # Icinga Repo
    if [ ! -f /etc/apt/sources.list.d/icinga.list ]; then
        curl -fsSL https://packages.icinga.com/icinga.key | gpg --dearmor -o /usr/share/keyrings/icinga-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/icinga-archive-keyring.gpg] https://packages.icinga.com/debian icinga-${OS_CODENAME} main" > /etc/apt/sources.list.d/icinga.list
        echo "[INFO] Icinga Repository für ${OS_CODENAME} hinzugefügt."
    else
        echo "[INFO] Icinga Repository existiert bereits."
    fi

    # InfluxDB Repo
    if [ ! -f /etc/apt/sources.list.d/influxdata.list ]; then
        curl -fsSL https://repos.influxdata.com/influxdata-archive_compat.key | gpg --dearmor -o /usr/share/keyrings/influxdata-archive_compat-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/influxdata-archive_compat-keyring.gpg] https://repos.influxdata.com/debian ${OS_CODENAME} stable" > /etc/apt/sources.list.d/influxdata.list
        echo "[INFO] InfluxDB Repository für ${OS_CODENAME} hinzugefügt."
    else
        echo "[INFO] InfluxDB Repository existiert bereits."
    fi

    # Grafana Repo
    if [ ! -f /etc/apt/sources.list.d/grafana.list ]; then
        wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor -o /usr/share/keyrings/grafana-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/grafana-archive-keyring.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
        echo "[INFO] Grafana Repository hinzugefügt."
    else
        echo "[INFO] Grafana Repository existiert bereits."
    fi
    
    echo "[INFO] Paketlisten werden erneut aktualisiert."
    apt-get update

    echo "[INFO] Hauptkomponenten werden installiert (PHP Version: ${PHP_VERSION})."
    apt-get install -y \
        icinga2 icinga2-ido-pgsql \
        nginx php${PHP_VERSION}-fpm php${PHP_VERSION}-pgsql php${PHP_VERSION}-intl php${PHP_VERSION}-imagick php${PHP_VERSION}-xml php${PHP_VERSION}-gd php${PHP_VERSION}-ldap \
        postgresql \
        influxdb2 \
        grafana \
        icingaweb2 icingacli

    echo "[INFO] Icinga Director Modul wird installiert."
    if [ ! -d /usr/share/icingaweb2/modules/director ]; then
        ICINGA_DIRECTOR_VERSION=$(curl -s "https://api.github.com/repos/Icinga/icingaweb2-module-director/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
        wget -O /tmp/director.tar.gz "https://github.com/Icinga/icingaweb2-module-director/archive/refs/tags/v${ICINGA_DIRECTOR_VERSION}.tar.gz"
        tar -C /usr/share/icingaweb2/modules -xzf /tmp/director.tar.gz
        mv /usr/share/icingaweb2/modules/icingaweb2-module-director-* /usr/share/icingaweb2/modules/director
        rm /tmp/director.tar.gz
        echo "[INFO] Icinga Director v${ICINGA_DIRECTOR_VERSION} installiert."
    else
        echo "[INFO] Icinga Director ist bereits installiert."
    fi

    echo "[INFO] Systemd Services werden aktiviert."
    systemctl enable --now icinga2 postgresql nginx php${PHP_VERSION}-fpm influxdb2 grafana-server
}

_configure() {
    echo ""
    echo "================================================="
    echo "  Phase 2: Konfiguration der Komponenten"
    echo "================================================="
    echo ""

    # 1. Passwörter und Credentials generieren und speichern
    echo "[INFO] Passwörter und API-Keys werden generiert und in ${CRED_FILE} gespeichert."
    ICINGAWEB_DB_PASS=$(_generate_local_password 24)
    DIRECTOR_DB_PASS=$(_generate_local_password 24)
    ICINGA_IDO_DB_PASS=$(_generate_local_password 24)
    ICINGA_API_USER_PASS=$(_generate_local_password 24)
    ICINGAWEB_ADMIN_PASS=$(_generate_local_password 16)
    GRAFANA_ADMIN_PASS=$(_generate_local_password 16)
    INFLUX_ADMIN_TOKEN=$(_generate_local_password 40)
    INFLUX_ICINGA_TOKEN=$(_generate_local_password 40)
    
    mkdir -p "$(dirname "$CRED_FILE")"
    chmod 700 "$(dirname "$CRED_FILE")"
    {
      echo "# --- Icinga Monitoring Stack Credentials ---"
      echo "# Automatisch generiert am $(date)"
      echo "# OS: Debian ${OS_CODENAME}"
      echo ""
      echo "## Icinga Web 2"
      echo "URL: https://${ZAMBA_HOSTNAME:-$(hostname -f)}/icingaweb2"
      echo "Benutzer: icingaadmin"
      echo "Passwort: ${ICINGAWEB_ADMIN_PASS}"
      echo ""
      echo "## Grafana"
      echo "URL: https://${ZAMBA_HOSTNAME:-$(hostname -f)}/grafana"
      echo "Benutzer: admin"
      echo "Passwort: ${GRAFANA_ADMIN_PASS}"
      echo ""
      echo "## InfluxDB 2 (für API-Nutzung)"
      echo "URL: http://localhost:8086"
      echo "Admin Token: ${INFLUX_ADMIN_TOKEN}"
      echo "Icinga Token: ${INFLUX_ICINGA_TOKEN}"
      echo "Organisation: icinga"
      echo "Bucket: icinga"
      echo ""
      echo "## Icinga2 Director API"
      echo "Benutzer: director"
      echo "Passwort: ${ICINGA_API_USER_PASS}"
    } > "$CRED_FILE"
    chmod 600 "$CRED_FILE"

    # 2. PostgreSQL konfigurieren
    echo "[INFO] PostgreSQL wird konfiguriert."
    sudo -u postgres psql -c "CREATE ROLE icingaweb2 WITH LOGIN PASSWORD '${ICINGAWEB_DB_PASS}';" &>/dev/null || echo "[INFO] Postgres-Rolle 'icingaweb2' existiert bereits."
    sudo -u postgres psql -c "CREATE ROLE director WITH LOGIN PASSWORD '${DIRECTOR_DB_PASS}';" &>/dev/null || echo "[INFO] Postgres-Rolle 'director' existiert bereits."
    sudo -u postgres psql -c "CREATE ROLE icinga_ido WITH LOGIN PASSWORD '${ICINGA_IDO_DB_PASS}';" &>/dev/null || echo "[INFO] Postgres-Rolle 'icinga_ido' existiert bereits."
    sudo -u postgres createdb -O icingaweb2 icingaweb2 &>/dev/null || echo "[INFO] Postgres-DB 'icingaweb2' existiert bereits."
    sudo -u postgres createdb -O director director &>/dev/null || echo "[INFO] Postgres-DB 'director' existiert bereits."
    sudo -u postgres createdb -O icinga_ido icinga_ido &>/dev/null || echo "[INFO] Postgres-DB 'icinga_ido' existiert bereits."
    sudo -u postgres psql -d icinga_ido -c "GRANT ALL ON SCHEMA public TO icinga_ido;"

    # 3. Icinga2 konfigurieren
    echo "[INFO] Icinga2 (ido-pgsql, api, influxdb2-writer) wird konfiguriert."
    icinga2 feature enable ido-pgsql api influxdb2-writer >/dev/null
    
    bash -c "cat > /etc/icinga2/features-available/ido-pgsql.conf" <<EOF
object IdoPgsqlConnection "ido-pgsql" {
  user = "icinga_ido",
  password = "${ICINGA_IDO_DB_PASS}",
  host = "localhost",
  database = "icinga_ido"
}
EOF
    bash -c "cat > /etc/icinga2/conf.d/api-users.conf" <<EOF
object ApiUser "director" {
  password = "${ICINGA_API_USER_PASS}"
  permissions = [ "object/modify/*", "object/query/*", "status/query", "actions/*", "events/*" ]
}
EOF
    bash -c "cat > /etc/icinga2/features-available/influxdb2-writer.conf" <<EOF
object Influxdb2Writer "influxdb2-writer" {
  host = "http://127.0.0.1:8086"
  organization = "icinga"
  bucket = "icinga"
  token = "${INFLUX_ICINGA_TOKEN}"
  flush_interval = 10s
  flush_threshold = 1024
}
EOF

    # 4. Icinga Web 2 & Director konfigurieren
    echo "[INFO] Icinga Web 2 und Director werden konfiguriert."
    icingacli module enable director
    mkdir -p /etc/icingaweb2
    bash -c "cat > /etc/icingaweb2/resources.ini" <<EOF
[icingaweb_db]
type = "db"
db = "pgsql"
host = "localhost"
port = "5432"
dbname = "icingaweb2"
username = "icingaweb2"
password = "${ICINGAWEB_DB_PASS}"

[director_db]
type = "db"
db = "pgsql"
host = "localhost"
port = "5432"
dbname = "director"
username = "director"
password = "${DIRECTOR_DB_PASS}"

[icinga_ido]
type = "db"
db = "pgsql"
host = "localhost"
port = "5432"
dbname = "icinga_ido"
username = "icinga_ido"
password = "${ICINGA_IDO_DB_PASS}"
EOF
    
    # 5. InfluxDB 2 konfigurieren
    echo "[INFO] InfluxDB 2 wird konfiguriert."
    influx setup --skip-verify --username admin --password "$GRAFANA_ADMIN_PASS" --org icinga --bucket icinga --token "$INFLUX_ADMIN_TOKEN" -f
    influx auth create --org icinga --all-access-org icinga --token "$INFLUX_ICINGA_TOKEN"
    
    # 6. Grafana konfigurieren
    echo "[INFO] Grafana wird konfiguriert."
    grafana-cli admin reset-admin-password "$GRAFANA_ADMIN_PASS"
    
    mkdir -p /etc/grafana/provisioning/datasources
    bash -c "cat > /etc/grafana/provisioning/datasources/influxdb.yaml" <<EOF
apiVersion: 1
datasources:
- name: InfluxDB-Icinga
  type: influxdb
  access: proxy
  url: http://localhost:8086
  jsonData:
    version: Flux
    organization: icinga
    defaultBucket: icinga
    tlsSkipVerify: true
  secureJsonData:
    token: "${INFLUX_ICINGA_TOKEN}"
EOF
    chown grafana:grafana /etc/grafana/provisioning/datasources/influxdb.yaml
    
    # 7. Nginx konfigurieren
    echo "[INFO] Nginx als Reverse Proxy wird konfiguriert."
    mkdir -p /etc/nginx/ssl
    if [ ! -L /etc/nginx/ssl/fullchain.pem ]; then
        ln -s /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/nginx/ssl/fullchain.pem
        ln -s /etc/ssl/private/ssl-cert-snakeoil.key /etc/nginx/ssl/privkey.pem
    fi
    
    bash -c "cat > /etc/nginx/sites-available/icinga-stack" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${ZAMBA_HOSTNAME:-$(hostname -f)};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${ZAMBA_HOSTNAME:-$(hostname -f)};

    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';

    root /usr/share/icingaweb2/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param ICINGAWEB_CONFIGDIR /etc/icingaweb2;
        fastcgi_param REMOTE_USER \$remote_user;
    }

    location /grafana {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/icinga-stack /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # PHP-FPM für Nginx anpassen
    sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' "/etc/php/${PHP_VERSION}/fpm/php.ini"
    sed -i "s|;date.timezone =|date.timezone = $(cat /etc/timezone)|" "/etc/php/${PHP_VERSION}/fpm/php.ini"
}

_setup() {
    echo ""
    echo "================================================="
    echo "  Phase 3: Setup und finaler Neustart"
    echo "================================================="
    echo ""
    
    # 1. Schemas importieren
    echo "[INFO] Datenbank-Schemas werden importiert."
    sudo -u postgres psql -d icinga_ido -c "SELECT current_user;" # Warmup
    PGPASSWORD="${ICINGA_IDO_DB_PASS}" psql -h localhost -U icinga_ido -d icinga_ido -f /usr/share/icinga2-ido-pgsql/schema/pgsql.sql &>/dev/null
    PGPASSWORD="${ICINGAWEB_DB_PASS}" psql -h localhost -U icingaweb2 -d icingaweb2 -f /usr/share/icingaweb2/etc/schema/pgsql.schema.sql &>/dev/null
    
    # 2. Icinga Web 2 Setup
    echo "[INFO] Icinga Web 2 Setup wird ausgeführt."
    ICINGAWEB_SETUP_TOKEN=$(icingacli setup token create)
    icingacli setup config webserver nginx --document-root /usr/share/icingaweb2/public
    icingacli setup --unattended --module icingaweb2 --setup-token "$ICINGAWEB_SETUP_TOKEN" \
        --db-type pgsql --db-host localhost --db-port 5432 --db-name icingaweb2 \
        --db-user icingaweb2 --db-pass "$ICINGAWEB_DB_PASS"
    icingacli setup --unattended --module monitoring --setup-token "$ICINGAWEB_SETUP_TOKEN" \
        --backend-type ido --resource icinga_ido
    icingacli user add icingaadmin --password "$ICINGAWEB_ADMIN_PASS" --role "Administrators"

    # 3. Director Setup
    echo "[INFO] Icinga Director Setup wird ausgeführt."
    icingacli director kickstart --endpoint localhost --user director --password "${ICINGA_API_USER_PASS}"
    icingacli director config set 'endpoint' 'localhost' --user 'director' --password "${ICINGA_API_USER_PASS}"
    icingacli director migration run
    icingacli director automation run

    # 4. Services neu starten, um alle Konfigurationen zu laden
    echo "[INFO] Alle Services werden neu gestartet."
    systemctl restart postgresql
    systemctl restart icinga2
    systemctl restart php${PHP_VERSION}-fpm
    systemctl restart nginx
    systemctl restart grafana-server
    
    echo "[INFO] Warte auf Icinga2 API..."
    sleep 15
    echo "[INFO] Director Konfiguration wird angewendet."
    icingacli director config deploy
}

_info() {
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
    echo "  Grafana:      https://${ZAMBA_HOSTNAME:-$(hostname -f)}/grafana"
    echo ""
    echo "Hinweis zu TLS: Der Server verwendet aktuell ein selbst-signiertes 'snakeoil'-Zertifikat."
    echo "Ersetzen Sie die Symlinks in /etc/nginx/ssl/ mit Ihren echten Zertifikaten und starten Sie Nginx neu:"
    echo "  systemctl restart nginx"
    echo ""
}

# --- Main Execution Logic ---
# This part is executed by the Zamba LXC Toolbox framework,
# which calls the _install, _configure, _setup, and _info functions in order.
# For standalone testing, you could uncomment the lines below.

# if [ "$EUID" -ne 0 ]; then
#   echo "[ERROR] Dieses Skript muss als Root ausgeführt werden."
#   exit 1
# fi
#
# # Load constants if running standalone
# ZAMBA_HOSTNAME=$(hostname -f)
# source ./constants-service.conf
#
# set -e # Exit on first error
# _install
# _configure
# _setup
# _info
# set +e
#
# exit 0
