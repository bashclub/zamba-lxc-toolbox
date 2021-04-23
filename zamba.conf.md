# `zamba.conf` options reference
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
```bash
LXC_MEM="1024"
```
### LXC_SWAP
Defines the amount of swap space in MB your LXC container is allowed to use (default: 1024)
```bash
LXC_SWAP="1024"
```
### LXC_HOSTNAME
Defines the hostname of your LXC container
```bash
LXC_SWAP="zamba"
```
### LXC_DOMAIN
Defines the domain name / search domain of your LXC container
```bash
LXC_DOMAIN="zmb.rocks"
```
### LXC_DHCP
Enable DHCP on LAN (eth0) - (Obtain an IP address automatically) [true/false]
```bash
LXC_DHCP=false
```
### LXC_IP
Defines the local IP address and subnet of your LXC container in CIDR format
```bash
LXC_IP="10.10.80.20/24"
```
### LXC_GW
Defines the default gateway IP address of your LXC container
```bash
LXC_GW="10.10.80.254"
```
### LXC_DNS
Defines the DNS server ip address of your LXC container
```bash
LXC_DNS="10.10.80.254"
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
LXC_PWD="S3cr3tp@ssw0rd"
```
### LXC_AUTHORIZED_KEY
Defines an authorized_keys file to push into the LXC container.
By default the authorized_keys will be inherited from your proxmox host.
```bash
LXC_AUTHORIZED_KEY="/root/.ssh/authorized_keys"
```
### LXC_TOOLSET
Define your (administrative) tools, you always want to have installed into your LXC container
```bash
LXC_TOOLSET="vim htop net-tools dnsutils mc sysstat lsb-release curl git gnupg2 apt-transport-https"
```
### LXC_TIMEZONE
Define the local timezone of your LXC container (default: Euroe/Berlin)
```bash
LXC_TIMEZONE="Europe/Berlin"
```
### LXC_LOCALE
Define system language on LXC container (locales)
```bash
LXC_LOCALE="de_DE.utf8"
```
This parameter is not used yet, but will be integrated in future releases.
<br>

## Zamba Server Section
This section configures the Zamba server (AD DC, AD member and standalone)
<br>

### ZMB_REALM
Defines the REALM for the Active Directory (AD DC, AD member)
```bash
ZMB_REALM="ZMB.ROCKS"
```
### ZMB_DOMAIN
Defines the domain name in your Active Directory or Workgroup (AD DC, AD member, standalone)
```bash
ZMB_DOMAIN="ZMB"
```
### ZMB_DNS_BACKEND
Defines the desired DNS server backend, supported are `SAMBA_INTERNAL` and `BIND9_DLZ` for more advanced usage
```bash
ZMB_DNS_BACKEND="SAMBA_INTERNAL"
```
### ZMB_ADMIN_USER
Defines the name of your domain administrator account (AD DC, AD member, standalone)
```bash
ZMB_ADMIN_USER="Administrator"
```
### ZMB_ADMIN_PASS
Defines the domain administrator's password (AD DC, AD member).
```bash
ZMB_ADMIN_PASS='1c@nd0@nyth1n9'
```
Please use 'single quotation marks' to avoid unexpected behaviour.
`zmb-ad` domain administrator has to meet the password complexity policy, if password is too weak, domain provisioning will fail.
### ZMB_SHARE
Defines the name of your Zamba share
```bash
ZMB_SHARE="share"
```
<br>

## Mailpiler section
This section configures the mailpiler email archive
<br>

### PILER_FQDN
Defines the (public) FQDN of your piler mail archive
```bash
PILER_FQDN="piler.zmb.rocks"
```
### PILER_SMARTHOST
Defines the smarthost for piler mail archive
```bash
PILER_SMARTHOST="10.10.80.20"
```
### PILER_VERSION
Defines the version number of piler mail archive to install
```bash
PILER_VERSION="1.3.10"
```
### PILER_SPHINX_VERSION
Defines the version of sphinx to install
```bash
PILER_SPHINX_VERSION="3.3.1"
```
### PILER_PHP_VERSION
Defines the php version to install
```bash
PILER_PHP_VERSION="7.4"
```
<br>

## Matrix section
This section configures the matrix chat server
<br>

### MATRIX_FQDN
Define the FQDN of your Matrix server
```bash
MATRIX_FQDN="matrix.zmb.rocks"
```

### MATRIX_ELEMENT_FQDN
Define the FQDN for the Element Web virtual host
```bash
MATRIX_ELEMENT_FQDN="element.zmb.rocks"
```
### MATRIX_ELEMENT_VERSION
Define the version of Element Web
```bash
MATRIX_ELEMENT_VERSION="v1.7.24"
```
### MATRIX_JITSI_FQDN
Define the FQDN for the Jitsi Meet virtual host
```bash
MATRIX_JITSI_FQDN="meet.zmb.rocks"
```