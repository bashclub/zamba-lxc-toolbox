#!/bin/bash

export LC_ALL=C
ZAMBA_CONF="/root/zamba-lxc-toolbox/conf/zamba.conf"

if [[ -f "$ZAMBA_CONF" ]]; then
    # Prüfen, ob die Datei älter als 3 Tage ist
    if find "$ZAMBA_CONF" -mtime +3 >/dev/null 2>&1; then
        echo "⚠️ zamba.conf ist älter als 3 Tage – Datei wird gelöscht: $ZAMBA_CONF"
        rm -f "$ZAMBA_CONF"
        exit 0
    else
        echo "❌ Problem: zamba.conf ist vorhanden und jünger als 3 Tage: $ZAMBA_CONF"
        exit 2
    fi
else
    echo "✅ OK: zamba.conf ist nicht vorhanden"
    exit 0
fi
