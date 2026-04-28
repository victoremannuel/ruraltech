# Task: RPv2 Points Fragment Handoff 2026-04-27

#ruraltech
#tarefas

## Context

Implementar o plano `/Users/victoremannuel/Downloads/ruraltech_rpv2_points_fragment_handoff_implementation_plan.md` para fechar o corredor síncrono entre `RPV2_POINTS fragment N ACK` e `RPV2_POINTS fragment N+1`, além de impedir que a sessão RPv2 da coleira volte a morrer como `RTR_PRESTART_TIMEOUT` depois do `BEGIN`.

## Action

- [x] Mapear o corredor crítico `POINTS_ACK -> next POINTS`
- [x] Colocar a coleira em estado explícito `rpv2InProgress` após `RPV2_BEGIN_RX`
- [x] Impedir `RTR_PRESTART_TIMEOUT` para sessões RPv2 já iniciadas
- [x] Abrir `RPV2_POINTS_RX_WINDOW_BEGIN` logo após `RPV2_POINTS_ACK_TX` quando ainda houver fragmentos
- [x] Instrumentar `RPV2_POINTS_ACK_PREPARE`, `RPV2_POINTS_ACK_TX`, `RPV2_POINTS_TO_ACK_LATENCY` e `RPV2_POINTS_RX_WINDOW_*`
- [x] Limpar sessão RPv2 zumbi da coleira quando o wake lock expira e o estado fica preso
- [x] Adicionar `RPV2_POINTS_TX_START` e `RPV2_POINTS_ACK_RX_WINDOW_*` na matriz
- [x] Validar ACK de pontos na matriz contra `fragmentIndex`, `acceptedPoints` e `nextExpectedFragment`
- [x] Remover o `delay` entre ACK de pontos e próximo TX na matriz
- [x] Adicionar log explícito `RPV2_SESSION_END_OK`
- [ ] Obter compilação conclusiva da coleira neste host
- [ ] Obter compilação conclusiva da matriz neste host
- [ ] Repetir bancada física provando `fragment 1 ACK -> fragment 2 RX`
- [ ] Repetir bancada física provando `fragment 2 ACK -> COMMIT/APPLY_STATUS`

## Status

Implementação aplicada localmente em `coleira/coleira.ino` e `gateway-matriz/gateway-matriz.ino`.

Validação local concluída:
- `git diff --check`
- `g++ -std=c++17 -Ifirmware/shared firmware/tests/rtr_diag_support_test.cpp`

Validação pendente:
- `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs coleira`
- `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`
- bancada serial `SET_FENCE` com os novos marcadores de `POINTS`

Blocker atual:
- `arduino-cli compile` continua entrando no padrão histórico de hang silencioso neste host, tanto para coleira quanto para matriz

## Next step

Executar compilação/flash em host estável e repetir a bancada exigindo:
- `RPV2_POINTS_ACK_TX fragmentIndex=1`
- `RPV2_POINTS_RX_WINDOW_BEGIN expectedFragment=2`
- `RPV2_POINTS_RX fragmentIndex=2`
- `RPV2_POINTS_ACK_TX fragmentIndex=2`
- `RPV2_POINTS_TX_OK fragmentIndex=2`
- `RPV2_POINTS_ACK_RX_WINDOW_BEGIN fragmentIndex=2`
- `RPV2_POINTS_ACK_RX fragmentIndex=2`
- `RPV2_SESSION_END_OK`

## Related

[[rpv2-begin-sync-handshake-2026-04-26]]
[[2026-04-27]]
