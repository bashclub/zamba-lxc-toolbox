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
        postgresql postgresql-client \
        influxdb2 \
        grafana \
        icingaweb2 icingacli

    echo "[INFO] Icinga Web 2 Module (Abhängigkeiten für Director) werden installiert."
    # Funktion zum Herunterladen und Entpacken von Modulen
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
        else
            echo "[INFO] Modul ${module_name} ist bereits installiert."
        fi
    }
    
    install_icinga_module "ipl" "icingaweb2-module-ipl"
    install_icinga_module "reactbundle" "icingaweb2-module-reactbundle"
    install_icinga_module "director" "icingaweb2-module-director"

    echo "[INFO] Systemd Services werden aktiviert."
    # Der Service für InfluxDB v2 heißt 'influxdb', nicht 'influxdb2'
    systemctl enable --now icinga2 postgresql nginx php${PHP_VERSION}-fpm influxdb grafana-server
}

_configure() {
    echo ""
    echo "================================================="
    echo "  Phase 2: Konfiguration der Komponenten"
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
    
    # 2. PostgreSQL konfigurieren
    echo "[INFO] PostgreSQL wird konfiguriert."
    sudo -u postgres psql -c "CREATE ROLE icingaweb2 WITH LOGIN PASSWORD '${ICINGAWEB_DB_PASS}';" &>/dev/null || echo "[INFO] Postgres-Rolle 'icingaweb2' existiert bereits."
    sudo -u postgres psql -c "CREATE ROLE director WITH LOGIN PASSWORD '${DIRECTOR_DB_PASS}';" &>/dev/null || echo "[INFO] Postgres-Rolle 'director' existiert bereits."
    sudo -u postgres psql -c "CREATE ROLE icinga_ido WITH LOGIN PASSWORD '${ICINGA_IDO_DB_PASS}';" &>/dev/null || echo "[INFO] Postgres-Rolle 'icinga_ido' existiert bereits."
    sudo -u postgres createdb -O icingaweb2 icingaweb2 &>/dev/null || echo "[INFO] Postgres-DB 'icingaweb2' existiert bereits."
    sudo -u postgres createdb -O director director &>/dev/null || echo "[INFO] Postgres-DB 'director' existiert bereits."
    sudo -u postgres createdb -O icinga_ido icinga_ido &>/dev/null || echo "[INFO] Postgres-DB 'icinga_ido' existiert bereits."
    sudo -u postgres psql -d icinga_ido -c "GRANT ALL ON SCHEMA public TO icinga_ido;"

    # 3. InfluxDB 2 konfigurieren und Icinga-Token generieren
    echo "[INFO] InfluxDB 2 wird konfiguriert."
    influx setup --skip-verify --username admin --password "$GRAFANA_ADMIN_PASS" --org icinga --bucket icinga --token "$INFLUX_ADMIN_TOKEN" -f
    
    echo "[INFO] Erstelle dedizierten InfluxDB Token für Icinga und Grafana."
    INFLUX_ICINGA_TOKEN=$(influx auth create --org icinga --all-access --json | grep -oP '"token": "\K[^"]+')
    if [ -z "$INFLUX_ICINGA_TOKEN" ]; then
        echo "[ERROR] Konnte InfluxDB Token für Icinga nicht erstellen." >&2
        exit 1
    fi
    echo "[INFO] InfluxDB Token erfolgreich erstellt."

    # 4. Credentials-Datei schreiben (jetzt sind alle Werte bekannt)
    echo "[INFO] Zugangsdaten werden in ${CRED_FILE} gespeichert."
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

    # 5. Icinga2 Konfigurationsdateien schreiben
    echo "[INFO] Icinga2 Konfigurationsdateien werden geschrieben."
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

    # 6. Icinga Web 2 Konfigurationsdateien schreiben
    echo "[INFO] Icinga Web 2 Konfigurationsdateien werden geschrieben."
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
    
    # 7. Grafana konfigurieren
    echo "[INFO] Grafana wird konfiguriert."
    # Grafana-Dienst stoppen, um DB-Sperre zu vermeiden
    echo "[INFO] Stoppe Grafana-Dienst für Passwort-Reset..."
    systemctl stop grafana-server
    grafana-cli admin reset-admin-password "$GRAFANA_ADMIN_PASS"
    echo "[INFO] Starte Grafana-Dienst neu."
    systemctl start grafana-server
    
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
    
    # 8. Nginx und Icinga2 API TLS Konfiguration
    echo "[INFO] Nginx und Icinga2 API für TLS werden konfiguriert."
    mkdir -p /etc/nginx/ssl
    if [ ! -L /etc/nginx/ssl/fullchain.pem ]; then
        ln -s /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/nginx/ssl/fullchain.pem
        ln -s /etc/ssl/private/ssl-cert-snakeoil.key /etc/nginx/ssl/privkey.pem
    fi

    # Sicherstellen, dass der 'icinga'-Benutzer existiert, bevor er modifiziert wird.
    if ! id -u icinga >/dev/null 2>&1; then
        echo "[WARN] Systembenutzer 'icinga' nicht gefunden. Wird erstellt."
        useradd --system --shell /usr/sbin/nologin --home-dir /var/lib/icinga2 icinga
    fi
    # Icinga-Benutzer zur ssl-cert Gruppe hinzufügen, um den Schlüssel lesen zu können
    usermod -a -G ssl-cert icinga

    # api.conf anpassen, um die Nginx/Snakeoil-Zertifikate zu verwenden
    bash -c "cat > /etc/icinga2/features-available/api.conf" <<EOF
object ApiListener "api" {
  cert_path = "/etc/nginx/ssl/fullchain.pem"
  key_path = "/etc/nginx/ssl/privkey.pem"
  ca_path = "/etc/ssl/certs/ca-certificates.crt"
  
  accept_config = true
  accept_commands = true
}
EOF

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
    
    # 1. Warten, bis PostgreSQL bereit ist
    echo "[INFO] Warte auf PostgreSQL-Dienst..."
    while ! pg_isready -q -h localhost -U postgres; do
        echo "[INFO] PostgreSQL ist noch nicht bereit, warte 2 Sekunden..."
        sleep 2
    done
    echo "[INFO] PostgreSQL ist bereit."

    # 2. Datenbank-Schemas importieren (als postgres-Benutzer für Robustheit)
    echo "[INFO] Datenbank-Schemas werden importiert."
    
    local IDO_SCHEMA="/usr/share/icinga2-ido-pgsql/schema/pgsql.sql"
    # KORREKTUR: Korrekter Pfad zur komprimierten Schema-Datei
    local IWEB_SCHEMA_GZ="/usr/share/doc/icingaweb2/schema/pgsql.schema.sql.gz"

    if [ ! -f "$IDO_SCHEMA" ]; then
        echo "[ERROR] IDO-Schema-Datei nicht gefunden: $IDO_SCHEMA" >&2
        exit 1
    fi
    if [ ! -f "$IWEB_SCHEMA_GZ" ]; then
        echo "[ERROR] IcingaWeb-Schema-Datei nicht gefunden: $IWEB_SCHEMA_GZ" >&2
        exit 1
    fi

    # Prüfen, ob die Tabellen bereits existieren, um Idempotenz zu gewährleisten
    if sudo -u postgres psql -d icinga_ido -tAc "SELECT 1 FROM information_schema.tables WHERE table_name = 'icinga_dbversion'" | grep -q 1; then
        echo "[INFO] Icinga IDO-Schema scheint bereits importiert zu sein."
    else
        echo "[INFO] Importiere Icinga IDO-Schema..."
        sudo -u postgres psql -d icinga_ido -f "$IDO_SCHEMA" &>/dev/null
    fi

    if sudo -u postgres psql -d icingaweb2 -tAc "SELECT 1 FROM information_schema.tables WHERE table_name = 'icingaweb_user'" | grep -q 1; then
        echo "[INFO] IcingaWeb2-Schema scheint bereits importiert zu sein."
    else
        echo "[INFO] Importiere IcingaWeb2-Schema..."
        # Entpacke die Datei und leite sie per Pipe an psql weiter
        gunzip -c "$IWEB_SCHEMA_GZ" | sudo -u postgres psql -d icingaweb2 &>/dev/null
    fi
    
    # 3. Icinga2 Features aktivieren (NACHDEM die DB bereit ist)
    echo "[INFO] Icinga2 Features werden aktiviert."
    icinga2 feature enable ido-pgsql api influxdb2-writer >/dev/null

    # 4. Icinga Web 2 Module in korrekter Reihenfolge aktivieren
    echo "[INFO] Icinga Web 2 Module werden aktiviert."
    icingacli module enable ipl
    icingacli module enable reactbundle
    icingacli module enable director

    # 5. Alle Dienste neu starten
    echo "[INFO] Alle Services werden neu gestartet, um Konfigurationen zu laden."
    systemctl restart postgresql
    systemctl restart icinga2
    systemctl restart php${PHP_VERSION}-fpm
    systemctl restart nginx
    systemctl restart grafana-server

    # 6. Icinga Web 2 Setup ausführen (NACHDEM die Dienste laufen)
    echo "[INFO] Icinga Web 2 Setup wird ausgeführt."
    ICINGAWEB_SETUP_TOKEN=$(icingacli setup token create)
    icingacli setup config webserver nginx --document-root /usr/share/icingaweb2/public
    icingacli setup --unattended --module icingaweb2 --setup-token "$ICINGAWEB_SETUP_TOKEN" \
        --db-type pgsql --db-host localhost --db-port 5432 --db-name icingaweb2 \
        --db-user icingaweb2 --db-pass "$ICINGAWEB_DB_PASS"
    icingacli setup --unattended --module monitoring --setup-token "$ICINGAWEB_SETUP_TOKEN" \
        --backend-type ido --resource icinga_ido
    icingacli user add icingaadmin --password "$ICINGAWEB_ADMIN_PASS" --role "Administrators"

    # 7. Director Setup ausführen (als letzter Schritt)
    echo "[INFO] Warte auf Icinga2 API..."
    sleep 15 # Gibt Icinga2 Zeit, vollständig zu starten
    echo "[INFO] Icinga Director Setup wird ausgeführt."
    icingacli director migration run # Importiert das Director DB Schema
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
    echo "Hinweis zu TLS: Der Server verwendet aktuell die Icinga2-eigenen, selbst-signierten Zertifikate."
    echo "Wenn Sie externe Zertifikate (z.B. von Let's Encrypt) verwenden möchten,"
    echo "passen Sie die Pfade in /etc/nginx/sites-available/icinga-stack und /etc/icinga2/features-available/api.conf an und starten Sie die Dienste neu."
    echo ""
}

# --- Main Execution Logic ---
# Dieser Block wird nur ausgeführt, wenn das Skript direkt aufgerufen wird,
# nicht wenn es von der Zamba Toolbox als Bibliothek geladen wird.
# Ideal für Standalone-Tests.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    
    if [ "$EUID" -ne 0 ]; then
      echo "[ERROR] Dieses Skript muss als Root ausgeführt werden."
      exit 1
    fi

    # Lade Konstanten, wenn das Skript standalone läuft
    if [ -f ./constants-service.conf ]; then
        source ./constants-service.conf
    else
        echo "[ERROR] Die Datei 'constants-service.conf' wird für den Standalone-Betrieb benötigt."
        exit 1
    fi
    
    # Setze einen Fallback-Hostnamen, falls ZAMBA_HOSTNAME nicht gesetzt ist
    ZAMBA_HOSTNAME=${ZAMBA_HOSTNAME:-$(hostname -f)}

    # Aktiviere den Bash Strict Mode für eine sichere Ausführung
    set -euo pipefail

    # Führe die Installationsphasen nacheinander aus
    _install
    _configure
    _setup
    _info

    set +euo pipefail
    
    exit 0
fi
