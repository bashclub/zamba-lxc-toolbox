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
### LXC_UNPRIVILEGED
Defines if the LXC container will be created in `unpprivileged` or `privileged` mode (default: 1)
```bash
LXC_UNPRIVILEGED="1"
```
Privileged also means the container runs as `root` user. Set this option only, if it's required for the service.
`Zamba AD DC`, `Zamba AD member`, `Zamba standalone` and `mailpiler` are required to run in privileged mode.
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
Defines the domain name /search domain of your LXC container
```bash
LXC_DOMAIN="zmb.rocks"
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
Defines the DNS server ip addres of your LXC container
```bash
LXC_DNS="10.10.80.254"
```
### LXC_BRIDGE
Defines the network bridge to bind the network adapter of your LXC container to
```bash
LXC_BRIDGE="vmbr0"
```
### LXC_VLAN
Defines the vlan id of the LXC container's network interface, if the network adapter should be connected untagged, just leave the value empty.
```bash
LXC_VLAN="80"
```
### LXC_PWD
Defines the `root` password of your LXC container
```bash
LXC_PWD="S3cr3tp@ssw0rd"
```
### LXC_AUTHORIZED_KEY
If you have a SSH key to add to the LXC container's `root` account authorized_keys, you can paste it here.
```bash
LXC_AUTHORIZED_KEY="ssh-rsa xxxxxxxx"
```
### LXC_TOOLSET
Define your (administrative) tools, you always want to have instlled into yout LXC container
```bash
LXC_TOOLSET="net-tools dnsutils mc sysstat lsb-release curl git"
```
### LXC_TIMEZONE
Define the local timezone of your LXC container (default: Euroe/Berlin)
```bash
LXC_TIMEZONE="Europe/Berlin"
```
### LXC_LOCALE
Define system language on LXC container
```bash
LXC_LOCALE="de_DE.utf8"
```
This parameter is not used yet, but will be integrated in future releases.
<br>

## Zamba Server Section
This section configured the Zamba server (AD DC, AD member and standalone)
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
### ZMB_ADMIN_USER
Defines the name of your domain administrator account (AD DC, AD member)
```bash
ZMB_ADMIN_USER="Administrator"
```
### ZMB_ADMIN_PASS
Defines the domain administrator's password (AD DC, AD member)
```bash
ZMB_ADMIN_PASS="1c@nd0@nyth1n9"
```
### ZMB_DOMAIN_ADMINS_GROUP
Defines the domain admins group of your active directory.
```bash
ZMB_DOMAIN_ADMINS_GROUP="domain admins"
```
On Windows Servers this group depends on the configured OS language.
### ZMB_SHARE
Defines the name of your Zamba share
```bash
ZMB_SHARE="share"
```