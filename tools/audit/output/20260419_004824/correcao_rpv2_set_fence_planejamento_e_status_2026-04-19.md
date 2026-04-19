# Correção RPv2 SET_FENCE — planejamento exato e status real — 2026-04-19

## Causa-raiz confirmada

O planner do `RPv2` ainda não usava o mesmo pipeline do envio real para medir o frame seguro.

Na prática:

- a matriz planejava com uma medição divergente
- o chunk planner podia concluir falsamente que nenhum ponto cabia
- o fluxo falhava com `reason=no_point_fits_in_frame` antes do rádio

Havia também um segundo defeito crítico:

- alguns caminhos marcavam `SET_FENCE` como `applied` cedo demais ao escolher `RPv2`
- isso criava risco de falso positivo mesmo sem `APPLY_STATUS` da coleira

## Mudança aplicada

### Matriz

- foi criada uma medição única do frame seguro em `LoRaGateway`
- o envio real da matriz agora usa essa mesma medição antes de transmitir
- o planner do `RPv2` passou a montar um `LoRaFrame` real de candidato e medir com a infraestrutura LoRa exata
- foram adicionados logs de:
  - `RPV2_BEGIN_SIZE_EVAL`
  - `RPV2_POINTS_SIZE_EVAL`
  - `RPV2_COMMIT_SIZE_EVAL`
  - `RPV2_PLAN_CHUNK_FIT`
  - `RPV2_PLAN_CHUNK_REJECT`
  - `RPV2_WAIT_ACK_*`
  - `RPV2_RX_ACK`
  - `RPV2_RX_NACK`
  - `RPV2_RX_APPLY_STATUS`
- o publisher de resultado passou a gravar:
  - `transport=radio_fence_v2`
  - `transportState`
  - `reasonCode`

### Status real

- foi removida a promoção precoce para `applied`
- agora o alvo só fica:
  - `terminal=true`
  - `ok=true`
  - `status=applied`

após `APPLY_STATUS` positivo real vindo da coleira

### Coleira

- foram adicionados logs de observabilidade:
  - `RPV2_BEGIN_RX`
  - `RPV2_POINTS_RX`
  - `RPV2_COMMIT_RX`
  - `RPV2_ACK_SENT`
  - `RPV2_NACK_SENT`
  - `RPV2_APPLY_STATUS_SENT`
  - `RPV2_STAGE_PROGRESS`
  - `RPV2_STAGE_COMPLETE`
  - `RPV2_CRC_OK`
  - `RPV2_CRC_FAIL`
  - `RPV2_SESSION_RESET`
  - `RPV2_ABORT_RX`

## Shared

- foram adicionados `static_assert` para os tamanhos on-wire
- foram criados testes nativos para:
  - codec
  - CRC
  - planner com a mesma conta de wire size usada no gateway
- foi adicionado um stub mínimo de `Arduino.h` só para testes host

## Arquivos alterados

- `gateway-matriz/LoRaGateway.h`
- `gateway-matriz/LoRaGateway.cpp`
- `gateway-matriz/gateway-matriz.ino`
- `coleira/coleira.ino`
- `firmware/shared/radio_proto_v2_types.h`
- `firmware/tests/rpv2_codec_test.cpp`
- `firmware/tests/rpv2_crc_test.cpp`
- `firmware/tests/rpv2_fence_planner_test.cpp`
- `firmware/tests/arduino_compat/Arduino.h`

## Resultado da validação local

### Testes nativos

- `rpv2_codec_test`: ok
- `rpv2_crc_test`: ok
- `rpv2_fence_planner_test`: ok

### Build da matriz

- `Sketch uses 1356875 bytes (69%)`
- `Global variables use 72916 bytes (22%)`

### Build da coleira

- `Sketch uses 1156369 bytes (58%)`
- `Global variables use 68464 bytes (20%)`

## Próxima validação de bancada

O próximo run deve procurar explicitamente:

1. `RPV2_BEGIN_SIZE_EVAL`
2. `RPV2_PLAN_CHUNK_FIT`
3. `RPV2_BEGIN_TX_OK`
4. `RPV2_BEGIN_RX`
5. `RPV2_ACK_SENT`
6. `RPV2_RX_ACK`
7. `RPV2_COMMIT_TX_OK`
8. `RPV2_COMMIT_RX`
9. `RPV2_APPLY_STATUS_SENT`
10. `RPV2_RX_APPLY_STATUS`

## Critério de sucesso desta rodada

Esta rodada fecha corretamente se:

- a matriz deixar de falhar em `no_point_fits_in_frame` para fences válidos
- nenhum caminho marcar `applied` antes do `APPLY_STATUS ok`
- a serial comprovar ida e volta do `RPv2`
