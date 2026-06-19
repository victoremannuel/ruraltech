# Implementação base do Radio Protocol v2 para SET_FENCE — 2026-04-19

## Escopo implementado nesta rodada

Foi implementado o núcleo firmware do `RPv2` para `SET_FENCE`, mantendo a camada LoRa segura já existente e trocando apenas o payload interno no enlace matriz -> coleira.

Entrou nesta rodada:

- contratos compartilhados do `RPv2` em `firmware/shared/`
- planejamento binário por tamanho real do frame seguro na matriz
- envio sequencial `BEGIN -> POINTS -> COMMIT` na matriz
- recepção binária na coleira
- ACK/NACK binários por etapa
- `APPLY_STATUS` binário ao final do commit válido

## O que ainda não entrou nesta rodada

Ainda não foi migrado nesta mesma passada:

- cache formal de capability no backend/cloud
- timeline detalhada de transporte no Supabase
- mapeamento de UI no app
- staging dual-bank em EEPROM externa 24LC256

Na coleira, o staging desta rodada ficou em memória e a persistência só acontece no `COMMIT` válido via caminho já existente de `persistFence(...)`.

## Mudança técnica principal

O `SET_FENCE` deixa de depender do JSON chunked para o transporte LoRa quando passa pelo caminho novo e usa o `RPv2` binário:

1. a matriz normaliza os pontos
2. converte para `latE7/lonE7`
3. calcula `radio_command_id` com `FNV-1a 64`
4. calcula `CRC32` do fence lógico
5. planeja os chunks com base no tamanho final do frame seguro
6. envia `BEGIN`
7. envia `POINTS`
8. envia `COMMIT`
9. aguarda `APPLY_STATUS`

## Arquivos alterados

- `firmware/shared/radio_proto_v2_constants.h`
- `firmware/shared/radio_proto_v2_reason_codes.h`
- `firmware/shared/radio_proto_v2_id.h`
- `firmware/shared/radio_proto_v2_crc.h`
- `firmware/shared/radio_proto_v2_types.h`
- `firmware/shared/radio_proto_v2_codec.h`
- `gateway-matriz/gateway-matriz.ino`
- `coleira/coleira.ino`

## Resultado das builds

### Matriz

- `Sketch uses 1351251 bytes (68%)`
- `Global variables use 72884 bytes (22%)`

### Coleira

- `Sketch uses 1154549 bytes (58%)`
- `Global variables use 68464 bytes (20%)`

## Como validar agora

1. gravar matriz e coleira com estes firmwares
2. disparar novo `SET_FENCE`
3. confirmar que o comando sai da matriz sem usar chunk JSON textual
4. confirmar na serial da coleira a recepção da sessão binária
5. verificar:
   - ACK do `BEGIN`
   - ACK dos `POINTS`
   - ACK do `COMMIT`
   - `APPLY_STATUS` positivo

## Risco residual desta rodada

Como capability/backhaul/status publisher completo ainda não foi migrado para o novo modelo, esta rodada entrega o núcleo do protocolo no firmware, mas ainda não o ciclo completo de produto descrito no plano.
