#!/bin/bash
# CameraIA — monitor de saúde do Frigate (BMax B4 Turbo) — v0.3.4
# Coleta CPU/load/mem do BMax + stats do Frigate, alerta Telegram em anomalias,
# e grava histórico local p/ relatório diário. Cron a cada 5 min.
# Uso: frigate_monitor.sh collect  |  frigate_monitor.sh daily
#
# 17/10/26: Frigate migrado do QNAP p/ o BMax. A API agora é consultada DIRETO
# por HTTP (porta 5000 aberta na LAN, sem auth) — sem SSH p/ o API. O SSH ao
# BMax só serve para métricas do host (locale-independent: /proc/*).
#
# ATENÇÃO: o path do medidor é o host do FRIGATE, não o NAS. Se um dia o
# Frigate voltar pro QNAP, troque FRIGATE_HOST/SSH_HOST de volta.

FRIGATE_HOST="192.168.2.174"
SSH_HOST="hal9000@192.168.2.174"
FRIGATE_API="http://${FRIGATE_HOST}:5000"
NFS_PATH="/mnt/frigate-media"
LOG_DIR="$HOME/logs"
HIST="$LOG_DIR/frigate_monitor.csv"
TG_TOKEN_FILE="$HOME/backups/get-tg-token.sh"
CHAT_ID="111597747"
CPU_ALERT=85          # %CPU total do BMax
LOAD_ALERT=6          # load avg 5min (4 threads no N150)
MEM_ALERT=90          # %mem usada (excl. cache)
DISK_ALERT=10         # % livre mínimo no NFS de gravações
FRIGATE_DOWN_STREAK=2 # amostras consecutivas p/ alertar Frigate down
CAMS_BAD_STREAK=3     # amostras consecutivas com câmera sem fps (15 min)
STATE="/tmp/frigate_monitor_state"

mkdir -p "$LOG_DIR"

ssh_host() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$SSH_HOST" "$@" 2>/dev/null
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
  local ts cpu_pct load5 mem_pct disk_free stats_json up

  ts=$(date '+%Y-%m-%d %H:%M')

  # ---- métricas do host do Frigate (Debian: /proc, sem depender de locale) ----
  read -r cpu_pct load5 mem_pct disk_free <<< "$(ssh_host '
    read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat
    sleep 2
    read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat
    du=$(( (u2+n2+s2+i2+w2+q2+sq2+st2) - (u1+n1+s1+i1+w1+q1+sq1+st1) ))
    di=$(( (i2+w2) - (i1+w1) ))
    cpu=$(( du>0 ? 100*(du-di)/du : 0 ))
    load=$(cut -d" " -f2 /proc/loadavg)
    mem=$(awk "/MemTotal/{t=\$2}/MemAvailable/{a=\$2}END{printf \"%d\", (t-a)*100/t}" /proc/meminfo)
    disk=$(df --output=pcent "'"$NFS_PATH"'" 2>/dev/null | tail -1 | tr -dc "0-9")
    [ -z "$disk" ] && disk="NA"
    [ -n "$disk" ] && disk=$(( 100 - disk ))
    echo "$cpu $load $mem $disk"
  ')"

  # ---- stats do Frigate (HTTP direto na LAN) ----
  stats_json=$(curl -s --max-time 8 "${FRIGATE_API}/api/stats")
  up="0"
  [ -n "$stats_json" ] && echo "$stats_json" | grep -q "camera_fps" && up="1"

  local det_fps="0" cam_ok="0" proc_fps_sum="0" cams_bad="" cams_bad_n="0"
  if [ "$up" = "1" ]; then
    read -r det_fps cam_ok proc_fps_sum cams_bad_n cams_bad <<< "$(echo "$stats_json" | /usr/bin/python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    det=round(sum(v.get('detection_fps',0) for v in d.get('detectors',{}).values()),1)
    cams=d.get('cameras',{})
    ok=sum(1 for v in cams.values() if v.get('camera_fps',0)>1)
    pfs=round(sum(v.get('process_fps',0) for v in cams.values()),1)
    bad=[c for c,v in cams.items() if v.get('camera_fps',0)<=1]
    print(det, ok, pfs, len(bad), ','.join(sorted(bad)) or '-')
except Exception:
    print('0 0 0 0 -')
" 2>/dev/null)"
  fi

  # ---- histórico ----
  [ -f "$HIST" ] || echo "timestamp,cpu_pct,load5,mem_used_pct,frigate_up,detector_fps,cameras_ok,process_fps,cameras_bad,nfs_free_pct" >> "$HIST"
  echo "$ts,${cpu_pct:-NA},${load5:-NA},${mem_pct:-NA},$up,${det_fps:-0},${cam_ok:-0},${proc_fps_sum:-0},${cams_bad_n:-0},${disk_free:-NA}" >> "$HIST"

  # ---- alerta: Frigate sem resposta ----
  local down_count=0
  [ -f "$STATE" ] && down_count=$(cat "$STATE")
  if [ "$up" != "1" ]; then
    down_count=$((down_count+1))
    echo "$down_count" > "$STATE"
    if [ "$down_count" = "$FRIGATE_DOWN_STREAK" ]; then
      tg_send "🚨 CameraIA: Frigate SEM resposta em ${FRIGATE_HOST}:5000 ($down_count amostras). CPU=${cpu_pct:-?}% load=${load5:-?} mem=${mem_pct:-?}%. Verificar 'docker ps' no BMax."
    fi
  else
    if [ "$down_count" -ge "$FRIGATE_DOWN_STREAK" ] 2>/dev/null; then
      tg_send "✅ CameraIA: Frigate voltou a responder (${cam_ok} câmeras ativas, detector ${det_fps} fps)."
    fi
    echo "0" > "$STATE"
  fi

  # ---- alerta: CPU alta sustentada (~30 min) ----
  local cpu_high_count cpu_pct_alert
  cpu_high_count=$(cat "${STATE}_cpu" 2>/dev/null || echo 0)
  cpu_pct_alert=${cpu_pct:-0}
  if awk -v c="$cpu_pct_alert" -v t="$CPU_ALERT" 'BEGIN{exit !(c>t)}'; then
    cpu_high_count=$((cpu_high_count+1))
    if [ "$cpu_high_count" = 6 ]; then
      tg_send "⚠️ CameraIA: CPU do BMax ≥${CPU_ALERT}% há ~30 min (${cpu_pct_alert}% agora, load ${load5:-?}). Verificar transcodes/Jellyfin e processos ffmpeg."
    fi
  else
    cpu_high_count=0
  fi
  echo "$cpu_high_count" > "${STATE}_cpu"

  # ---- alerta: câmera sem fps (DVR/RTSP) ----
  local cams_bad_count
  cams_bad_count=$(cat "${STATE}_cams" 2>/dev/null || echo 0)
  if [ "$up" = "1" ] && [ "${cams_bad_n:-0}" -gt 0 ] 2>/dev/null; then
    cams_bad_count=$((cams_bad_count+1))
    if [ "$cams_bad_count" = "$CAMS_BAD_STREAK" ]; then
      tg_send "⚠️ CameraIA: ${cams_bad_n} câmera(s) sem fps há ~15 min (${cams_bad}). Suspeitar de sessão RTSP do DVR, encoder ou rede antes de culpar o Frigate."
    fi
  else
    cams_bad_count=0
  fi
  echo "$cams_bad_count" > "${STATE}_cams"

  # ---- alerta: métricas do host cegas (SSH ao BMax falhando) ----
  # Lição 17/10: sshd do BMax caiu com o Frigate 100% saudável; o CSV virou NA
  # em cpu/mem e ninguém foi avisado (só percebi ao tentar entrar).
  local ssh_count
  ssh_count=$(cat "${STATE}_ssh" 2>/dev/null || echo 0)
  if [ "${cpu_pct:-NA}" = "NA" ] || [ -z "${cpu_pct:-}" ]; then
    ssh_count=$((ssh_count+1))
    if [ "$ssh_count" = 3 ]; then
      tg_send "⚠️ CameraIA: sem métricas do host há ~15 min (SSH ${SSH_HOST} falhando). O Frigate responde? $( [ "$up" = "1" ] && echo "sim, API ok — problema é o sshd" || echo "NÃO — verificar o host" )."
    fi
  else
    ssh_count=0
  fi
  echo "$ssh_count" > "${STATE}_ssh"

  # ---- alerta: espaço no NFS de gravações ----
  local disk_count
  disk_count=$(cat "${STATE}_disk" 2>/dev/null || echo 0)
  if [ "${disk_free:-NA}" != "NA" ] && [ "${disk_free:-100}" -lt "$DISK_ALERT" ] 2>/dev/null; then
    disk_count=$((disk_count+1))
    if [ "$disk_count" = 12 ]; then  # ~1h
      tg_send "⚠️ CameraIA: NFS de gravações com apenas ${disk_free}% livre (${NFS_PATH}). Baixar retenção no config do Frigate."
    fi
  else
    disk_count=0
  fi
  echo "$disk_count" > "${STATE}_disk"

  # ---- rotação do histórico (30 dias) / gzip mensal ----
  find "$LOG_DIR" -name "frigate_monitor.csv.*" -mtime +30 -delete 2>/dev/null
  if [ "$(date '+%d%H')" = "0106" ] && [ -f "$HIST" ]; then
    gzip -c "$HIST" > "$HIST.$(date +%Y%m -d 'last month').gz" && : > "$HIST"
  fi
}

daily() {
  local today
  today=$(date '+%Y-%m-%d')
  /usr/bin/python3 - "$HIST" "$today" <<'PYEOF'
import csv, sys
path, today = sys.argv[1], sys.argv[2]
rows = []
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
    vals = []
    for r in rows:
        try:
            vals.append(float(r[k]))
        except (KeyError, TypeError, ValueError):
            pass
    return vals

cpu = fl('cpu_pct')
load = fl('load5')
mem = fl('mem_used_pct')
up = sum(1 for r in rows if r['frigate_up'] == '1')
cams = fl('cameras_ok')
bad = fl('cameras_bad')
det = fl('detector_fps')
disk = fl('nfs_free_pct')

print(f"Período: {rows[0]['timestamp']} → {rows[-1]['timestamp']} ({len(rows)} amostras)")
if cpu:  print(f"CPU BMax: min {min(cpu):.0f}% / méd {sum(cpu)/len(cpu):.0f}% / max {max(cpu):.0f}%")
if load: print(f"Load:     méd {sum(load)/len(load):.1f} / max {max(load):.1f}")
if mem:  print(f"RAM:      méd {sum(mem)/len(mem):.0f}% / max {max(mem):.0f}%")
print(f"Frigate up: {up}/{len(rows)} amostras ({100*up/len(rows):.0f}%)")
if cams: print(f"Câmeras com fps (mín): {min(cams):.0f}")
if bad:  print(f"Amostras com câmera sem fps: {sum(1 for v in bad if v > 0)}/{len(bad)}")
if det:  print(f"Detector: méd {sum(det)/len(det):.1f} fps / max {max(det):.1f} fps")
if disk: print(f"NFS livre (mín): {min(disk):.0f}%")
PYEOF
}

case "$1" in
  collect) collect ;;
  daily)   daily ;;
  *) echo "uso: $0 {collect|daily}"; exit 1 ;;
esac
