# PMG-Integration des KI-Rspamd Filters

Diese Anleitung beschreibt, wie das PMG als zentrale Filter-Instanz die Scores deines externen Rspamd-LXC abfragt, visualisiert und gewichtet, ohne die eigene Filterhoheit zu verlieren.

## 1. Architektur-Übersicht

Das PMG fungiert als SMTP-Relay. Der externe Rspamd wird als **Before-Queue Milter** eingebunden. Er verarbeitet die Mail, setzt Header-Attribute und das PMG wertet diese Header innerhalb seines eigenen Regelwerks aus.


---

## 2. Persistente Milter-Anbindung (Updatesicher)

Damit Postfix den Rspamd-LXC anspricht, muss die Konfiguration über das PMG-Template-System erfolgen.


1. **Template-Verzeichnis erstellen:**

   ```javascript
   mkdir -p /etc/pmg/templates
   cp /var/lib/pmg/templates/main.cf.in /etc/pmg/templates/
   
   ```
2. **Milter in `main.cf.in` eintragen:** Öffne `/etc/pmg/templates/main.cf.in` und füge am Ende (vor den lokalen Overrides) folgende Zeilen hinzu:

   ```javascript
   smtpd_milters = inet:IP_DEINES_LXC:11332
   milter_default_action = accept
   milter_protocol = 6
   
   ```
3. **Konfiguration generieren:**

   ```javascript
   pmgconfig sync
   
   ```


---

## 3. Score-Gewichtung (SpamAssassin-Integration)

Da das PMG-UI keine direkte Punkte-Addition erlaubt, integrieren wir die Rspamd-Ergebnisse direkt in den internen Scan-Prozess. Dies stellt sicher, dass die Scores im **Tracking Center** namentlich auftauchen.


1. **Konfigurationsdatei erstellen:** Erstelle auf dem PMG-Host: `/etc/mail/spamassassin/rspamd_scores.cf`
2. **Regeln definieren:** Kopiere diesen Block in die Datei:

   ```javascript
   # Rspamd Medium (4 - 5.9)
   header RSPAMD_MEDIUM X-Rspamd-Score =~ /^([45]\.[0-9]+)/
   describe RSPAMD_MEDIUM Rspamd bewertet diese Mail als leicht verdaechtig (4-5.9)
   score RSPAMD_MEDIUM 1.5
   
   # Rspamd High (6 - 14.9)
   header RSPAMD_HIGH X-Rspamd-Score =~ /^([6-9]|1[0-4])\.[0-9]+/
   describe RSPAMD_HIGH Rspamd bewertet diese Mail als Spam (6-14.9)
   score RSPAMD_HIGH 4.0
   
   # Rspamd Critical (15+)
   header RSPAMD_CRITICAL X-Rspamd-Score =~ /^(1[5-9]|[2-9][0-9]|[1-9][0-9][0-9])\.[0-9]+/
   describe RSPAMD_CRITICAL Rspamd (KI/Llama) ist sich absolut sicher: Scam/Betrug (15+)
   score RSPAMD_CRITICAL 10.0
   
   ```
3. **Dienst neu starten:**

   ```javascript
   systemctl restart pmg-smtp-filter
   
   ```


---

## 4. UI-Logik für harte Aktionen (Optional)

Wenn du für extrem hohe Scores (`RSPAMD_CRITICAL`) eine sofortige Quarantäne erzwingen möchtest, kannst du dies im WebUI ergänzen:


1. **What Object:** Erstelle unter *Mail Filter > What Objects* ein **Match Field**.
   * **Name:** `Rspamd-Critical-Header`
   * **Field:** `X-Rspamd-Score`
   * **Value:** `^(1[5-9]|[2-9][0-9])\..*`
2. **Rule:** Erstelle eine Regel mit Priorität **99**.
   * **What:** `Rspamd-Critical-Header`
   * **Action:** `Quarantine`


---

## 5. Verifizierung & Monitoring

Nach der Integration sollten eingehende E-Mails im PMG Tracking Center detailliert aufgeschlüsselt werden.

* **Live-Log Prüfung:** Überwache die Auswertung der neuen Header live auf der Konsole:

  ```javascript
  tail -f /var/log/mail.log | grep -E "RSPAMD_(MEDIUM|HIGH|CRITICAL)"
  
  ```
* **Tracking Center:** In der Detailansicht einer E-Mail unter **Spam Analysis** erscheint nun z. B. der Eintrag: `RSPAMD_HIGH (4.00)`


---

### Wartungshinweise

* **Persistent:** Die `.cf`-Dateien unter `/etc/mail/spamassassin/` bleiben bei PMG-Updates erhalten.
* **Anpassung:** Sollten zu viele False Positives auftreten, senke einfach die `score`-Werte in der `rspamd_scores.cf` und starte den `pmg-smtp-filter` neu.