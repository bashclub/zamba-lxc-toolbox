#!/bin/bash
#
# This script has basic functions like a random password generator
LXC_RANDOMPWD=32

random_password() {
    set +o pipefail
    LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom 2>/dev/null | head -c${LXC_RANDOMPWD}
}

generate_dhparam() {
    openssl dhparam -out /etc/nginx/dhparam.pem 2048
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