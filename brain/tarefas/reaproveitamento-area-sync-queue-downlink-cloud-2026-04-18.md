# Task: Reaproveitamento Area Sync para Queue Downlink Cloud 2026-04-18

#ruraltech
#tarefas

## Context

Reaproveitar o material da task `auditoria-area-sync-e2e.md` como base operacional da proxima fase de validacao do fluxo `cloud -> matriz -> coleira`, com foco em `SET_FENCE` via `property_commands -> matrix_command_queues`, sem reabrir investigacao de deep sleep, uplink local ou relay.

Estado de partida consolidado nesta rodada:
- `DIAG_STAGE=4` ja esta preparado na matriz para cloud/backhaul sem relay
- a coleira permanece sem novas mudancas
- relay RF segue fora desta fase
- o objetivo imediato passa a ser homologar `queue/downlink cloud` com rastreabilidade por `commandId`

## Action

- [x] Revisar o plano `plano_reaproveitamento_area_sync_queue_downlink_cloud_ia.md`
- [x] Confirmar que a task base `auditoria-area-sync-e2e.md` ja documenta a trilha E2E `SET_FENCE`
- [x] Confirmar presenca dos logs estruturados `[AREA_SYNC]` no firmware:
  - matriz com eventos de fila, despacho LoRa, ACK/NACK e publicacao de resultado
  - coleira com eventos de recepcao, montagem, apply e ACK/NACK
- [x] Confirmar existencia dos scripts de apoio:
  - `tools/audit/serial_listener.py`
  - `tools/audit/supabase_poller.py`
  - `tools/e2e/area_sync_e2e.py`
- [x] Confirmar que as dependencias declaradas para os scripts ja cobrem `pyserial` e `httpx`
- [x] Definir que o primeiro caso de homologacao do downlink cloud sera `SET_FENCE`
- [x] Criar ambiente virtual local em `tools/audit/.venv` com `pyserial` e `httpx` instalados para executar a trilha de auditoria sem depender do Python global
- [x] Ajustar `tools/e2e/area_sync_e2e.py` para:
  - expor `--help` sem falhar antes por ambiente
  - consolidar `commandId` no relatorio final a partir dos artefatos do poller
- [x] Executar uma rodada real de homologacao E2E `SET_FENCE` com:
  - matriz em `/dev/tty.usbserial-59470049741`
  - coleira em `/dev/tty.usbserial-1420`
  - restauracao do poligono original ao final
- [x] Executar verificacao estatica/evidencial do `SET_FENCE` preso em `queued` cobrindo:
  - contrato backend -> matriz
  - consistencia de `matrixRuntimeId`
  - consistencia de `queue_key`
  - comparacao `PING` vs `SET_FENCE`
  - localizacao da primeira transicao de status no codigo
- [x] Aplicar instrumentacao minima na matriz para fechar o ponto cego antes do dispatcher:
  - evento `[AREA_SYNC][MATRIX][WARN][QUEUE_POLL_SKIPPED]`
  - evento `[AREA_SYNC][MATRIX][INFO][QUEUE_EMPTY]`
- [x] Implementar rodada de correcao `queue_empty` focada em leitura/interpretação da fila:
  - instrumentacao de HTTP + shape + parse na matriz
  - compatibilidade do loader com resposta em objeto e array
  - logs de item encontrado e item filtrado
  - observabilidade da edge function `matrix-cloud` para quantidade de itens retornados
- [x] Implementar rodada de correcao `invalid_json` focada em parse robusto e resposta minima:
  - `matrix-cloud` reduzida para devolver apenas o primeiro item da fila com `limit 1`
  - shape simplificado `{ command_id, payload }`
  - sanitizacao do corpo no ESP32 antes do parse
  - separacao entre `fila vazia` e `erro de conteudo`
  - log explicito de erro real de desserializacao
- [x] Implementar rodada de correcao `missing_points` focada em normalizacao do payload `SET_FENCE`:
  - resolucao de `points` em cascata (`root.points`, `payload.points`, `payload.payload.points`)
  - promocao dos campos aninhados relevantes para um payload canônico
  - calculo de `pointCount` depois da normalizacao
  - logs explicitos de `pointsSource`
- [x] Implementar rodada de correcao `payload_too_large` focada em chunking real por bytes:
  - planner especifico do `SET_FENCE` com overhead real do chunk
  - remocao de metadados redundantes por parte
  - log explicito de tamanho avaliado por chunk antes do envio
- [x] Implementar rodada de correcao `point_chunk_too_large` focada em chunk candidato real:
  - planner progressivo baseado no payload realmente serializado
  - reducao da faixa de pontos ate caber no limite LoRa
  - reuso da mesma montagem de chunk no planejamento e no envio final
  - log explicito das tentativas do planner
- [ ] Regravar firmwares usados na bancada se a instrumentacao `[AREA_SYNC]` ainda nao estiver embarcada nas placas
- [x] Consolidar resultado binario da fase:
  - `Queue/downlink cloud (SET_FENCE): FALHOU`

## Status

Em andamento.

Base de reaproveitamento confirmada nesta rodada:
- a task `auditoria-area-sync-e2e.md` ja serve como fundacao da trilha `queue/downlink cloud`
- os logs estruturados `[AREA_SYNC]` principais ja estao no firmware da matriz e da coleira
- os scripts de auditoria e orquestracao ja existem no repositorio
- o ambiente local agora tem `.venv` dedicado em `tools/audit/.venv`, suficiente para executar `serial_listener.py`, `supabase_poller.py` e `area_sync_e2e.py`
- o orquestrador E2E agora consegue gerar relatorio com `commandId` resolvido a partir dos artefatos do poller, fortalecendo a correlacao exigida pelo plano
- a homologacao E2E foi executada de fato no run `tools/audit/output/20260419_004824`
- resultado objetivo do run:
  - `Queue/downlink cloud (SET_FENCE): FALHOU`
  - `commandId`: `AUTO_AREA_FENCE:kQSjWOVdkqTNDM9WBggT:7685085E8B9186D1:23A00185B336A70A`
  - o comando foi criado em `property_commands`
  - o comando entrou em `matrix_command_queues`
  - nao houve transicao alem de `queued`
  - nao houve eventos `[AREA_SYNC]` da matriz nem da coleira para esse `commandId`
  - nao houve `ACK`, `NACK` nem `propertyEvents` finais
- a serial da matriz mostrou backhaul conectado e `decrypt_failed` de uplink da coleira, mas nao mostrou consumo auditavel do downlink `SET_FENCE`
- a serial da coleira mostrou operacao normal de uplink/deep sleep, sem evidenciar recepcao do comando `SET_FENCE`
- a verificacao estatica/evidencial desta rodada fechou em:
  - payload `SET_FENCE` compativel com o consumidor da matriz
  - `matrixRuntimeId` consistente entre backend, Supabase e firmware gravado
  - `queue_key` consistente entre `matrix_queue_keys` e `RTDB_QUEUE_KEY` do firmware gravado
  - primeira transicao `queued -> dispatching` existe no codigo para `SET_FENCE`
  - a primeira divergencia real entre `PING` e `SET_FENCE` fica apenas no envio LoRa (`sendLoRaJsonFrame` vs `sendFenceCommandChunked`)
  - como o run real nao mostrou `QUEUE_COMMAND_LOADED`, o primeiro ponto provavel da quebra fica antes do dispatcher ou na carga da fila
- conclusao tecnica atual:
  - classificacao principal: `lacuna de observabilidade`
  - ponto provavel: `gateway-matriz/gateway-matriz.ino::processNextQueuedCommand()`
  - a mudanca minima util ja foi aplicada para expor gates silenciosos e fila vazia
- relatorio detalhado desta verificacao salvo em:
  - `tools/audit/output/20260419_004824/verificacao_set_fence_queued_2026-04-19.md`
- nova rodada aplicada nesta sessao:
  - `loadNextQueuedCommand()` agora registra `httpStatus`, tamanho do corpo, prefixo truncado, shape e contagem de itens
  - o loader agora aceita tanto objeto mapeado por `commandId` quanto array de itens
  - campos aninhados em `payload` passam a ser promovidos para o topo quando necessario
  - filtros locais (`expiresAtMs`, `binding`, `propertyId`, `propertyScopeId`, `matrixGatewayId`) agora registram `expected` vs `actual`
  - a edge function `matrix-cloud` passou a logar `itemCount`, `firstCommandId` e `firstCreatedAtMs` para GET da fila
- relatorio curto desta rodada salvo em:
  - `tools/audit/output/20260419_004824/correcao_set_fence_queue_empty_2026-04-19.md`
- nova rodada aplicada nesta sessao:
  - a `matrix-cloud` agora devolve somente o primeiro item da fila com resposta minima em shape simples
  - o loader da matriz agora sanitiza prefixo ate o primeiro `{` ou `[`
  - falhas de parse passam a emitir `QUEUE_DESERIALIZE_ERROR` com `errorKind` real
  - corpo presente com erro de parse nao e mais tratado como `QUEUE_EMPTY`
  - o parser continua aceitando temporariamente array, objeto simples e objeto legado mapeado por `commandId`
- relatorio curto desta rodada salvo em:
  - `tools/audit/output/20260419_004824/correcao_set_fence_invalid_json_2026-04-19.md`
- nova rodada aplicada nesta sessao:
  - causa-raiz atual confirmada: `points` chegava em `payload.payload.points`
  - `sendFenceCommandChunked()` passou a resolver pontos em cascata
  - a normalizacao do payload passou a promover campos aninhados relevantes do `SET_FENCE`
  - `pointCount` agora usa o payload ja normalizado
  - novos logs adicionados: `FENCE_POINTS_RESOLVED` e `FENCE_POINTS_RESOLUTION_FAIL`
- relatorio curto desta rodada salvo em:
  - `tools/audit/output/20260419_004824/correcao_set_fence_missing_points_2026-04-19.md`
- nova rodada aplicada nesta sessao:
  - causa-raiz atual confirmada: o planner de chunk do `SET_FENCE` subestimava o overhead real
  - `splitFencePointArrayForPayload()` agora calcula chunks com o overhead efetivo do payload transmitido
  - cada chunk de cerca deixou de repetir `matrix_gateway_id` e `requested_at_ms`
  - novo log adicionado: `FENCE_CHUNK_SIZE_EVAL`
- relatorio curto desta rodada salvo em:
  - `tools/audit/output/20260419_004824/correcao_set_fence_payload_too_large_2026-04-19.md`
- nova rodada aplicada nesta sessao:
  - causa-raiz atual confirmada: ainda havia diferenca entre o chunk planejado e o chunk realmente serializado
  - `splitFencePointArrayForPayload()` agora testa payloads candidatos reais, do maior intervalo para o menor
  - o planner reduz progressivamente a faixa de pontos ate encontrar um chunk valido
  - `sendFenceCommandChunked()` passou a reutilizar a mesma rotina de montagem usada no planejamento
  - novo log adicionado: `FENCE_CHUNK_PLAN`
  - se nem um ponto couber, a falha agora fica explicita como `fence_single_point_chunk_too_large`
- relatorio curto desta rodada salvo em:
  - `tools/audit/output/20260419_004824/correcao_set_fence_point_chunk_too_large_2026-04-19.md`
- build desta rodada:
  - `Sketch uses 1346995 bytes (68%)`
  - `Global variables use 72884 bytes (22%)`

## Next step

1. Regravar a matriz com a instrumentacao nova desta rodada
2. Deploy da `matrix-cloud` com o shape minimo desta rodada
3. Repetir a homologacao E2E `SET_FENCE`
4. Classificar o novo run usando os novos eventos:
   - `QUEUE_BODY_SANITIZED` -> havia bytes indevidos antes do JSON
   - `QUEUE_DESERIALIZE_ERROR` -> erro real de parse/memoria
   - `FENCE_POINTS_RESOLVED` -> origem real dos pontos no payload normalizado
   - `QUEUE_COMMAND_LOADED pointCount>0` -> saida efetiva de `missing_points`
   - `FENCE_CHUNK_PLAN fit=0/1` -> decisao real do planner com payload serializado
   - `FENCE_CHUNK_SIZE_EVAL` -> chunking real por bytes
   - `LORA_TX_ATTEMPT part=0 total>1` ou `LORA_TX_OK` -> envio LoRa finalmente liberado
5. Se ainda travar, corrigir apenas o ponto funcional revelado pelos novos logs

## Related

[[projetos/ruraltech]]
[[tarefas/auditoria-area-sync-e2e]]
[[arquitetura/fluxo-comandos]]
