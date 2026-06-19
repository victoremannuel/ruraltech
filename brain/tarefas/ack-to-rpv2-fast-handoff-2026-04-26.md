# Task: ACK to RPv2 Fast Handoff 2026-04-26

#ruraltech
#tarefas

## Context

Implementar o plano `ruraltech_ack_to_rpv2_fast_handoff_plan.md` para remover trabalho lento entre `RTR_PAGE_ACK` e `RPV2 BEGIN` na `gateway-matriz`, preservando a janela síncrona de ACK já estabilizada na rodada anterior.

## Action

- [x] Identificar o caminho atual onde `RTR_PAGE_ACK` ainda dispara side effects lentos antes do `BEGIN`
- [x] Separar o consumo rápido do ACK dos side effects lentos de progresso/evento
- [x] Fechar a `RTR_PAGE_ACK_RX_WINDOW` antes de iniciar o handoff para `RPV2 BEGIN`
- [x] Iniciar o primeiro `RPV2 BEGIN` diretamente do fast path pós-ACK, sem depender do wake loop deferred
- [x] Remover `SET_FENCE_PROGRESS awaiting_begin_ack` do trecho anterior ao `BEGIN_TX`
- [x] Adicionar marcadores e métricas `RTR_ACK_TO_RPV2_*` em memória e no `/status`
- [x] Validar localmente com testes host-side do suporte diagnóstico
- [ ] Conseguir compilação conclusiva da `gateway-matriz` neste host
- [ ] Repetir bancada física confirmando `RTR_PAGE_ACK_FAST_PATH_MATCH -> RTR_PAGE_ACK_RX -> RTR_PAGE_ACK_RX_WINDOW_END -> RTR_ACK_TO_RPV2_FAST_HANDOFF_BEGIN -> RPV2_BEGIN_TX_OK`

## Status

Implementação local concluída no código da matriz.

Validação local concluída:
- `firmware/tests/rtrv1_page_ack_window_diag_test.cpp`
- `firmware/tests/rtrv1_page_ack_correlation_test.cpp`
- `firmware/tests/rtrv1_fast_path_priority_test.cpp`
- `git diff --check`

Validação pendente:
- `arduino-cli compile` da matriz continua inconclusivo neste host por hang silencioso
- bancada física ainda não executada após esta rodada

## Next step

Obter um build conclusivo da `gateway-matriz`, gravar a placa e repetir o smoke físico `SET_FENCE`, medindo especialmente `pageAck.lastAckToRpv2BeginLatencyMs` e a ausência de `CLOUD_TX_BEGIN`/`COMMAND_MARK_DISPATCHING_BEGIN` antes de `RPV2_BEGIN_TX_OK`.

## Related

[[reaproveitamento-area-sync-queue-downlink-cloud-2026-04-18]]
[[2026-04-26]]
