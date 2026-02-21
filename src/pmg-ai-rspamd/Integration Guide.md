# 🛡️ Integration Guide: PMG & Mailcow an Rspamd-AI

Dieses Dokument beschreibt die Anbindung von Proxmox Mail Gateway (PMG) und Mailcow-Instanzen an das zentrale `pmg-ai-rspamd` Gehirn.

## 1. Integration: Proxmox Mail Gateway (PMG)

Das PMG dient als Grobfilter und nutzt den Rspamd-LXC via Milter-Protokoll für die KI-Analyse.

### Schritt A: Whitelist-Eintrag im Rspamd-LXC

Bevor das PMG senden darf, muss seine IP im Rspamd-LXC hinterlegt werden, damit Rspamd die Mail nicht als "Relay-Versuch von extern" blockiert.


1. Erstelle auf dem **Rspamd-LXC** eine neue Datei für das PMG:

   ```javascript
   cat << 'EOF' > /etc/rspamd/local.d/local_addrs.d/pmg-gateway.conf
   # IP des Proxmox Mail Gateways
   local_addrs = "10.10.10.50"; 
   EOF
   
   ```
2. Rspamd neu laden: `systemctl reload rspamd`

### Schritt B: PMG Postfix Konfiguration

Auf dem **PMG-Server** (via SSH):


1. Template-System vorbereiten:

   ```javascript
   mkdir -p /etc/pmg/templates
   cp /var/lib/pmg/templates/main.cf.in /etc/pmg/templates/main.cf.in
   
   ```
2. Am Ende von `/etc/pmg/templates/main.cf.in` einfügen:

   ```javascript
   # Rspamd Milter Integration
   smtpd_milters = inet:10.10.10.200:11332
   non_smtpd_milters = inet:10.10.10.200:11332
   milter_protocol = 6
   milter_default_action = accept
   
   ```

   *(Ersetze* `*10.10.10.200*` *durch die IP deines Rspamd-LXC)*.
3. Aktivieren: `pmgconfig sync --restart 1`


---

## 2. Integration: Mailcow Remote Learning

Hier bringen wir der Mailcow bei, Spam/Ham nicht lokal zu lernen, sondern an dein KI-Gehirn zu senden.

### Option A: Via VPN (Sicherster Weg)

**Voraussetzung:** Mailcow-IP ist im Rspamd-LXC unter `secure_ips.d/` hinterlegt.


1. Erstelle auf dem **Rspamd-LXC** den Eintrag:

   ```javascript
   cat << 'EOF' > /etc/rspamd/local.d/secure_ips.d/kunde-mailcow.conf
   secure_ip = "10.8.0.10"; # VPN-IP der Mailcow
   EOF
   
   ```
2. In der **Mailcow UI** unter *Konfiguration > System-Konfiguration > Rspamd*:
   * **Rspamd-Host:** `10.8.0.200` (VPN-IP des LXC)
   * **API-Key / Passwort:** Dein `rspamadm pw` Klartext-Passwort.

### Option B: Via HTTPS (Ohne VPN über Public IP)

Wenn kein VPN möglich ist, nutzen wir einen Reverse Proxy (z. B. Nginx) auf dem LXC-Host, um die API per TLS zu schützen.

**Sicherheits-Warnung:** Öffne niemals Port 11334 direkt zum Internet!


1. Installiere Nginx auf dem LXC-Host (oder einem Proxy davor).
2. Nginx-Config (Auszug):

   ```javascript
   server {
       listen 443 ssl;
       server_name rspamd-api.deine-domain.de;
       # SSL-Zertifikat hier konfigurieren (Certbot)
   
       location / {
           proxy_pass http://127.0.0.1:11334;
           allow 1.2.3.4; # Nur die öffentliche IP der Mailcow erlauben!
           deny all;
       }
   }
   
   ```
3. In der **Mailcow** nun als Host `https://rspamd-api.deine-domain.de` eintragen.


---

## 3. Erfolgskontrolle (Debugging)

Um zu sehen, ob die KI arbeitet, schau in das Log des Rspamd-LXC:

```javascript
tail -f /var/log/rspamd/rspamd.log | grep -i "QWEN"
```

Wenn eine Mail vom PMG kommt, solltest du einen Eintrag wie diesen sehen: `... (main) <...> symbol: QWEN_LLM_FRAUD(2.50); ... score: 5 ...`


---