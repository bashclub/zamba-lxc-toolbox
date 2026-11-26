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
    # Detect an ASCII-armored key by its content: `file` is not always installed
    # and does not call every armored key "ASCII" (#141)
    if grep -q -- "-----BEGIN PGP PUBLIC KEY BLOCK-----" "${tmp_key_file}"; then
        echo "🔍 Format erkannt: ASCII. Konvertiere den Schlüssel..."
        # Wenn es ASCII ist, konvertiere es mit --dearmor
        if gpg --batch --yes --dearmor -o "${apt_key_path}" "${tmp_key_file}"; then
            rm -f "${tmp_key_file}"
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
        if mv "${tmp_key_file}" "${apt_key_path}"; then
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

#### Online and offline backup of a samba AD DC ####
# Writes /usr/local/bin/smb-backup with a daily cron job. The online backup
# authenticates with the administrator keytab /root/admin.keytab (created by
# zmb-ad_auto-map-root.sh), so no password is stored on disk (#133).
inst_smb_backup() {
    cat << EOF > /etc/default/smb-backup
# Settings of /usr/local/bin/smb-backup
BACKUP_DIR=/${LXC_SHAREFS_MOUNTPOINT}
SERVER=${LXC_HOSTNAME}.${LXC_DOMAIN}
KEYTAB=/root/admin.keytab
EOF

    cat << 'EOF' > /usr/local/bin/smb-backup
#!/bin/bash
# Online and offline backup of this samba AD DC.
# usage: smb-backup [KEEP]   keeps the newest KEEP backups of each kind (default: 7)
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
set -u
. /etc/default/smb-backup

keep=${1:-7}
if ! [[ "$keep" =~ ^[1-9][0-9]*$ ]]; then
  echo "usage: $0 [KEEP]   KEEP: number of backups to keep, at least 1" >&2
  exit 2
fi

rc=0
mkdir -p "$BACKUP_DIR/online" "$BACKUP_DIR/offline"

prune () {
  # the file names end with a timestamp, so sorting by name sorts by age
  find "$BACKUP_DIR/$1" -maxdepth 1 -type f -name '*.tar.bz2' | sort | head -n "-$keep" | xargs -r -d '\n' rm -f --
}

echo "$(date) Starting samba-ad-dc online backup"
ccache=$(mktemp)
principal=$(klist -k "$KEYTAB" 2>/dev/null | awk 'NR > 3 { print $2; exit }')
if [ -n "$principal" ] \
   && KRB5CCNAME="FILE:$ccache" kinit -k -t "$KEYTAB" "$principal" \
   && KRB5CCNAME="FILE:$ccache" samba-tool domain backup online --targetdir="$BACKUP_DIR/online" --server="$SERVER" --use-kerberos=required ; then
  echo "$(date) Finished samba-ad-dc online backup. Cleaning up old online backups..."
  prune online
else
  echo "$(date) samba-ad-dc online backup failed"
  rc=$((rc + 1))
fi
KRB5CCNAME="FILE:$ccache" kdestroy -q 2> /dev/null
rm -f "$ccache"

echo "$(date) Starting samba-ad-dc offline backup"
if samba-tool domain backup offline --targetdir="$BACKUP_DIR/offline" ; then
  echo "$(date) Finished samba-ad-dc offline backup. Cleaning up old offline backups..."
  prune offline
else
  echo "$(date) samba-ad-dc offline backup failed"
  rc=$((rc + 1))
fi

exit $rc
EOF
    chmod 0750 /usr/local/bin/smb-backup

    cat << EOF > /etc/cron.d/smb-backup
0 23 * * * root /usr/local/bin/smb-backup 7 >> /var/log/smb-backup.log 2>&1
EOF

    cat << EOF > /etc/logrotate.d/smb-backup
/var/log/smb-backup.log {
        weekly
        rotate 12
        compress
        delaycompress
        missingok
        notifempty
        create 644 root root
}
EOF
}

#### Find a Checkmk release ####
# Prints "VERSION FILE SHA256" of a checkmk release for this Debian release.
# First parameter is the edition (community, pro, ultimate, ultimatemt - legacy names like raw are accepted)
# Second parameter is the version (optional):
#   empty     = latest stable release
#   2.4 / 2.4.0 = latest patch release of branch 2.4.0
#   2.4.0p18    = exactly this release (checksum is only available for the latest patch release of a branch)
# SHA256 is "-" when checkmk publishes no checksum for the release.
cmk_find_release() {
    local cmk_edition cmk_version cmk_branch cmk_os cmk_release cmk_latest cmk_file cmk_sha256
    case "${1}" in
        raw|cre|community)      cmk_edition=community ;;
        enterprise|cee|pro)     cmk_edition=pro ;;
        cloud|cce|ultimate)     cmk_edition=ultimate ;;
        managed|cme|ultimatemt) cmk_edition=ultimatemt ;;
        *) echo "❌ Unknown checkmk edition '${1}'." >&2; return 1 ;;
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
        echo "❌ No checkmk release found for edition '${cmk_edition}', version '${cmk_version:-latest}' on ${cmk_os}." >&2
        return 1
    fi
    read -r cmk_latest cmk_file cmk_sha256 <<< "${cmk_release}"

    if [ -z "${cmk_version}" ] || [ "${cmk_version}" == "${cmk_branch}" ]; then
        cmk_version=${cmk_latest}
    elif [ "${cmk_version}" != "${cmk_latest}" ]; then
        # older patch release: same file name scheme as the latest one of this branch, but no checksum
        cmk_file=${cmk_file/${cmk_latest}/${cmk_version}}
        cmk_sha256=""
    fi
    echo "${cmk_version} ${cmk_file} ${cmk_sha256:--}"
}

#### Download and install Checkmk ####
# Parameters: see cmk_find_release
inst_checkmk() {
    local cmk_release cmk_version cmk_file cmk_sha256
    cmk_release=$(cmk_find_release "${1}" "${2:-}") || exit 1
    read -r cmk_version cmk_file cmk_sha256 <<< "${cmk_release}"

    echo "Downloading checkmk ${cmk_version} (${cmk_file})..."
    if ! curl -fsSL -o "/tmp/${cmk_file}" "https://download.checkmk.com/checkmk/${cmk_version}/${cmk_file}"; then
        echo "❌ Download of checkmk ${cmk_version} failed."
        exit 1
    fi
    if [ "${cmk_sha256}" != "-" ]; then
        if ! echo "${cmk_sha256}  /tmp/${cmk_file}" | sha256sum -c -; then
            echo "❌ Checksum of checkmk ${cmk_version} does not match."
            rm -f "/tmp/${cmk_file}"
            exit 1
        fi
    else
        echo "⚠️ No checksum available for checkmk ${cmk_version}, skipping verification."
    fi
    DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt -y -qq install "/tmp/${cmk_file}"
    rm -f "/tmp/${cmk_file}"
}

#### Automatic Checkmk patch updates ####
# Installs /usr/local/sbin/cmk-update with a daily systemd timer. The timer is
# only enabled with CMK_AUTO_UPDATE=1; without it, cmk-update can still be run
# by hand or the timer enabled later: systemctl enable --now cmk-update.timer
# Only patch releases of a site's branch are installed (e.g. 2.4.0p18 -> p19):
# major releases have to be upgraded one after another and checked by hand.
inst_cmk_autoupdate() {
    cat << EOF > /etc/default/cmk-update
# Settings of /usr/local/sbin/cmk-update
CMK_EDITION=${CMK_EDITION}
# Each site is backed up here before its update (only the latest backup is kept)
BACKUP_DIR=/opt/cmk-update-backup
EOF

    {
        cat << 'EOF'
#!/bin/bash
# Installs the newest patch release of each site's checkmk branch and updates
# the site. Every site is backed up first and restored from the backup if it
# does not come up again; a release that was rolled back is not retried.
# usage: cmk-update [--force]    --force retries releases that were rolled back
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

. /etc/default/cmk-update
STATE=/var/lib/cmk-update

log() { echo "cmk-update: $*"; logger -t cmk-update -- "$*" 2> /dev/null || true; }

EOF
        declare -f cmk_find_release inst_checkmk
        cat << 'EOF'

# A site is healthy when all its services run and its own apache serves the
# login page (asked directly, the system apache may redirect other sites).
site_healthy() {
    local site=$1 url port _
    port=$(omd config "$site" show APACHE_TCP_PORT 2> /dev/null || true)
    url="http://127.0.0.1:${port}/${site}/check_mk/login.py"
    if [ -n "${CMK_UPDATE_HEALTH_URL:-}" ]; then
        # shellcheck disable=SC2059
        url=$(printf "$CMK_UPDATE_HEALTH_URL" "$site")
    fi
    for _ in $(seq 1 60); do
        if omd status --bare "$site" 2> /dev/null | grep -qx 'OVERALL 0' \
            && [ "$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$url")" = 200 ]; then
            return 0
        fi
        sleep 2
    done
    return 1
}

force=0
[ "${1:-}" = "--force" ] && force=1

mkdir -p "$STATE" "$BACKUP_DIR"
chmod 700 "$STATE" "$BACKUP_DIR"
exec 9> "$STATE/lock"
flock -n 9 || { log "already running"; exit 0; }
touch "$STATE/failed"

rc=0
newest=$(cmk_find_release "$CMK_EDITION" "" | cut -d' ' -f1) || newest=""

for site in $(omd sites --bare); do
    current=$(omd version --bare "$site")      # e.g. 2.4.0p18.cre
    branch=$(grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' <<< "$current")
    cur_ver=$(grep -oE '^[0-9]+\.[0-9]+\.[0-9]+(p[0-9]+)?' <<< "$current")

    if ! release=$(cmk_find_release "$CMK_EDITION" "$branch"); then
        log "ERROR: no checkmk release found for site $site (branch $branch)"
        rc=1
        continue
    fi
    latest=${release%% *}

    if [ "$latest" = "$cur_ver" ]; then
        if [ -n "$newest" ] && [[ "$newest" != "$branch"* ]]; then
            log "site $site is up to date on $cur_ver; checkmk $newest is available, a major upgrade has to be done by hand"
        fi
        continue
    fi
    if [ "$force" -eq 0 ] && grep -qx "$site $latest" "$STATE/failed"; then
        log "skipping $latest for site $site, it was rolled back before (use --force to retry)"
        continue
    fi

    if ! omd versions --bare | grep -q "^${latest}\."; then
        if ! ( inst_checkmk "$CMK_EDITION" "$latest" ); then
            log "ERROR: installing checkmk $latest failed"
            rc=1
            continue
        fi
    fi
    target=$(omd versions --bare | grep -m1 "^${latest}\.")

    # the backup needs about the size of the site
    need=$(du -sxk "/omd/sites/$site" | cut -f1)
    avail=$(df -Pk "$BACKUP_DIR" | awk 'NR == 2 { print $4 }')
    if [ "$avail" -lt $(( need * 12 / 10 )) ]; then
        log "ERROR: not enough space in $BACKUP_DIR to back up site $site before the update"
        rc=1
        continue
    fi

    backup="$BACKUP_DIR/$site-$cur_ver.tar.gz"
    log "updating site $site from $cur_ver to $latest (backup: $backup)"
    omd stop "$site" || true
    rm -f "$BACKUP_DIR/$site-"*.tar.gz
    if ! omd backup "$site" "$backup"; then
        log "ERROR: backup of site $site failed, not updating it"
        omd start "$site" || true
        rc=1
        continue
    fi

    if omd -f -V "$target" update --conflict=install "$site" && omd start "$site" && site_healthy "$site"; then
        log "site $site updated from $cur_ver to $latest"
        sed -i "/^$site /d" "$STATE/failed"
    else
        log "ERROR: site $site does not work with $latest, restoring $cur_ver from $backup"
        omd stop "$site" || true
        omd -f restore --reuse --kill "$site" "$backup" || log "ERROR: restore of site $site failed, see $backup"
        omd start "$site" || true
        grep -qx "$site $latest" "$STATE/failed" || echo "$site $latest" >> "$STATE/failed"
        rc=1
    fi
done

omd cleanup > /dev/null 2>&1 || true
exit $rc
EOF
    } > /usr/local/sbin/cmk-update
    chmod 0750 /usr/local/sbin/cmk-update

    cat << EOF > /etc/systemd/system/cmk-update.service
[Unit]
Description=Install checkmk patch releases and update the sites
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/cmk-update
EOF

    cat << EOF > /etc/systemd/system/cmk-update.timer
[Unit]
Description=Daily checkmk patch update

[Timer]
OnCalendar=*-*-* 04:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    if [ "${CMK_AUTO_UPDATE:-1}" -eq 1 ]; then
        systemctl enable --now cmk-update.timer
    fi
}
