# Task: RPv2 Begin Sync Handshake 2026-04-26

#ruraltech
#tarefas

## Context

Implementar o plano `/Users/victoremannuel/Downloads/ruraltech_rpv2_begin_sync_handshake_plan.md` para fechar o handshake síncrono entre `RTR_PAGE_ACK` e `RPV2_BEGIN`, removendo a lacuna em que a coleira deixava de escutar o `BEGIN` logo após transmitir o ACK do page.

## Action

- [x] Mapear o corredor crítico `RTR_PAGE_RX -> RTR_PAGE_ACK_TX -> RPV2_BEGIN`
- [x] Abrir janela imediata de `RPV2_BEGIN_RX` na coleira logo após `RTR_PAGE_ACK_TX`
- [x] Bloquear o retorno ao loop normal da coleira até `RPV2_BEGIN_RX_WINDOW_END`
- [x] Adicionar telemetria da janela imediata da coleira: `RPV2_BEGIN_RX_WINDOW_*`
- [x] Instrumentar `RPV2_BEGIN_ACK_PREPARE`, `RPV2_BEGIN_ACK_TX` e `RPV2_BEGIN_TO_ACK_LATENCY`
- [x] Adicionar `RPV2_BEGIN_TX_START` e as métricas separadas `RTR_ACK_TO_RPV2_BEGIN_TX_START_LATENCY` e `RTR_ACK_TO_RPV2_BEGIN_TX_OK_LATENCY` na matriz
- [x] Abrir `RPV2_BEGIN_ACK_RX_WINDOW_BEGIN` antes dos side effects lentos `awaiting_begin_ack/page_acked`
- [x] Adicionar telemetria da janela imediata da matriz: `RPV2_BEGIN_ACK_RX_WINDOW_*`
- [ ] Obter compilação conclusiva da coleira neste host
- [ ] Obter compilação conclusiva da matriz neste host
- [ ] Repetir bancada física provando `RTR_PAGE_ACK_TX -> RPV2_BEGIN_RX_WINDOW_BEGIN -> RPV2_BEGIN_RX -> RPV2_BEGIN_ACK_TX`
- [ ] Repetir bancada física provando `RPV2_BEGIN_TX_START -> RPV2_BEGIN_TX_OK -> RPV2_BEGIN_ACK_RX_WINDOW_BEGIN -> RPV2_BEGIN_ACK_RX`

## Status

Implementação aplicada localmente em `coleira/coleira.ino` e `gateway-matriz/gateway-matriz.ino`.

Validação local concluída:
- `git diff --check`
- `g++ -std=c++17 -Ifirmware/shared firmware/tests/rtr_diag_support_test.cpp`

Validação pendente:
- `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs coleira`
- `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`
- smoke físico `SET_FENCE` com auditoria serial dos novos marcadores

Blocker atual:
- `arduino-cli compile` voltou ao padrão histórico de hang silencioso neste host, sem saída útil após dezenas de segundos para coleira e matriz

## Next step

Executar compilação/flash em host estável e repetir a bancada serial exigindo:
- `RTR_PAGE_ACK_TX`
- `RPV2_BEGIN_RX_WINDOW_BEGIN`
- `RPV2_BEGIN_RX`
- `RPV2_BEGIN_ACK_TX`
- `RPV2_BEGIN_TX_START`
- `RPV2_BEGIN_TX_OK`
- `RPV2_BEGIN_ACK_RX_WINDOW_BEGIN`
- `RPV2_BEGIN_ACK_RX`

## Related

[[ack-to-rpv2-fast-handoff-2026-04-26]]
[[2026-04-26]]
