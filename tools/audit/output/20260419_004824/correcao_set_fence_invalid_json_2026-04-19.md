# Correção SET_FENCE invalid_json — 2026-04-19

## Problema visado

A matriz já consultava a fila correta e recebia `HTTP 200`, mas ainda caía em:

- `QUEUE_FETCH_HTTP_OK_INVALID_JSON`
- seguido de `QUEUE_EMPTY`

Isso misturava dois estados semânticos diferentes:

- corpo realmente vazio
- corpo presente, porém inválido/incompatível para o parser local

## Hipótese principal

- a resposta da `matrix-cloud` ainda estava pesada demais para o ESP32
- o parser precisava aceitar um shape mais simples e também sanitizar prefixos indevidos antes do parse

## Correção aplicada

### `matrix-cloud`

- GET da fila agora consulta com:
  - `order by created_at_ms asc`
  - `limit 1`
- a resposta foi reduzida para um objeto simples:
  - `{ "command_id": "...", "payload": { ... } }`
- a function mantém `Content-Type` JSON via `corsHeaders()`
- logs da function agora incluem:
  - `runtimeId`
  - `queueKey` truncado
  - `itemCount`
  - `firstCommandId`
  - `firstCreatedAtMs`
  - `firstExpiresAtMs`
  - `responseShape`
  - `responseBytes`
  - `candidateExpired`
  - `empty`

### Matriz

- o loader agora:
  - sanitiza o corpo antes do parse, procurando o primeiro `{` ou `[`
  - registra quantos bytes de prefixo foram descartados
  - registra o erro real de desserialização (`InvalidInput`, `NoMemory`, `IncompleteInput`, `TooDeep`, `EmptyInput`)
  - diferencia `fila vazia` de `erro de conteúdo`
  - aceita durante a transição:
    - array com item
    - objeto simples `{ command_id, payload }`
    - objeto legado mapeado por `commandId`
  - promove campos do `payload` para o topo quando necessário
- quando há erro de parse com corpo presente, o fluxo não cai mais automaticamente em `QUEUE_EMPTY`

## Logs novos adicionados

- `QUEUE_DESERIALIZE_ERROR`
- `QUEUE_BODY_SANITIZED`

Além dos eventos da rodada anterior:

- `QUEUE_FETCH_HTTP_FAIL`
- `QUEUE_FETCH_HTTP_OK_EMPTY_ARRAY`
- `QUEUE_FETCH_HTTP_OK_NONEMPTY_ARRAY`
- `QUEUE_FETCH_HTTP_OK_OBJECT`
- `QUEUE_FETCH_HTTP_OK_UNEXPECTED_SHAPE`
- `QUEUE_FETCH_HTTP_OK_INVALID_JSON`
- `QUEUE_ITEM_FOUND`
- `QUEUE_ITEM_FILTERED_OUT`
- `COMMAND_MARK_DISPATCHING_BEGIN`

## Arquivos alterados

- `firmware/shared/AreaSyncLogger.h`
- `gateway-matriz/gateway-matriz.ino`
- `supabase/functions/matrix-cloud/index.ts`

## Expectativa de serial após o flash

Se a function devolver item simples corretamente:

- `QUEUE_FETCH_HTTP_OK_OBJECT`
- `QUEUE_ITEM_FOUND`
- `QUEUE_COMMAND_LOADED`
- `COMMAND_MARK_DISPATCHING_BEGIN`
- `DISPATCH_BEGIN`

Se ainda houver ruído antes do JSON:

- `QUEUE_BODY_SANITIZED`

Se o item ainda for grande demais ou inválido:

- `QUEUE_FETCH_HTTP_OK_INVALID_JSON`
- `QUEUE_DESERIALIZE_ERROR errorKind=NoMemory|InvalidInput|...`

Sem cair em `QUEUE_EMPTY` como se a fila estivesse vazia.

## Como validar

1. Flash da matriz com este patch
2. Deploy da `matrix-cloud`
3. Repetir a homologação E2E `SET_FENCE`
4. Conferir:
   - logs `matrix_queue_get` na function
   - serial da matriz com `QUEUE_BODY_SANITIZED` / `QUEUE_DESERIALIZE_ERROR` ou avanço para `QUEUE_ITEM_FOUND`

## Observações de validação local

- compilação do firmware da matriz deve passar nesta rodada
- `deno` não está instalado neste ambiente, então a validação sintática da function ficou limitada à revisão estática
