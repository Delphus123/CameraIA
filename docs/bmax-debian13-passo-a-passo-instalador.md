# BMax B4 Turbo — Passo a passo do instalador Debian 13

Complemento de `docs/bmax-b4-turbo-debian13-instalacao.md` (decisões e
justificativas). Este documento é a sequência tela-a-tela do `debian-installer`
e o pós-instalação imediato. Ter os dois abertos (papel ou celular) ajuda.

Hardware: **disco único** — SSD M.2 SATA 512GB de fábrica. Sem NVMe interno.

## 0. Antes de começar

### 0.0 Boot inicial no Windows (uma vez, antes de tudo)

A licença OEM fica na BIOS/motherboard — não há nada a salvar ao apagar o
disco. Mas o boot no Windows de fábrica vale por 3 motivos:

1. **Testar hardware na janela de garantia**: os 2 HDMI, Ethernet, Wi-Fi,
   USB, fan (barulho normal é baixo).
2. **Conferir versão da BIOS**: `Win+R` → `msinfo32` → "BIOS Version/Date".
   Se o site da BMAX (bmaxit.com/download.html, informando o **PN code do
   adesivo de baixo**) tiver versão mais nova, atualizar **antes** de apagar:
   baixar o pacote do PN exato, rodar o `.exe` como administrador, na tomada,
   sem interromper (a máquina reinicia sozinha 2-3 vezes).
3. Conferir a saúde do SSD no Gerenciador de Discos.

### 0.1 Teclas de boot

| Tecla (apertar repetidamente ao ligar) | O que abre |
|---|---|
| **F11** | **Menu de boot** (escolher o pendrive) — é esta que você quer |
| Delete | Setup da BIOS/UEFI (também: State After G3 → S0, seção 6.6 do guia) |
| F4 (dentro da BIOS) | Salvar e sair |
| F9 | Recovery do Windows da BMAX (ignorar após instalar Debian) |

- Pendrive ANTES de ligar. Apertar F11 várias vezes desde o primeiro segundo
  (o logotipo BMAX dura pouco).
- No menu de boot, escolher a entrada **"UEFI: <marca do pendrive>,
  Partition 1/2"** — a que começa com "UEFI:". Não escolher a entrada USB
  "legacy" sem o prefixo UEFI.
- F11 confirmado no B4 Ultra (mesma família, relato lemongrass-studio.net,
  2026). Se não abrir nada no Turbo: Delete → BIOS → aba Boot → ajustar a
  ordem → F4 salva.

### 0.2 Gravação do pendrive

```bash
# macOS: conferir o checksum e gravar no raw device
shasum -a 256 ~/Downloads/debian-13.x.x-amd64-netinst.iso   # conferir com a soma do site
diskutil list disk4            # CONFIRMAR que disk4 é o pendrive!
diskutil unmountDisk /dev/disk4
sudo gdd if=~/Downloads/debian-13.x.x-amd64-netinst.iso of=/dev/rdisk4 bs=4M status=progress conv=fsync
diskutil eject /dev/disk4
```

```bash
# Linux/Pi: idem, com dd e /dev/sdX (confira com lsblk!)
sha256sum debian-13.x.x-amd64-netinst.iso
sudo dd if=debian-13.x.x-amd64-netinst.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

## 1. Instalador, tela por tela

Menu de boot do pendrive → escolher **"Install"** (texto; "Graphical install"
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

Com disco único, o instalador mostra **um único disco de ~512 GB** (genérico,
SATA — às vezes listado como `/dev/sda`). Zero risco de disco errado.

1. Selecionar cada partição existente (Windows de fábrica: C:, recovery, MSR,
   EFI) → **"Delete the partition"** até o disco ficar todo "FREE SPACE".
2. Selecionar o "FREE SPACE" → "Create a new partition":
   - **Partição 1**: 1.0 GB, no início ("Beginning"), "Use as: **EFI System
     Partition**", flag bootable (o d-i marca sozinho). Montagem `/boot/efi`.
   - **Partição 2**: todo o resto, "Use as: **btrfs journaling file system**".
3. Ao confirmar a partição Btrfs, o instalador cria subvolumes `@` (para `/`)
   e `@home` (para `/home`) automaticamente. Se ele perguntar, manter `@` e
   `@home` como propostos.
4. **Não** usar as opções de "mount options" no instalador — o
   `compress=zstd:1,noatime,ssd` entra no fstab no pós-instalação (passo 2.1),
   onde dá pra revisar antes de aplicar.

"Finish partitioning and write changes to disk" → "Yes".

| Tela | Escolha |
|---|---|
| Mirror do arquivo Debian | Brasil (ex.: br.debian.org) ou deb.debian.org |
| HTTP proxy | vazio |
| Participar do survey (popcon) | No |
| **Software selection (tasksel)** | desmarcar TUDO; marcar apenas **GNOME** e **standard system utilities** |
| GRUB no disco primário | **Yes** → `/dev/sda` (único disco) |
| Installation complete | Continue → retira o pendrive quando reiniciar |

## 2. Pós-instalação imediato (primeiro boot, terminal)

Logar com `delphus`. Todo comando a seguir com `sudo` (já funciona).

### 2.1 Subvolumes extras + opções de montagem

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

Pegar o UUID com `lsblk -f` (partição Btrfs = a ~511GB, `/dev/sda2`).

```bash
sudo mkdir -p /.snapshots
sudo mount -a   # se algum erro: corrigir o fstab antes de seguir
```

(O `/var/lib/docker` só terá conteúdo depois do passo 2.3 — montar antes de
instalar o Docker garante que ele nasça dentro do subvolume.)

### 2.2 Repos, atualização, QSV

Seguir seção 6.1 do guia principal (sources.list com
`contrib non-free non-free-firmware`, `apt full-upgrade`,
`intel-media-va-driver-non-free`, `vainfo`).

### 2.3 Docker (com log rotation!), NFS, snapper, zram, unattended

Seguir seções 6.2 a 6.6 do guia principal, nesta ordem:
1. Docker CE (repo oficial) → o `/var/lib/docker` já cai no subvolume `@docker`
   — e **aplicar o `/etc/docker/daemon.json` com log rotation** (10m×3) antes
   de subir qualquer container
2. NFS automount do NAS (`/mnt/frigate-media`)
3. snapper + primeiro snapshot "instalação limpa"
4. zram-tools (`ALGO=zstd`, `PERCENT=50`)
5. unattended-upgrades + conferir `fstrim.timer`
6. **BIOS: State After G3 → S0** (só dá pra fazer com reboot — Delete no logo)
7. Wi-Fi off (`rfkill block wifi`) — rede é cabo

### 2.4 Bay 2.5" e S40G

- Bay 2.5": vazio (reserva pra mídia local futura).
- S40G: não tem slot no Turbo — fica pra outro uso ou case USB-C (nunca boot).

## 3. Checklist final (tudo verde = pronto pro Docker)

- [ ] `vainfo` lista perfis H264/HEVC/VP9/AV1 (QSV ok)
- [ ] `docker run --rm hello-world` funciona
- [ ] `df -h /mnt/frigate-media` mostra o pool do NAS
- [ ] `sudo snapper list` tem o snapshot "instalação limpa"
- [ ] `zramctl` mostra ~8G de zram
- [ ] `lsblk` confirma: disco único sda, `@docker` montado
- [ ] `/etc/docker/daemon.json` com log rotation ativo
- [ ] `cat /sys/class/dmi/id/power_on_after_fail` / BIOS: auto power-on G3→S0

Próximo passo: compose do Frigate/Jellyfin/Hermes apontando para
`/mnt/frigate-media` (ver plano de migração).
