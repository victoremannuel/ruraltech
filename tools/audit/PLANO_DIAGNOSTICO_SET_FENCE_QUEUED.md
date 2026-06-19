# Plano de diagnóstico — `SET_FENCE` parado em `queued`

## Contexto

Na execução `tools/e2e/area_sync_e2e.py` do run `20260419_002501`, o fluxo evidenciado foi:

- área existente localizada
- polígono alterado
- update no Supabase concluído com sucesso
- `commandId` gerado
- transição de status observada apenas até `queued`
- ausência de evidência serial na matriz
- ausência de evidência serial na coleira
- ausência de eventos parseados em `serial_matrix_area_sync.jsonl`
- ausência de eventos parseados em `serial_collar_area_sync.jsonl`

Resumo do diagnóstico atual:

```text
área alterada -> commandId criado -> status = queued
```

O fluxo **não** foi homologado ponta a ponta para o caminho:

```text
app/supabase -> matrix_command_queues -> matriz -> LoRa -> coleira -> ACK -> persistência de resultado
```

---

## Objetivo

Identificar exatamente em qual ponto o comando `SET_FENCE` deixa de avançar após entrar em `queued`, produzindo evidência suficiente para classificar o caso em uma destas categorias:

1. **fila não consumida pela matriz**
2. **matriz consumiu, mas não despachou LoRa**
3. **LoRa foi despachado, mas a coleira não recebeu ou não aplicou**
4. **a telemetria/logs existem, mas não foram capturados/parsers não reconheceram**
5. **o fluxo completo funciona e o problema estava apenas na instrumentação do teste**

---

## Hipótese principal

A hipótese principal, com base nos artefatos atuais, é:

> o comando está sendo criado corretamente no backend, porém a matriz da bancada não está consumindo ou não está evidenciando o consumo da fila do downlink cloud.

---

## Critério de sucesso

O plano será considerado concluído quando for possível responder, com evidência objetiva, às perguntas abaixo:

- o comando entrou na fila correta?
- a matriz carregou esse `commandId`?
- a matriz tentou transmitir esse comando por LoRa?
- a coleira recebeu e processou o comando?
- houve ACK, timeout, erro de roteamento ou silêncio total?

---

## Artefatos de referência desta falha

Run analisado:

- `tools/audit/output/20260419_002501/supabase_timeline.jsonl`
- `tools/audit/output/20260419_002501/supabase_snapshots.jsonl`
- `tools/audit/output/20260419_002501/serial_matrix_raw.log`
- `tools/audit/output/20260419_002501/serial_matrix_area_sync.jsonl`
- `tools/audit/output/20260419_002501/serial_collar_raw.log`
- `tools/audit/output/20260419_002501/serial_collar_area_sync.jsonl`

---

## Estratégia de execução

A investigação deve seguir de cima para baixo, travando o ponto exato onde a evidência desaparece:

1. confirmar criação correta do comando no backend
2. confirmar presença do comando na fila consumida pela matriz
3. confirmar execução do consumidor na matriz
4. confirmar tentativa de envio LoRa
5. confirmar recepção/processamento na coleira
6. confirmar retorno/ACK e persistência no backend

---

## Etapa 1 — Validar o comando no backend

### Objetivo

Comprovar que o `SET_FENCE` foi materializado corretamente no Supabase.

### Verificações

- localizar o `commandId` gerado no run
- validar `deviceId`, `propertyId`, `areaId` e payload do polígono
- verificar se o comando foi escrito também na estrutura usada pela matriz para consumo
- verificar timestamps de criação e eventual atualização

### Evidência esperada

Pelo menos uma destas situações deve ficar provada:

- o comando existe apenas no registro principal e **não** foi propagado para a fila da matriz
- o comando existe no registro principal **e** na fila de consumo da matriz

### Resultado possível

- **Se não entrou na fila da matriz:** corrigir backend/pipeline de enfileiramento
- **Se entrou na fila da matriz:** avançar para a etapa 2

---

## Etapa 2 — Confirmar se a matriz está consumindo a fila

### Objetivo

Descobrir se a matriz da bancada está ativa como consumidora do downlink cloud.

### Checklist

- confirmar que a matriz usada no teste é de fato a placa esperada
- confirmar porta serial correta
- confirmar firmware atual na matriz
- confirmar que o firmware contém os logs de auditoria esperados, especialmente algo como:
  - `QUEUE_COMMAND_LOADED`
  - `DISPATCH_BEGIN`
  - `LORA_TX_OK`
  - `LORA_TX_FAIL`
  - `COMMAND_ACK`
  - `[AREA_SYNC][MATRIX] ...`
- confirmar configuração de `DIAG_STAGE` e demais flags de diagnóstico
- confirmar que a matriz está online e fazendo polling/stream/consulta do backend

### Evidência esperada

No momento em que o comando entra em `queued`, deve existir ao menos um log da matriz indicando que o comando foi visto.

### Interpretação

- **Sem qualquer log da matriz sobre o `commandId`:** a fila não está sendo consumida ou a instrumentação não está embarcada
- **Com log de carga do comando, mas sem envio LoRa:** o problema está na camada da matriz após o consumo

---

## Etapa 3 — Validar instrumentação serial da matriz

### Objetivo

Eliminar a possibilidade de falso negativo por captura/parsing.

### Ações

- abrir serial da matriz manualmente antes do teste
- reiniciar a matriz e observar logs de boot
- disparar um comando simples e conhecido para verificar se os logs aparecem
- conferir se o listener atual reconhece exatamente o formato emitido pela matriz
- comparar `serial_matrix_raw.log` com o parser que gera `serial_matrix_area_sync.jsonl`

### Evidência esperada

- se o raw log mostrar atividade e o JSONL continuar vazio, o parser está incompleto
- se o raw log também estiver vazio, o problema é captura, porta errada, baud rate ou ausência de logs no firmware

### Resultado possível

- **Problema de parser/listener**
- **Problema de instrumentação do firmware**
- **Problema real de não consumo**

---

## Etapa 4 — Confirmar tentativa de downlink LoRa

### Objetivo

Verificar se a matriz tentou despachar o comando para a coleira.

### Evidências que devem existir

- log de início de dispatch do `commandId`
- log de serialização do payload
- log de envio LoRa com `deviceId` alvo
- log de sucesso ou falha da transmissão

### Interpretação

- **Consumiu fila, mas não há `DISPATCH_BEGIN`:** falha na lógica de seleção/processamento do comando
- **Há `DISPATCH_BEGIN`, mas não há `LORA_TX_OK`/`LORA_TX_FAIL`:** falha antes do rádio
- **Há `LORA_TX_FAIL`:** investigar rádio/configuração/endereçamento
- **Há `LORA_TX_OK`:** avançar para a etapa 5

---

## Etapa 5 — Confirmar recepção e aplicação na coleira

### Objetivo

Descobrir se a coleira recebeu, validou e aplicou o `SET_FENCE`.

### Evidências esperadas na coleira

- log de recepção do comando
- identificação do `commandId`
- validação de integridade/autenticidade
- escrita do polígono local
- confirmação de persistência local
- eventual ACK de volta à matriz
- evento local de atualização da geofence

### Interpretação

- **Sem log na coleira e com `LORA_TX_OK` na matriz:** falha de rádio/endereçamento/criptografia/compatibilidade de payload
- **Com log de recepção, mas sem aplicação:** falha de parsing, validação ou persistência local
- **Com aplicação e sem ACK:** falha no retorno da confirmação

---

## Etapa 6 — Confirmar retorno ao backend

### Objetivo

Fechar a auditoria ponta a ponta após o processamento local.

### Verificações

- mudança de status além de `queued`
- registro de entrega, timeout, erro ou sucesso
- atualização em timeline/snapshots
- correlação do `commandId` com logs da matriz e da coleira

### Resultado esperado ideal

```text
queued -> picked_up_by_matrix -> dispatched -> received_by_collar -> applied -> acked -> persisted
```

Mesmo que esses nomes exatos de status não existam hoje, a auditoria precisa mostrar equivalentes claros.

---

## Plano de execução prático

### Rodada 1 — Confirmar se a matriz está realmente instrumentada

1. conectar somente a matriz
2. abrir serial manualmente
3. reiniciar a placa
4. verificar logs de boot
5. confirmar presença de logs `[AREA_SYNC]` ou equivalentes
6. registrar hash/versão/commit do firmware gravado

**Saída esperada:** prova de que a matriz em bancada está ou não com o firmware correto.

### Rodada 2 — Confirmar consumo da fila sem depender da coleira

1. deixar só a matriz ligada
2. disparar alteração de área
3. observar se o `commandId` aparece na matriz
4. correlacionar com Supabase

**Saída esperada:** prova de consumo ou não consumo da fila.

### Rodada 3 — Confirmar dispatch LoRa

1. manter matriz e coleira ligadas
2. disparar novo `SET_FENCE`
3. observar logs da matriz para dispatch
4. observar logs da coleira para recepção

**Saída esperada:** ponto exato da quebra entre matriz e coleira.

### Rodada 4 — Validar parser/listener

1. comparar o conteúdo dos raw logs com o JSONL gerado
2. ajustar regex/parsers se houver eventos não reconhecidos
3. repetir um teste curto até aparecer correlação automática correta

**Saída esperada:** confiança nos artefatos automáticos do teste.

---

## Perguntas que precisam ser respondidas nesta ordem

1. o comando foi criado corretamente?
2. ele entrou na fila consumida pela matriz?
3. a matriz viu esse comando?
4. a matriz tentou enviar?
5. a coleira recebeu?
6. a coleira aplicou?
7. houve ACK?
8. o backend registrou o desfecho?

Se qualquer resposta for “não”, esse ponto vira o foco da correção.

---

## Possíveis causas-raiz mais prováveis

### Grupo A — Backend / fila

- trigger/pipeline cria o comando, mas não replica para a fila consumida pela matriz
- filtro por propriedade/dispositivo impede enqueue real
- comando fica `queued` em uma tabela, mas a matriz lê outra fonte

### Grupo B — Matriz

- firmware da matriz sem consumidor habilitado
- firmware da matriz sem logs de auditoria embarcados
- matriz em porta errada, baud errado ou placa errada
- `DIAG_STAGE`/flags não ativam o comportamento esperado

### Grupo C — Rádio / protocolo

- dispatch não chega a ser chamado
- endereçamento LoRa incorreto
- payload acima do suportado ou em formato inesperado
- incompatibilidade de criptografia/serialização

### Grupo D — Coleira

- coleira recebe, mas rejeita payload
- coleira recebe, mas falha ao persistir fence local
- coleira aplica e não envia ACK

### Grupo E — Observabilidade

- o fluxo acontece, mas a serial não captura
- o raw captura, mas o parser não reconhece
- o backend não reflete o status intermediário

---

## Saída final esperada da auditoria

Ao fim da próxima rodada, o relatório deve encerrar com uma frase binária e objetiva como uma destas:

- **PASSOU:** `SET_FENCE` saiu do app, foi consumido pela matriz, transmitido por LoRa, aplicado na coleira e confirmado com evidência correlacionada por `commandId`.
- **FALHOU NA FILA:** comando criado no backend, mas não consumido pela matriz.
- **FALHOU NA MATRIZ:** matriz consumiu, mas não transmitiu.
- **FALHOU NO RÁDIO/PROTOCOLO:** matriz transmitiu, mas coleira não recebeu/processou.
- **FALHOU NA COLEIRA:** recepção ocorreu, mas não houve aplicação local ou ACK.
- **FALHOU NA OBSERVABILIDADE:** há indícios do fluxo, mas a instrumentação atual não permite comprovação robusta.

---

## Próxima ação recomendada

Executar primeiro a **Rodada 1** e a **Rodada 2**, porque hoje o maior indício é de quebra antes da primeira evidência da matriz.

Enquanto isso, qualquer ajuste na lógica da coleira deve ser adiado, pois ainda não existe prova de que o `SET_FENCE` sequer está sendo efetivamente despachado pela matriz.
