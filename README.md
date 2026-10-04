# CameraIA 📹🧠

Sistema de vigilância com **IA local** — NVR self-hosted baseado em [Frigate](https://frigate.video/), sem nuvem e sem assinatura.

> **Referência:** [NO compres un NVR: monta Frigate y dota de IA a tus cámaras](https://youtu.be/2LC653Mecz8) — Home Assistant y Domótica Fácil. O vídeo monta o Frigate num mini PC (Ryzen 5, 16 GB RAM, SSD 512 GB), resgatando a licença do Windows 11 pré-instalado antes de apagá-lo, e mostra detecção de pessoas ao vivo integrada ao Home Assistant.

## O que é

O Frigate é um NVR open source que roda em Docker e faz **detecção de objetos em tempo real** (pessoa, carro, animal) nos streams RTSP de câmeras IP — mesmo de câmeras "burras". Em vez de alertar por movimento bruto, ele grava e notifica **só quando importa**, e publica cada detecção via MQTT para automações no Home Assistant.

## Roadmap

### Fase 0 — Avaliar o hardware ✅ CONCLUÍDA (26/09/26)
- [x] **DVR: Hikvision DS-7216HQHI-K2** (16ch BNC HDTVI/AHD/CVI/CVBS + até 8 IP, 6 MP, RTSP :554, LAN gigabit)
  - Câmeras coaxiais permanecem nos BNC; DVR as expõe via RTSP:
    main `rtsp://user:pass@IP:554/Streaming/Channels/N01` · sub `...N02`
  - Criar usuário dedicado no DVR para o Frigate (sem privilégios de admin)
  - DVR segue como gravador oficial; Frigate adiciona IA por cima
- [x] **Host do Frigate: QNAP TS-453Be** (Celeron J3455 4-core, 16 GB RAM, iGPU HD 500, 4 baias)
  - x86 + Container Station (Docker) ✅ · OpenVINO na iGPU Gen9 ✅ · VAAPI/QSV ✅
  - 16 GB = Frigate + QTS + busca semântica com folga
  - Limite: J3455 modesto — piloto 4–6 câmeras @5fps no sub-stream, escalar monitorando CPU
  - Gravações do Frigate → storage local do próprio NAS
  - **Acesso à interface via Tailscale:** `https://100.114.5.31:8971`
  - Acesso local alternativo: `https://192.168.2.170:8971`
  - A porta `8971` usa HTTPS; o certificado inicial é autoassinado
- [ ] Instalar Container Station no QTS (se ainda não tiver)
- [x] Criar usuário Frigate no DVR e testar RTSP — **RTSP :554 aberto e autenticando OK (26/09)**; sem imagem porque a **fonte 12V das câmeras queimou** (bloqueio físico pendente). O `Connection reset` nos canais era canal sem vídeo.
- [ ] **Trocar fonte 12V do sistema de câmeras** (bloqueio físico — câmeras off)
- [ ] Revalidar RTSP com câmeras ligadas (`ffprobe rtsp://frigate:...@192.168.2.182/Streaming/Channels/101`)

### Fase 1 — Prova de conceito
- [x] Arquivos de deploy prontos no repo: `frigate/docker-compose.yml` (Frigate + Mosquitto, /dev/dri, pastas /share/Container/frigate) e `frigate/config.yml` (OpenVINO GPU, VAAPI, 4 câmeras piloto, detect 704x480@5fps no sub-stream, retain motion 14d/eventos 30d)
- [ ] No NAS: criar pastas `/share/Container/frigate/{config.yml,media,db,mosquitto}` e subir `docker compose up -d`
- [ ] Validar detecção de pessoa ao vivo
- [ ] Ajustar zonas (`required_zones`) e máscaras

### Fase 2 — Refinamento
- [ ] Criar **zonas** (`required_zones`) — elimina mais falsos alertas que trocar de hardware
- [ ] Criar **máscaras de movimento** (relógio, folhagem)
- [ ] Ajustar retenção de gravações (por detecção, não 24/7)
- [ ] Live view pelo go2rtc (evitar borda verde / problemas de codec)

### Fase 3 — Automação
- [ ] Integração Frigate + Home Assistant (HACS)
- [ ] Automações: notificação com snapshot, acender luz por presença em zona
- [ ] Avaliar busca semântica ("van preta na entrada à noite") — exige 8–16 GB RAM

## Vantagens e desvantagens

### Vantagens
- **Zero assinatura / sem nuvem**: tudo processado e gravado localmente; sem mensalidade, sem depender de servidor do fabricante
- **Privacidade total**: as imagens nunca saem de casa
- **Detecta objetos, não movimento**: dispara só quando é pessoa/carro — quase zero falso positivo
- **Revive câmeras baratas**: qualquer câmera IP com RTSP ganha IA
- **Integração nativa com Home Assistant**: sensores, automações, notificações com snapshot
- **Leve e barato de rodar**: mini PC sem ventilador basta; OpenVINO na iGPU Intel é o detector recomendado hoje

### Desvantagens
- **Curva de aprendizado real**: Docker, config YAML, tuning de zonas/máscaras
- **Exige hardware dedicado ligado 24/7** — e aceleração de hardware importa: só CPU não escala (caso real: 9 câmeras = 80–115% CPU; com iGPU + OpenVINO → 25–40%)
- **Live view e streams dão trabalho**: bordas verdes, formatos, ajuste go2rtc/proporção
- **Armazenamento**: gravação por detecção ou 24/7 consome disco rápido (NAS/SSD)
- **Sem suporte oficial**: comunidade/GitHub, sem SLA
- **Câmeras só-Wi-Fi/app de nuvem (sem RTSP) não servem**

## Referências
- Vídeo: https://youtu.be/2LC653Mecz8
- Frigate: https://frigate.video/ · GitHub: https://github.com/blakeblackshear/frigate
- Detectors suportados (2026): OpenVINO (iGPU Intel) > Hailo-8 (M.2) > ONNX (GPU NVIDIA/AMD) > Coral (reserva) — evitar `cpu`
