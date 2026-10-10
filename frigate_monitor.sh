#!/bin/bash
# CameraIA — monitor de saúde do Frigate/QNAP (TS-453Be)
# Coleta CPU/mem/load do NAS + stats do Frigate, alerta Telegram em anomalias,
# e grava histórico local p/ relatório diário. Cron a cada 5 min.
# Uso: frigate_monitor.sh collect  |  frigate_monitor.sh daily

NAS_IP="192.168.2.170"
SSH_KEY="$HOME/.ssh/nas_cameraia"
SSH_PORT="2048"
LOG_DIR="$HOME/logs"
HIST="$LOG_DIR/frigate_monitor.csv"
TG_TOKEN_FILE="$HOME/backups/get-tg-token.sh"
CHAT_ID="111597747"
CPU_ALERT=85          # %CPU total
LOAD_ALERT=8          # load avg 5min (4 cores)
MEM_ALERT=90          # %mem usada (excl. cache)
FRIGATE_DOWN_STREAK=2 # amostras consecutivas p/ alertar Frigate down
STATE="/tmp/frigate_monitor_state"

mkdir -p "$LOG_DIR"

ssh_nas() {
  ssh -i "$SSH_KEY" -p "$SSH_PORT" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "hermes@$NAS_IP" "$@" 2>/dev/null
}

tg_send() {
  local msg="$1"
  local token
  token=$(bash "$TG_TOKEN_FILE" 2>/dev/null)
  [ -z "$token" ] && return 1
  curl -s --max-time 10 -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    -d chat_id="$CHAT_ID" -d text="$msg" > /dev/null
}

collect() {
  local ts cpu_idle load5 mem_used_pct stats_line det_fps cam_lines

  ts=$(date '+%Y-%m-%d %H:%M')
  # CPU idle + load + mem do NAS (busybox no QNAP: parse robusto do top)
  read -r cpu_idle load5 mem_used_pct <<< "$(ssh_nas '
    top -b -n 2 -d 2 | grep "^CPU" | tail -1 > /tmp/mon_cpu
    idle=$(awk '"'"'{for(i=1;i<=NF;i++) if($i=="idle") print $(i-1)}'"'"' /tmp/mon_cpu | tr -d %)
    load=$(cat /proc/loadavg | cut -d" " -f2)
    free | awk '"'"'NR==2{tot=$2; free=$4; buff=$6; printf "%d", (tot-free-buff)*100/tot}'"'"' > /tmp/mon_mem
    mem=$(cat /tmp/mon_mem)
    rm -f /tmp/mon_cpu /tmp/mon_mem
    echo "$idle $load $mem"
  ')"

  # Stats do Frigate via API interna (porta 5000, sem auth)
  local stats_json
  stats_json=$(ssh_nas 'curl -s --max-time 8 http://localhost:5000/api/stats')
  local up="0"
  if [ -n "$stats_json" ] && echo "$stats_json" | grep -q "camera_fps"; then
    up="1"
  fi

  # detector fps e cameras detectando
  det_fps="0"; cam_ok="0"; proc_fps_sum="0"
  if [ "$up" = "1" ]; then
    det_fps=$(echo "$stats_json" | /usr/bin/python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    det=d.get('detectors',{})
    fps=[v.get('detection_start') and 0 or 0 for v in det.values()]
    print(round(sum(v.get('detection_fps',0) for v in det.values()),1))
except: print(0)" 2>/dev/null)
    cam_ok=$(echo "$stats_json" | /usr/bin/python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    cams=[c for c,v in d.get('cameras',{}).items() if v.get('camera_fps',0)>1]
    print(len(cams))
except: print(0)" 2>/dev/null)
    proc_fps_sum=$(echo "$stats_json" | /usr/bin/python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(round(sum(v.get('process_fps',0) for v in d.get('cameras',{}).values()),1))
except: print(0)" 2>/dev/null)
  fi

  # grava histórico (csv)
  [ -f "$HIST" ] || echo "timestamp,cpu_idle_pct,load5,mem_used_pct,frigate_up,detector_fps,cameras_ok,process_fps" >> "$HIST"
  echo "$ts,${cpu_idle:-NA},${load5:-NA},${mem_used_pct:-NA},$up,${det_fps:-0},${cam_ok:-0},${proc_fps_sum:-0}" >> "$HIST"

  # ---- alertas ----
  local down_count=0
  [ -f "$STATE" ] && down_count=$(cat "$STATE")
  if [ "$up" != "1" ]; then
    down_count=$((down_count+1))
    echo "$down_count" > "$STATE"
    if [ "$down_count" = "$FRIGATE_DOWN_STREAK" ]; then
      tg_send "🚨 CameraIA: Frigate SEM resposta ($down_count amostras seguidas). CPU_idle=${cpu_idle:-?}% load=${load5:-?}. Verificar container no NAS."
    fi
  else
    if [ "$down_count" -ge "$FRIGATE_DOWN_STREAK" ] 2>/dev/null; then
      tg_send "✅ CameraIA: Frigate voltou a responder (${cam_ok} câmeras ativas, detector ${det_fps} fps)."
    fi
    echo "0" > "$STATE"
  fi

  # CPU alta sustentada (usa contagem em state tb)
  local cpu_high_count
  cpu_high_count=$(cat "${STATE}_cpu" 2>/dev/null || echo 0)
  local cpu_pct
  cpu_pct=$(awk -v i="${cpu_idle:-100}" 'BEGIN{print 100-i}')
  if awk -v c="$cpu_pct" -v t="$CPU_ALERT" 'BEGIN{exit !(c>t)}'; then
    cpu_high_count=$((cpu_high_count+1))
    if [ "$cpu_high_count" = 6 ]; then  # 6 amostras = ~30 min sustentado
      tg_send "⚠️ CameraIA: CPU do NAS ≥${CPU_ALERT}% há ~30 min (${cpu_pct}% agora, load ${load5:-?}). Esperado com Jellyfin transcodificando junto. Se travar, pausar scan/transcode do Jellyfin."
    fi
  else
    cpu_high_count=0
  fi
  echo "$cpu_high_count" > "${STATE}_cpu"

  # rotação simples do histórico (mantém 30 dias)
  find "$LOG_DIR" -name "frigate_monitor.csv.*" -mtime +30 -delete 2>/dev/null
  # gzip mensal (1º do mês)
  if [ "$(date '+%d%H')" = "0106" ] && [ -f "$HIST" ]; then
    gzip -c "$HIST" > "$HIST.$(date +%Y%m -d 'last month').gz" && : > "$HIST"
  fi
}

daily() {
  # relatório diário: min/média/max CPU e load, uptime do Frigate, alertas do dia
  local today
  today=$(date '+%Y-%m-%d')
  /usr/bin/python3 - "$HIST" "$today" <<'PYEOF'
import csv, sys, datetime
path, today = sys.argv[1], sys.argv[2]
rows=[]
try:
    with open(path) as f:
        for r in csv.DictReader(f):
            if r['timestamp'].startswith(today):
                rows.append(r)
except FileNotFoundError:
    print("sem histórico")
    sys.exit(0)
if not rows:
    print(f"sem amostras hoje ({today})")
    sys.exit(0)
def fl(k):
    vals=[]
    for r in rows:
        try: vals.append(float(r[k]))
        except: pass
    return vals
cpu=[100-v for v in fl('cpu_idle_pct')]
load=fl('load5')
up=sum(1 for r in rows if r['frigate_up']=='1')
print(f"Período: {rows[0]['timestamp']} → {rows[-1]['timestamp']} ({len(rows)} amostras)")
if cpu: print(f"CPU: min {min(cpu):.0f}% / méd {sum(cpu)/len(cpu):.0f}% / max {max(cpu):.0f}%")
if load: print(f"Load: méd {sum(load)/len(load):.1f} / max {max(load):.1f}")
print(f"Frigate up: {up}/{len(rows)} amostras ({100*up/len(rows):.0f}%)")
PYEOF
}

case "$1" in
  collect) collect ;;
  daily)   daily ;;
  *) echo "uso: $0 {collect|daily}"; exit 1 ;;
esac
