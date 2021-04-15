# Zamba LXC Toolbox

## About
Zamba LXC Toolbox is a collection of scripts to easily install LXC containers with preconfigured services.
### Requirements
Proxmox VE Server with at least one configured ZFS Pool.
### Included services:
- `just-lxc` => Debian LXC Container only
- `zmb-ad` => ZMB (Samba) Active Directory Domain Controller
- `zmb-member` => ZMB (Samba) AD member with ZFS volume snapshot support
- `zmb-standalone` => ZMB (Samba) standalone server with ZFS volume snapshot support (previous versions)
- `mailpiler` => mailpiler mail archive [mailpiler.org](https://www.mailpiler.org/)
- `matrix` => Matrix Synapse Homeserver [matrix.org](https://matrix.org/docs/projects/server/synapse) with Element Web [Element on github](https://github.com/vector-im/element-web)
## Usage
Just ssh into your Proxmox machine and clone this git repository. Make sure you have installed `git`.
### Clone this Repository
```bash
apt update
apt -y install git
git clone https://github.com/cpzengel/zamba-lxc-toolbox
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