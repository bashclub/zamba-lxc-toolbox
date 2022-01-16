#!/usr/bin/python3
import os
from src import config_base, menu

# Check installation of zfs-auto-snapshot, if not installed, just notify user
config_base.check_zfs_autosnapshot()
    
cfg = {}
# set template storage
t_storages = config_base.get_pve_storages(content=config_base.PveStorageContent.vztmpl)
if len(t_storages.keys()) > 1:
    t_stors={}
    for st in t_storages.keys():
        t_stors[st] = f"driver: {t_storages[st]['driver']}\tfree space: {int(t_storages[st]['available'])/1024/1024:.2f} GB"
    cfg['LXC_TEMPLATE_STORAGE'] = menu.radiolist("Select container template storage", "Please choose the storage, where your container templates are stored.", t_stors)
elif len(t_storages.keys()) == 1:
    cfg['LXC_TEMPLATE_STORAGE'] = next(iter(t_storages))
else:
    print("Could not find any storage enabled for container templates. Please ensure your storages are configured properly.")
    os._exit(1)

# get zmb service
cfg['ZMB_SERVICE'] = menu.radiolist("Select service","Please choose the service to install:", config_base.get_zmb_services())

# get static ct features
ct_features = config_base.get_ct_features(cfg["ZMB_SERVICE"])
cfg['LXC_UNPRIVILEGED'] = ct_features['unprivileged']
# get ct id
cfg['LXC_NBR'] = menu.question("Container ID", f"Please select an ID for the {cfg['ZMB_SERVICE']} container.", menu.qType.Integer, config_base.get_ct_id(), config_base.validate_ct_id)

# configure rootfs
r_storages = config_base.get_pve_storages(driver=config_base.PveStorageType.zfspool,content=config_base.PveStorageContent.rootdir)
if len(r_storages.keys()) > 1:
    r_stors = {}
    for st in r_storages.keys():
        r_stors[st] = f"driver: {r_storages[st]['driver']}\tfree space: {int(r_storages[st]['available'])/1024/1024:.2f} GB"
    cfg['LXC_ROOTFS_STORAGE'] = menu.radiolist("Select rootfs storage", "Please choose the storage for your container's rootfs",r_stors)
elif len(r_storages.keys()) == 1:
    cfg['LXC_ROOTFS_STORAGE'] = next(iter(r_storages))
else:
    print("Could not find any storage enabled for container filesystems. Please ensure your storages are configured properly.")
    os._exit(1)

cfg['LXC_ROOTFS_SIZE'] = menu.question("Set rootfs size","Please type in the desired rootfs size (GB)", menu.qType.Integer,32)

# create additional mountpoints
if 'size' in ct_features['sharefs'].keys():
    f_storages = config_base.get_pve_storages(driver=config_base.PveStorageType.zfspool,content=config_base.PveStorageContent.rootdir)
    if len(f_storages.keys()) > 1:
        f_stors = {}
        for st in f_storages.keys():
            f_stors[st] = f"driver: {f_storages[st]['driver']}\tfree space: {int(f_storages[st]['available'])/1024/1024:.2f} GB"
        cfg['LXC_SHAREFS_STORAGE'] = menu.radiolist("Select sharefs storage", "Please choose the storage of your shared filesystem", f_stors)
    elif len(r_storages.keys()) == 1:
        cfg['LXC_SHAREFS_STORAGE'] = next(iter(f_storages))
    else:
        print("Could not find any storage enabled for container filesystems. Please ensure your storages are configured properly.")
        os._exit(1)
    cfg['LXC_SHAREFS_SIZE'] = menu.question("Select sharefs size","Please type in the desired size (GB) of your shared filesystem", menu.qType.Integer,ct_features['sharefs']['size'])
    cfg['LXC_SHAREFS_MOUNTPOINT'] = menu.question("Select sharefs mountpoint","Please type in the folder where to mount your shared filesystem inside the container.", menu.qType.String,ct_features['sharefs']['mountpoint'])

# configure ram and swap
cfg['LXC_MEM'] = menu.question("Set container RAM", "Please type in the desired amount of RAM for the container (MB)",menu.qType.Integer,ct_features["mem"])
cfg['LXC_SWAP'] = menu.question("Set container Swap", "Please type in the desired amount of Swap for the container (MB)",menu.qType.Integer,ct_features["swap"])
cfg['LXC_HOSTNAME'] = menu.question("Set container Hostname", "Please type in the desired hostname of the container",menu.qType.String,ct_features['hostname'])
cfg['LXC_DOMAIN'] = menu.question("Set container search domain", "Please type in the search domain of your network.", menu.qType.String,ct_features['domain'])
cfg['LXC_TIMEZONE'] = 'host' # TODO
cfg['LXC_LOCALE'] = "de_DE.utf8" # TODO

# get pve bridge
bridges = config_base.get_pve_bridges()
if len(bridges) > 1:
    cfg['LXC_BRIDGE'] = menu.radiolist("Select PVE Network Bridge", f"Please select the network bridge to connect the {cfg['ZMB_SERVICE']} container",bridges)
elif len(bridges) == 1:
    cfg['LXC_BRIDGE'] = bridges[0]
else:
    print("Could not find any bridge device to connect container. Please ensure your networksettings are configured properly.")
    os._exit(1)

cfg['LXC_VLAN'] = menu.question("Set vlan tag", "You you want to tag your container's network to a vlan? (0 = untagged, 1 - 4094 = tagged vlan id)",menu.qType.Integer,0, config_base.validate_vlan)

# configure network interface
if  cfg['ZMB_SERVICE'] != 'zmb-ad':
    enable_dhcp = menu.question("Set network mode", "Do you want to configure the network interface in dhcp mode?",menu.qType.Boolean,default=True)
else:
    enable_dhcp = False
if enable_dhcp == True:
    cfg["LXC_NET_MODE"] = 'dhcp'
else:
    cfg["LXC_NET_MODE"] = 'static'
    cfg["LXC_IP"] = menu.question("Set interface IP Addess", "Pleace type in the containers IP address (CIDR Format).",menu.qType.String,default='10.10.10.10/8')
    cfg["LXC_GW"] = menu.question("Set interface default gateway", "Pleace type in the containers default gateway.",menu.qType.String,default='10.10.10.1')
cfg['LXC_DNS']  = menu.question("Set containers dns server", "Pleace type in the containers dns server. ZMB AD will use this as dns forwarder",menu.qType.String,default='10.10.10.1')

cfg['LXC_PWD'] = menu.question("Set root password", "Please type in the containers root password", menu.qType.String,default='')
cfg['LXC_AUTHORIZED_KEY'] = menu.question ("Set authorized_keys file to import", "Please select authorized_keys file to import.", menu.qType.String, default='~/.ssh/authorized_keys')

os.system('clear')
print (f"#### Zamba LXC Toolbox ####\n")
print (f"GLOBAL CONFIGURATION:")
print (f"\tct template storage:\t{cfg['LXC_TEMPLATE_STORAGE']}")
print (f"\nCONTAINER CONFIGURATION:")
print (f"\tzmb service:\t\t{cfg['ZMB_SERVICE']}")
print (f"\tcontainer id:\t\t{cfg['LXC_NBR']}")
print (f"\tunprivileged:\t\t{cfg['LXC_UNPRIVILEGED']}")
for feature in ct_features['features'].keys():
    if feature == 'nesting':
        cfg['LXC_NESTING'] = ct_features['features'][feature]
        print (f"\t{feature}:\t\t{cfg['LXC_NESTING']}")
print (f"\tcontainer memory:\t{cfg['LXC_MEM']} MB")
print (f"\tcontainer swap:\t\t{cfg['LXC_SWAP']} MB")
print (f"\tcontainer hostname:\t{cfg['LXC_HOSTNAME']}")
print (f"\tct search domain:\t{cfg['LXC_DOMAIN']}")
print (f"\tcontainer timezone\t{cfg['LXC_TIMEZONE']}")
print (f"\tcontainer language\t{cfg['LXC_LOCALE']}")
print (f"\nSTORAGE CONFIGURATION:")
print (f"\trootfs storage:\t\t{cfg['LXC_ROOTFS_STORAGE']}")
print (f"\trootfs size:\t\t{cfg['LXC_ROOTFS_SIZE']} GB")
if 'size' in ct_features['sharefs'].keys():
    print (f"\tsharefs storage:\t{cfg['LXC_SHAREFS_STORAGE']}")
    print (f"\tsharefs size:\t\t{cfg['LXC_SHAREFS_SIZE']} GB")
    print (f"\tsharefs mountpoint:\t{cfg['LXC_SHAREFS_MOUNTPOINT']}")
print (f"\nNETWORK CONFIGURATION:")
print (f"\tpve bridge:\t\t{cfg['LXC_BRIDGE']}")
if cfg['LXC_VLAN'] > 0:
    print (f"\tcontainer vlan:\t\t{cfg['LXC_VLAN']}")
else:
    print (f"\tcontainer vlan:\t\tuntagged")
print (f"\tnetwork mode:\t\t{cfg['LXC_NET_MODE']}")
if enable_dhcp == False:
    print (f"\tip address (CIDR):\t{cfg['LXC_IP']}")
    print (f"\tdefault gateway:\t{cfg['LXC_GW']}")
    print (f"\tdns server / forwarder:\t{cfg['LXC_GW']}")
print (f"\nCONTAINER CREDENTIALS:")
print (f"\troot password:\t\t{cfg['LXC_PWD']}")
print (f"\tauthorized ssh keys:\t{cfg['LXC_AUTHORIZED_KEY']}")