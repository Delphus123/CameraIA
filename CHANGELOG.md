# Changelog — CameraIA

Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), versionamento semântico.

> Histórico anterior (Fase 0–1: piloto 4 câmeras, gravação main H.264, fix do modelo 300x300) precede este changelog — ver `git log`.

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
