#!/bin/bash
#
# Zamba LXC Toolbox - Service Installer
# Service: icinga-stack
#
# Description: Führt die Installation und Konfiguration des Icinga2 Stacks mit MariaDB durch.
# Dieses Skript ist eigenständig und verwendet nur Standard-OS-Befehle.
#

# --- Internal Helper Functions ---
_generate_local_password() {
    openssl rand -base64 "$1"
}


# --- Service Functions (_install, _configure, _setup, _info) ---

_install() {
    echo ""
    echo "================================================="
    echo "  Phase 1: Installation der Pakete (MariaDB Edition)"
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
    fi

    # InfluxDB Repo
    if [ ! -f /etc/apt/sources.list.d/influxdata.list ]; then
        curl -fsSL https://repos.influxdata.com/influxdata-archive_compat.key | gpg --dearmor -o /usr/share/keyrings/influxdata-archive_compat-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/influxdata-archive_compat-keyring.gpg] https://repos.influxdata.com/debian ${OS_CODENAME} stable" > /etc/apt/sources.list.d/influxdata.list
    fi

    # Grafana Repo
    if [ ! -f /etc/apt/sources.list.d/grafana.list ]; then
        wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor -o /usr/share/keyrings/grafana-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/grafana-archive-keyring.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
    fi
    
    echo "[INFO] Paketlisten werden erneut aktualisiert."
    apt-get update

    echo "[INFO] Hauptkomponenten werden installiert (PHP Version: ${PHP_VERSION})."
    apt-get install -y \
        icinga2 icinga2-ido-mysql \
        nginx php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql php${PHP_VERSION}-intl php${PHP_VERSION}-imagick php${PHP_VERSION}-xml php${PHP_VERSION}-gd php${PHP_VERSION}-ldap \
        mariadb-server mariadb-client \
        influxdb2 \
        grafana \
        icingaweb2 icingacli

    echo "[INFO] Icinga Web 2 Module (Abhängigkeiten für Director) werden installiert."
    install_icinga_module() {
        local module_name="$1"
        local repo_name="$2"
        if [ ! -d "/usr/share/icingaweb2/modules/${module_name}" ]; then
            echo "[INFO] Installiere Modul: ${module_name}"
            local version=$(curl -s "https://api.github.com/repos/Icinga/${repo_name}/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
            wget -O "/tmp/${module_name}.tar.gz" "https://github.com/Icinga/${repo_name}/archive/refs/tags/v${version}.tar.gz"
            tar -C /usr/share/icingaweb2/modules -xzf "/tmp/${module_name}.tar.gz"
            mv "/usr/share/icingaweb2/modules/${repo_name}-"* "/usr/share/icingaweb2/modules/${module_name}"
            rm "/tmp/${module_name}.tar.gz"
        fi
    }
    
    install_icinga_module "ipl" "icingaweb2-module-ipl"
    install_icinga_module "reactbundle" "icingaweb2-module-reactbundle"
    install_icinga_module "incubator" "icingaweb2-module-incubator"
    install_icinga_module "director" "icingaweb2-module-director"

    echo "[INFO] Systemd Services werden aktiviert."
    systemctl enable --now icinga2 mariadb nginx php${PHP_VERSION}-fpm influxdb grafana-server
}

_configure() {
    echo ""
    echo "================================================="
    echo "  Phase 2: Konfiguration der Komponenten (MariaDB Edition)"
    echo "================================================="
    echo ""

    # 1. Passwörter generieren
    echo "[INFO] Passwörter und API-Keys werden generiert."
    ICINGAWEB_DB_PASS=$(_generate_local_password 24)
    DIRECTOR_DB_PASS=$(_generate_local_password 24)
    ICINGA_IDO_DB_PASS=$(_generate_local_password 24)
    ICINGA_API_USER_PASS=$(_generate_local_password 24)
    ICINGAWEB_ADMIN_PASS=$(_generate_local_password 16)
    GRAFANA_ADMIN_PASS=$(_generate_local_password 16)
    INFLUX_ADMIN_TOKEN=$(_generate_local_password 40)
    
    # 2. MariaDB konfigurieren
    echo "[INFO] MariaDB wird konfiguriert."
    mysql -e "CREATE DATABASE IF NOT EXISTS icingaweb2 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE DATABASE IF NOT EXISTS director CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE DATABASE IF NOT EXISTS icinga_ido CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    
    mysql -e "CREATE USER IF NOT EXISTS 'icingaweb2'@'localhost' IDENTIFIED BY '${ICINGAWEB_DB_PASS}';"
    mysql -e "CREATE USER IF NOT EXISTS 'director'@'localhost' IDENTIFIED BY '${DIRECTOR_DB_PASS}';"
    mysql -e "CREATE USER IF NOT EXISTS 'icinga_ido'@'localhost' IDENTIFIED BY '${ICINGA_IDO_DB_PASS}';"

    mysql -e "GRANT ALL PRIVILEGES ON icingaweb2.* TO 'icingaweb2'@'localhost';"
    mysql -e "GRANT ALL PRIVILEGES ON director.* TO 'director'@'localhost';"
    mysql -e "GRANT ALL PRIVILEGES ON icinga_ido.* TO 'icinga_ido'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"

    # 3. InfluxDB 2 konfigurieren
    echo "[INFO] InfluxDB 2 wird konfiguriert."
    influx setup --skip-verify --username admin --password "$GRAFANA_ADMIN_PASS" --org icinga --bucket icinga --token "$INFLUX_ADMIN_TOKEN" -f
    INFLUX_ICINGA_TOKEN=$(influx auth create --org icinga --all-access --json | grep -oP '"token": "\K[^"]+')
    if [ -z "$INFLUX_ICINGA_TOKEN" ]; then echo "[ERROR] Konnte InfluxDB Token nicht erstellen." >&2; exit 1; fi

    # 4. Credentials-Datei schreiben
    echo "[INFO] Zugangsdaten werden in ${CRED_FILE} gespeichert."
    mkdir -p "$(dirname "$CRED_FILE")" && chmod 700 "$(dirname "$CRED_FILE")"
    {
      echo "# --- Icinga Monitoring Stack Credentials ---"
      echo "URL: https://${ZAMBA_HOSTNAME:-$(hostname -f)}/icingaweb2; Benutzer: icingaadmin; Passwort: ${ICINGAWEB_ADMIN_PASS}"
      echo "URL: https://${ZAMBA_HOSTNAME:-$(hostname -f)}/grafana; Benutzer: admin; Passwort: ${GRAFANA_ADMIN_PASS}"
      echo "InfluxDB Admin Token: ${INFLUX_ADMIN_TOKEN}"
      echo "Icinga Director API: Benutzer: director; Passwort: ${ICINGA_API_USER_PASS}"
    } > "$CRED_FILE" && chmod 600 "$CRED_FILE"

    # 5. Icinga2 Konfigurationsdateien schreiben
    echo "[INFO] Icinga2 Konfigurationsdateien werden geschrieben."
    bash -c "cat > /etc/icinga2/features-available/ido-mysql.conf" <<EOF
object IdoMysqlConnection "ido-mysql" {
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
  auth_token = "${INFLUX_ICINGA_TOKEN}"
}
EOF

    # 6. Icinga Web 2 Konfigurationsdateien schreiben
    echo "[INFO] Icinga Web 2 Konfigurationsdateien werden geschrieben."
    mkdir -p /etc/icingaweb2
    bash -c "cat > /etc/icingaweb2/resources.ini" <<EOF
[icingaweb_db]
type = "db"
db = "mysql"
host = "localhost"
dbname = "icingaweb2"
username = "icingaweb2"
password = "${ICINGAWEB_DB_PASS}"

[director_db]
type = "db"
db = "mysql"
host = "localhost"
dbname = "director"
username = "director"
password = "${DIRECTOR_DB_PASS}"

[icinga_ido]
type = "db"
db = "mysql"
host = "localhost"
dbname = "icinga_ido"
username = "icinga_ido"
password = "${ICINGA_IDO_DB_PASS}"
EOF
    
    # 7. Grafana konfigurieren
    echo "[INFO] Grafana wird konfiguriert."
    systemctl stop grafana-server
    grafana-cli admin reset-admin-password "$GRAFANA_ADMIN_PASS"
    systemctl start grafana-server
    
    mkdir -p /etc/grafana/provisioning/datasources
    bash -c "cat > /etc/grafana/provisioning/datasources/influxdb.yaml" <<EOF
apiVersion: 1
datasources:
- name: InfluxDB-Icinga
  type: influxdb
  access: proxy
  url: http://localhost:8086
  jsonData: { version: "Flux", organization: "icinga", defaultBucket: "icinga" }
  secureJsonData: { token: "${INFLUX_ICINGA_TOKEN}" }
EOF
    chown grafana:grafana /etc/grafana/provisioning/datasources/influxdb.yaml
    
    # 8. Nginx TLS Konfiguration
    echo "[INFO] Nginx für TLS wird konfiguriert."
    mkdir -p /etc/nginx/ssl
    if [ ! -L /etc/nginx/ssl/fullchain.pem ]; then
        ln -s /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/nginx/ssl/fullchain.pem
        ln -s /etc/ssl/private/ssl-cert-snakeoil.key /etc/nginx/ssl/privkey.pem
    fi

    bash -c "cat > /etc/nginx/sites-available/icinga-stack" <<EOF
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
    location /grafana {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$http_host;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/icinga-stack /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' "/etc/php/${PHP_VERSION}/fpm/php.ini"
    sed -i "s|;date.timezone =|date.timezone = $(cat /etc/timezone)|" "/etc/php/${PHP_VERSION}/fpm/php.ini"
}

_setup() {
    echo ""
    echo "================================================="
    echo "  Phase 3: Setup und finaler Neustart (MariaDB Edition)"
    echo "================================================="
    echo ""
    
    echo "[INFO] Icinga2 API wird initialisiert und Zertifikate werden erstellt."
    icinga2 api setup
    
    echo "[INFO] Warte auf MariaDB-Dienst..."
    while ! mysqladmin ping -h localhost --silent; do
        echo "[INFO] MariaDB ist noch nicht bereit, warte 2 Sekunden..."
        sleep 2
    done
    echo "[INFO] MariaDB ist bereit."

    echo "[INFO] Datenbank-Schemas werden importiert."
    local IDO_SCHEMA="/usr/share/icinga2-ido-mysql/schema/mysql.sql"
    local IWEB_SCHEMA="/usr/share/icingaweb2/schema/mysql.schema.sql"

    if [ ! -f "$IDO_SCHEMA" ]; then echo "[ERROR] IDO-Schema nicht gefunden: $IDO_SCHEMA" >&2; exit 1; fi
    if [ ! -f "$IWEB_SCHEMA" ]; then echo "[ERROR] IcingaWeb-Schema nicht gefunden: $IWEB_SCHEMA" >&2; exit 1; fi

    if mysql -e "use icinga_ido; show tables;" | grep -q "icinga_dbversion"; then
        echo "[INFO] Icinga IDO-Schema scheint bereits importiert zu sein."
    else
        echo "[INFO] Importiere Icinga IDO-Schema..."
        mysql icinga_ido < "$IDO_SCHEMA"
    fi

    if mysql -e "use icingaweb2; show tables;" | grep -q "icingaweb_user"; then
        echo "[INFO] IcingaWeb2-Schema scheint bereits importiert zu sein."
    else
        echo "[INFO] Importiere IcingaWeb2-Schema..."
        mysql icingaweb2 < "$IWEB_SCHEMA"
    fi
    
    echo "[INFO] Icinga2 Features werden aktiviert."
    icinga2 feature enable ido-mysql api influxdb2-writer >/dev/null

    echo "[INFO] Icinga Web 2 Module werden in korrekter Reihenfolge aktiviert."
    icingacli module enable ipl
    icingacli module enable reactbundle
    icingacli module enable incubator
    icingacli module enable director

    echo "[INFO] Alle Services werden neu gestartet."
    systemctl restart mariadb
    systemctl restart icinga2
    systemctl restart php${PHP_VERSION}-fpm
    systemctl restart nginx
    systemctl restart grafana-server

    echo "[INFO] Icinga Web 2 Setup wird ausgeführt."
    ICINGAWEB_SETUP_TOKEN=$(icingacli setup token create)
    icingacli setup config webserver nginx --document-root /usr/share/icingaweb2/public
    
    # KORREKTUR: 'config' wurde zu den setup-Befehlen hinzugefügt.
    icingacli setup config module --unattended --module icingaweb2 --setup-token "$ICINGAWEB_SETUP_TOKEN" \
        --db-type mysql --db-host localhost --db-name icingaweb2 \
        --db-user icingaweb2 --db-pass "$ICINGAWEB_DB_PASS"
        
    icingacli setup config module --unattended --module monitoring --setup-token "$ICINGAWEB_SETUP_TOKEN" \
        --backend-type ido --resource icinga_ido
        
    icingacli user add icingaadmin --password "$ICINGAWEB_ADMIN_PASS" --role "Administrators"

    echo "[INFO] Warte auf Icinga2 API..."
    sleep 15
    echo "[INFO] Icinga Director Setup wird ausgeführt."
    icingacli director migration run
    icingacli director kickstart --endpoint localhost --user director --password "${ICINGA_API_USER_PASS}"
    icingacli director config set 'endpoint' 'localhost' --user 'director' --password "${ICINGA_API_USER_PASS}"
    icingacli director automation run
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
}

# --- Main Execution Logic ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$EUID" -ne 0 ]; then
      echo "[ERROR] Dieses Skript muss als Root ausgeführt werden."
      exit 1
    fi
    if [ -f ./constants-service.conf ]; then
        source ./constants-service.conf
    else
        echo "[ERROR] Die Datei 'constants-service.conf' wird für den Standalone-Betrieb benötigt."
        exit 1
    fi
    ZAMBA_HOSTNAME=${ZAMBA_HOSTNAME:-$(hostname -f)}
    set -euo pipefail
    _install
    _configure
    _setup
    _info
    set +euo pipefail
    exit 0
fi
