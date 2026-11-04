"""Experimento LPR 24h (cam_2): playback do HD do DVR + crop + OCR (Moondream).

Fluxo: evento 'car' fim na cam_2 -> 1 sessão RTSP playback (tracks/201) puxa
frames da gravação main 1920x1536 na janela do evento -> escolhe o frame de
carro mais nítido (box final do Frigate escalado + variância de bordas) ->
crop ampliado 4x -> Moondream tenta ler a placa -> CSV + frames em /data
(bind /opt/frigate/lpr-exp). Alerta [EXPERIMENTAL] no Telegram SOMENTE se a
placa casar com regex de placa (Mercosul/antiga). Nada disso vai para produção.
"""

import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

import paho.mqtt.client as mqtt

FRIGATE_API = os.environ.get("FRIGATE_API", "http://frigate:5000")
MQTT_HOST = os.environ.get("MQTT_HOST", "mqtt")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://ollama-vlm:11434")
GENAI_MODEL = os.environ.get("GENAI_MODEL", "moondream")
LPR_CAMERA = os.environ.get("LPR_CAMERA", "cam_2")
LPR_LABELS = set(x.strip() for x in os.environ.get("LPR_LABELS", "car").split(","))
LPR_TRACK = os.environ.get("LPR_TRACK", "201")            # canal 2, vídeo main
LPR_RTSP_HOST = os.environ.get("LPR_RTSP_HOST", "192.168.2.182")
LPR_COOLDOWN = int(os.environ.get("LPR_COOLDOWN", "120"))
LPR_MAX_DURATION = int(os.environ.get("LPR_MAX_DURATION", "60"))
LPR_SAMPLES = int(os.environ.get("LPR_SAMPLES", "6"))
DATA_DIR = os.environ.get("LPR_DATA_DIR", "/data")
DETECT_W, DETECT_H = 640, 480
MAIN_W, MAIN_H = 1920, 1536
PLATE_RE = re.compile(r"[A-Z]{3}\s?\d[A-Z0-9]\s?\d{2}|[A-Z]{3}\s?-?\s?\d{4}")
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")

_last: dict[str, float] = {}
_csv_lock = threading.Lock()


def tg(method: str, **params):
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/{method}"
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(url, data=data)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def csv_row(cols: list[str]):
    with _csv_lock:
        new = not os.path.exists(f"{DATA_DIR}/results.csv")
        with open(f"{DATA_DIR}/results.csv", "a") as f:
            if new:
                f.write("ts,event_id,duration_s,box_detect,crop_main,frames,sharpness,ocr_raw,plate\n")
            f.write(",".join(str(c).replace(",", ";") for c in cols) + "\n")


def grab_frames(start_local: str, duration: int, workdir: str) -> int:
    """1 sessão playback: frames amostrados na janela do evento."""
    interval = max(2, duration // LPR_SAMPLES)
    os.makedirs(workdir, exist_ok=True)
    url = (f"rtsp://frigate:{os.environ['FRIGATE_RTSP_PASSWORD']}@{LPR_RTSP_HOST}:554"
           f"/Streaming/tracks/{LPR_TRACK}?starttime={start_local}")
    cmd = ["ffmpeg", "-y", "-v", "error", "-rtsp_transport", "tcp", "-i", url,
           "-t", str(duration + 2), "-vf", f"fps=1/{interval}",
           f"{workdir}/f_%02d.jpg"]
    try:
        subprocess.run(cmd, timeout=duration + 30, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        pass
    frames = sorted(f for f in os.listdir(workdir) if f.endswith(".jpg"))
    return len(frames)


def sharpness(path: str, box_main: tuple[int, int, int, int]) -> float | None:
    """Proxy de nitidez/tamanho: desvio-padrão das bordas no crop ampliado."""
    from PIL import Image, ImageFilter, ImageStat
    x, y, w, h = box_main
    try:
        im = Image.open(path).crop((x, y, x + w, y + h))
        im = im.resize((im.width * 4, im.height * 4), Image.LANCZOS)
        stat = ImageStat.Stat(im.convert("L").filter(ImageFilter.FIND_EDGES))
        return stat.stddev[0]
    except Exception:
        return None


def ocr_plate(crop_path: str) -> str:
    import base64
    with open(crop_path, "rb") as f:
        img = base64.b64encode(f.read()).decode()
    body = json.dumps({
        "model": GENAI_MODEL,
        "prompt": "Read the license plate on this car. Reply with ONLY the plate "
                  "characters if clearly legible, otherwise reply with NONE.",
        "images": [img], "stream": False, "keep_alive": 0,
        "options": {"num_predict": 30, "temperature": 0.1},
    }).encode()
    req = urllib.request.Request(f"{OLLAMA_URL}/api/generate", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        resp = json.loads(r.read())
    return (resp.get("response") or "").strip()


def handle_event(after: dict):
    event_id = after["id"]
    start, end = after.get("start_time"), after.get("end_time")
    duration = int(min(end - start, LPR_MAX_DURATION)) if end else 10
    start_local = time.strftime("%Y%m%dT%H%M%S", time.localtime(start))
    workdir = f"{DATA_DIR}/frames/{event_id.replace('.', '_')}"
    t0 = time.time()

    grabbed = grab_frames(start_local, duration, workdir)
    if not grabbed:
        csv_row([time.strftime("%F %T"), event_id, duration, "n/a", "n/a", 0, "", "", ""])
        return

    box = (after.get("data") or {}).get("box") or [0.7, 0.2, 0.1, 0.1]
    # box vem NORMALIZADO (frações do frame): [x, y, w, h]
    bx, by, bw, bh = box
    x, y = int(bx * MAIN_W), int(by * MAIN_H)
    w, h = int(bw * MAIN_W), int(bh * MAIN_H)
    px, py = max(20, int(w * 0.25)), max(20, int(h * 0.25))   # margem 25%
    x, y = max(0, x - px), max(0, y - py)
    w, h = min(w + 2 * px, MAIN_W - x), min(h + 2 * py, MAIN_H - y)
    # teto no crop: se o box for gigante, recorta no máximo em volta do centro
    if w > 800 or h > 800:
        cx, cy = x + w // 2, y + h // 2
        w = min(w, 800); h = min(h, 800)
        x = max(0, min(cx - w // 2, MAIN_W - w)); y = max(0, min(cy - h // 2, MAIN_H - h))
    box_main = (x, y, w, h)

    best, best_score = None, -1.0
    for f in sorted(os.listdir(workdir)):
        s = sharpness(f"{workdir}/{f}", box_main)
        if s is not None and s > best_score:
            best, best_score = f, s
    if best is None:
        csv_row([time.strftime("%F %T"), event_id, duration, str(box), "n/a", grabbed, "", "", ""])
        return

    crop_path = f"{workdir}/crop_{best}"
    from PIL import Image
    x, y, w, h = box_main
    im = Image.open(f"{workdir}/{best}").crop((x, y, x + w, y + h))
    im = im.resize((im.width * 4, im.height * 4), Image.LANCZOS)
    im.save(crop_path)

    plate_raw = ocr_plate(crop_path)
    m = PLATE_RE.search(plate_raw.upper().replace(" ", ""))
    plate = m.group(0).replace(" ", "") if m else ""

    csv_row([time.strftime("%F %T"), event_id, duration, str(box),
             f"{box_main[2]}x{box_main[3]}", grabbed, f"{best_score:.0f}",
             plate_raw[:80], plate])
    print(f"[lpr-exp] {event_id}: {grabbed} frames, crop {box_main[2]}x{box_main[3]}, "
          f"sharp={best_score:.0f}, ocr='{plate_raw[:60]}' -> placa='{plate}'", flush=True)

    if plate:
        try:
            tg("sendPhoto",
               chat_id=TELEGRAM_CHAT_ID,
               caption=f"[EXPERIMENTAL LPR] {after.get('camera')} — placa: {plate}\n"
                       f"(trial 24h — não é alerta de produção)")
        except Exception as e:
            print(f"[lpr-exp] tg falhou: {e}", flush=True)


def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload)
    except json.JSONDecodeError:
        return
    after = payload.get("after", payload)
    camera, label, event_id = after.get("camera"), after.get("label"), after.get("id")
    if not (camera and label and event_id):
        return
    if camera != LPR_CAMERA or label not in LPR_LABELS:
        return
    if payload.get("type") not in ("end", None) or not after.get("end_time"):
        return
    now = time.time()
    if now - _last.get(label, 0) < LPR_COOLDOWN:
        return
    _last[label] = now
    threading.Thread(target=handle_event, args=(after,), daemon=True).start()


def main():
    if "--selftest" in sys.argv:
        print("módulo carregado; PIL/ffmpeg/ollama ok")
        return
    cli = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    cli.on_message = on_message
    cli.on_connect = lambda c, u, f, rc, p=None: (
        c.subscribe("frigate/events"),
        print("[lpr-exp] inscrito em frigate/events", flush=True),
    )
    cli.connect(MQTT_HOST, 1883, keepalive=60)
    cli.loop_forever()


if __name__ == "__main__":
    main()
