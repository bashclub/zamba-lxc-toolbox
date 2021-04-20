**** Version 0.1 ****
- `locales` are now configured noninteractive #21
- timezone is now configured with `pct set` command in `install.sh` #22
- changed command sequence in `install.sh` - select container first, then start the installation
- improved / updated documentation
- replaced `just-lxc` container by `debian-priv` and `debian-unpriv` container
- (un)privileged now defined as constant based on created service #6
- improved log messages in `install.sh`