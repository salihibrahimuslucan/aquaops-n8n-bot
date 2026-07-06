@echo off
rem AquaOps n8n baslatici — veri D:'de, saat dilimi Istanbul, Telegram icin tunnel
set N8N_USER_FOLDER=D:\n8n-ops-bot
set GENERIC_TIMEZONE=Europe/Istanbul
set TZ=Europe/Istanbul
set N8N_DIAGNOSTICS_ENABLED=false
cd /d D:\n8n-ops-bot
call node_modules\.bin\n8n.cmd start --tunnel
