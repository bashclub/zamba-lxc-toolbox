# Zamba LXC Toolbox

## About
Zamba LXC Toolbox is a collection of scripts to easily install Debian LXC containers with preconfigured services on Proxmox with ZFS.
The main feature is `Zamba`, the fusion of ZFS and Samba in three different flavours (standalone, active directory dc or active directory member), preconfigured to access ZFS snapshots by "Windows Previous Versions" to easily recover encrypted by ransomware files, accidently deleted files or just to revert changes.
The package also provides LXC container installers for `mailpiler`, `matrix-synapse` + `element-web` and more services will follow in future releases.
### Requirements
Proxmox VE Server (>=6.30) with at least one configured ZFS Pool.
### Included services:
- `checkmk` => Check_MK 2.0 Monitoring Server
- `debian-priv` => Debian privileged container with basic toolset
- `debian-unpriv` => Debian unprivileged container with basic toolset
- `kopano-core` => Kopano Core Grouoware [kopano.io](https://kopano.io/)
- `mailpiler` => mailpiler mail archive [mailpiler.org](https://www.mailpiler.org/)
- `matrix` => Matrix Synapse Homeserver [matrix.org](https://matrix.org/docs/projects/server/synapse) with Element Web [Element on github](https://github.com/vector-im/element-web)
- `nextcloud` => Nextcloud Server [nextcloud.com](https://nextcloud.com/) with fail2ban und redis configuration
- `onlyoffice` => OnlyOffice [onlyoffice.com](https://onlyoffice.com)
- `open3a` => Open3a web based accounting software [open3a.de](https://open3a.de)
- `proxmox-pbs` => Proxmox Backup Server [proxmox.com](https://proxmox.com/en/proxmox-backup-server)
- `urbackup` => UrBackup Server [urbackup.org](https://urbackup.org)
- `zammad` => Zammad Helpdesk and Ticketing Software [zammad.org](https://zammad.org/)
- `zmb-ad` => ZMB (Samba) Active Directory Domain Controller, DNS Backends `SAMBA_INTERNAL` and `BIND9_DLZ` are supported
- `zmb-member` => ZMB (Samba) AD member with ZFS volume snapshot support (previous versions)
- `zmb-standalone` => ZMB (Samba) standalone server with ZFS volume snapshot support (previous versions)
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
Copy `zamba.conf.example` located in `conf` directory to a new file (default: `zamba.conf`) and adjust your desired settings.
For further information about configuration variables, have a look at [conf/README.md](conf/README.md)
```bash
cp conf/zamba.conf.example conf/zamba.conf
```
### Installation
After configuring, you are able to launch the script interactively (only works with `conf/zamba.conf`):
```bash
bash install.sh
```
### Advanced Usage
You can set optional parameters (config file, service, container id):
#### Example:
```bash
bash install.sh -i 280 -c conf/my-zmb-service.conf -s zmb-member
```
You can also view possible parameters with `install.sh -h`

After container creation, you will be prompted to select the service to install and depending on the service there may be some more questions during installation.

Once the script has finished, the container is installed and running and you can continue with the service specific configuration.
