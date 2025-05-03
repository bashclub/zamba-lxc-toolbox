# USE THIS FOLDER TO STORE YOUR OWN ZMB CONFIGS
# Configuration options reference
This is the reference of all config options you can set in `zamba.conf`
<br>

## Linux Container Section
In this section all settings relevant for the LXC container.
<br>

### LXC_TEMPLATE_STORAGE
Defines the Proxmox storage where your LXC container template are stored (default: local)
```bash
LXC_TEMPLATE_STORAGE="local"
```
### LXC_ROOTFS_SIZE
Defines the size in GB of the LXC container's root filesystem (default: 32)
```bash
LXC_ROOTFS_SIZE="32"
```
Depending on your environment, you should consider increasing the size for use of `mailpiler` or `matrix`.
### LXC_ROOTFS_STORAGE
Defines the Proxmox storage where your LXC container's root filesystem will be generated (default: local-zfs)
```bash
LXC_ROOTFS_STORAGE="local-zfs"
```
### LXC_SHAREFS_SIZE
Defines the size in GB your LXC container's filesystem shared by Zamba (AD member & standalone) (default: 100)
```bash
LXC_SHAREFS_SIZE="100"
```
### LXC_SHAREFS_STORAGE
Defines the Proxmox storage where your LXC container's filesystem shared by Zamba will be generated (default: local-zfs)
```bash
LXC_SHAREFS_STORAGE="local-zfs"
```
### LXC_SHAREFS_MOUNTPOINT
Defines the mountpoint of the filesystem shared by Zamba inside your LXC container (default: tank)
```bash
LXC_SHAREFS_MOUNTPOINT="tank"
```
### LXC_MEM
Defines the amount of RAM in MB your LXC container is allowed to use (default: 1024)
If a service needs more minimum memory, LXC_MEM will be overwritten.
```bash
LXC_MEM=1024
```
### LXC_SWAP
Defines the amount of swap space in MB your LXC container is allowed to use (default: 1024)
```bash
LXC_SWAP=1024
```
### LXC_HOSTNAME
Defines the hostname of your LXC container (Default: Name of installed Service)
```bash
LXC_HOSTNAME="zamba"
```
### LXC_DOMAIN
Defines the domain name / search domain of your LXC container
```bash
LXC_DOMAIN="y2hay.com"
```
### LXC_DHCP
Enable DHCP on LAN (eth0) - (Obtain an IP address automatically) [true/false]
```bash
LXC_DHCP=true
```
### LXC_IP
Defines the local IP address and subnet of your LXC container in CIDR format
```bash
LXC_IP="10.10.0.101/24"
```
### LXC_GW
Defines the default gateway IP address of your LXC container
```bash
LXC_GW="10.10.0.1"
```
### LXC_DNS
Defines the DNS server ip address of your LXC container
```bash
LXC_DNS="1.1.1.1"
```
`zmb-ad` used this DNS server for installation, after installation and domain provisioning it will be used as forwarding DNS
For other services this should be your active directory domain controller (if present, else a DNS server of your choice)
### LXC_BRIDGE
Defines the network bridge to bind the network adapter of your LXC container
```bash
LXC_BRIDGE="vmbr0"
```
### LXC_VLAN
Defines the vlan id of the LXC container's network interface, if the network adapter should be connected untagged, just leave the value empty.
```bash
LXC_VLAN="80"
```
### LXC_PWD
Defines the `root` password of your LXC container. Please use 'single quotation marks' to avoid unexpected behaviour.
```bash
LXC_PWD='666666'
```
### LXC_AUTHORIZED_KEY
Defines an authorized_keys file to push into the LXC container.
By default the authorized_keys will be inherited from your proxmox host.
```bash
LXC_AUTHORIZED_KEY="/root/.ssh/authorized_keys"
```
### LXC_TOOLSET
Define your (administrative) tools, you always want to have installed into your LXC container
``` bash
LXC_TOOLSET="vim htop net-tools dnsutils btop sysstat mc"
```
### LXC_TIMEZONE
Define the local timezone of your LXC container (default: Euroe/Berlin)
```bash
LXC_TIMEZONE="UTC"
```
### LXC_LOCALE
Define system language on LXC container (locales)
```bash
LXC_LOCALE="en_US.utf8"
```
This parameter is not used yet, but will be integrated in future releases.

### LXC_VIM_BG_DARK
Set dark background for vim syntax highlighting (0 or 1)
```bash
LXC_VIM_BG_DARK=1
```

<br>

## Zamba Server Section
This section configures the Zamba server (AD DC, AD member and standalone)
<br>

### ZMB_REALM
Defines the REALM for the Active Directory (AD DC, AD member)
```bash
ZMB_REALM="y2hay.y2home"
```
### ZMB_DOMAIN
Defines the domain name in your Active Directory or Workgroup (AD DC, AD member, standalone)
```bash
ZMB_DOMAIN="y2home"
```
### ZMB_ADMIN_USER
Defines the name of your domain administrator account (AD DC, AD member, standalone)
```bash
ZMB_ADMIN_USER="Administrator"
```
### ZMB_ADMIN_PASS
Defines the domain administrator's password (AD DC, AD member).
```bash
ZMB_ADMIN_PASS='Parabola617!'
```
Please use 'single quotation marks' to avoid unexpected behaviour.
`zmb-ad` domain administrator has to meet the password complexity policy, if password is too weak, domain provisioning will fail.
### ZMB_SHARE
Defines the name of your Zamba share
```bash
ZMB_SHARE="lclpool"
```
<br>

## Mailpiler section
This section configures the mailpiler email archive
<br>

### PILER_FQDN
Defines the (public) FQDN of your piler mail archive
```bash
PILER_FQDN="piler.y2hay.com"
```
### PILER_SMARTHOST
Defines the smarthost for piler mail archive
```bash
PILER_SMARTHOST="mail.y2hay.com"
```
<br>

## Matrix section
This section configures the matrix chat server
<br>

### MATRIX_FQDN
Define the FQDN of your Matrix server
```bash
MATRIX_FQDN="enterthe.matrix.y2hay.com"
```

### MATRIX_ELEMENT_FQDN
Define the FQDN for the Element Web virtual host
```bash
MATRIX_ELEMENT_FQDN="element.y2hay.com"
```

### MATRIX_ADMIN_USER
Define the administrative user of matrix service
```bash
MATRIX_ADMIN_USER="admin"
```

### MATRIX_ADMIN_PASSWORD
Define the admin password
```bash
MATRIX_ADMIN_PASSWORD="Parabola617!"
```

## Nextcloud-Section

### NEXTCLOUD_FQDN
Define the FQDN of your Nextcloud server
```bash
NEXTCLOUD_FQDN="cloudy.y2hay.com"
```

### NEXTCLOUD_ADMIN_USR
The initial admin-user which will be configured
```bash
NEXTCLOUD_ADMIN_USR="zmb-admin"
```

### NEXTCLOUD_ADMIN_PWD
Build a strong password for this user. Username and password will shown at the end of the instalation. 
```bash
NEXTCLOUD_ADMIN_PWD="Parabola617!"
```
### NEXTCLOUD_DATA
Defines the data directory, which will be createt under LXC_SHAREFS_MOUNTPOINT
```bash
NEXTCLOUD_DATA="nc_data"
```
### NEXTCLOUD_REVPROX
Defines the trusted reverse proxy, which will enable the detection of source ip to fail2ban
```bash
NEXTCLOUD_REVPROX="10.10.0.254"
```

## Check_MK-Section

### CMK_INSTANCE
Define the name of your checkmk instance
```bash
CMK_INSTANCE=zmbrocks
```

### CMK_ADMIN_PW
Define the password of user 'cmkadmin'
```bash
CMK_ADMIN_PW='666666'
```

### CMK_EDITION
checkmk edition (raw or free)
- raw = completely free
- free = limited version of the enterprise edition (25 hosts, 1 instance)
```bash
CMK_EDITION=raw
```
### Kopano-Section

### KOPANO_FQDN
Define the FQDN of your Nextcloud server
```bash
KOPANO_FQDN="kopano.y2hay.com"
```


### KOPANO_MAILGW=
Define the host, to which mails will send.
```bash
KOPANO_MAILGW="10.10.0.114"
```

### KOPANO_REPKEY
Kopano test- or subscription-key offerd from 
https://kopano.com/downloads-demo/?demo=Kopano+Groupware&headline=Packages&target=Debian+11
```bash
KOPANO_REPKEY="1234567890abcdefghijklmno"
```

### vaultwarden Section

### VW_SMTP_HOST
Hostname of your mailserver
```bash
VW_SMTP_HOST=mail.bashclub.org
```

### VW_SMTP_FROM
email address to send from
```bash
VW_SMTP_FROM="vaultwarden@bashclub.org"
```

### VW_SMTP_FROM_NAME
display name to send from
```bash
VW_SMTP_FROM_NAME="Vaultwarden Password Manager"
```
    
### VW_SMTP_PORT
Smtp-port of your mailserver
```bash
VW_SMTP_PORT=587
```

### VW_SMTP_SSL
Use ssl true/false
```bash
VW_SMTP_SSL=false
```

### VW_SMTP_EXPLICIT_TLS
Use starttls true/false
```bash
VW_SMTP_EXPLICIT_TLS=false
```

### VW_SMTP_USERNAME
Username of your mailbox
```bash
VW_SMTP_USERNAME=vaultwarden@bashclub.org
```

### VW_SMTP_PASSWORD
Password of your mailbox
```bash
VW_SMTP_PASSWORD="Parabola617!"
```

