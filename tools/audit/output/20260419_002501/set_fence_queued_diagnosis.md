# Diagnóstico SET_FENCE parado em queued

**commandId:** `AUTO_AREA_FENCE:kQSjWOVdkqTNDM9WBggT:B222C54D07E35367:23A00185B336A70A`

**Classificação:** `fila nao consumida pela matriz ou captura serial inexistente`

**Racional:** o comando entrou em matrix_command_queues, mas nao ha qualquer evidência serial da matriz no run

## Resumo

- property_commands: `5`
- command_events: `1`
- matrix_queue: `1`
- property_events: `0`
- matrix raw bytes: `0`
- collar raw bytes: `0`
- matrix AREA_SYNC events: `0`
- collar AREA_SYNC events: `0`

## Respostas

- `comando_criado`: `True`
- `entrou_na_fila_da_matriz`: `True`
- `matriz_viu_o_comando`: `False`
- `matriz_tentou_enviar_lora`: `False`
- `coleira_recebeu`: `False`
- `houve_ack_ou_retorno_backend`: `False`

## Próximos passos

- confirmar serial manual da matriz antes do proximo teste
- confirmar porta serial e firmware gravado na matriz
- repetir rodada com listener stdout/stderr capturados
- comparar se a matriz em bancada esta consumindo matrix_command_queues para o runtime_id esperado
