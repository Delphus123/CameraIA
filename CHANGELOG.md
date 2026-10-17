# Changelog — CameraIA

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), versionamento semântico.

> Histórico anterior (Fase 0–1: piloto 4 câmeras, gravação main H.264, fix do modelo 300x300) precede este changelog — ver `git log`.

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
