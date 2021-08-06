# Zamba LXC Toolbox

# IMPORTANT NOTE:
`devel` branch is still under heavy development, do not use this on a productive machine!

## About
Zamba LXC Toolbox is a collection of scripts to easily install Debian LXC containers with preconfigured services on Proxmox with ZFS.
The main feature is `Zamba`, the fusion of ZFS and Samba in three different flavours (standalone, active directory dc or active directory member), preconfigured to access ZFS snapshots by "Windows Previous Versions" to easily recover encrypted by ransomware files, accidently deleted files or just to revert changes.
The package also provides LXC container installers for `mailpiler`, `matrix-synapse` + `element-web` and more services will follow in future releases.
### Requirements
Proxmox VE Server with at least one configured ZFS Pool.
### Included services:
- `zmb-standalone` => ZMB (Samba) standalone server with ZFS volume snapshot support (previous versions)
- `zmb-ad` => ZMB (Samba) Active Directory Domain Controller, DNS Backends `SAMBA_INTERNAL` and `BIND9_DLZ` are supported
- `zmb-member` => ZMB (Samba) AD member with ZFS volume snapshot support (previous versions)
- `mailpiler` => mailpiler mail archive [mailpiler.org](https://www.mailpiler.org/)
- `matrix` => Matrix Synapse Homeserver [matrix.org](https://matrix.org/docs/projects/server/synapse) with Element Web [Element on github](https://github.com/vector-im/element-web)
- `nextcloud` => Nextcloud Server [nextcloud.com](https://nextcloud.com/) with fail2ban und redis configuration
- `checkmk` => CheckMK 2.0 Raw Edition [checkmk.com](https://checkmk.com) with our Fork of Matrix Notification Plugin (https://github.com/bashclub/check_mk_matrix_notifications)
- `open3a` => Open3A accounting software for small and medium business [open3a.de](https://www.open3a.de/)
- `debian-unpriv` => Debian unprivileged container with basic toolset
- `debian-priv` => Debian privileged container with basic toolset
## Usage
Just ssh into your Proxmox machine and clone this git repository. Make sure you have installed `git`.
```bash
apt update
apt -y install git
```
### Clone this Repository
```bash
git clone https://github.com/bashclub/zamba-lxc-toolbox
cd zamba-lxc-toolbox
```
### Configuration
To fit your requirements, please edit the file `zamba.conf` with your favourite text editor (e.g. `vim` or `nano`).
The required adjustments are in the LXC container section and in the section for the service you want to launch.
For further information about the config variables, have a look at [zamba.conf.md](zamba.conf.md)
### Installation
After configuring, you are able to launch the script interactively:
```bash
bash install.sh
```
After container creation, you will be prompted to select the service to install and depending on the service there may be some more questions during installation.

Once the script has finished, the container is installed and running and you can continue with the service specific configuration.
