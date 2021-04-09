# Zamba

## About
Zamba is a Toolbox for Proxmox (ZFS) admins, which fires a container with preconfigured services.
### Inclueded services:
- ZMB (Samba) AD member with ZFS volume snapshot support
- mailpiler mail archive [mailpiler.org](https://www.mailpiler.org/)
- Matrix Synapse Homeserver [matrix.org](https://matrix.org/docs/projects/server/synapse) with Element Web [Element on github](https://github.com/vector-im/element-web)
### Planned features / ideas for future releases
- ZMB (Samba) standalone with ZFS volume snapshot support
- ZMB (Samba) Active Directory Domain Controller
- Nextcloud Server [nextcloud.com](https://nextcloud.com/)
- optional Addon: Cockpit (including ZFS Manager) [cockpit-project.org](https://cockpit-project.org/)
- check_mk RAW Edition [checkmk.com](https://checkmk.com)
- Zabbix [zabbix.com](https://zabbix.com)
- Abgleich control machine (ZFS Snapshot and Backup engine) [Abgleich on github](https://github.com/pleiszenburg/abgleich)
## Usage
Just ssh into your Proxmox machine and clone this git repository. Make sure you have installed `git`.
### Clone this Repository
```bash
apt update
apt -y install git
git clone https://git.spille-edv.de/thorsten.spille/zamba
cd zamba
```
### Configuration
To fit your requirements, please edit the file `zamba.conf` with your favourite test editor (e.g. `vim` or `nano`).
The required adjustments are in the LXC container section and in the section for the service you want to launch.
For further information about the config variables, have a look at [zamba.conf.md](zamba.conf.md)
### Installation
After configuring, you are able to launch the script interactively:
```bash
bash install.sh
```
After container creation, you will be prompted to select the service to install and depending on the service there may be some more questions during installation.

Once the script has finished, the container is installed and running and you can continue with the service specific configuration.