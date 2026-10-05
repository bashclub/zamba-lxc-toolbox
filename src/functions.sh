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
    apt_key_path=/usr/share/keyrings/${apt_name}-archive-keyring.gpg
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
            chmod 644 ${apt_key_path}
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
            chmod 644 ${apt_key_path}
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
    PHP_MODULES=${1}
    PHP_VERSION=${2:-8.4}
    IFS=',' read -ra MODULE_ARRAY <<< "$PHP_MODULES"
    PKGS=()
    for PHP_MODULE in "${MODULE_ARRAY[@]}"; do
        PKGS+=( "php${PHP_VERSION}-${PHP_MODULE}" )
    done
    apt_repo "php" "https://packages.sury.org/php/apt.gpg" "https://packages.sury.org/php/" "$(lsb_release -sc)" "main"
    apt update && DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends php-common "${PKGS[@]}"
}

#### Set repo and install Postgresql ####
# First paramater is postgres version, default ist curren version postgres 18
inst_postgresql() {
    POSTGRES_VERSION=${1:-18}
    
    apt_repo "postgresql" "https://www.postgresql.org/media/keys/ACCC4CF8.asc" "http://apt.postgresql.org/pub/repos/apt" "$(lsb_release -cs)-pgdg" "main"
    apt update && DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends postgresql-${POSTGRES_VERSION}
}

#### Set repo and install Crowdsec ####
inst_crowdsec() {
    apt_repo "crowdsec" "https://packagecloud.io/crowdsec/crowdsec/gpgkey" "https://packagecloud.io/crowdsec/crowdsec/any" "any" "main"
    apt update && DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends crowdsec
    DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends crowdsec-firewall-bouncer-nftables
}

#### Set repo and install 45drives (cockpit) ####
inst_45drives() {
    apt_repo "45drives" "https://repo.45drives.com/key/gpg.asc" "https://repo.45drives.com/enterprise/debian" "bookworm" "main"
    apt update
}

#### Set repo and install Docker ####
inst_docker() {
    apt_repo "docker" "https://download.docker.com/linux/debian/gpg" "https://download.docker.com/linux/debian" "$(lsb_release -cs)" stable
    apt update
    DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin pwgen
}
#### Set repo and install MongoDB ####
inst_mongodb() {
    MONGODB_VERSION=${1:-8.0}

    apt_repo "mongodb" "https://www.mongodb.org/static/pgp/server-$MONGODB_VERSION.asc" "http://repo.mongodb.org/apt/debian" "bookworm/mongodb-org/$MONGODB_VERSION" "main"
    apt update
    DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq mongodb-org
}

#### Set repo and install MongoDB ####
inst_bashclub() {
    BASHCLUB_COMPONENT=${1:-release}

    apt_repo "bashclub-$BASHCLUB_COMPONENT" "https://apt.bashclub.org/gpg/bashclub.pub" "https://apt.bashclub.org/$BASHCLUB_COMPONENT" "$(lsb_release -cs)" "main"
    apt update
}

#### Download and install Checkmk ####
# First parameter is the edition (community, pro, ultimate, ultimatemt - legacy names like raw are accepted)
# Second parameter is the version (optional):
#   empty     = latest stable release
#   2.4 / 2.4.0 = latest patch release of branch 2.4.0
#   2.4.0p18    = exactly this release (checksum is only available for the latest patch release of a branch)
inst_checkmk() {
    local cmk_edition cmk_version cmk_branch cmk_os cmk_release cmk_latest cmk_file cmk_sha256
    case "${1}" in
        raw|cre|community)      cmk_edition=community ;;
        enterprise|cee|pro)     cmk_edition=pro ;;
        cloud|cce|ultimate)     cmk_edition=ultimate ;;
        managed|cme|ultimatemt) cmk_edition=ultimatemt ;;
        *) echo "❌ Unknown checkmk edition '${1}'."; exit 1 ;;
    esac
    cmk_version=${2:-}
    # short branch notation: 2.4 -> 2.4.0
    if [[ "${cmk_version}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        cmk_version="${cmk_version}.0"
    fi
    cmk_branch=$(grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' <<< "${cmk_version}" || true)
    cmk_os=$(lsb_release -cs)

    cmk_release=$(curl -fsSL https://download.checkmk.com/stable_downloads.json | jq -r \
        --arg ed "${cmk_edition}" --arg os "${cmk_os}" --arg branch "${cmk_branch}" '
        .checkmk | to_entries
        | map(select(.value.editions[$ed][$os] != null))
        | map(select(if $branch == "" then .value.class == "stable" else .key == $branch end))
        | sort_by(.key | split(".") | map(tonumber)) | last // empty
        | [.value.version, .value.editions[$ed][$os][]] | @tsv') || true
    if [ -z "${cmk_release}" ]; then
        echo "❌ No checkmk release found for edition '${cmk_edition}', version '${cmk_version:-latest}' on ${cmk_os}."
        exit 1
    fi
    read -r cmk_latest cmk_file cmk_sha256 <<< "${cmk_release}"

    if [ -z "${cmk_version}" ] || [ "${cmk_version}" == "${cmk_branch}" ]; then
        cmk_version=${cmk_latest}
    elif [ "${cmk_version}" != "${cmk_latest}" ]; then
        # older patch release: same file name scheme as the latest one of this branch, but no checksum
        cmk_file=${cmk_file/${cmk_latest}/${cmk_version}}
        cmk_sha256=""
    fi

    echo "Downloading checkmk ${cmk_version} (${cmk_file})..."
    if ! curl -fsSL -o "/tmp/${cmk_file}" "https://download.checkmk.com/checkmk/${cmk_version}/${cmk_file}"; then
        echo "❌ Download of checkmk ${cmk_version} failed."
        exit 1
    fi
    if [ -n "${cmk_sha256}" ]; then
        echo "${cmk_sha256}  /tmp/${cmk_file}" | sha256sum -c -
    else
        echo "⚠️ No checksum available for checkmk ${cmk_version}, skipping verification."
    fi
    DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install "/tmp/${cmk_file}"
    rm -f "/tmp/${cmk_file}"
}
