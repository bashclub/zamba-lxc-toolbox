#!/bin/bash

set -e

SMB_CONF="/etc/samba/smb.conf"
USERMAP_FILE="/etc/samba/user.map"
KEYTAB_PATH="/root/admin.keytab"
SYSTEMD_SERVICE="/etc/systemd/system/kinit-admin.service"
SYSTEMD_TIMER="/etc/systemd/system/kinit-admin.timer"
BASH_PROFILE="/root/.bash_profile"

# 1. Domain & Realm aus smb.conf auslesen
DOMAIN_NAME=$(awk -F '=' '/^[[:space:]]*workgroup[[:space:]]*=/ {gsub(/ /, "", $2); print $2}' "$SMB_CONF")
REALM_NAME=$(awk -F '=' '/^[[:space:]]*realm[[:space:]]*=/ {gsub(/ /, "", $2); print toupper($2)}' "$SMB_CONF")

if [[ -z "$DOMAIN_NAME" || -z "$REALM_NAME" ]]; then
    echo "[FEHLER] Konnte 'workgroup' oder 'realm' aus smb.conf nicht auslesen."
    exit 1
fi

echo "[INFO] Domain: $DOMAIN_NAME"
echo "[INFO] Realm: $REALM_NAME"

# 2. user.map schreiben
echo "!root = ${DOMAIN_NAME}\\Administrator" > "$USERMAP_FILE"
echo "[OK] Benutzerzuordnung geschrieben in $USERMAP_FILE"

# 3. smb.conf patchen
if ! grep -q "^username map *= *$USERMAP_FILE" "$SMB_CONF"; then
    sed -i "/^\[global\]/a username map = $USERMAP_FILE" "$SMB_CONF"
    echo "[OK] smb.conf wurde um 'username map' ergänzt."
else
    echo "[INFO] 'username map' bereits gesetzt."
fi

# 4. Keytab erzeugen
echo "[INFO] Erzeuge Keytab für Administrator..."
samba-tool domain exportkeytab "$KEYTAB_PATH" --principal="administrator@$REALM_NAME"
chmod 600 "$KEYTAB_PATH"
echo "[OK] Keytab gespeichert unter $KEYTAB_PATH"

# 5. systemd-Service + Timer für automatisches kinit
echo "[INFO] Erstelle systemd-Service & Timer..."

cat > "$SYSTEMD_SERVICE" <<EOF
[Unit]
Description=Kerberos Kinit für Administrator
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/kinit -kt $KEYTAB_PATH administrator@$REALM_NAME
EOF

cat > "$SYSTEMD_TIMER" <<EOF
[Unit]
Description=Kerberos Kinit für Administrator (Boot)

[Timer]
OnBootSec=10sec
Unit=kinit-admin.service

[Install]
WantedBy=multi-user.target
EOF

# Aktivieren
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now kinit-admin.timer

# 6. root-Login: .bash_profile anpassen
echo "[INFO] Ergänze .bash_profile von root, um bei Login kinit auszuführen..."
mkdir -p "$(dirname "$BASH_PROFILE")"
touch "$BASH_PROFILE"

# Block nur hinzufügen, wenn er nicht bereits vorhanden ist
if ! grep -q "kinit -kt $KEYTAB_PATH administrator@$REALM_NAME" "$BASH_PROFILE"; then
    cat >> "$BASH_PROFILE" <<EOF

# Automatisches Kerberos-Ticket beim Login holen
if ! klist -s; then
    echo "[INFO] Kein gültiges Kerberos-Ticket – führe kinit aus..."
    kinit -kt $KEYTAB_PATH administrator@$REALM_NAME && echo "[INFO] Kerberos-Ticket aktualisiert."
fi
EOF
    echo "[OK] .bash_profile angepasst."
else
    echo "[INFO] .bash_profile enthält bereits kinit-Befehl."
fi

# 7. samba-ad-dc neu starten
echo "[INFO] Starte samba-ad-dc neu..."
systemctl restart samba-ad-dc

# 8. Testausgaben
echo "[INFO] getent passwd root:"
getent passwd root || echo "[WARNUNG] Kein Eintrag für root"

echo
echo "[INFO] Test: samba-tool user list (falls kein Passwort kommt, war's erfolgreich):"
samba-tool user list | head -n 5 || echo "[WARNUNG] Fehler bei samba-tool"

