#!/bin/bash

set -euo pipefail

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

source /root/functions.sh
source /root/zamba.conf
source /root/constants-service.conf

RSPAMD_PASSWORD=$(random_password)
LLM=llama3.1:8b

DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt install -y redis-server unbound python3-venv rspamd zstd nginx ssl-cert

# Eine abgeschottete Python-Umgebung in /opt/oletools erstellen
python3 -m venv /opt/oletools

# Oletools innerhalb dieser Umgebung installieren (berührt das System nicht!)
/opt/oletools/bin/pip install oletools python-magic
ln -s /opt/oletools/bin/olevba /usr/local/bin/olevba3


# install olefy servvice
curl -o /usr/local/bin/olefy.py https://raw.githubusercontent.com/HeinleinSupport/olefy/master/olefy.py
chmod +x /usr/local/bin/olefy.py
sed -i "s/addr_re = re.compile('\[\\\[\" \\\]\]')/addr_re = re.compile(r'\[\\\[\" \\\]\]')/g" /usr/local/bin/olefy.py

# olefy Systemd-Service anlegen
cat << 'EOF' > /etc/systemd/system/olefy.service
[Unit]
Description=Olefy Daemon for Rspamd
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/opt/oletools/bin/python3 /usr/local/bin/olefy.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# oletools update
cat << 'EOF' > /usr/local/bin/apt-hook-oletools.sh
#!/bin/bash
# Unterdrücke Standard-Ausgaben, fange aber das Ergebnis auf
UPDATE_OUT=$(/opt/oletools/bin/pip install --upgrade oletools 2>&1)

# Prüfen, ob der Text "Successfully installed" im Output vorkommt
if echo "$UPDATE_OUT" | grep -q "Successfully installed"; then
    # Neues Update wurde gefunden und installiert! Dienst neu starten:
    systemctl restart olefy
    # Einen sauberen Eintrag ins System-Log (syslog) schreiben
    logger -t oletools-updater "Neues Oletools Update via APT-Hook installiert. Olefy Dienst neu gestartet."
fi

# Immer erfolgreich beenden (Exit Code 0), damit apt niemals blockiert wird
exit 0
EOF

# Skript ausführbar machen
chmod +x /usr/local/bin/apt-hook-oletools.sh

# apt hook
cat << EOF > /etc/apt/apt.conf.d/99oletools-update
# Automatisches Update von Oletools nach jedem dpkg-Lauf
DPkg::Post-Invoke { "/usr/local/bin/apt-hook-oletools.sh || true"; };
EOF

# download ollama
curl -fsSL https://ollama.com/install.sh | bash 2>/dev/null

# konfiguriere ollama, dass llm dauerhaft geladen bleibt
mkdir -p /etc/systemd/system/ollama.service.d
cat << 'EOF' > /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_KEEP_ALIVE=-1"
EOF

# qwen3 llm herunterladen
ollama pull $LLM

# ollama qwen3 preload service erstellen
cat << EOF > /etc/systemd/system/ollama-preload.service
[Unit]
Description=Preload Qwen3 Model into Ollama
After=ollama.service
Requires=ollama.service

[Service]
Type=oneshot
# Warteschleife: Prüfe im Sekundentakt, ob die API erreichbar ist, bevor wir weitermachen
ExecStartPre=/bin/bash -c 'until curl -s http://127.0.0.1:11434/ > /dev/null; do sleep 1; done'
# Erst wenn der Port antwortet, laden wir das Modell
ExecStart=/usr/bin/curl -s -X POST http://127.0.0.1:11434/api/generate -d '{"model": "$LLM", "keep_alive": -1}'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# milter socket für rspamd konfigurieren
cat << EOF > /etc/rspamd/local.d/worker-proxy.inc
# Lausche auf allen Schnittstellen (für das PMG)
bind_socket = "${LXC_IP%/*}:11332";
# Aktiviere explizit das Milter-Protokoll
milter = yes;
EOF

# rspamd an redis anbinden
cat << 'EOF' > /etc/rspamd/local.d/redis.conf
servers = "127.0.0.1";
write_servers = "127.0.0.1";
EOF

# lua script for llm integration
cat << EOF > /etc/rspamd/lua.local.d/ollama_ai.lua
local logger = require "rspamd_logger"
local http = require "rspamd_http"
local ucl = require "ucl"

local function ollama_check(task)
    logger.errx(task, "KI-Check: ANALYSE START (Llama-3.1-8B)")
    
    local text_parts = task:get_text_parts()
    local email_text = ""
    
    if text_parts then
        for _, part in ipairs(text_parts) do
            email_text = email_text .. tostring(part:get_content() or "")
        end
    end

    -- Abbruch bei zu kurzen Mails
    if #email_text < 15 then 
        logger.errx(task, "KI-Check: Text zu kurz für Analyse")
        return 
    end

    local req_data = {
      model = "$LLM",
      messages = {
        {
          role = "system",
          content = "You are a cybersecurity analyst. Score the following email for fraud/phishing from 0 to 10. Output ONLY the integer number."
        },
        {
          role = "user",
          content = "Rate this content: " .. string.sub(email_text, 1, 1000)
        }
      },
      stream = false,
      options = {
        num_predict = 5,
        temperature = 0.0
      }
    }

    http.request({
      task = task,
      url = 'http://127.0.0.1:11434/api/chat',
      body = ucl.to_format(req_data, 'json'),
      timeout = 25.0,
      callback = function(err, code, body, headers)
        -- Falls der Dienst nicht erreichbar ist
        if err or code ~= 200 then
            logger.errx(task, "KI-Check: Ollama API Fehler oder Timeout")
            return 
        end

        local parser = ucl.parser()
        local res, _ = parser:parse_string(body)
        if res then
            local data = parser:get_object()
            local reply = data.message and data.message.content or ""
            local score_num = reply:match("%d+")
            
            if score_num then
                local score = tonumber(score_num)
                logger.errx(task, "KI-Check: Ergebnis erhalten: %s/10", score)
                
                -- 1. Header: Basis-Info (Wird immer gesetzt, wenn KI geantwortet hat)
                task:set_milter_reply({
                    ['add_header'] = {['X-AI-Scanner'] = 'Llama-3.1-8B-Verified'}
                })

                -- 2. Header & Symbol: Nur bei Verdacht (Score >= 7)
                if score >= 7 then
                    task:insert_result('OLLAMA_LLM_FRAUD', 1.0, "Score " .. score .. "/10")
                    task:set_milter_reply({
                        ['add_header'] = {['X-AI-Fraud-Rating'] = tostring(score) .. '/10'}
                    })
                    logger.errx(task, "KI-Check: Symbol und Header gesetzt (Betrugsverdacht)")
                end
            end
        end
      end
    })
end

rspamd_config:register_symbol({
  name = 'OLLAMA_LLM_FRAUD',
  callback = ollama_check,
  flags = 'async',
  score = 6.0,
  description = 'AI-based fraud detection using Llama-3.1-8B'
})
EOF

# dns resolver konfigurieren
cat << 'EOF' > /etc/rspamd/local.d/options.inc
dns {
    nameserver = ["127.0.0.1"];
}

# Basis-Regeln, die immer gelten müssen
local_addrs = "127.0.0.1";
local_addrs = "::1";

task_timeout = 59s;

# Lade alle Server-spezifischen Dateien (*.conf)
.include(try=true,glob=true) "$LOCAL_CONFDIR/local_addrs.d/*.conf"
EOF

PWHASH=$(rspamadm pw --password "$RSPAMD_PASSWORD")
cat << EOF > /etc/rspamd/local.d/worker-controller.inc

bind_socket = "127.0.0.1:11334";
password = "$PWHASH"; 

# Basis-Regeln (LXC-interner Zugriff)
secure_ip = "127.0.0.1";
secure_ip = "::1";
secure_ip = "${LXC_IP%/*}";

# Lade alle Server-spezifischen Dateien (*.conf)
.include(try=true,glob=true) "\$LOCAL_CONFDIR/secure_ips.d/*.conf"
EOF

cat << EOF > /etc/rspamd/local.d/actions.conf
# Alle Aktionen, die normalerweise ablehnen würden, auf null setzen
reject = null;      # Niemals ablehnen
add_header = 6.0;   # Ab diesem Score den X-Spam-Header setzen
greylist = null;    # Greylisting deaktivieren (macht PMG schon besser)
rewrite_subject = null;
EOF

cat << EOF > /etc/rspamd/local.d/milter_headers.conf
# Diese Header werden für jede Mail geschrieben
use = ["spam-header", "symbols", "score"];

header_names {
    "spam-header" = "X-Spam-Flag";
    "symbols" = "X-Rspamd-Symbols";
    "score" = "X-Rspamd-Score";
}

# Fügt den Score immer hinzu, egal wie hoch er ist
skip_local = false;
extended_symbols = true;
EOF

# oletools aktivieren
cat << 'EOF' > /etc/rspamd/local.d/oletools.conf
enabled = true;
servers = "127.0.0.1:10050"; # Standard-Port von olefy
EOF

# learning aktivieren
cat << 'EOF' > /etc/rspamd/local.d/classifier-ham-spam.conf
# Nutze Redis als Backend für gelerntes Wissen
backend = "redis";
# Erlaube das Lernen (wichtig für deine Mailcows!)
autolearn = true;
EOF

# betreffzeilen anzeigen
cat << 'EOF' > /etc/rspamd/local.d/history_redis.conf
# Speichere die letzten Mail-Logs in Redis für die WebUI
subject_privacy = false; # Zeigt Betreffzeilen im Dashboard an (hilfreich für MSPs)
EOF

# set include for local modules
cat << 'EOF' > /etc/rspamd/local.d/groups.conf
# Lade alle Symbol-Definitionen aus dem scores.d Verzeichnis
.include(try=true,glob=true) "$LOCAL_CONFDIR/scores.d/*.conf"
EOF

# create folder for trusted addresses
mkdir -p /etc/rspamd/local.d/local_addrs.d
mkdir -p /etc/rspamd/local.d/secure_ips.d

# persistenz in redis aktivieren
sed -i 's/appendonly no/appendonly yes/g' /etc/redis/redis.conf
sed -i 's/^#\? \?appendfsync .*/appendfsync everysec/g' /etc/redis/redis.conf

# nginx konfigurieren
mkdir -p /etc/nginx/ssl

# Symlinks auf Snakeoil (Pfade ggf. anpassen, falls ssl-cert nicht installiert ist)
ln -s /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/nginx/ssl/fullchain.pem
ln -s /etc/ssl/private/ssl-cert-snakeoil.key /etc/nginx/ssl/privkey.pem

# Starke Diffie-Hellman Parameter generieren (wichtig!)
openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048

# generiere config
cat << EOF > /etc/nginx/sites-available/rspamd_proxy
# HTTP - Redirect auf HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $LXC_HOSTNAME.$LXC_DOMAIN;
    return 301 https://\$host\$request_uri;
}

# HTTPS - Sicherer Proxy
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $LXC_HOSTNAME.$LXC_DOMAIN;

    # Zertifikate
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    ssl_dhparam /etc/nginx/ssl/dhparam.pem;

    # TLS Sicherheit nach Stand der Technik (Modern)
    ssl_protocols TLSv1.3; # TLS 1.2 entfernt für maximale Sicherheit
    ssl_prefer_server_ciphers off;

    # Security Headers
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;";

    # Proxy-Einstellungen
    location / {
        proxy_pass http://127.0.0.1:11334; # Dein Rspamd Controller/UI
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Wichtig für lange KI-Analysen
        proxy_read_timeout 120s;
        proxy_connect_timeout 120s;

        # Optional: Zusätzlicher Schutz auf Nginx-Ebene
        # allow 1.2.3.4; # Deine Admin IP
        # deny all;
    }
}
EOF
ln -s /etc/nginx/sites-available/rspamd_proxy /etc/nginx/sites-enabled/
nginx -t

# dienste aktivieren
systemctl daemon-reload
systemctl enable --now unbound olefy ollama ollama-preload.service
systemctl restart redis-server rspamd nginx

echo "Your rspamd instance setup is finished!"
echo "Please visit http://${LXC_IP%/*}:11334/"
echo "rspamd password is: $RSPAMD_PASSWORD"