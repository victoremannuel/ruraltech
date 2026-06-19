# Diagnóstico SET_FENCE parado em queued

**commandId:** `AUTO_AREA_FENCE:kQSjWOVdkqTNDM9WBggT:7685085E8B9186D1:23A00185B336A70A`

**Classificação:** `ha sinais em ambas as pontas; revisar parser ou correlacao fina por commandId`

**Racional:** existem indícios seriais nas duas pontas, entao o problema pode estar na instrumentacao do teste ou na correlacao

## Resumo

- property_commands: `5`
- command_events: `1`
- matrix_queue: `1`
- property_events: `0`
- matrix raw bytes: `4946`
- collar raw bytes: `24939`
- matrix AREA_SYNC events: `0`
- collar AREA_SYNC events: `0`

## Respostas

- `comando_criado`: `True`
- `entrou_na_fila_da_matriz`: `True`
- `matriz_viu_o_comando`: `True`
- `matriz_tentou_enviar_lora`: `False`
- `coleira_recebeu`: `True`
- `houve_ack_ou_retorno_backend`: `False`

## Próximos passos

- confirmar serial manual da matriz antes do proximo teste
- confirmar porta serial e firmware gravado na matriz
- repetir rodada com listener stdout/stderr capturados
- comparar se a matriz em bancada esta consumindo matrix_command_queues para o runtime_id esperado
