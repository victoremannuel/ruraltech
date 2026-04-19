# Correção SET_FENCE queue empty — 2026-04-19

## Hipótese atacada

- `Hipótese A`: a matriz recebe resposta válida da fila em shape inesperado
- `Hipótese B`: `loadNextQueuedCommand()` interpreta errado uma resposta válida e termina como `QUEUE_EMPTY`

## Logs novos adicionados

### Matriz

- `QUEUE_FETCH_HTTP_FAIL`
- `QUEUE_FETCH_HTTP_OK_EMPTY_ARRAY`
- `QUEUE_FETCH_HTTP_OK_NONEMPTY_ARRAY`
- `QUEUE_FETCH_HTTP_OK_OBJECT`
- `QUEUE_FETCH_HTTP_OK_INVALID_JSON`
- `QUEUE_FETCH_HTTP_OK_UNEXPECTED_SHAPE`
- `QUEUE_PARSE_FAIL`
- `QUEUE_ITEM_FOUND`
- `QUEUE_ITEM_FILTERED_OUT`
- `COMMAND_MARK_DISPATCHING_BEGIN`

### Edge function `matrix-cloud`

- `matrix_queue_get` com:
  - `runtimeId`
  - `queueKey` truncado
  - `itemCount`
  - `firstCommandId`
  - `firstCreatedAtMs`
  - `empty`

## Correção aplicada

- o loader da matriz agora aceita e diferencia:
  - objeto mapeado por `commandId`
  - array de itens
  - JSON inválido
  - shape inesperado
  - corpo vazio/nulo
- o loader também normaliza campos vindos aninhados em `payload` quando necessário:
  - `command`
  - `commandId`
  - `propertyId`
  - `propertyScopeId`
  - `matrixGatewayId`
  - `targetDeviceIds`
  - `targetGatewayIds`
  - `createdAtMs`
  - `expiresAtMs`
- antes de publicar `dispatching`, a matriz agora emite `COMMAND_MARK_DISPATCHING_BEGIN`
- filtros locais relevantes agora logam `expected` vs `actual`

## Arquivos alterados

- `firmware/shared/AreaSyncLogger.h`
- `gateway-matriz/gateway-matriz.ino`
- `supabase/functions/matrix-cloud/index.ts`

## Expectativa de serial após o flash

Se a fila vier vazia de verdade:
- `QUEUE_FETCH_HTTP_OK_EMPTY_ARRAY`
- ou `QUEUE_FETCH_HTTP_OK_OBJECT` com `itemCount=0` seguido de `QUEUE_EMPTY`

Se a fila vier em shape incompatível:
- `QUEUE_FETCH_HTTP_OK_UNEXPECTED_SHAPE`
- ou `QUEUE_FETCH_HTTP_OK_INVALID_JSON`

Se a fila vier com item válido:
- `QUEUE_ITEM_FOUND`
- `QUEUE_COMMAND_LOADED`
- `QUEUE_COMMAND_ACCEPTED`
- `COMMAND_MARK_DISPATCHING_BEGIN`
- `DISPATCH_BEGIN`

Se o item for descartado por regra local:
- `QUEUE_ITEM_FILTERED_OUT`
- `QUEUE_COMMAND_REJECTED`

## Próximos passos de validação

1. Flash da matriz com este patch
2. Repetir a homologação E2E `SET_FENCE`
3. Conferir serial da matriz e logs da edge function `matrix_queue_get`
4. Classificar o ponto exato:
   - resposta vazia real
   - resposta incompatível
   - item carregado
   - item filtrado localmente
