# Correção SET_FENCE missing_points — 2026-04-19

## Causa-raiz confirmada

O `SET_FENCE` já chegava até a matriz, mas os pontos estavam aninhados em um nível adicional do payload:

- `payload.payload.points`

O envio LoRa usava apenas:

- `payload.points`

Por isso o fluxo avançava até:

- `QUEUE_ITEM_FOUND`
- `QUEUE_COMMAND_LOADED`
- `DISPATCH_BEGIN`

mas ainda falhava com:

- `LORA_TX_FAIL reason=missing_points`

## Mudança mínima aplicada

- foi criada uma resolução canônica dos pontos em cascata:
  - `root.points`
  - `payload.points`
  - `payload.payload.points`
- a normalização do payload passou a promover, quando necessário:
  - `points`
  - `cmd_id`
  - `command_id`
  - `property_id`
  - `property_scope_id`
  - `target_device_ids`
  - `target_gateway_ids`
  - `matrix_gateway_id`
  - `matrixRuntimeId`
  - `polygon_kind`
  - `origin_doc_type`
  - `origin_doc_id`
- `pointCount` agora é calculado a partir do payload já normalizado

## Logs novos

- `FENCE_POINTS_RESOLVED`
- `FENCE_POINTS_RESOLUTION_FAIL`

## Arquivos alterados

- `firmware/shared/AreaSyncLogger.h`
- `gateway-matriz/gateway-matriz.ino`

## Expectativa de validação em bancada

Após flash da matriz, ao repetir o E2E `SET_FENCE`, o esperado é:

1. `FENCE_POINTS_RESOLVED resolvedSource=payload.payload.points pointCount>0`
2. `QUEUE_COMMAND_LOADED ... pointCount>0`
3. `DISPATCH_BEGIN`
4. `LORA_TX_OK`

Se ainda falhar, o novo ponto de quebra deve aparecer explicitamente em:

- `FENCE_POINTS_RESOLUTION_FAIL`
ou
- `LORA_TX_FAIL` com outro motivo real
