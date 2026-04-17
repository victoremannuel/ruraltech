# Task: Auditoria ponta a ponta — atualização de área (SET_FENCE)

#ruraltech
#tarefas

## Contexto

Implementação de observabilidade E2E para o fluxo de atualização de área:
`app/backend → Supabase → auto-sync-area-fence → property_commands → matrix_command_queues → gateway-matriz → (LoRa) → coleira → apply + ACK + polygon_apply_result → Supabase`

## Action

- [x] Criar `firmware/shared/AreaSyncLogger.h` com macros `[AREA_SYNC][ROLE][LEVEL][EVENT]`
- [x] Adicionar logs `[AREA_SYNC][MATRIX]` no `gateway-matriz/gateway-matriz.ino`:
  - `QUEUE_COMMAND_LOADED` / `QUEUE_COMMAND_ACCEPTED` / `QUEUE_COMMAND_REJECTED`
  - `DISPATCH_BEGIN` / `DISPATCH_TARGET`
  - `LORA_TX_ATTEMPT` / `LORA_TX_OK` / `LORA_TX_FAIL`
  - `ACK_MATCH` / `NACK_MATCH`
  - `COLLAR_EVENT_POLYGON_APPLY_SUCCESS` / `COLLAR_EVENT_POLYGON_APPLY_FAILURE`
  - `COMMAND_RESULT_PUBLISHED`
- [x] Adicionar logs `[AREA_SYNC][COLLAR]` no `coleira/coleira.ino`:
  - `RX_FENCE_COMMAND` / `RX_FENCE_CHUNK_BEGIN` / `RX_FENCE_CHUNK_APPEND` / `RX_FENCE_CHUNK_FINAL`
  - `BINDING_MISSING` / `SCOPE_MISMATCH` / `PARSE_FAIL` / `ASSEMBLE_FAIL`
  - `FENCE_APPLY_OK` / `POLYGON_AUDIT_EVENT_QUEUED`
  - `ACK_SENT` / `NACK_SENT`
- [x] Documentar gateway comum como N/A: firmware `gateway/` não participa do caminho SET_FENCE
- [x] Criar `tools/audit/serial_listener.py` — listener serial parseável com saída `.log` + `.jsonl`
- [x] Criar `tools/audit/supabase_poller.py` — polling de `property_commands`, `property_command_events`, `matrix_command_queues`, `propertyEvents`
- [x] Criar `tools/e2e/area_sync_e2e.py` — orquestrador E2E: busca área, aplica delta ~1m, dispara, aguarda terminal, gera relatório
- [ ] **Regravar firmwares** (gateway-matriz + coleira) — aguardando confirmação do usuário
- [ ] Executar auditoria de campo com serial monitor + Supabase
- [ ] Gerar relatório final em `tools/audit/output/<timestamp>/`

## Status

**Aguardando regravação de firmwares pelo usuário.**

## Gateway comum

O firmware em `gateway/` atua como nó LoRa relay genérico — não possui lógica de despacho de comandos SET_FENCE nem participa ativamente do caminho auditado. Logs `[AREA_SYNC][COMMON_GATEWAY]` foram reservados no `AreaSyncLogger.h` para uso futuro, mas não foram instrumentados nesta iteração (não aplicável no estado atual do repositório).

## Critérios de aceite

1. Área alterada no banco
2. Edge function gerou comando novo
3. `property_commands` contém `originDocType=area` + `originDocId=<areaId>`
4. Matriz logou `QUEUE_COMMAND_LOADED` + `LORA_TX_OK`
5. Coleira logou `RX_FENCE_COMMAND` + `FENCE_APPLY_OK`
6. Coleira logou `ACK_SENT`
7. Matriz logou `COLLAR_EVENT_POLYGON_APPLY_SUCCESS`
8. Supabase refletiu resultado final
9. Todos os registros correlacionados pelo mesmo `commandId`

## Próximo passo

Usuário regrava gateway-matriz e coleira → confirma → executar `tools/e2e/area_sync_e2e.py`

## Related

[[fluxo-comandos]]
[[auditoria-app-to-coleira-v2.4.0]]
