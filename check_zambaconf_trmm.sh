#!/bin/bash

export LC_ALL=C

ZAMBA_CONF="/root/zamba-lxc-toolbox/conf/zamba.conf"

if [[ -f "$ZAMBA_CONF" ]]; then
    echo "❌ Problem: zamba.conf ist vorhanden: $ZAMBA_CONF"
    exit 2
else
    echo "✅ OK: zamba.conf ist nicht vorhanden"
    exit 0
fi
