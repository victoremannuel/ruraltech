# Correção SET_FENCE point_chunk_too_large — 2026-04-19

## Causa-raiz confirmada

O `SET_FENCE` já tinha saído da fase de normalização e do `missing_points`, mas o planner ainda definia os chunks com uma estimativa incremental de custo.

Isso deixava um buraco entre:

- o chunk "planejado"
- e o chunk realmente serializado e enviado

Na prática, a matriz podia aceitar um intervalo de pontos durante o planejamento e só descobrir tarde demais que aquele pedaço ainda ficava grande demais, gerando nova quebra em `point_chunk_too_large`.

## Mudança mínima aplicada

- o planner de `SET_FENCE` deixou de usar a heurística por delta de ponto
- a matriz agora monta um payload candidato real para cada faixa `[start,end)`
- cada candidato é medido com `measureJson(...)` sobre o mesmo shape do envio final
- o planner tenta primeiro o maior intervalo restante e reduz progressivamente até caber
- o envio final passou a reutilizar a mesma rotina de montagem de chunk usada no planejamento
- quando nem um chunk com 1 ponto couber, a falha agora fica explícita como:
  - `fence_single_point_chunk_too_large`

## Log novo

- `FENCE_CHUNK_PLAN`

Campos:

- `commandId`
- `start`
- `end`
- `pointCount`
- `jsonBytes`
- `packedBytes`
- `cipherBytes`
- `limitBytes`
- `fit`

Esse log mostra exatamente quais faixas de pontos foram testadas e em qual tentativa o payload passou a caber.

## Arquivos alterados

- `firmware/shared/AreaSyncLogger.h`
- `gateway-matriz/gateway-matriz.ino`

## Resultado da build

- `Sketch uses 1346995 bytes (68%)`
- `Global variables use 72884 bytes (22%)`

## Como validar na bancada

1. Regravar a matriz com este firmware
2. Disparar nova alteração de área via cloud
3. Procurar na serial:
   - `FENCE_POINTS_RESOLVED`
   - `QUEUE_COMMAND_LOADED ... pointCount>0`
   - `FENCE_CHUNK_PLAN ... fit=0` seguido de uma tentativa menor com `fit=1`
   - `FENCE_CHUNK_SIZE_EVAL`
   - `LORA_TX_ATTEMPT`
   - `LORA_TX_OK`

## Se ainda falhar

O próximo ponto de quebra deve ficar explícito em uma destas formas:

- `fence_single_point_chunk_too_large`
- `payload_too_large`
- `lora_send_failed`

Com isso, a próxima rodada deixa de ser adivinhação e passa a ser um ajuste orientado pelo payload real.
