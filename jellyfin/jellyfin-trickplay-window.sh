#!/bin/bash
# jellyfin-trickplay-window.sh — mantém o "Generate Trickplay Images" do Jellyfin
# dentro da janela 0h–5h: o trigger diário do Jellyfin inicia ~00:01; este script
# roda às 05:00 (cron) e ABORTA a task se ainda estiver rodando. A extração é
# incremental — o que sobrou retoma na noite seguinte, até a biblioteca completar.
# Uso: jellyfin-trickplay-window.sh  (sem argumentos; tudo embutido)
set -u

DB="/opt/jellyfin/config/data/jellyfin.db"
TASK_KEY="RefreshTrickplayImages"
JF_URL="http://localhost:8096"
NOTIFY="$HOME/bin/tg_notify.sh"

token=$(sudo sqlite3 "file:${DB}?mode=ro&immutable=1" \
        "SELECT AccessToken FROM ApiKeys ORDER BY Id LIMIT 1;" 2>/dev/null)
if [ -z "$token" ]; then
    "$NOTIFY" "⏰ trickplay/Jellyfin: FALHA — não consegui ler a API key do DB (${DB}). Task NÃO abortada."
    exit 1
fi

tasks=$(curl -s --max-time 15 -H "Authorization: MediaBrowser Token=\"${token}\"" \
        "${JF_URL}/ScheduledTasks")
if [ -z "$tasks" ]; then
    "$NOTIFY" "⏰ trickplay/Jellyfin: FALHA — API do Jellyfin não respondeu em ${JF_URL}. Task NÃO abortada."
    exit 1
fi

# parse JSON robusto (a API devolve tudo em linha única — grep não serve)
info=$(printf '%s' "$tasks" | python3 -c "
import json, sys
for t in json.load(sys.stdin):
    if t.get('Key') == '${TASK_KEY}':
        print(t.get('State', '?'), t.get('Id', ''), int(t.get('CurrentProgressPercentage') or 0))
        break
")
state=$(echo "$info" | cut -d' ' -f1)
task_id=$(echo "$info" | cut -d' ' -f2)
progress=$(echo "$info" | cut -d' ' -f3)

if [ "$state" != "Running" ]; then
    "$NOTIFY" "⏰ trickplay/Jellyfin 05:00: task não estava rodando (state=${state:-desconhecido}) — biblioteca completa ou fora da janela. Nada a fazer."
    exit 0
fi

http=$(curl -s --max-time 15 -o /dev/null -w '%{http_code}' \
       -X DELETE -H "Authorization: MediaBrowser Token=\"${token}\"" \
       "${JF_URL}/ScheduledTasks/Running/${task_id}")

if [ "$http" = "204" ] || [ "$http" = "200" ]; then
    "$NOTIFY" "⏰ trickplay/Jellyfin 05:00: task abortada no fim da janela 0h–5h. Retoma hoje à noite ~00:01 e continua de onde parou (progressivo até completar a biblioteca)."
else
    "$NOTIFY" "⏰ trickplay/Jellyfin: FALHA ao abortar a task (HTTP ${http}). Trickplay pode continuar fora da janela — checar CPU do Jellyfin."
    exit 1
fi
