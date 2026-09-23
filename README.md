# CameraIA 📹🧠

Sistema de vigilância com **IA local** — NVR self-hosted baseado em [Frigate](https://frigate.video/), sem nuvem e sem assinatura.

> **Referência:** [NO compres un NVR: monta Frigate y dota de IA a tus cámaras](https://youtu.be/2LC653Mecz8) — Home Assistant y Domótica Fácil. O vídeo monta o Frigate num mini PC (Ryzen 5, 16 GB RAM, SSD 512 GB), resgatando a licença do Windows 11 pré-instalado antes de apagá-lo, e mostra detecção de pessoas ao vivo integrada ao Home Assistant.

## O que é

O Frigate é um NVR open source que roda em Docker e faz **detecção de objetos em tempo real** (pessoa, carro, animal) nos streams RTSP de câmeras IP — mesmo de câmeras "burras". Em vez de alertar por movimento bruto, ele grava e notifica **só quando importa**, e publica cada detecção via MQTT para automações no Home Assistant.

## Roadmap

### Fase 0 — Avaliar o hardware atual ✅ primeiro passo
- [ ] Inventariar o hardware disponível na rede (mini PC / Raspberry Pi / NAS / PC velho)
- [ ] Verificar CPU: Intel ≥ 6ª geração? → detector **OpenVINO na iGPU** (recomendado, zero custo extra)
- [ ] Verificar GPU dedicada NVIDIA/AMD? → detector **ONNX**
- [ ] Sem acelerador e consumo for restrição rígida? → **Coral USB** (só como reserva; não é mais o padrão)
- [ ] Testar decodificação de vídeo por hardware (VAAPI/QSV/NVDEC) — o Coral só acelera a IA, não o decode
- [ ] Mínimo prático: CPU x86, 8 GB RAM (16 GB p/ busca semântica), SSD/NAS p/ gravações
- [ ] **Evitar detector `cpu` puro** — OpenVINO em modo CPU já é mais eficiente

### Fase 1 — Prova de conceito
- [ ] Instalar Frigate via Docker Compose (+ broker MQTT Mosquitto)
- [ ] Conectar 1 câmera RTSP com **dois streams**: sub-stream 720p@5fps p/ detectar, stream principal p/ gravar
- [ ] Detecção de pessoa ao vivo validada

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
