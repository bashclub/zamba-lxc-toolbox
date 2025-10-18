#!/bin/bash
#
# This script has basic functions like a random password generator
LXC_RANDOMPWD=32

random_password() {
    set +o pipefail
    LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom 2>/dev/null | head -c${LXC_RANDOMPWD}
}

generate_dhparam() {
    openssl dhparam -dsaparam -out /etc/nginx/dhparam.pem 2048
    cat << EOF > /etc/cron.monthly/generate-dhparams
#!/bin/bash
openssl dhparam -out /etc/nginx/dhparam.gen 4096 > /dev/null 2>&1
mv /etc/nginx/dhparam.gen /etc/nginx/dhparam.pem
systemctl restart nginx
EOF
    chmod +x /etc/cron.monthly/generate-dhparams
}

apt_repo() {
    apt_name=$1
    apt_key_url=$2
    apt_key_path=/usr/share/keyrings/${apt_name}.gpg
    apt_repo_url=$3
    apt_suites=$4
    apt_components=$5
    tmp_key_file=$(mktemp)
    if ! curl -fsSL -o "${tmp_key_file}" "${apt_key_url}"; then
        echo "❌ Fehler beim Herunterladen des Schlüssels."
        rm -f "${tmp_key_file}"
        exit 1
    fi
    if file "${tmp_key_file}" | grep -q "ASCII"; then
        echo "🔍 Format erkannt: ASCII. Konvertiere den Schlüssel..."
        # Wenn es ASCII ist, konvertiere es mit --dearmor
        if sudo gpg --dearmor -o "${apt_key_path}" "${tmp_key_file}"; then
            echo "✅ Schlüssel erfolgreich nach ${apt_key_path} konvertiert."
        else
            echo "❌ Fehler bei der Konvertierung des ASCII-Schlüssels."
            rm -f "${tmp_key_file}" # Temporäre Datei aufräumen
            exit 1
        fi
    else
        echo "🔍 Format erkannt: Binär. Kopiere den Schlüssel direkt..."
        # Wenn es kein ASCII ist, gehen wir von Binär aus und verschieben die Datei
        if sudo mv "${tmp_key_file}" "${apt_key_path}"; then
            echo "✅ Schlüssel erfolgreich nach ${apt_key_path} kopiert."
        else
            echo "❌ Fehler beim Kopieren des binären Schlüssels."
            rm -f "${tmp_key_file}"
            exit 1
        fi
    fi

    if [[ $(lsb_release -r | cut -f2) -gt 12 ]]; then
        cat << EOF > /etc/apt/sources.list.d/${apt_name}.sources
Types: deb
URIs: $apt_repo_url
Suites: $apt_suites
Components: $apt_components
Enabled: yes
Signed-By: $apt_key_path
EOF
    else
        echo "deb [signed-by=${apt_key_path}] ${apt_repo_url} ${apt_suites} ${apt_components}" > /etc/apt/sources.list.d/${apt_name}.list
    fi
}

#### Set repo and install Nginx ####
inst_nginx() {
    apt_repo "nginx" "https://nginx.org/keys/nginx_signing.key" "http://nginx.org/packages/mainline/debian" "$(lsb_release -cs)" "nginx"
    apt update && DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends nginx
}

#### Set repo and install PHP ####
inst_php() {
    apt_repo "php" "https://packages.sury.org/php/apt.gpg" "https://packages.sury.org/php/" "$(lsb_release -sc)" "main"
    apt update && DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends php-common php$NEXTCLOUD_PHP_VERSION-{fpm,gd,curl,pgsql,xml,zip,intl,mbstring,bz2,ldap,apcu,bcmath,gmp,imagick,igbinary,mysql,redis,smbclient,sqlite3,cli,common,opcache,readline}
}

#### Set repo and install Postgresql ####
inst_postgresql() {
    apt_repo "postgresql" "https://www.postgresql.org/media/keys/ACCC4CF8.asc" "http://apt.postgresql.org/pub/repos/apt" "$(lsb_release -cs)-pgdg" "main"
    apt update && DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends postgresql-$POSTGRES_VERSION
}

#### Set repo and install Crowdsec ####
inst_crowdsec() {
    apt_repo "crowdsec" "https://packagecloud.io/crowdsec/crowdsec/gpgkey" "https://packagecloud.io/crowdsec/crowdsec/any" "any" "main"
    apt update && DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends crowdsec
    DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends crowdsec-firewall-bouncer-nftables
}
