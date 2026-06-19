# Correção SET_FENCE payload_too_large — 2026-04-19

## Causa-raiz confirmada

O `SET_FENCE` já entrava no caminho fragmentado, mas o planejamento dos chunks subestimava o overhead real do payload transmitido.

O planner antigo considerava basicamente:

- `chunked`
- `part`
- `total`
- `points`

Mas o chunk real ainda carregava metadados adicionais como:

- `cmd_id`
- `scope_id`
- `polygon_kind`
- `origin_doc_type`
- `origin_doc_id`

Com isso, a matriz ainda planejava `total=1` para um payload que já excedia `cfg::LORA_MAX_PAYLOAD_BYTES`.

## Mudança mínima aplicada

- foi criado um planner específico para `SET_FENCE`:
  - `splitFencePointArrayForPayload(...)`
- esse planner calcula o custo de chunk usando um `probe` com o overhead real dos campos que o chunk final carrega
- o chunk do `SET_FENCE` foi enxugado:
  - removeu `matrix_gateway_id`
  - removeu `requested_at_ms`
- a matriz agora loga a avaliação de tamanho por chunk antes do envio

## Log novo

- `FENCE_CHUNK_SIZE_EVAL`

Campos:

- `commandId`
- `part`
- `total`
- `jsonBytes`
- `packedBytes`
- `cipherBytes`
- `limitBytes`

## Arquivos alterados

- `firmware/shared/AreaSyncLogger.h`
- `gateway-matriz/gateway-matriz.ino`

## Expectativa em bancada

Depois do flash, o esperado é:

1. `FENCE_POINTS_RESOLVED ... pointCount>0`
2. `QUEUE_COMMAND_LOADED ... pointCount>0`
3. `DISPATCH_BEGIN`
4. `LORA_TX_ATTEMPT part=0 total>1` ou `LORA_TX_OK`
5. `FENCE_CHUNK_SIZE_EVAL` mostrando chunks dentro do orçamento

Se ainda falhar, o próximo motivo deve ficar explícito no chunk que exceder o limite real.
