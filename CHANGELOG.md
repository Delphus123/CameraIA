# Changelog — CameraIA

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), versionamento semântico.

> Histórico anterior (Fase 0–1: piloto 4 câmeras, gravação main H.264, fix do modelo 300x300) precede este changelog — ver `git log`.

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
