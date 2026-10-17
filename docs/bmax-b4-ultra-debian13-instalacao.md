# BMax B4 Ultra — Guia de instalação Debian 13

Papel da máquina: appliance 24/7 rodando Docker (Frigate + Jellyfin + Hermes),
com GUI disponível. Gravações e biblioteca de mídia ficam no NAS (NFS) — o
host só precisa de estabilidade, QSV funcionando e Docker.

## 1. ISO

**Escolha: `debian-13.x.x-amd64-netinst.iso`** (site cdimage.debian.org).

- Desde o Debian 12, a ISO oficial **já inclui os firmwares non-free** — o
  Wi-Fi Realtek 8821CE e os firmwares de GPU da Intel funcionam de cara.
- Netinst exige rede no instalador — usar o cabo Ethernet (obrigatório pro
  Frigate de qualquer forma).
- Verificar o SHA256 antes de gravar (`sha256sum` na página de download).
- Gravação: `dd` ou balenaEtcher em pendrive ≥ 1GB.

Não usar: DVD completo (desnecessário), "live" com installer (não ganha nada aqui).

## 2. Desktop / Window manager

**Escolha: GNOME** (marcar "GNOME" e "standard system utilities" no tasksel).

- Padrão do projeto, Wayland nativo, zero tuning necessário; o N150 + iGPU
  24EU roda GNOME desktop liso.
- Alternativa mais leve se quiser poupar ~700MB de RAM: **XFCE**
  ("Xfce" no tasksel). Tudo o mais neste guia é idêntico.
- Evitar KDE neste papel: mais pacotes, mais pontos de atualização, sem
  benefício pra um host de containers.

## 3. Filesystem

**Escolha: Btrfs no NVMe (sistema) + ext4 no SSD SATA (rascunho).**

### Por que Btrfs no sistema (e não ext4)

- Snapshots atômicos **antes/depois de cada update** — se um upgrade quebrar o
  boot ou um serviço, rollback em segundos (workflow na seção 7).
- CoW + checksums pegam bit-rot silencioso em disco único.
- Suportado **nativamente pelo instalador** do Debian — zero gambiarra.

### Por que NÃO ZFS

- O instalador do Debian **não suporta root em ZFS** — exigiria live-installer
  com passos manuais frágeis que precisam ser refeitos a cada major upgrade.
- Os benefícios do ZFS (RAID, compressão, dedup) não se aplicam: disco único,
  sem redundância necessária (dados críticos estão no NAS em RAID5), e a
  compressão zstd do Btrfs cobre o resto.
- Regra prática: ZFS brilha com múltiplos discos e dados primários locais —
  não é este cenário. Btrfs + snapshots + dados no NAS = mesmo resultado,
  10% do esforço.

## 4. Partições

Disco do sistema = **S40G (NVMe, slot PCIe)**. SSD SATA de fábrica = rascunho.

### NVMe (S40G) — particionamento manual no instalador

| # | Tamanho | Tipo | FS / conteúdo | Montagem |
|---|---|---|---|---|
| 1 | 1 GB | EFI System | FAT32 | `/boot/efi` |
| 2 | resto (~511 GB) | Linux | Btrfs (subvolumes abaixo) | — |

Subvolumes Btrfs (criar em "Opções de montagem" → usar como → Btrfs, editando
os subvolumes após criar o volume):

| Subvolume | Montagem | Snapshots? |
|---|---|---|
| `@` | `/` | sim (via snapper) |
| `@home` | `/home` | sim (opcional) |
| `@docker` | `/var/lib/docker` | **NUNCA** — imagens/volumes em snapshot multiplicam o uso do disco e congelam writes durante o snapshot |
| `@snapshots` | `/.snapshots` | destino dos snapshots do snapper |

Opções de montagem do root (e herdeiras): `compress=zstd:1,noatime,ssd,subvol=@`.
A compressão zstd vale o CPU (N150 sobra) e ganha ~20-30% de espaço em
camadas de imagem Docker e logs.

> Dica prática: se o particionador do d-i complicar, caminho mais simples é
> deixar o instalador criar Btrfs padrão (`@` e `@home`) e criar `@docker` e
> `@snapshots` no pós-instalação com `btrfs subvolume create`, antes de
> instalar o Docker.

### SSD SATA (fábrica) — disco de rascunho

- Uma partição única, **ext4**, montada em `/srv/spare`.
- ext4 de propósito: é disco de sujeira (cache de download, logs antigos,
  temp) — CoW/snapshots aqui só atrapalham. Formatar com `nodiscard`,
  montagem com `noatime`.
- 2.5" bay: vazio por ora. Se um dia precisar de mídia local (fora do NAS),
  é lá — nunca no NVMe do sistema.

### Swap

- **Sem partição de swap.** Usar **zram**: `apt install zram-tools`, depois em
  `/etc/default/zramswap`: `ALGO=zstd`, `PERCENT=50` (~8 GB em 16 GB de RAM).
- Motivo: swap em disco SSD gasta células e é lento; zram comprime na RAM e é
  instantâneo. Com 16 GB e a carga prevista, swap de disco dificilmente seria
  tocado.

## 5. Passos no instalador (resumo das escolhas)

1. Boot no pendrive → Install (não Graphical Install — o desktop vem do tasksel).
2. Language: pt_BR; locale pt_BR.UTF-8; timezone America/Sao_Paulo.
3. Hostname sugerido: `bmax4`; domínio vazio ou `lan`.
4. Root: senha própria; usuário comum: `delphus` (ou o que preferir) com sudo
   (marcar "sudo" nos grupos no pós-instalação se o instalador não oferecer).
5. Particionamento: **Manual** → layout da seção 4.
6. Tasksel: marcar apenas **GNOME** e **standard system utilities**.
   NÃO marcar "web server", "print server" etc.
7. GRUB: instalar no disco primário (NVMe).

> Senha do root: recomendação atualizada — deixar **em branco** no instalador.
> Com root em branco, o d-i bloqueia a conta root e adiciona o primeiro usuário
> ao grupo `sudo` automaticamente (padrão mais limpo e auditável).

## 6. Pós-instalação (checklist obrigatório)

### 6.1 Repos e firmware

`/etc/apt/sources.list` deve ficar (trixie usa componentes separados):

```
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
```

```bash
sudo apt update && sudo apt full-upgrade
sudo apt install intel-media-va-driver-non-free vainfo
vainfo   # deve listar perfis iHD (H264/HEVC/VP9/AV1 decode) — valida o QSV pro Jellyfin
```

### 6.2 Docker (repo oficial, não o docker.io do Debian)

```bash
# conforme docs.docker.com/engine/install/debian
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update && sudo apt install docker-ce docker-compose-plugin
sudo usermod -aG docker $USER
```

### 6.3 NFS (gravações do Frigate + biblioteca Jellyfin no NAS)

```bash
sudo apt install nfs-common
# /etc/fstab — ajustar exports conforme o QNAP
192.168.2.170:/Container/frigate/media  /mnt/frigate-media  nfs4  _netdev,x-systemd.automount,x-systemd.idle-timeout=60,noatime  0  0
sudo mkdir -p /mnt/frigate-media && sudo systemctl daemon-reload && sudo mount -a
```

O `x-systemd.automount` evita boot travado se o NAS estiver fora do ar.

### 6.4 Snapshots: snapper + btrfs-assistant

```bash
sudo apt install snapper btrfs-assistant   # btrfs-assistant = GUI
sudo snapper -c root create-config /
sudo snapper -c root create --description "instalação limpa"
```

Automatizar snapshots pré/pós `apt` (hook do snapper — pacote
`snapd`-independente; no Debian usar o script de `snapper` + apt hook ou
`apt-btrfs-snapshot` se disponível). Alternativa GUI completa: Timeshift
(tb. suporta Btrfs, mais simples, sem timeline por apt).

### 6.5 Manutenção e hardening leve

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades   # patches de segurança automáticos
```

- Manter o disco SATA de rascunho fora de monitoramento crítico.
- Sem RAID local, o backup real das configs do host é: repo git (compose,
  configs) + retention do NAS (gravações) + export do banco do Hermes.

## 7. Workflow de rollback (o motivo do Btrfs)

Update quebrou o boot/serviço:

1. Reiniciar → menu GRUB → "Debian GNU/Linux, with Linux ... (recovery)" ou,
   se o snapper-grub estiver configurado, escolher o snapshot direto no menu.
2. `sudo snapper list` → identificar o snapshot pré-update.
3. `sudo snapper rollback <N>` → reboot.
4. Se o problema foi um `apt upgrade`: repetir o update depois que o pacote
   for corrigido (ou segurar o pacote com `apt-mark hold`).

## 8. Resumo de decisões

| Decisão | Escolha | Motivo em uma linha |
|---|---|---|
| ISO | netinst amd64 (firmware incluso) | mínimo, rede garantida via cabo |
| Desktop | GNOME (alt: XFCE) | padrão, leve no N150, GUI quando precisar |
| FS do sistema | Btrfs + snapper | snapshots/rollback nativos no instalador |
| FS do rascunho | ext4 no SSD SATA | sujeira não precisa de CoW |
| ZFS | não | root sem suporte no d-i, sem RAID local, dados no NAS |
| Swap | zram 8 GB | sem desgaste de SSD, instantâneo |
| Docker | em `@docker` fora de snapshots | snapshots não devem capturar imagens |
| Dados | NAS via NFS automount | gravações e mídia nunca no disco do sistema |
| QSV | intel-media-va-driver-non-free | transcode Jellyfin por hardware |
| Updates | unattended-upgrades (security) + snapper pré/pós | appliance sem surpresa |
