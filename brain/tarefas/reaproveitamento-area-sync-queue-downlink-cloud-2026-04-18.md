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
- [x] Implementar nucleo firmware do `SET_FENCE` via `RPv2` binario:
  - contratos compartilhados (`constants`, `types`, `reason codes`, `id`, `crc`, `codec`)
  - planejamento por tamanho real do frame seguro na matriz
  - sessao `BEGIN -> POINTS -> COMMIT` na matriz
  - recepcao binaria na coleira com `ACK/NACK/APPLY_STATUS`
- [x] Corrigir o `RPv2` para usar medicao exata e status real:
  - planner usando o mesmo pipeline do envio real
  - remocao de `applied` precoce na matriz
  - `transportState` e `reasonCode` persistidos no resultado
  - logs estruturados extras na matriz e na coleira
  - testes nativos de codec, CRC e planner
- [x] Consolidar resultado binario da fase:
  - `Queue/downlink cloud (SET_FENCE): FALHOU` (fase 1 - legado JSON)
  - `Protocolo RPv2 binário: IMPLEMENTADO` (fase 2 - validação local aprovada)
  - `Validação de bancada: PENDENTE` (próxima rodada)
- [x] Implementar Fase 0 + Fase 1 do plano cirúrgico de transporte LoRa confiável:
  - contratos shared `RTRv1` para `PAGE/PAGE_ACK`, constantes, reason codes, CRC e `sessionId`
  - testes host `rtrv1_codec_test`, `rtrv1_page_test` e `rtrv1_crc_test`
  - matriz enviando `RTR_PAGE` antes da sessão `RPv2` de `SET_FENCE`
  - coleira respondendo `RTR_PAGE_ACK` e entrando em `session mode`
  - bloqueio de `deep sleep` com `wake lock` durante a sessão
  - logs obrigatórios de `RTR_DISCOVERY_WINDOW_*`, `RTR_PAGE_*` e `RTR_SESSION_MODE_*`

## Status

**Atualizado: 2026-04-19**

Rodada de implementação RPv2 concluída e primeira entrega de `RTRv1 paging + wake lock` aplicada localmente. Validação host aprovada, aguardando validação de bancada.

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
- nova rodada aplicada nesta sessao:
  - o enlace matriz -> coleira passou a ter um caminho binario `RPv2` para `SET_FENCE`
  - foram criados os contratos compartilhados de protocolo em `firmware/shared/`
  - a matriz agora calcula `radio_command_id` com `FNV-1a 64`, `CRC32` do fence e planeja por tamanho real do frame seguro
  - a matriz envia sessao binaria `BEGIN -> POINTS -> COMMIT` e aguarda `ACK/NACK/APPLY_STATUS`
  - a coleira agora reconhece o payload binario `RPv2`, remonta em staging de memoria, valida CRC no `COMMIT` e so entao persiste/aplica a cerca
  - a coleira responde com `ACK/NACK` binarios por etapa e `APPLY_STATUS` binario ao final
  - esta rodada ainda nao migra capability cache/backend/app para o fluxo completo do plano
- relatorio curto desta rodada salvo em:
  - `tools/audit/output/20260419_004824/implementacao_radio_proto_v2_set_fence_2026-04-19.md`
- builds desta rodada:
  - matriz: `Sketch uses 1351251 bytes (68%)`
  - matriz: `Global variables use 72884 bytes (22%)`
  - coleira: `Sketch uses 1154549 bytes (58%)`
  - coleira: `Global variables use 68464 bytes (20%)`
- nova rodada aplicada nesta sessao:
  - causa-raiz confirmada: o planner ainda nao usava o mesmo pipeline do envio real para medir o frame seguro
  - `LoRaGateway` agora expõe uma medicao unica do frame seguro reutilizada pelo envio e pelo planner
  - o planner do `RPv2` passou a medir `LoRaFrame` real de candidato e registrar as metricas por etapa
  - foram removidos os caminhos que marcavam `SET_FENCE` como `applied` antes de `APPLY_STATUS ok`
  - `publishSimpleCommandResult()` passou a persistir `transport`, `transportState` e `reasonCode`
  - a coleira ganhou logs adicionais para `BEGIN`, `POINTS`, `COMMIT`, `ACK/NACK`, `APPLY_STATUS`, CRC e reset de sessao
  - foram criados testes nativos para `codec`, `crc` e `planner`
- relatorio curto desta rodada salvo em:
  - `tools/audit/output/20260419_004824/correcao_rpv2_set_fence_planejamento_e_status_2026-04-19.md`
- validacao local desta rodada:
  - testes nativos `rpv2_codec_test`, `rpv2_crc_test` e `rpv2_fence_planner_test`: ok
  - matriz: `Sketch uses 1356875 bytes (69%)`
  - matriz: `Global variables use 72916 bytes (22%)`
  - coleira: `Sketch uses 1156369 bytes (58%)`
  - coleira: `Global variables use 68464 bytes (20%)`
- nova rodada aplicada nesta sessao:
  - criado o contrato shared `RTRv1` em `firmware/shared/` com foco inicial em `PAGE/PAGE_ACK`
  - adicionados os testes host `rtrv1_codec_test`, `rtrv1_page_test` e `rtrv1_crc_test`
  - a matriz agora envia `RTR_PAGE` antes de iniciar `sendFenceCommandRpv2Session()`
  - a matriz agora aguarda `RTR_PAGE_ACK` e registra `RTR_PAGE_PLAN`, `RTR_PAGE_TX_OK` e `RTR_PAGE_ACK_RX`
  - a coleira agora aceita `MsgType::RTR_CONTROL`, valida `RTR_PAGE`, responde `RTR_PAGE_ACK` e entra em `session mode`
  - a coleira passou a segurar `wake lock` e a evitar `deep sleep` enquanto a sessão estiver ativa
  - a coleira passou a registrar `RTR_DISCOVERY_WINDOW_OPEN`, `RTR_DISCOVERY_WINDOW_CLOSE`, `RTR_PAGE_RX`, `RTR_PAGE_ACK_TX`, `RTR_SESSION_MODE_ENTER`, `RTR_SESSION_WAKE_LOCK_HOLD` e `RTR_SESSION_MODE_EXIT`
  - o `gateway` comum foi ajustado para também reconhecer/relayar `RTR_CONTROL` no caminho best-effort atual
- validacao local desta rodada:
  - testes nativos `rtrv1_codec_test`, `rtrv1_page_test` e `rtrv1_crc_test`: ok
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs coleira`: ok
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`: ok
  - coleira: `Sketch uses 1158485 bytes (58%)`
  - coleira: `Global variables use 68496 bytes (20%)`
  - matriz: `Sketch uses 1358231 bytes (69%)`
  - matriz: `Global variables use 72916 bytes (22%)`

Historico adicional desta rodada:
- 2026-04-19: recebido plano cirúrgico externo para transporte LoRa confiável orientado a sessão
- 2026-04-19: recorte executado deliberadamente em `Fase 0 + Fase 1`, preservando o `RPv2` já implantado para `SET_FENCE`
- 2026-04-19: `RTRv1` foi introduzido como camada de controle interna sem reescrever o envelope `LoRaFrame`
- 2026-04-19: o fluxo atual ficou `RTR_PAGE -> RTR_PAGE_ACK -> RPV2 BEGIN/POINTS/COMMIT`, preparando a migração incremental para a sessão confiável completa do plano

## Next step

### Validação da fase RTRv1 paging + wake lock (próxima rodada de bancada)

1. Regravar matriz e coleira com a rodada `RTRv1 + RPv2`
2. Validar em bancada o handshake:
   - `RTR_PAGE_PLAN`
   - `RTR_PAGE_TX_OK`
   - `RTR_PAGE_RX`
   - `RTR_PAGE_ACK_TX`
   - `RTR_PAGE_ACK_RX`
   - `RTR_SESSION_MODE_ENTER`
3. Confirmar que a coleira permanece acordada por wake lock e não entra em `deep sleep` antes do término ou timeout da sessão
4. Repetir a homologação E2E `SET_FENCE` já existente com o novo paging à frente da sessão `RPv2`

### Validação da fase RPv2 (continuação após paging)

1. Regravar matriz e coleira com instrumentação RPv2
2. Deploy da `matrix-cloud` ( já com shape mínimo)
3. Repetir homologação E2E `SET_FENCE`
4. Procurar na serial os eventos RPv2:
   - `RPV2_BEGIN_SIZE_EVAL` → medição do frame BEGIN
   - `RPV2_PLAN_CHUNK_FIT` → decisão do planner (fit=1 = cabe)
   - `RPV2_BEGIN_TX_OK` / `RPV2_BEGIN_RX` → ida e volta do BEGIN
   - `RPV2_ACK_SENT` / `RPV2_RX_ACK` → ACK da coleira
   - `RPV2_POINTS_TX_OK` / `RPV2_POINTS_RX` → chunks de pontos
   - `RPV2_COMMIT_TX_OK` / `RPV2_COMMIT_RX` → commit final
   - `RPV2_APPLY_STATUS_SENT` / `RPV2_RX_APPLY_STATUS` → status de aplicação
   - `RPV2_CRC_OK` / `RPV2_CRC_FAIL` → validação CRC na coleira
5. Verificar no backend:
   - `transport=radio_fence_v2`
   - `transportState` e `reasonCode` persistidos
   - `applied=true` somente após `APPLY_STATUS` positivo

### Critérios de sucesso da fase RPv2

- [ ] Serial da matriz mostra sessão completa (BEGIN → POINTS → COMMIT)
- [ ] Serial da coleira mostra recepção e aplicação (RX → CRC OK → APPLY)
- [ ] Backend mostra `transport=radio_fence_v2` e `status=applied`
- [ ] Nenhum falso positivo (sem `applied` precoce)
- [ ] CRC validado corretamente em ambos os lados
- [ ] Logs de `PAGE/PAGE_ACK` comprovam wake-up antes do `BEGIN`

## Related

[[projetos/ruraltech]]
[[tarefas/auditoria-area-sync-e2e]]
[[arquitetura/fluxo-comandos]]
