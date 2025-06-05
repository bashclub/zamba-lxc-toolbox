#!/bin/bash

export LC_ALL=C
EXIT_CODE=0

# Alle .conf-Dateien im Verzeichnis /root/zamba-lxc-toolbox/conf/
CONF_DIR="/root/zamba-lxc-toolbox/conf"
CONF_FILES=("$CONF_DIR"/*.conf)

# Zusätzlich die einzelne Datei /root/zamba.conf
CONF_FILES+=("/root/zamba.conf")

for CONF in "${CONF_FILES[@]}"; do
    if [[ -f "$CONF" ]]; then
        if [[ $(find "$CONF" -mtime +3) ]]; then
            echo "⚠️ Datei ist älter als 3 Tage – wird gelöscht: $CONF"
            rm -f "$CONF"
        else
            echo "❌ Problem: Datei ist vorhanden und jünger als 3 Tage: $CONF"
            EXIT_CODE=2
        fi
    else
        echo "✅ OK: Datei nicht vorhanden: $CONF"
    fi
done

exit $EXIT_CODE
