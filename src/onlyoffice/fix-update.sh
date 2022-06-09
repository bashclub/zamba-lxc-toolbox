#!/bin/bash

cat > /usr/local/bin/ods-apt-pre-hook << DFOE
#!/bin/bash
rm /etc/nginx/conf.d/ds-ssl.conf
systemctl stop nginx.service
DFOE
chmod +x /usr/local/bin/ods-apt-pre-hook

cat > /usr/local/bin/ods-apt-post-hook << DFOE
#!/bin/bash
rm /etc/nginx/conf.d/ds.conf
ln -sf /etc/onlyoffice/documentserver/nginx/ds-ssl.conf /etc/nginx/conf.d/ds-ssl.conf
systemctl restart nginx
DFOE
chmod +x /usr/local/bin/ods-apt-post-hook


cat << EOF > /etc/apt/apt.conf.d/80-ods-apt-pre-hook
DPkg::Pre-Invoke {"/usr/local/bin/ods-apt-pre-hook";};
EOF

cat << EOF > /etc/apt/apt.conf.d/80-ods-apt-post-hook
DPkg::Post-Invoke {"/usr/local/bin/ods-apt-post-hook";};
EOF
