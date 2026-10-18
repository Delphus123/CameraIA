# Changelog — CameraIA

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), versionamento semântico.

> Histórico anterior (Fase 0–1: piloto 4 câmeras, gravação main H.264, fix do modelo 300x300) precede este changelog — ver `git log`.

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
