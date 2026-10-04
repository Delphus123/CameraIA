#!/bin/bash
# ============================================================
# CameraIA — Deploy do Frigate no QNAP TS-453Be (Container Station)
# Rodar via SSH no NAS (Container Station → Terminal) como admin.
# Requer: Container Station instalado (✅) e fonte 12V das câmeras OK.
# ============================================================
set -e
BASE=/share/Container/frigate
mkdir -p $BASE/media $BASE/db $BASE/mosquitto

# baixar configs do repo público
curl -fsSL -o $BASE/config.yml https://raw.githubusercontent.com/Delphus123/CameraIA/master/frigate/config.yml
curl -fsSL -o $BASE/docker-compose.yml https://raw.githubusercontent.com/Delphus123/CameraIA/master/frigate/docker-compose.yml

# conferir iGPU visível (precisa listar renderD128)
ls -la /dev/dri/ || echo "ATENÇÃO: /dev/dri ausente — iGPU não exposta"

# subir
cd $BASE && docker compose up -d
sleep 25
docker compose ps
docker logs frigate 2>&1 | tail -15
echo "=== UI: http://$(hostname -I | awk '{print $1}'):8971 ==="
