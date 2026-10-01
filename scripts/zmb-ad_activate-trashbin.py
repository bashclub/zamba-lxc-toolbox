#!/usr/bin/env python3
import argparse
import os
import sys
from samba.samdb import SamDB
from samba.param import LoadParm
from samba.auth import system_session
import ldb


def get_samdb():
    if os.geteuid() != 0:
        print("[!] Dieses Skript muss als root ausgeführt werden.", file=sys.stderr)
        sys.exit(2)

    lp = LoadParm()
    try:
        lp.load_default()
    except Exception:
        if os.path.exists("/etc/samba/smb.conf"):
            lp.load("/etc/samba/smb.conf")
        else:
            print("[!] Konnte smb.conf nicht laden.", file=sys.stderr)
            sys.exit(2)

    samdb_path = lp.samdb_url()
    if not samdb_path:
        private_dir = lp.get("private dir") or "/var/lib/samba/private"
        samdb_path = os.path.join(private_dir, "sam.ldb")

    try:
        session = system_session(lp)
        samdb = SamDB(
            url=samdb_path,
            session_info=session,
            credentials=None,
            lp=lp,
        )
        return samdb
    except Exception as e:
        print(f"[!] Fehler beim Öffnen der SAM-Datenbank ({samdb_path}): {e}", file=sys.stderr)
        sys.exit(2)


def is_recycle_bin_enabled(samdb):
    config_dn = samdb.get_config_basedn().get_linearized()
    partitions_dn = f"CN=Partitions,{config_dn}"

    res = samdb.search(
        base=partitions_dn,
        scope=ldb.SCOPE_BASE,
        attrs=["msDS-EnabledFeature"],
    )

    if len(res) > 0 and "msDS-EnabledFeature" in res[0]:
        enabled_features = [
            f.decode("utf-8") if isinstance(f, bytes) else str(f)
            for f in res[0]["msDS-EnabledFeature"]
        ]
        for feat in enabled_features:
            if "Recycle Bin Feature" in feat:
                return True
    return False


def main():
    parser = argparse.ArgumentParser(
        description="Active Directory Recycle Bin Status prüfen und aktivieren (Samba AD)."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Prüft nur, ob der Papierkorb aktiv ist (Exit 0 = aktiv, 1 = inaktiv).",
    )
    args = parser.parse_args()

    samdb = get_samdb()
    enabled = is_recycle_bin_enabled(samdb)

    if args.check:
        if enabled:
            print("[+] Active Directory Papierkorb ist AKTIVIERT.")
            sys.exit(0)
        else:
            print("[-] Active Directory Papierkorb ist NICHT aktiviert.")
            sys.exit(1)

    # Standard-Ablauf: Aktivieren falls noch nicht aktiv
    if enabled:
        print("[+] Der Active Directory Papierkorb ist BEREITS AKTIV!")
        return

    config_dn = samdb.get_config_basedn().get_linearized()
    partitions_dn = f"CN=Partitions,{config_dn}"
    feature_dn = f"CN=Recycle Bin Feature,CN=Optional Features,CN=Directory Service,CN=Windows NT,CN=Services,{config_dn}"

    print(f"[*] Configuration DN : {config_dn}")
    print(f"[*] Partitions DN    : {partitions_dn}")
    print(f"[*] Feature DN       : {feature_dn}")
    print("\n[*] Aktiviere Active Directory Recycle Bin...")

    msg = ldb.Message()
    msg.dn = ldb.Dn(samdb, partitions_dn)
    msg["msDS-EnabledFeature"] = ldb.MessageElement(
        [feature_dn], ldb.FLAG_MOD_ADD, "msDS-EnabledFeature"
    )

    try:
        samdb.modify(msg, controls=["relax:0"])
        print("[+] ERFOLG: Active Directory Papierkorb wurde erfolgreich aktiviert!")
    except ldb.LdbError as err:
        num, text = err.args
        print(f"[!] Fehler bei der Aktivierung (LDB Error {num}): {text}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
