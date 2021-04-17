# Zamba LXC Toolbox

## About
Zamba LXC Toolbox is a collection of scripts to easily install Debian LXC containers with preconfigured services on Proxmox with ZFS.
The main feature is `Zamba`, the fusion of ZFS and Samba in three different flavours (standalone, active directory dc or active directory member), preconfigured to access ZFS snapshots by "Windows Previous Versions" to easily recover encrypted by ransomware files, accidently deleted files or just to revert changes.
The package also provides LXC container installers for `mailpiler`, `matrix-synapse` + `element-web` and more services will follow in future releases.
### Requirements
Proxmox VE Server with at least one configured ZFS Pool.
### Included services:
- `just-lxc` => Debian LXC Container only
- `zmb-ad` => ZMB (Samba) Active Directory Domain Controller, DNS Backends `SAMBA_INTERNAL` and `BIND9_DLZ` are supported
- `zmb-member` => ZMB (Samba) AD member with ZFS volume snapshot support
- `zmb-standalone` => ZMB (Samba) standalone server with ZFS volume snapshot support (previous versions)
- `mailpiler` => mailpiler mail archive [mailpiler.org](https://www.mailpiler.org/)
- `matrix` => Matrix Synapse Homeserver [matrix.org](https://matrix.org/docs/projects/server/synapse) with Element Web [Element on github](https://github.com/vector-im/element-web)
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
