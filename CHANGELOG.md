# Changelog — CameraIA

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), versionamento semântico.

> Histórico anterior (Fase 0–1: piloto 4 câmeras, gravação main H.264, fix do modelo 300x300) precede este changelog — ver `git log`.

## [0.4.3] — 2026-11-04

### Documentado

- `docs/lpr-cam-recomendacao.md`: recomendação registrada de câmera LPR via
  coaxial para futuro ponto de leitura de placas — DS-2CE16H8-TIT3Z (5MP TVI
  varifocal 2.8-12mm, ~R$ 400-600), com plano de instalação, alternativas
  avaliadas (DS-TCG405/406-E ANPR embarcado; captura TVI 1080p de terceiros;
  TVI box + C-mount) e limitações medidas da cam_2 atual.

### Corrigido

- **lpr-exp**: `box` do evento vem NORMALIZADO (frações do frame), não em
  pixels — o crop saía do tamanho do frame inteiro; agora converte por
  `MAIN_W/H`, com margem 25% e teto de 800 px no lado do crop. CSV coerced
  para str (crash com ints nos 2 primeiros eventos).

## [0.4.2] — 2026-11-04

### Adicionado

- **Experimento LPR 24h** (`frigate/ai-notify/lpr_experiment.py`, container
  `lpr-exp`): no fim de cada evento `car` na cam_2, um playback RTSP único
  (`Streaming/tracks/201`) puxa da gravação main 1920×1536 do DVR ~6 frames
  da janela do evento; escolhe o de carro mais nítido (box final escalado +
  variância de bordas), faz crop 4× e tenta ler a placa com o Moondream.
  Resultados em `/opt/frigate/lpr-exp/results.csv` + frames; alerta
  `[EXPERIMENTAL]` no Telegram somente se a placa casar Mercosul/antiga.
  Pré-requisitos validados 04/11/26: relógio do DVR corrigido (em sync c/
  BMax), playback RTSP do HD funcional (downtime de teste: 23 s), main
  confirmado H.264 1920×1536@15fps. Placa de carro longe ≈ 30-35 px no main
  (abaixo dos 60-100 px de OCR confiável) — experimento mede a taxa real de
  leitura em 24h de tráfego.

## [0.4.1] — 2026-11-04

### Alterado

- **ai-notify restrito a cam_1/cam_2** (`CAMERAS=cam_1,cam_2`) — fase de
  monitoramento decidida pelo Rafael.
- **Car removido dos alertas** (`LABELS=person,motorcycle`): carros parados
  geravam notificação sem valor. Veredito técnico anexado ao config: placa de
  carro em movimento na cam_2 ocupa ~10 px na sub-stream 960×480 (zoom real
  medido) — OCR de placa precisa de ~60–100 px; leitura de placa exigirá
  main stream (ou câmera dedicada de LPR) no futuro.

## [0.4.0] — 2026-11-04

### Adicionado

- **Alertas de evento no Telegram com descrição GenAI local** (`frigate/ai-notify/`):
  bridge MQTT→Telegram que, no fim de cada evento `person`/`car`/`motorcycle`,
  envia a foto do snapshot imediatamente e a descrição em inglês (decisão do
  Rafael) como mensagem de acompanhamento, gerada pelo Moondream no Ollama
  local (`frigate/ollama-vlm/docker-compose.yml`, container `ollama-vlm`,
  rede `frigate_default`, API só em loopback no host :11435). Cooldown de
  300 s por câmera+label; token do bot em `/opt/frigate/ai-notify.env`
  (chmod 600, fora do repo). Token budget medido: snapshot único ≈ 900 tokens
  (cabe no contexto nativo 2048 do Moondream); descrição em ~35 s no N150,
  pico 738 MiB RAM.
- `snapshots.enabled: true` no Frigate (qualidade 80) — exigido pelo bridge
  (foto + snapshot do evento).

### Alterado

- `objects.track`: sincronizado com produção (adicionado `motorcycle`, que
  estava só no config deployado via UI).
- GenAI nativo do Frigate avaliado e **mantido desligado** (`objects.genai.
  enabled: false`): sequências de thumbnails geram 2.2–7.3k tokens — acima do
  contexto nativo do Moondream (2048) e acima do timeout de 120 s do cliente
  Frigate com Qwen2.5-VL-3B no N150 (3–10 min de inferência). Benchmarks
  documentados nos comentários do config; rollback documentado inline.

## [0.3.10] — 2026-10-18

### Alterado

- **Monitor local, sem SSH** (`frigate_monitor.sh`): com o Pi desativado, o
  monitor roda no próprio BMax e lê as métricas do host direto de `/proc` —
  removida a volta por `sshd@localhost` (dependência frágil: sshd caiu em
  17/10 com Frigate saudável e o CSV virou NA sem alerta). Alerta de métricas
  cegas repaginado para leitura local. Validado: collect com CPU/load/mem/4
  câmeras, zero NA.

## [0.3.9] — 2026-10-18

### Adicionado

- `jellyfin/jellyfin-trickplay-window.sh`: aborta a task "Generate Trickplay
  Images" do Jellyfin às 05:00 (cron), confinando o trickplay à janela 0h–5h.
  O trigger diário já inicia ~00:01; a extração é incremental, então o excedente
  retoma na noite seguinte. Autentica lendo a API key direto do DB
  (`ApiKeys.AccessToken`, header `Authorization: MediaBrowser Token=` — o
  `X-Emby-Token` devolve 401). Notifica Telegram em sucesso e falha.

## [0.3.8] — 2026-10-18

### Alterado

- **Detector do Frigate CPU→GPU**: OpenVINO passa a inferir na iGPU do N150
  (`detectors.ov.device: GPU`, iGPU 24EU) para aliviar a CPU. Medido em
  produção: processo do detector caiu de ~147% para ~17% CPU, load 5min de
  2,5 → 0,7; 4/4 câmeras a 5fps, detection_fps 5,5, decode VAAPI intacto e sem
  erros -38. Rollback: `device: CPU` (backup em
  `/opt/frigate/configdir/config.yml.pre-gpu-20261018`).
- Config de produção sincronizado no repo: schema `record:` de retenção
  (alerts/detections 30d, continuous 0, motion 14d), `lpr` e `version 0.18-0`
  que estavam só no `/opt/frigate/configdir`.

## [0.3.7] — 2026-10-17

### Alterado

- **Jellyfin migrado do QNAP para o BMax** (host network, `/dev/dri`, config
  local em `/opt/jellyfin`): 1,9G de config copiados, 3.261 itens e 5
  bibliotecas preservadas (Filmes, Shows, Documentarios, Livros e Cursos,
  Series), mídia lida por NFS do share `Multimedia` (1,3T). QNAP com o
  container parado (`Exited 0`) como rollback.

### Corrigido

- Volume do Jellyfin apontava para o share raiz (`/mnt/multimedia`), então o
  container via as pastas erradas e a biblioteca ficava vazia; o correto é
  `/mnt/multimedia/Videos`.
- fstab do BMax: os dois NFS deixaram de usar `x-systemd.automount`. Com bind
  mount de container o automount expira por inatividade e o container passa a
  enxergar a pasta vazia por baixo do mount — sintoma idêntico a "arquivos
  desapareceram". Agora são mounts permanentes com `nofail`.

### Validado

- Jellyfin 12.2.0 healthy em ~40s, `/health` 200, 500/500 itens amostrados do
  banco existem no disco, LibraryMonitor assistindo as 5 pastas.
- Transcode QSV no N150 com o ffmpeg do próprio Jellyfin: 1080p x264 → 720p
  h264_qsv a 277 fps / **11,6× tempo real**; saída hevc_qsv e h264_qsv
  confirmadas por ffprobe (1280×720).
- Frigate segue saudável após a mudança de fstab: 4/4 câmeras em 5 fps e 63
  segmentos novos em 3 min no NFS.

## [0.3.6] — 2026-10-17

### Corrigido

- Monitor falava com o BMax na porta 22 e passou a registrar `NA` em CPU/RAM
  quando o sshd foi movido para a **2048** (padrão da casa). `SSH_PORT=2048`
  no script.
- Criado `~/.ssh/config` no Pi com os aliases `bmax`/`bmaxb4` (host, porta 2048,
  usuário, chave), para não errar a porta em comandos manuais.

## [0.3.5] — 2026-10-17

### Adicionado

- `jellyfin/docker-compose.bmax.yml`: stack do Jellyfin para o BMax (host network,
  `/dev/dri` p/ Quick Sync, config/cache locais em `/opt/jellyfin`, mídia por NFS
  em `/mnt/multimedia` → `/media/Videos` ro). Mantém os caminhos internos do QNAP
  para o banco de bibliotecas continuar válido.
- Monitor: alerta de "métricas do host cegas" quando o SSH ao BMax falha por
  ~15 min (hoje o sshd caiu e o CSV só ficou `NA`, sem ninguém avisar).

### Bloqueado

- Deploy do Jellyfin depende de (1) sshd do BMax de volta no ar e (2) regra NFS
  do share `Multimedia` → 192.168.2.174 pela GUI do QTS (só admin).

## [0.3.4] — 2026-10-17

### Alterado

- `frigate_monitor.sh` repontado do QNAP para o **BMax**: API consultada direto
  por HTTP (`192.168.2.174:5000`), métricas de CPU/load/RAM lidas de `/proc`
  no host (independente de locale, que no Debian `top` sairia com vírgula),
  gravações medidas no NFS (`nfs_free_pct`). Cron atualizado para
  `/home/hal9000/CameraIA/frigate_monitor.sh` (clone canônico, antes apontava
  para `Projects/CameraIA`, desatualizado).
- CSV ganhou as colunas `cameras_bad` e `nfs_free_pct`; histórico antigo
  arquivado como `frigate_monitor.csv.pre-bmax-20261017` (as colunas de CPU
  mudaram de semântica: `cpu_pct` do BMax, não `cpu_idle_pct` do NAS).

### Adicionado

- Alertas novos: câmera sem `camera_fps` por ~15 min (suspeita de sessão
  RTSP/encoder do DVR) e NFS de gravações abaixo de 10% livre.
- Relatório diário com câmeras com fps (mínimo), amostras com câmera muda,
  detector fps médio/máximo e NFS livre mínimo.

### Validado

- `collect` roda em ~2,5s: CPU 4%, load 0,9, RAM 17%, Frigate up, 4/4 câmeras,
  `process_fps` 20,3, NFS 70% livre. Alerta de teste entregue no Telegram (msg 492).
- Fluxo completo conferido no BMax: evento `person` na cam_4 às 21:04:56
  (score 0.93) publicado em `frigate/events` via MQTT, com clip servido por
  `/api/events/<id>/clip.mp4`, gravação H.264 960×480 válida no NFS e frame
  extraído do MP4 mostrando a pessoa detectada.

## [0.3.3] — 2026-10-17

### Alterado

- **Cutover concluído**: o Frigate de produção deixou o QNAP TS-453Be e roda no
  BMax B4 Turbo (`/opt/frigate`, compose `frigate/docker-compose.bmax.yml`),
  gravando no NFS do NAS (`/mnt/frigate-media` → `/media/frigate`). Container
  `frigate` do QNAP parado (`Exited 137`) mantido como rollback.
- Histórico preservado via cópia do `configdir` (3.145 eventos, 2 usuários,
  `.jwt_secret`) — sem migração de banco e sem cópia das ~92G de gravações.

### Validado

- Frigate 0.18.2 healthy em ~45s, `RestartCount=0`; 4/4 câmeras em
  `camera_fps` 5,1 com `skipped_fps` 0; detector OpenVINO CPU ~17ms (vs ~170ms
  no J3455); 185 segmentos novos em 15 min no NFS; evento de `person` novo
  tocável via `/api/events/<id>/clip.mp4`.

## [0.3.2] — 2026-10-17

### Adicionado

- `frigate/docker-compose.bmax.yml`: stack do Frigate para o BMax B4 Turbo —
  config/db locais em `/opt/frigate`, gravações no NAS via NFS4
  (`/mnt/frigate-media` → `/media/frigate`, mesmo path de dentro do container
  do QNAP, então as ~92G existentes são reaproveitadas sem cópia), detector
  OpenVINO em CPU e `/dev/dri` reservado ao Jellyfin.
- `frigate/config.ghost.yml`: config sem câmeras para validar o host NOVO sem
  abrir sessão RTSP no DS-7216 (limite prático ~4 sessões) e sem disputar a
  pasta de gravações com o Frigate que ainda roda no QNAP.

### Validado

- Ghost boot no BMax: Frigate 0.18.2 healthy em ~45s, modelo 300x300 carregado
  no OpenVINO CPU (inference ~10ms), SQLite criado, NFS com escrita root ok.

## [0.3.1] — 2026-10-17

### Adicionado

- Setup real do BMax concluído: árvore Btrfs corrigida (@/@home/@docker/@snapshots
  no nível de topo, zstd+noatime), Docker CE + log rotation, QSV validado,
  snapper, zram 8G, NFS do NAS montado em /mnt/frigate-media (91G visíveis).
- Seção 6.3: passo a passo da regra NFS no QTS com o detalhe crítico do
  squash (`no_users` — all/root squash quebra a gravação do Frigate).
- Seção 6.3a: lição do rollout — rename de `@rootfs`→`@` quebra o prefixo
  embutido do GRUB; `grub-install` + `update-grub` obrigatórios, com receita
  de boot manual de emergência.

## [0.3.0] — 2026-10-17

### Alterado (breaking)

- Hardware real = BMax B4 **Turbo** (não Ultra): sem slot NVMe. Guia e passo
  a passo reescritos para disco único SATA: sistema em Btrfs no SSD de
  fábrica, S40G fora da máquina, bay 2.5" como reserva.

### Adicionado

- Seção 6.6: otimizações Turbo (BIOS State After G3→S0, log rotation do
  Docker 10m×3, fstrim, Wi-Fi off, governor padrão).

## [0.2.4] — 2026-10-17

### Adicionado

- Passo a passo: nota sobre boot inicial no Windows — licença OEM fica na
  BIOS (nada a salvar); vale ligar para teste de garantia, conferir o S40G e
  update de BIOS.

## [0.2.3] — 2026-10-17

### Adicionado

- Passo a passo: seção "0.0 Ordem física" — instalar o S40G no slot NVMe
  ANTES de gravar o pendrive/instalar.

## [0.2.2] — 2026-10-17

### Adicionado

- `docs/bmax-debian13-passo-a-passo-instalador.md` — sequência tela-a-tela do
  debian-installer + pós-instalação (teclas de boot do B4 Ultra: F11 menu,
  Delete BIOS; subvolumes @docker/@snapshots, fstab com zstd, SSD SATA como
  rascunho, checklist final).

### Corrigido

- Guia principal: recomendação de senha do root em branco no instalador
  (bloqueia root e dá `sudo` ao primeiro usuário automaticamente).

## [0.2.1] — 2026-10-17

### Adicionado

- `docs/bmax-b4-ultra-debian13-instalacao.md` — guia de decisão completo da
  instalação Debian 13 no BMax B4 Ultra (ISO, GNOME, Btrfs+snapper, layout de
  subvolumes com @docker fora de snapshots, zram, Docker CE, NFS do NAS, QSV),
  parte do planejamento da migração Frigate/Jellyfin/Hermes para o mini PC.
