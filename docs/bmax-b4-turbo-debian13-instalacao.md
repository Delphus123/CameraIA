# BMax B4 Turbo — Guia de instalação Debian 13

Papel da máquina: appliance 24/7 rodando Docker (Frigate + Jellyfin + Hermes),
com GUI disponível. Gravações e biblioteca de mídia ficam no NAS (NFS) — o
host só precisa de estabilidade, QSV funcionando e Docker.

Hardware real (B4 Turbo): N150 4C/4T @3.6GHz, 16GB SO-DIMM DDR4-2666 (1 slot,
não expansível — teto do N150), **SSD M.2 SATA 512GB (único disco)**,
expansão: só bay 2.5" SATA. **Não tem slot NVMe** — o S40G não serve
internamente (caso: case USB-C, nunca boot).

## 1. ISO

**Escolha: `debian-13.x.x-amd64-netinst.iso`** (site cdimage.debian.org).

- Desde o Debian 12, a ISO oficial **já inclui os firmwares non-free** — o
  Wi-Fi Realtek 8821CE e os firmwares de GPU da Intel funcionam de cara.
- Netinst exige rede no instalador — usar o cabo Ethernet (obrigatório pro
  Frigate de qualquer forma).
- Verificar o SHA256 antes de gravar (`shasum -a 256` no macOS).
- Gravação: `dd` (Linux) / `gdd` com `of=/dev/rdisk4` (macOS) ou balenaEtcher,
  pendrive ≥ 1GB.

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

**Escolha: Btrfs no SSD SATA (disco único do sistema).**

### Por que Btrfs (e não ext4)

- Snapshots atômicos **antes/depois de cada update** — se um upgrade quebrar o
  boot ou um serviço, rollback em segundos (workflow na seção 7).
- CoW + checksums pegam bit-rot silencioso em disco único.
- Suportado **nativamente pelo instalador** do Debian — zero gambiarra.
- O SSD SATA é DRAM-less, mas com zram (sem swap em disco), logs rotacionados
  e zstd, o padrão de acesso fica leve. Não é NVMe, e não precisa ser: os
  dados pesados (gravação, mídia) estão no NAS via gigabit.

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

Disco único = **SSD M.2 SATA de fábrica (512GB)**.

| # | Tamanho | Tipo | FS / conteúdo | Montagem |
|---|---|---|---|---|
| 1 | 1 GB | EFI System | FAT32 | `/boot/efi` |
| 2 | resto (~511 GB) | Linux | Btrfs (subvolumes abaixo) | — |

Subvolumes Btrfs:

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

### Bay 2.5" SATA

- Vazio por ora. Se um dia precisar de mídia local (fora do NAS), é lá —
  HDD 2.5" barato ou SSD SATA. Nunca mídia no disco do sistema.

### SSD NVMe S40G

- Não tem slot no Turbo. Opções: fica pra outro uso, ou case USB-C
  (o Type-C do Turbo é full features) como disco de rascunho/downloads —
  **nunca como disco de boot** (USB é frágil pra appliance 24/7).

### Swap

- **Sem partição de swap.** Usar **zram**: `apt install zram-tools`, depois em
  `/etc/default/zramswap`: `ALGO=zstd`, `PERCENT=50` (~8 GB em 16 GB de RAM).
- Motivo: swap em disco SSD gasta células e é lento; zram comprime na RAM e é
  instantâneo. Com 16 GB e a carga prevista, swap de disco dificilmente seria
  tocado.

## 5. Passos no instalador (resumo das escolhas)

1. Boot no pendrive (F11) → Install (não Graphical Install — o desktop vem do
   tasksel).
2. Language: pt_BR; locale pt_BR.UTF-8; timezone America/Sao_Paulo.
3. Hostname sugerido: `bmax4`; domínio vazio ou `lan`.
4. Root: senha **em branco** → o d-i bloqueia root e dá `sudo` ao primeiro
   usuário automaticamente. Usuário: `delphus`.
5. Particionamento: **Manual** → layout da seção 4 (apagar as partições do
   Windows de fábrica antes).
6. Tasksel: marcar apenas **GNOME** e **standard system utilities**.
   NÃO marcar "web server", "print server" etc.
7. GRUB: no disco único (`/dev/sda`).

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

**Rotação de logs do Docker** (no SATA de 512GB, sem isso os logs json lotam
o disco — otimização essencial no Turbo):

```bash
sudo tee /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
sudo systemctl restart docker
```

### 6.3 NFS (gravações do Frigate + biblioteca Jellyfin no NAS)

**No QTS (obrigatório, via GUI)** — regra de NFS host access no share
`Container` (Control Panel → Privilege Settings → Shared Folders → Container
→ Edit → Permissions → NFS host access):

- **IP/network:** `192.168.2.174` (o BMax)
- **Privilege:** `read/write`
- **Squash options:** **`no_users`** — este é o ponto crítico. `all_users`
  (`all_squash`) e `root_users` (`root_squash`) mapeiam o root do container do
  Frigate para `nobody` e a gravação falha com Permission denied. Só
  `no_users` deixa o root gravar como root.
- Apply na janela **e** Apply de novo em Win/Mac/NFS → NFS service (o segundo
  Apply é o que regenera o `/etc/exports` via `gen_exports`).

**No BMax:**

```bash
sudo apt install nfs-common
# /etc/fstab
192.168.2.170:/Container/frigate/media  /mnt/frigate-media  nfs4  _netdev,x-systemd.automount,x-systemd.idle-timeout=60,noatime  0  0
sudo mkdir -p /mnt/frigate-media && sudo systemctl daemon-reload && sudo mount -a
```

O `x-systemd.automount` evita boot travado se o NAS estiver fora do ar.
Validação: `touch /mnt/frigate-media/.t` como root e apagar — se der
Permission denied, o squash do QTS está errado.

### 6.3a Lição do rollout — rename de subvolume x GRUB

O instalador do Debian cria o root como subvolume `@rootfs` e o GRUB
(UEFI, `grubx64.efi`) embute o prefixo apontando pra `@rootfs/boot/grub`.
**Renomear o subvolume quebra o boot** (a máquina cai no `grub>`).
Depois de renomear `@rootfs` → `@`, rodar SEMPRE:

```bash
sudo grub-install /dev/sda && sudo update-grub
```

Boot manual de emergência no `grub>` (funciona com o prefixo quebrado):

```
search.fs_uuid 4fba3a0e-5ace-4da2-9ea8-7a5986d7d537 root
linux ($root)/@/boot/vmlinuz-<versao> root=UUID=4fba3a0e-5ace-4da2-9ea8-7a5986d7d537 rootflags=subvol=@ ro quiet
initrd ($root)/@/boot/initrd.img-<versao>
boot
```

Obs. desta máquina: mount por `UUID=` no fstab — usar o prefixo `UUID=`
completo (UUID pelado como origem falha com "special device does not
exist").

### 6.4 Snapshots: snapper + btrfs-assistant

```bash
sudo apt install snapper btrfs-assistant   # btrfs-assistant = GUI
sudo snapper -c root create-config /
sudo snapper -c root create --description "instalação limpa"
```

Automatizar snapshots pré/pós `apt` (hook do snapper + apt hook ou
`apt-btrfs-snapshot` se disponível). Alternativa GUI completa: Timeshift
(tb. suporta Btrfs, mais simples, sem timeline por apt).

### 6.5 Manutenção e hardening leve

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades   # patches de segurança automáticos
systemctl status fstrim.timer                     # já vem ativo no Debian — confirma
```

- Sem RAID local, o backup real das configs do host é: repo git (compose,
  configs) + retention do NAS (gravações) + export do banco do Hermes.

### 6.6 Otimizações específicas do Turbo

1. **Auto power-on após queda de luz** (BIOS): Delete no boot → Chipset →
   South Cluster Configuration → **State After G3 → S0 State** → F4 salva.
   Appliance de vigilância tem que voltar sozinho da falta de energia.
2. **Ethernet, não Wi-Fi**: o Wi-Fi 5 do Turbo (~250Mbps) é inútil pra RTSP;
   deixa desabilitado por software (`rfkill block wifi` ou NetworkManager) e
   ganha estabilidade + ~1W.
3. **fstrim semanal** ativo (6.5) — obrigatório pro SATA DRAM-less.
4. **CPU governor**: deixar o padrão `schedutil`/`powersave` — em carga o
   N150 escala sozinho até 3.6GHz; forçar `performance` só aumenta calor e
   fan sem ganho em transcode/inference.
5. **Fan**: manter as frentes/traseiras do case desobstruídas; se o vento
   incomodar, é sinal de carga — ver CPU com `htop`, não abafar o aparelho.

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
| FS do sistema | Btrfs + snapper (disco único SATA) | snapshots/rollback nativos no instalador |
| ZFS | não | root sem suporte no d-i, sem RAID local, dados no NAS |
| Swap | zram 8 GB | sem desgaste de SSD, instantâneo |
| Docker | em `@docker` fora de snapshots + log rotation 10m×3 | protege o SSD de 512GB |
| S40G | fora da máquina (case USB se precisar) | Turbo não tem slot NVMe |
| Bay 2.5" | vazio (reserva) | mídia local só se o NAS um dia não der conta |
| Dados | NAS via NFS automount | gravações e mídia nunca no disco do sistema |
| QSV | intel-media-va-driver-non-free | transcode Jellyfin por hardware |
| BIOS | State After G3 → S0 | auto power-on após queda de luz |
| Updates | unattended-upgrades (security) + snapper pré/pós | appliance sem surpresa |
