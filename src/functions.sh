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

    wget -q -O - ${apt_key_url} | gpg --dearmor -o ${apt_key_path}
    echo "deb [signed-by=${apt_key_path}] ${apt_repo_url}" > /etc/apt/sources.list.d/${apt_name}.list
}
#### Set repo and install Nginx ####
inst_nginx() {
    apt_repo "nginx" "https://nginx.org/keys/nginx_signing.key" "http://nginx.org/packages/mainline/debian $(lsb_release -cs) nginx"
    apt update && DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends nginx
}
#### Set repo and install PHP ####
inst_php() {
    curl -sSLo /usr/share/keyrings/sury_php.gpg https://packages.sury.org/php/apt.gpg
    echo "deb [signed-by=/usr/share/keyrings/sury_php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/sury_php.list
    apt update && DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends php-common php$NEXTCLOUD_PHP_VERSION-{fpm,gd,curl,pgsql,xml,zip,intl,mbstring,bz2,ldap,apcu,bcmath,gmp,imagick,igbinary,mysql,redis,smbclient,sqlite3,cli,common,opcache,readline}
}
#### Set repo and install Postgresql ####
inst_postgresql() {
    apt_repo "postgresql" "https://www.postgresql.org/media/keys/ACCC4CF8.asc" "http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main"
    apt update && DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends postgresql-$POSTGRES_VERSION
}
#### Set repo and install Crowdsec ####
inst_crowdsec() {
    apt_repo "crowdsec" "https://packagecloud.io/crowdsec/crowdsec/gpgkey" " https://packagecloud.io/crowdsec/crowdsec/any any main"
    apt update && DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends crowdsec
    DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y -qq --no-install-recommends crowdsec-firewall-bouncer-nftables
}
