# Verificação SET_FENCE queued — 2026-04-19

## 1. Arquivos inspecionados

- `supabase/functions/auto-sync-area-fence/index.ts`
- `supabase/functions/queue-lora-command/index.ts`
- `supabase/functions/_shared/supabase.ts`
- `supabase/functions/matrix-cloud/index.ts`
- `gateway-matriz/gateway-matriz.ino`
- `firmware/shared/AreaSyncLogger.h`
- `tools/audit/output/20260419_004824/area_sync_e2e_report.md`
- `tools/audit/output/20260419_004824/supabase_snapshots.jsonl`
- `tools/audit/output/20260419_004824/supabase_timeline.jsonl`
- `tools/audit/output/20260419_004824/serial_matrix_raw.log`
- `tools/audit/output/20260419_004824/serial_collar_raw.log`
- `tools/audit/output/20260419_004824/serial_matrix_listener_meta.json`
- `tools/audit/output/20260419_004824/serial_collar_listener_meta.json`

## 2. Função que consome a fila

- Arquivo: `gateway-matriz/gateway-matriz.ino`
- Função: `processNextQueuedCommand()`
- Resumo:
  - exige `queuePollingConfigured()`, `bindingReady`, `backhaulWindowOpen()`, ausência de operação ativa
  - lê a fila via `loadNextQueuedCommand()`
  - valida `expiresAtMs`, `propertyId`, `propertyScopeId`, `matrixGatewayId`
  - para `SET_FENCE`, `SET_PARAMS` e `PING`, chama `dispatchQueuedSimpleCommand()`
  - para rejeição/sucesso inicial publica status via `publishImmediateMatrixCommandResult()` ou `publishSimpleCommandResult()`

## 3. Função que trata SET_FENCE

- Arquivo: `gateway-matriz/gateway-matriz.ino`
- Função: `dispatchQueuedSimpleCommand()`
- Resumo:
  - lê `command`, `propertyId`, `propertyScopeId`, `matrixGatewayId`, `targetDeviceIds`, `payload`
  - injeta `cmd_id = commandId`
  - para `SET_FENCE`, faz `AS_MATRIX_DISPATCH_BEGIN`, `AS_MATRIX_LORA_TX_ATTEMPT` e chama `sendFenceCommandChunked()`
  - se o envio LoRa der certo, publica `dispatching` com `publishSimpleCommandResult("dispatching")`
  - se der errado, retorna `false` e o caller grava `failed`

## 4. Divergências entre payload real e esperado

| Campo | Observado | Esperado no consumidor | Compatível? | Observação |
|---|---|---|---|---|
| `command` | `SET_FENCE` | `SET_FENCE` | sim | comando suportado explicitamente |
| `commandId` | presente no topo | `commandDoc["commandId"]` via chave do item | sim | o firmware usa a chave da fila como `commandId` |
| `cmd_id` | presente no payload | `payload.cmd_id` | sim | ainda é reforçado no firmware |
| `points` | `[[lat, lon], ...]` com 6 pontos | array JSON em `payload.points` | sim | o consumidor só lê o array; não há divergência de shape aqui |
| `property_id` | presente no payload | usado como metadado de auditoria | sim | o gate principal usa `propertyId` do topo |
| `property_scope_id` | presente no payload | usado como metadado; gate usa topo | sim | o topo e o payload estão coerentes |
| `target_device_ids` | presente no payload | consumidor usa `targetDeviceIds` do topo | sim | backend grava ambos |
| `polygon_kind` | `area` | `polygon_kind` ou `polygonKind` | sim | `pickFirstText()` aceita ambos |
| `origin_doc_type` | `area` | `origin_doc_type` ou `originDocType` | sim | compatível |
| `origin_doc_id` | id da área | `origin_doc_id` ou `originDocId` | sim | compatível |
| `matrixRuntimeId` | `matriz_fazenda_01` | `matrixCloudId()` / caminho RTDB | sim | firmware e backend convergem |
| `matrixGatewayId` | `192.168.4.1` | comparado com binding da matriz | sim | bate com `gateways.id` e runtime_status |

Resposta da fase de contrato:
- o payload observado está compatível com o consumidor
- não foi encontrada divergência material de snake_case/camelCase para explicar o `queued`

## 5. Runtime e queue_key

- `matrixRuntimeId` no enqueue: `matriz_fazenda_01`
- `RTDB_MATRIX_ID` no firmware gravado: `matriz_fazenda_01`
- `queue_key` no Supabase (`matrix_queue_keys`): `HcTWH2NTTwED761QDPfuTtTOMA9inllJYO9WqmgOXJh6LQmuGjG5DqT3OPl8tHrk`
- `RTDB_QUEUE_KEY` no firmware gravado: `HcTWH2NTTwED761QDPfuTtTOMA9inllJYO9WqmgOXJh6LQmuGjG5DqT3OPl8tHrk`
- `binding_ready` observado no `gateways`/`runtime_status`: `true`
- `property_scope_id` observado no `gateways`/`runtime_status`: `9FFFC95AA1624895`

Conclusão desta fase:
- `runtime_id consistente`
- `queue_key consistente`

## 6. Comparação PING vs SET_FENCE

- O consumidor da fila é o mesmo para `PING` e `SET_FENCE`: `processNextQueuedCommand()`
- O primeiro caminho de status também é o mesmo:
  - aceita o item
  - chama `dispatchQueuedSimpleCommand()`
  - publica `dispatching` em `publishSimpleCommandResult()`
- A primeira divergência real entre os fluxos aparece dentro de `dispatchQueuedSimpleCommand()`:
  - `PING` usa `sendLoRaJsonFrame()`
  - `SET_FENCE` usa `sendFenceCommandChunked()`
- Porém a evidência do run `20260419_004824` não chegou nem ao primeiro log `AS_MATRIX_QUEUE_LOADED`, então a quebra observada está antes dessa divergência ou no máximo no carregamento da fila

Resposta objetiva:
- o que o `PING` tem que o `SET_FENCE` não tem?
  - na prática, só o caminho de envio LoRa simples (`sendLoRaJsonFrame`) em vez do chunked (`sendFenceCommandChunked`)
  - mas isso ainda não explica este run, porque não houve prova de entrada do `SET_FENCE` no dispatcher

## 7. Logs e observabilidade

Logs relevantes encontrados no firmware:
- `AS_MATRIX_QUEUE_LOADED`: prova que a matriz carregou um item `SET_FENCE` da fila
- `AS_MATRIX_QUEUE_ACCEPTED`: prova que passou pelos gates de validade/binding/scope/gateway
- `AS_MATRIX_QUEUE_REJECTED`: prova rejeição explícita com motivo
- `AS_MATRIX_DISPATCH_BEGIN`: prova entrada no handler do `SET_FENCE`
- `AS_MATRIX_LORA_TX_ATTEMPT` / `AS_MATRIX_LORA_TX_OK` / `AS_MATRIX_LORA_TX_FAIL`: provam tentativa de envio LoRa
- `AS_MATRIX_ACK_MATCH` / `AS_MATRIX_NACK_MATCH`: provam retorno correlacionado por `commandId`
- `AS_MATRIX_RESULT_PUBLISHED`: prova publicação de status final

Evidência do run real `20260419_004824`:
- `property_commands`: comando criado com `status=queued`
- `matrix_command_queues`: item presente para `matriz_fazenda_01` com o mesmo `queue_key` do firmware
- `matrix_command_results`: vazio para o `commandId`
- `property_command_events`: apenas evento inicial `queued`
- serial da matriz: sem `QUEUE_COMMAND_LOADED`, sem `DISPATCH_BEGIN`, sem `LORA_TX_OK`
- serial da coleira: sem `RX_FENCE_COMMAND`, sem `FENCE_APPLY_OK`, sem `ACK_SENT`

Conclusão desta fase:
- existe `lacuna de observabilidade` exatamente antes da carga efetiva do item da fila, porque os returns iniciais de `processNextQueuedCommand()` eram silenciosos

## 8. Primeiro ponto provável da quebra

`gateway-matriz/gateway-matriz.ino::processNextQueuedCommand()` está morrendo antes de produzir `AS_MATRIX_QUEUE_LOADED`, muito provavelmente em um gate silencioso (`queuePollingConfigured`, `bindingReady`, `backhaulWindowOpen`, operação ativa) ou retornando sem item em `loadNextQueuedCommand()`.

## 9. Necessita mudança de código?

`sim`

## 10. Mudança mínima recomendada

- Instrumentar `processNextQueuedCommand()` para emitir logs estruturados quando:
  - o poll é bloqueado antes do consumo
  - a leitura da fila não retorna item
- Esta mudança foi aplicada nesta rodada:
  - novo evento `QUEUE_POLL_SKIPPED`
  - novo evento `QUEUE_EMPTY`
  - ambos amortizados em 10s para evitar spam serial

## Conclusão técnica principal

- Classificação: `lacuna de observabilidade`
- Subclassificação operacional: `primeiro ponto provável da quebra antes do dispatcher`
- Leitura objetiva:
  - `SET_FENCE` está compatível com o consumidor
  - `runtime_id` e `queue_key` estão consistentes
  - a primeira transição `queued -> dispatching` existe no código para `SET_FENCE`
  - o run real não produziu evidência de entrada em `processNextQueuedCommand()` após `loadNextQueuedCommand()`
  - portanto a menor correção útil é fechar o ponto cego do consumidor da fila, não alterar o contrato nem a coleira
