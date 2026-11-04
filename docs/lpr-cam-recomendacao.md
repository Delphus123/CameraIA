# Recomendação: câmera dedicada de leitura de placas (LPR) via coaxial

> Registrada em 04/11/2026 a pedido do Rafael. Contexto: a cam_2 (sub 960×480)
> não resolve leitura de placas — placa de carro em movimento tem ~10 px no
> detect e ~30-35 px no playback main 3MP (medido em zoom real, 04/11/26).
> OCR confiável precisa de 60-100 px de largura de placa.

## Recomendação escolhida (opção 1 do comparativo de 04/11/26)

**Hikvision DS-2CE16H8-TIT3Z** — bullet TVI 5MP, lente varifocal motorizada
2.8-12mm, obturador até 1/50.000s, IR 40m, IP67, 4-em-1 (TVI/AHD/CVI/CVBS).
Preço no BR: ~R$ 400-600.

### Por que ela

- Única opção >720p de resolução que **reusa o cabo coaxial** e se compra
  facilmente no Brasil (a linha "LPR TVI" da Hikvision no BR — DS-2CE16C8-TIW3Z
  — é só 720p; as 5MP TVI genéricas têm lente fixa grande-angular, não servem).
- **Física da leitura**: com saída em 3MP (o DS-7216HQHI-K2 aceita 3MP nos
  canais 1-4) + zoom em 12mm mirado no ponto de passagem a 10-15 m, a placa
  atinge ~100-130 px de largura — acima do limiar de 60-100 px do OCR.

### Plano de instalação (quando for executar)

1. **Posição dedicada ao ponto de passagem** (portão/entrada): altura 3-6 m,
   a 10-15 m do veículo, ângulo raso (10-30° em relação à rua). NÃO substituir
   a posição da cam_2 — ela continua cobrindo o pátio/rua; esta câmera é
   exclusiva do ponto de leitura.
2. Entrar num canal coax livre do DVR (16 canais; cam_1-4 usam 1-4), saída da
   câmera configurada em **3MP@15fps TVI** (o DVR só aceita 3MP nos canais 1-4;
   em outro canal, 1080p@30fps).
3. **Shutter manual 1/1000-1/2000s** via OSD (pelo próprio coax, UTC) — crítico
   contra motion blur em carro em movimento.
4. Zoom travado em ~12mm focado na placa no ponto de leitura; conferir o IR
   noturno (a placa reflete IR — a leitura noturna é P&B e funciona).
5. Integrar ao Frigate como câmera dedicada (ex.: cam_lpr) e ao pipeline
   `lpr-exp` (playback+crop+OCR, v0.4.2-0.4.3) — ou, com o box grande no ponto
   fixo, avaliar OCR dedicado (PaddleOCR) em vez do Moondream.

### Alternativas avaliadas e descartadas

- **DS-TCG405-E / TCG406-E** (IP 4MP, ANPR embarcado ≥98%, lê a placa na
  câmera): tecnicamente a melhor (~R$ 5.7-6.5 mil), mas exige cabo de rede/PoE
  até o ponto — não reusa o coax. Revisitar se a leitura de placas virar
  requisito crítico de segurança/controle de acesso.
- **Câmeras de captura TVI 1080p de terceiros** (linhas TLP-P, lente auto-iris
  6-50mm): projetadas para LPR, mas só 2MP e disponibilidade limitada no BR.
- **TVI box DS-2CC12D9T-A + lente C-mount 25-50mm**: rig clássico 1080p, mais
  peças e ajuste manual — plano B da opção coax.

### Estado atual (04/11/26)

- Experimento LPR 24h rodando com a cam_2 atual (`lpr-exp`, v0.4.3) para medir
  a taxa real de leitura com o main 3MP por playback do HD do DVR.
- Esta recomendação foi registrada SEM data de execução — abrir janela de
  instalação quando o Rafael decidir.
