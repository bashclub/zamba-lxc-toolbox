**** Zamba LXC Toolbox devel branch ****
- added dhcp support
- fixed hardcoded samba sharename in `zmb-standalone` script
- added support for container id's larger than 999
- added optional parameters for ct id, service and config file
- mailpiler version now configured to download `latest` version
- added `conf` folder to store user configs
- splitted basic container setup and service installation into multiple scripts
- created `constants` to minimize config variables
- added `wsdd` to `zmb-standalone` service

**** Zamba LXC Toolbox v0.1 ****
- `locales` are now configured noninteractive #21
- timezone is now configured with `pct set` command in `install.sh` #22
- changed command sequence in `install.sh` - select container first, then start the installation
- improved / updated documentation
- replaced `just-lxc` container by `debian-priv` and `debian-unpriv` container
- (un)privileged now defined as constant based on created service #6
- improved log messages in `install.sh`
- `mailpiler`: website is now also `default_host`, removed nginx default site, dns entry is still required
- changed `mailpiler` version to 1.3.11
- changed `element-web` version to 1.7.25
- `LXC_AUTHORIZED_KEY` variable now defines an `authorized_keys` file, by default the configuration of you proxmox host will be inherited (`~/.ssh/authorized_keys`)
