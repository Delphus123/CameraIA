"""Frigate -> Telegram: alerta imediato + descrição GenAI local (Moondream, imagem única).

Desenho (N150 CPU): o GenAI nativo do Frigate ficou inviável (seq. de thumbnails =
2-7k tokens; qwen lenta demais p/ timeout 120s; moondream não passa de ctx 2048).
Este bridge faz o caminho próprio: no fim do evento envia a FOTO na hora e chama o
Ollama diretamente com UM snapshot (~900 tokens, cabe no ctx do moondream, ~35s).
A descrição (em inglês, decisão do Rafael) vai como mensagem de acompanhamento.

Deploy: docker compose up -d --build (rede frigate_default, junto do frigate/mqtt).
"""

import json
import os
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

import paho.mqtt.client as mqtt

FRIGATE_API = os.environ.get("FRIGATE_API", "http://frigate:5000")
MQTT_HOST = os.environ.get("MQTT_HOST", "mqtt")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://ollama-vlm:11434")
GENAI_MODEL = os.environ.get("GENAI_MODEL", "moondream")
GENAI_PROMPT = os.environ.get(
    "GENAI_PROMPT",
    "Describe this security camera snapshot concisely: what is visible, what any "
    "person/vehicle is doing, and notable details (clothing, objects). Plain English, max 2 sentences.",
)
LABELS = set(x.strip() for x in os.environ.get("LABELS", "person,car,motorcycle").split(","))
CAMERAS = set(x.strip() for x in os.environ.get("CAMERAS", "").split(",") if x.strip())
DESC_TIMEOUT = int(os.environ.get("DESC_TIMEOUT", "120"))
COOLDOWN = int(os.environ.get("COOLDOWN", "300"))           # s por camera+label
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")

_last_sent: dict[str, float] = {}


def tg(method: str, **params):
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/{method}"
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(url, data=data)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def tg_send_photo(photo_url: str, caption: str):
    """Envia a foto do evento direto da API do Frigate via multipart."""
    import uuid

    boundary = uuid.uuid4().hex
    with urllib.request.urlopen(photo_url, timeout=30) as r:
        image = r.read()
    parts = []
    for name, value in (("chat_id", TELEGRAM_CHAT_ID), ("caption", caption[:1024])):
        parts.append(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n".encode()
        )
    parts.append(
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"event.jpg\"\r\n"
        f"Content-Type: image/jpeg\r\n\r\n".encode() + image + b"\r\n"
    )
    body = b"".join(parts) + f"--{boundary}--\r\n".encode()
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendPhoto"
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def generate_description(event_id: str) -> str:
    """Chama o Ollama com UM snapshot do evento (cabe no contexto do moondream)."""
    import base64

    snap_url = f"{FRIGATE_API}/api/events/{event_id}/snapshot.jpg?width=480"
    with urllib.request.urlopen(snap_url, timeout=30) as r:
        img_b64 = base64.b64encode(r.read()).decode()
    body = json.dumps({
        "model": GENAI_MODEL,
        "prompt": GENAI_PROMPT,
        "images": [img_b64],
        "stream": False,
        "keep_alive": 0,
        # num_predict corta os loops de repetição do Moondream; repeat_penalty/
        # temperature ESTRANHAMENTE matam a geração (6-1 tokens) — não usar.
        "options": {"num_predict": 100},
    }).encode()
    req = urllib.request.Request(
        f"{OLLAMA_URL}/api/generate", data=body,
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=DESC_TIMEOUT) as r:
        resp = json.loads(r.read())
    return (resp.get("response") or "").strip()


def send_alert(camera: str, label: str, event_id: str):
    when = time.strftime("%d/%m %H:%M:%S")
    caption = f"📹 {camera} — {label} — {when}"
    photo = f"{FRIGATE_API}/api/events/{event_id}/snapshot.jpg"
    try:
        tg_send_photo(photo, caption)
    except Exception as e:  # foto falhou -> manda texto
        print(f"sendPhoto falhou ({e}); enviando só texto", flush=True)
        tg("sendMessage", chat_id=TELEGRAM_CHAT_ID, text=caption)
    print(f"alerta enviado: {camera} {label} {event_id}", flush=True)

    # descrição como acompanhamento — não bloqueia o alerta
    try:
        desc = generate_description(event_id)
        if desc:
            tg("sendMessage", chat_id=TELEGRAM_CHAT_ID,
               text=f"🤖 {camera} — {label}:\n{desc[:1500]}")
            print(f"descrição enviada para {event_id}", flush=True)
    except Exception as e:
        print(f"descrição falhou para {event_id}: {e}", flush=True)


def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload)
    except json.JSONDecodeError:
        return
    after = payload.get("after", payload)
    camera, label, event_id = after.get("camera"), after.get("label"), after.get("id")
    if not (camera and label and event_id):
        return
    if label not in LABELS:
        return
    if CAMERAS and camera not in CAMERAS:
        return
    # só eventos FINALIZADOS (end de verdade, não heartbeat de update)
    if payload.get("type") not in ("end", None) or not after.get("end_time"):
        return
    key = f"{camera}:{label}"
    now = time.time()
    if now - _last_sent.get(key, 0) < COOLDOWN:
        print(f"cooldown ativo, descartado: {key}", flush=True)
        return
    _last_sent[key] = now
    threading.Thread(
        target=send_alert, args=(camera, label, event_id), daemon=True
    ).start()


def main():
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        sys.exit("TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID não definidos")
    if "--test" in sys.argv:
        tg("sendMessage", chat_id=TELEGRAM_CHAT_ID,
           text="🧪 Teste ai-notify: bridge Frigate→Telegram operacional.")
        print("mensagem de teste enviada")
        return
    cli = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    cli.on_message = on_message
    cli.on_connect = lambda c, u, f, rc, p=None: (
        c.subscribe("frigate/events"),
        print("conectado ao MQTT, inscrito em frigate/events", flush=True),
    )
    cli.connect(MQTT_HOST, 1883, keepalive=60)
    cli.loop_forever()


if __name__ == "__main__":
    main()
