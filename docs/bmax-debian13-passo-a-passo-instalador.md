# BMax B4 Ultra — Passo a passo do instalador Debian 13

Complemento de `docs/bmax-b4-ultra-debian13-instalacao.md` (decisões e
justificativas). Este documento é a sequência tela-a-tela do `debian-installer`
e o pós-instalação imediato. Ter os dois abertos (papel ou celular) ajuda.

## 0. Antes de começar — teclas de boot do B4 Ultra

| Tecla (apertar repetidamente ao ligar) | O que abre |
|---|---|
| **F11** | **Menu de boot** (escolher o pendrive) — é esta que você quer |
| Delete | Setup da BIOS/UEFI |
| F4 (dentro da BIOS) | Salvar e sair |
| F9 | Recovery do Windows da BMAX (ignorar após instalar Debian) |

- Pendrive ANTES de ligar. Apertar F11 várias vezes desde o primeiro segundo
  (o logotipo BMAX dura pouco).
- No menu de boot, escolher a entrada **"UEFI: <marca do pendrive>,
  Partition 1/2"** — a que começa com "UEFI:". Não escolher a entrada USB
  "legacy" sem o prefixo UEFI.
- Fonte: relato de instalação real em B4 Ultra (lemongrass-studio.net, 2026) —
  F11 confirmado nessa máquina. Se F11 não abrir nada, Delete → BIOS → aba
  Boot → ajustar ordem e F4 para salvar.

## 1. Gravação do pendrive

```bash
# no Pi ou em qualquer Linux
sha256sum debian-13.x.x-amd64-netinst.iso   # conferir com a soma do site
sudo dd if=debian-13.x.x-amd64-netinst.iso of=/dev/sdX bs=4M status=progress conv=fsync
# sdX = o pendrive INTEIRO (sem número de partição) — confira com lsblk antes!
```

## 2. Instalador, tela por tela

Boot menu do pendrive → escolher **"Install"** (texto; "Graphical install"
também funciona, mas o desktop vem do tasksel de qualquer forma).

| Tela | Escolha |
|---|---|
| Language | Portuguese (Brasil) |
| Location | Brasil |
| Keyboard | Português Brasileiro |
| (possível tela "Missing firmware") | Carregar firmware se oferecer pelo pendrive; se não tiver, **continuar** — a Ethernet Realtek funciona sem |
| Network: interface | a eth0/enp1s0 que aparecer (cabo já conectado no roteador) |
| Hostname | `bmax4` |
| Domain | vazio |
| Senha do root | **DEIXAR EM BRANCO** → o instalador bloqueia root e dá `sudo` ao primeiro usuário automaticamente |
| Full name | Rafael Laguardia |
| Username | `delphus` |
| Senha do usuário | a sua (gerenciador de senhas) |
| Clock | America/Sao_Paulo (vem pré-selecionado por causa do locale) |

### Particionamento — "Manual" (a parte importante)

O instalador mostra os dois discos. **Identificá-los pelo modelo**:
- ~512 GB "ADATA Spectrix S40G..." = **NVMe** (sistema) — provavelmente
  `/dev/nvme0n1`
- "SSD de 512 GB" genérico (SATADOM/generic) = SSD SATA de fábrica

**No SSD SATA de fábrica:** selecionar a partição existente → "Delete the
partition" (se oferecer) e deixar o disco como **"FREE SPACE" / não usado**.
NÃO criar nada nele agora — formataremos no pós-instalação (evita instalar
sem querer no disco errado).

**No NVMe (S40G):** se vier com Windows/partições de fábrica:
1. Selecionar cada partição → "Delete the partition" até o disco ficar todo
   "FREE SPACE".
2. Selecionar o "FREE SPACE" → "Create a new partition":
   - **Partição 1**: 1.0 GB, no início ("Beginning"), "Use as: **EFI System
     Partition**", flag bootable (o d-i marca sozinho). Montagem `/boot/efi`.
   - **Partição 2**: todo o resto, "Use as: **btrfs journaling file system**".
3. Ao confirmar a partição Btrfs, o instalador cria subvolumes `@` (para `/`)
   e `@home` (para `/home`) automaticamente. Verificar no resumo que aparece
   "btrfs / subvolume @ ... ext4-signed... /" — se ele perguntar, manter `@`
   e `@home` como propostos.
4. **Não** usar as opções de "mount options" no instalador — o
   `compress=zstd:1,noatime,ssd` entra no fstab no pós-instalação (passo 3.1),
   onde dá pra revisar antes de aplicar.

"Finish partitioning and write changes to disk" → "Yes".

| Tela | Escolha |
|---|---|
| Mirror do arquivo Debian | Brasil (ex.: br.debian.org) ou deb.debian.org |
| HTTP proxy | vazio |
| Participar do survey (popcon) | No |
| **Software selection (tasksel)** | desmarcar TUDO; marcar apenas **Xfce**? Não — **GNOME** e **standard system utilities** |
| GRUB no disco primário | **Yes** → escolher `/dev/nvme0n1` (o S40G) |
| Installation complete | Continue → retira o pendrive quando reiniciar |

## 3. Pós-instalação imediato (primeiro boot, terminal)

Logar com `delphus`. Todo comando a seguir com `sudo` (já funciona).

### 3.1 Subvolumes extras + opções de montagem

```bash
sudo btrfs subvolume create /@docker
sudo btrfs subvolume create /@snapshots
# "/" agora é o subvolume @ montado em / — os novos ficam acessíveis por lá
```

Editar `/etc/fstab` — as linhas Btrfs devem ficar assim (ajustar UUID):

```
UUID=<uuid-do-btrfs>  /                btrfs  compress=zstd:1,noatime,ssd,subvol=@            0 0
UUID=<uuid-do-btrfs>  /home            btrfs  compress=zstd:1,noatime,ssd,subvol=@home        0 0
UUID=<uuid-do-btrfs>  /var/lib/docker  btrfs  compress=zstd:1,noatime,ssd,subvol=@docker      0 0
UUID=<uuid-do-btrfs>  /.snapshots      btrfs  compress=zstd:1,noatime,ssd,subvol=@snapshots   0 0
```

Pegar o UUID com `lsblk -f /dev/nvme0n1p2`. Antes de aplicar, mover o
conteúdo atual do docker (se existir) e criar os pontos de montagem:

```bash
sudo mkdir -p /.snapshots
sudo mount -a   # se algum erro: corrigir o fstab antes de seguir
```

(O `/var/lib/docker` só terá conteúdo depois do passo 3.3 — montar antes de
instalar o Docker garante que ele nasça dentro do subvolume.)

### 3.2 Repos, atualização, QSV

Seguir seção 6.1 do guia principal (sources.list com
`contrib non-free non-free-firmware`, `apt full-upgrade`,
`intel-media-va-driver-non-free`, `vainfo`).

### 3.3 Docker, NFS, snapper, zram, unattended-upgrades

Seguir seções 6.2 a 6.5 do guia principal, nesta ordem:
1. Docker CE (repo oficial) → o `/var/lib/docker` já cai no subvolume `@docker`
2. NFS automount do NAS (`/mnt/frigate-media`)
3. snapper + primeiro snapshot "instalação limpa"
4. zram-tools (`ALGO=zstd`, `PERCENT=50`)
5. unattended-upgrades

### 3.4 Formatar o SSD SATA de fábrica (rascunho)

```bash
sudo mkfs.ext4 -L spare /dev/sda1   # conferir o dispositivo com lsblk — NÃO é o nvme!
echo '/dev/disk/by-label/spare  /srv/spare  ext4  noatime,nofail  0  2' | sudo tee -a /etc/fstab
sudo mkdir -p /srv/spare && sudo mount -a
```

## 4. Checklist final (tudo verde = pronto pro Docker)

- [ ] `vainfo` lista perfis H264/HEVC/VP9/AV1 (QSV ok)
- [ ] `docker run --rm hello-world` funciona
- [ ] `df -h /mnt/frigate-media` mostra o pool do NAS
- [ ] `sudo snapper list` tem o snapshot "instalação limpa"
- [ ] `zramctl` mostra ~8G de zram
- [ ] `lsblk` confirma: sistema no S40G, `@docker` montado, SATA em `/srv/spare`

Próximo passo: compose do Frigate/Jellyfin/Hermes apontando para
`/mnt/frigate-media` (ver plano de migração).
