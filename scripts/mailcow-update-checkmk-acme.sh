#!/bin/bash

DEBUG_LOG="/tmp/mailcow_debug.log"
echo "" > "$DEBUG_LOG"

debug() {
    echo "[DEBUG] $1"
    echo "[DEBUG] $1" >> "$DEBUG_LOG"
}

debug "Starte Mailcow Check Script"

MAILCOW_PATH="/opt/mailcow-dockerized"
SPOOL_DIR="/var/lib/check_mk_agent/spool"
INTERVAL_SECONDS=87000
SPOOL_FILE="${SPOOL_DIR}/${INTERVAL_SECONDS}_mailcow_update"
CERT_DIR="${MAILCOW_PATH}/data/assets/ssl"

mkdir -p "$SPOOL_DIR"
TMP_FILE="$(mktemp)"

debug "Spool-Datei: $SPOOL_FILE"
debug "Temporäre Datei: $TMP_FILE"

# KORREKTER Header für Checkmk Local Checks
echo "<<<local>>>" > "$TMP_FILE"

debug "Wechsle ins Mailcow-Verzeichnis: $MAILCOW_PATH"
if ! cd "$MAILCOW_PATH"; then
    echo "2 Mailcow_Update - ERROR: Verzeichnis $MAILCOW_PATH nicht gefunden" >> "$TMP_FILE"
    echo "3 Mailcow_Version - UNKNOWN: Verzeichnis nicht gefunden" >> "$TMP_FILE"
    mv "$TMP_FILE" "$SPOOL_FILE"
    exit 2
fi

NOW="$(date '+%Y-%m-%d %H:%M:%S')"
debug "Aktuelle Zeit: $NOW"

debug "Lese Mailcow Git-Version aus..."
GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null)

debug "GIT_TAG=$GIT_TAG"
debug "GIT_COMMIT=$GIT_COMMIT"

if [[ -n "$GIT_TAG" ]]; then
    echo "0 Mailcow_Version - OK: Version $GIT_TAG ($GIT_COMMIT)" >> "$TMP_FILE"
else
    echo "0 Mailcow_Version - OK: Commit $GIT_COMMIT (kein Tag)" >> "$TMP_FILE"
fi

###############################################################################
# UPDATE-CHECK
###############################################################################

debug "Führe update.sh --check aus..."
UPDATE_CHECK=$(./update.sh --check 2>&1)
RET=$?
debug "Update Check Rückgabecode: $RET"

EXIT_CODE=0

if echo "$UPDATE_CHECK" | grep -q "No updates available"; then
    debug "Kein Update verfügbar."
    echo "0 Mailcow_Update - OK: Kein Update verfügbar ($NOW)" >> "$TMP_FILE"
else
    debug "Update verfügbar! Starte Update..."

    UPDATE_OUTPUT=$(./update.sh --force --skip-ping-check 2>&1)
    EXIT_CODE=$?

    if [ "$EXIT_CODE" -eq 0 ]; then
        debug "Update erfolgreich."
        echo "0 Mailcow_Update - OK: Update erfolgreich durchgeführt ($NOW)" >> "$TMP_FILE"
    else
        debug "Update fehlgeschlagen."
        echo "2 Mailcow_Update - CRITICAL: Update fehlgeschlagen ($NOW)" >> "$TMP_FILE"
        echo "$UPDATE_OUTPUT" >> "$TMP_FILE"
    fi
fi

###############################################################################
# SSL-ZERTIFIKATE PRÜFEN (mit SANs)
###############################################################################

debug "Beginne SSL-Zertifikat-Scan unter: $CERT_DIR"
debug "Ignoriere Verzeichnis: $CERT_DIR/backups"
debug "Ignoriere Datei: $CERT_DIR/acme/account.pem"
debug "Ignoriere Dateien: key.pem, dhparams.pem"

if [ ! -d "$CERT_DIR" ]; then
    echo "3 Mailcow_Certificates - UNKNOWN: SSL-Verzeichnis fehlt" >> "$TMP_FILE"
else

    while IFS= read -r -d '' CERT_FILE; do
        debug "Prüfe Zertifikat: $CERT_FILE"

        REL_PATH="${CERT_FILE#${CERT_DIR}/}"
        CERT_NAME="${REL_PATH//\//_}"

        # Ablaufdatum lesen
        END_DATE_RAW=$(openssl x509 -enddate -noout -in "$CERT_FILE" 2>/dev/null | cut -d= -f2)

        # SANs extrahieren
        SANS=$(openssl x509 -noout -text -in "$CERT_FILE" \
             | grep -A1 "Subject Alternative Name" \
             | tail -n1 \
             | sed 's/DNS://g' \
             | sed 's/, /,/g' \
             | xargs)

        debug "SANs: $SANS"

        if [ -z "$END_DATE_RAW" ]; then
            echo "3 Mailcow_Cert_${CERT_NAME} - UNKNOWN: Kein Ablaufdatum ($CERT_FILE)" >> "$TMP_FILE"
            continue
        fi

        END_EPOCH=$(date -d "$END_DATE_RAW" +%s 2>/dev/null)
        NOW_EPOCH=$(date +%s)
        SECONDS_LEFT=$((END_EPOCH - NOW_EPOCH))
        DAYS_LEFT=$((SECONDS_LEFT / 86400))

        debug "Noch $DAYS_LEFT Tage gültig"

        if [ "$SECONDS_LEFT" -le 0 ]; then
            STATE=2; STATE_TEXT="CRITICAL"; MSG="abgelaufen"
        elif [ "$DAYS_LEFT" -le 14 ]; then
            STATE=2; STATE_TEXT="CRITICAL"; MSG="läuft in <=14 Tagen ab"
        elif [ "$DAYS_LEFT" -le 30 ]; then
            STATE=1; STATE_TEXT="WARNING"; MSG="läuft bald ab"
        else
            STATE=0; STATE_TEXT="OK"; MSG="gültig"
        fi

        echo "${STATE} Mailcow_Cert_${CERT_NAME} - ${STATE_TEXT}: ${MSG}, Ablauf: ${END_DATE_RAW}, SANs: ${SANS}" >> "$TMP_FILE"

    done < <(
        find "$CERT_DIR" \
          -path "${CERT_DIR}/backups" -prune -o \
          -type f \
          ! -path "$CERT_DIR/acme/account.pem" \
          ! -name "key.pem" \
          ! -name "dhparams.pem" \
          \( -name "*.crt" -o -name "*.pem" -o -name "*.cert" \) \
          -print0
    )
fi

###############################################################################
# SPEICHERN
###############################################################################

debug "Speichere Spool-Datei: $SPOOL_FILE"
mv "$TMP_FILE" "$SPOOL_FILE"

debug "Script fertig. Exit-Code: $EXIT_CODE"
exit "$EXIT_CODE"

