#!/usr/bin/python3
from pathlib import Path
import os
import ipaddress
import socket
import json
import subprocess
from enum import Enum

def check_zfs_autosnapshot():
    proc = subprocess.Popen(["dpkg","-l","zfs-auto-snapshot"],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    proc.communicate()
    if proc.returncode > 0:
        print ("'zfs-auto-snapshot' is NOT installed on your system. This ist required for 'previous versions' feature in Zamba containers.\nYou can install it with the following command:\n\tapt install zfs-auto-snapshot\n")
        input ("Press Enter to continue...")

# get_pve_bridges queries and returns availabe Proxmox bridges
def get_pve_bridges():
    pve_bridges=[]
    ifaces=os.listdir(os.path.join("/","sys","class","net"))
    for iface in ifaces:
        if "vmbr" in iface:
            pve_bridges.append(iface)
    return pve_bridges

# get_pve_storages queries and returns available Proxmox bridges
def get_pve_storages(driver=None,content=None):
    pve_storages={}
    cmd = ["pvesm","status","--enabled","1"]
    if content != None:
        cmd.extend(["--content",content.name])
    result = subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE).communicate()
    stdout = result[0].decode("utf-8").split('\n')
    for line in filter(lambda x: len(x)>0, stdout):
        if not "Status" in line:
            item = [x for x in line.split(' ') if x.strip()]
            storage = {}
            storage["driver"] = item[1]
            storage["status"] = item[2]
            storage["total"] = item[3]
            storage["used"] = item[4]
            storage["available"] = item[5]
            storage["percent_used"] = item[6]

            if driver == None:
                pve_storages[item[0]] = storage
            else:
                if driver.name == storage["driver"]:
                    pve_storages[item[0]] = storage

    return pve_storages

# get_zmb_services queries and returns available Zamba services
def get_zmb_services():
    zmb_services={}
    for item in Path.iterdir(Path.joinpath(Path.cwd(),"src")):
        if Path.is_dir(item) and "__" not in item.name:
            with open(os.path.join(item._str, "info"),"r") as info:
                description = info.read()
                zmb_services[item.name] = description
    return zmb_services

# get_ct_id queries and returns the next available container id
def get_ct_id(base="ct"):
    with open("/etc/pve/.vmlist","r") as v:
        vmlist_json = json.loads(v.read())
    ct_id = 100
    for cid in vmlist_json["ids"].keys():
        if int(cid) > ct_id and base == "ct" and vmlist_json["ids"][cid]["type"] == "lxc":
            ct_id = int(cid)
        elif int(cid) > ct_id and base == "all":
            ct_id = int(cid)
    while True:
        ct_id = ct_id + 1
        if ct_id not in vmlist_json["ids"].keys():
            break
    return ct_id

# validate_ct_id queries if ct_id is available and returns as boolean
def validate_ct_id(ct_id:int):
    with open("/etc/pve/.vmlist","r") as v:
        vmlist_json = json.loads(v.read())
    ct_id = str(ct_id)
    if int(ct_id) >= 100 and int(ct_id) <= 999999999 and ct_id not in vmlist_json["ids"].keys():
        return True
    else:
        return False

def validate_vlan(tag:int):
    if int(tag) >= 1 and int(tag) <= 4094:
        return True
    else:
        return False

def get_ct_features(zmb_service):
    with open(Path.joinpath(Path.cwd(),"src",zmb_service,"features.json")) as ff:
        return json.loads(ff.read())


class PveStorageContent(Enum):
    images = 0
    rootdir = 1
    vztmpl = 2
    backup = 3
    iso = 4
    snippets = 5

class PveStorageType(Enum):
    zfspool = 0
    dir = 1
    nfs = 2
    cifs = 3
    pbs = 4
    glusterfs = 5
    cephfs = 6
    lvm = 7
    lvmthin = 8
    iscsi = 9
    iscsidirect = 10
    rbd = 11
    zfs = 12