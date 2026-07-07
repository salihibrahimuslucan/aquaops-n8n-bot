@echo off
rem AquaOps n8n baslatici — veri D:'de, saat dilimi Istanbul, Telegram icin tunnel
rem NOT: n8n 2.29'da yerlesik "n8n start --tunnel" kaldirilmis (start --help'te yok,
rem verilse de sessizce yok sayiliyor ve webhook URL'i localhost'ta kalip Telegram
rem "Bad request" ile aktivasyonu reddediyor). Bu yuzden localtunnel npm paketiyle
rem manuel tunel acilip WEBHOOK_URL n8n'e o adresle veriliyor.
set N8N_USER_FOLDER=D:\n8n-ops-bot
set GENERIC_TIMEZONE=Europe/Istanbul
set TZ=Europe/Istanbul
set N8N_DIAGNOSTICS_ENABLED=false
set WEBHOOK_URL=https://your-subdomain.loca.lt/
cd /d D:\n8n-ops-bot
start "AquaOps Tunnel" cmd /c "npx --yes localtunnel --port 5678 --subdomain your-subdomain"
timeout /t 5 /nobreak >nul
call node_modules\.bin\n8n.cmd start
