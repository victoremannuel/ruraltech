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
- [x] Implementar a correção cirúrgica do wake/paging na matriz:
  - `PendingWakeSession` por alvo de `SET_FENCE`
  - state machine assíncrono `paging_waiting_uplink -> paging_ready -> awaiting_page_ack -> page_acked -> session_start_ready`
  - presença recente por `deviceId` e promoção por uplink válido
  - `RTR_PAGE_ACK` tratado de forma assíncrona no loop principal
  - handoff assíncrono para o `RPv2` já existente
  - desativação do page single-shot bloqueante no caminho cloud de `SET_FENCE`
  - testes host do orquestrador e correlação de ACK
- [x] Aplicar correção cirúrgica de build da matriz pós-rodada WDT-safe:
  - isolar `case rtrwake::State::SESSION_IN_PROGRESS` com escopo explícito em `processPendingWakeSessionStep(...)`
  - preservar sem alteração a lógica incremental do wake loop, logs e diagnósticos expostos em `/status`
  - revalidar a compilação da matriz até o limite confiável deste host
- [x] Aplicar correção cirúrgica para bloquear `RTR_PAGE` com wake hint vencido:
  - helper puro `hasFreshWakeHint(...)` e `wakeHintAgeMs(...)` em `RtrWakeOrchestrator.h`
  - guarda explícita no fast-path de uplink antes de `trySendRtrPage(...)`
  - guarda explícita no `case PAGING_READY_TO_SEND` antes do envio do page
  - retorno controlado para `PAGING_WAITING_UPLINK` sem limpar `plan`, `commandId` ou contexto da sessão
  - log obrigatório `RTR_WAKE_HINT_STALE ... action=wait_next_uplink`
  - teste host dedicado `firmware/tests/rtrv1_stale_wake_hint_test.cpp`

## Status

**Atualizado: 2026-04-25**

Rodada de implementação RPv2 concluída, `RTRv1 paging + wake lock` aplicada e correção do wake orchestration assíncrono da matriz concluída localmente. Validação host e builds aprovados; validação física de bancada segue pendente.

Nova rodada aplicada em 2026-04-21:
- `loadNextQueuedCommand()` agora trata corpo semanticamente vazio como vazio real, inclusive ruído equivalente a `null`, sem cair em `QUEUE_FETCH_HTTP_OK_UNEXPECTED_SHAPE`
- `loadNextQueuedCommand()` agora trata `empty_object` como fila vazia limpa, reduzindo ruído operacional de bancada
- `buildFenceRpv2Plan()` agora emite resumo terminal inequívoco `RPV2_PLAN_FINAL` com `planReady=1/0`, total de chunks e faixa de tamanhos finais
- falha terminal do planner agora registra `RPV2_PLAN_FAILED_TERMINAL` antes de abortar o fluxo, reforçando o fail-fast antes de wake/page
- `RtrWakeOrchestrator` agora exige `pageSent` real para considerar timeout de ACK e expõe helper para detectar estado inválido
- `processPendingWakeSessions()` agora falha explicitamente quando a sessão entra em `PAGING_AWAITING_ACK` sem envio real de page, em vez de mascarar isso como timeout legítimo
- logs de `RTR_PAGE_TIMEOUT_RETRY` e `RTR_PAGE_TIMEOUT_FINAL` agora carregam contexto de `pageSent`, `lastPageSentAtMs` e `ackDeadlineAtMs`
- TTL default de `SET_FENCE` no backend foi ampliado de 15 para 30 minutos para reduzir expiração prematura em bancada
- testes host reforçados:
  - `rtrv1_wake_scheduler_test.cpp` cobre a invariável de não haver timeout sem page real
  - `rpv2_fence_planner_test.cpp` agora prova que 6 pontos exigem chunking em mais de uma parte no envelope atual
  - `supabase/functions/_shared/supabase.test.ts` criado para validar o TTL de `SET_FENCE` e o fallback de comando desconhecido
- validação desta rodada:
  - `g++ ... firmware/tests/rpv2_fence_planner_test.cpp`: ok
  - `g++ ... firmware/tests/rtrv1_wake_scheduler_test.cpp`: ok
  - `g++ ... firmware/tests/rtrv1_terminal_failure_status_test.cpp`: ok
  - `deno test supabase/functions/_shared/supabase.test.ts`: não executado neste host (`deno: command not found`)
- `arduino-cli compile` para `gateway-matriz`, `coleira` e `gateway`: inconclusivo neste host; os processos entram no padrão histórico de hang sem saída final

Nova rodada aplicada em 2026-04-21 (fast-path `RTR_PAGE_ACK`):
- o `loop()` principal da matriz agora tenta consumir `RTR_PAGE_ACK` antes de `enqueueAcceptedUplink(rx)` e antes de qualquer retry/holdoff do caminho normal
- foi criado o helper `tryHandlePendingWakePageAckFastPath()` em `gateway-matriz.ino` para decodificar `RTR_PAGE_ACK`, correlacionar por `deviceId + sessionId + messageId` e consumir o ACK no mesmo ciclo de `lora.receive(rx)`
- `RTR_PAGE_ACK` consumido no fast-path deixa de entrar na `acceptedUplinkQueue`, removendo dependência de drenagem posterior, `acceptedUplinkQuietMs` e janela de backhaul para essa etapa de controle
- o orquestrador ganhou helpers explícitos para `canConsumePageAckFastPath()` e `isLatePageAck()`, reforçando a separação entre ACK consumível e ACK tardio
- os logs agora distinguem:
  - `RTR_PAGE_ACK_FAST_PATH_MATCH` para match imediato
  - `RTR_PAGE_ACK_FAST_PATH_SKIP` quando há correlação mas a sessão não está consumível naquele estado
  - `RTR_PAGE_ACK_FAST_PATH_LATE` e `RTR_PAGE_ACK_LATE` para ACK tardio após deadline
- testes host reforçados:
  - `rtrv1_page_ack_correlation_test.cpp`
  - `rtrv1_fast_path_priority_test.cpp`
  - `rtrv1_terminal_failure_status_test.cpp`
- validação desta rodada:
  - `g++ ... firmware/tests/rtrv1_page_ack_correlation_test.cpp`: ok
  - `g++ ... firmware/tests/rtrv1_fast_path_priority_test.cpp`: ok
  - `g++ ... firmware/tests/rtrv1_terminal_failure_status_test.cpp`: ok
  - `g++ ... firmware/tests/rtrv1_wake_scheduler_test.cpp`: ok

Nova rodada aplicada em 2026-04-21 (`RPV2` pós-`RTR_PAGE_ACK`, WDT + wake lock):
- `waitForRpv2Response()` na matriz deixou de fazer busy-loop puro:
  - agora alimenta `feedWatchdogIfEnabled()` a cada iteração
  - usa `delay(1)` quando não há frame e após encaminhar frame não correlacionado
  - registra `RPV2_WAIT_HEARTBEAT` com elapsed controlado por estágio
- `executeFenceCommandRpv2Plan()` agora registra transições explícitas `RPV2_STAGE_TRANSITION` entre `begin`, `points`, `commit` e `apply_status`, além de alimentar o watchdog entre etapas
- `processPendingWakeSessions()` agora registra `RPV2_SESSION_BEGIN_DISPATCH`, `RPV2_SESSION_END_APPLIED` e `RPV2_SESSION_END_FAILED`
- a coleira ganhou retenção explícita de sessão `RPV2` independente da janela `RTR_PAGE` original:
  - novo helper `holdRpv2Session(...)`
  - `RPV2_BEGIN`, `RPV2_POINTS` e `RPV2_COMMIT` agora rearmam/estendem o hold com logs `RPV2_SESSION_HOLD`
  - rearm inicial agora emite `RPV2_SESSION_REARM`
- o laço final da coleira agora segura o dispositivo acordado enquanto `rpv2FenceSession_.active` estiver ativo, com log `RPV2_SESSION_WAKE_LOCK_HOLD`, evitando deep sleep prematuro entre `BEGIN/POINTS/COMMIT/APPLY_STATUS`
- validação desta rodada:
  - `g++ ... firmware/tests/rtrv1_page_ack_correlation_test.cpp`: ok
  - `g++ ... firmware/tests/rtrv1_fast_path_priority_test.cpp`: ok
  - `g++ ... firmware/tests/rtrv1_terminal_failure_status_test.cpp`: ok
  - `g++ ... firmware/tests/rtrv1_wake_scheduler_test.cpp`: ok
- builds Arduino continuam sem confirmação conclusiva neste host por histórico de hang do `arduino-cli compile`

Nova rodada aplicada em 2026-04-25 (fix cirúrgico de build da matriz pós-WDT-safe):
- corrigido o erro de compilação `jump to case label / crosses initialization of 'const char* sessionReason'` em `gateway-matriz/gateway-matriz.ino`
- o `case rtrwake::State::SESSION_IN_PROGRESS` em `processPendingWakeSessionStep(...)` passou a usar bloco explícito `{ ... }`, restaurando o escopo C++ correto sem mexer na máquina de estados
- a lógica WDT-safe recém-introduzida foi preservada integralmente:
  - handoff em ticks distintos `PAGE_ACKED -> SESSION_START_READY -> SESSION_IN_PROGRESS`
  - logs `RTR_BEGIN_DISPATCH_DEFERRED`, `RTR_BEGIN_DISPATCH_START` e diagnóstico de wake loop
  - campos adicionais de `/status` da matriz relacionados ao wake loop
- validação desta rodada:
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`: pré-processamento/cache do sketch confirmados em `~/Library/Caches/arduino/sketches/B803C21924EBF1231D7A09BC72D83B61/`
  - `gateway-matriz.ino.cpp` gerado no cache sem reaparecimento do erro sintático anterior durante a rodada
  - encerrado sem conclusão final confiável por retorno ao padrão histórico de hang silencioso do `arduino-cli` neste host

Nova rodada aplicada em 2026-04-25 (wake hint vencido bloqueando `RTR_PAGE`):
- `gateway-matriz/RtrWakeOrchestrator.h` agora expõe helpers puros `hasFreshWakeHint(...)` e `wakeHintAgeMs(...)`, reaproveitáveis em teste host e no firmware
- `gateway-matriz/gateway-matriz.ino` agora valida a idade do hint antes de qualquer `RTR_PAGE` em dois pontos:
  - fast-path logo após uplink aceito
  - loop incremental em `processPendingWakeSessionStep(...)` no estado `PAGING_READY_TO_SEND`
- quando o hint está vencido, a matriz:
  - registra `RTR_WAKE_HINT_STALE` com `deviceId`, `commandId`, `ageMs`, `maxAgeMs`, estado e ação
  - volta a sessão para `PAGING_WAITING_UPLINK`
  - limpa apenas `nextPageAttemptAtMs` e `cloudTxDeferred`
  - preserva `plan`, `commandId`, `radioCommandId`, `sessionNonce` e restante do contexto da sessão
- o limiar adotado nesta rodada reaproveita `rtrv1::FAST_PAGE_DEADLINE_MS` (`300 ms`), mantendo coerência com o diagnóstico existente `RTR_PAGE_SOFT_DEADLINE_MISSED`
- teste host novo `firmware/tests/rtrv1_stale_wake_hint_test.cpp` cobre:
  - hint fresco no limite de `300 ms`
  - hint vencido com `301 ms`
  - retorno para `PAGING_WAITING_UPLINK`
  - nova promoção imediata para `PAGING_READY_TO_SEND` quando chega outro uplink
- validação desta rodada:
  - `c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_stale_wake_hint_test.cpp`: ok
  - `c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_wake_scheduler_test.cpp`: ok
  - `c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_fast_path_priority_test.cpp`: ok
  - `c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat firmware/tests/rtrv1_terminal_failure_status_test.cpp`: ok

Nova rodada aplicada em 2026-04-21 (proveniência de firmware / SHA de bancada):
- criado `firmware/shared/build_info.h` com fallback seguro para metadata de build (`gitSha`, `gitShortSha`, `buildUtc`, `dirty`, `buildSource`)
- criado gerador local `tools/audit/generate_build_info.py`, que escreve `firmware/shared/generated_build_info.h` a partir do git atual
- matriz e coleira agora logam `FW_PROVENANCE` no boot com papel do firmware, SHA, short SHA, dirty flag, build UTC e contexto de perfil/dispositivo
- `/status` da matriz e da coleira agora expõem:
  - `firmwareRole`
  - `firmwareVersion`
  - `gitSha`
  - `gitShortSha`
  - `buildUtc`
  - `buildDirty`
  - `buildSource`
- criado checklist local `tools/audit/check_firmware_provenance.py` para invalidar a bancada quando o SHA esperado nao bater com o header gerado e com os campos obrigatorios do runtime
- `generated_build_info.h` foi adicionado ao `.gitignore` para manter a proveniência local sem poluir o versionamento
- validação desta rodada:
  - `python3 tools/audit/generate_build_info.py`: ok
  - `python3 -m py_compile tools/audit/generate_build_info.py tools/audit/check_firmware_provenance.py tools/audit/check_matrix_cloud_pretest.py`: ok
  - `python3 tools/audit/check_firmware_provenance.py`: ok
  - SHA gerado nesta workspace: `891dd586bcc53a54143968d4b182f6f91bed48d0`
  - short SHA gerado nesta workspace: `891dd586`
  - dirty gerado nesta workspace: `1`

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
- nova rodada aplicada nesta sessao:
  - a matriz ganhou `PendingWakeSession` em buffer fixo, com estado explícito e correlação de `PAGE_ACK`
  - a matriz agora mantém o `SET_FENCE` pendente em `paging_waiting_uplink` em vez de falhar por tentativa única imediata
  - uplink válido da coleira agora vira `wake hint`, atualiza presença e promove a sessão para `paging_ready`
  - `RTR_PAGE` passou a ser enviado por scheduler não bloqueante, com até 2 campanhas
  - `RTR_PAGE_ACK` passou a ser tratado no caminho assíncrono de uplink aceito, sem `waitForRtrPageAck()` no fluxo cloud principal
  - o handoff para `RPv2` agora acontece apenas após `page_acked`, em tick separado
  - o caminho antigo de retry de `activeSimpleCommand` foi neutralizado para `SET_FENCE` quando houver wake sessions pendentes
  - foi criado `gateway-matriz/RtrWakeOrchestrator.h` para concentrar a lógica pura do state machine e permitir testes host
- validacao local desta rodada:
  - testes nativos `rtrv1_wake_scheduler_test`, `rtrv1_page_ack_correlation_test` e `rtrv1_presence_hint_test`: ok
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`: ok
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs coleira`: ok
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway`: ok
  - matriz: `Sketch uses 1375563 bytes (69%)`
  - matriz: `Global variables use 85588 bytes (26%)`
  - coleira: `Sketch uses 1158533 bytes (58%)`
  - coleira: `Global variables use 68496 bytes (20%)`
  - gateway comum: `Sketch uses 1916207 bytes (97%)`
  - gateway comum: `Global variables use 75332 bytes (22%)`
- nova rodada aplicada em 2026-04-20:
  - a matriz ganhou fast-path explícito no uplink aceito com precedência de `RTR_PAGE` sobre o publish cloud
  - novos logs na matriz: `RTR_WAKE_FAST_PATH_START`, `RTR_WAKE_FAST_PATH_SKIP`, `RTR_WAKE_TO_PAGE_LATENCY`, `RTR_WAKE_UPLINK_DEFERRED_CLOUD_TX` e `RTR_WAKE_CLOUD_TX_RESUMED`
  - a matriz passou a registrar o evento terminal `rtr_page_timeout_final` e a preservar `reason=page_timeout_final` no fechamento agregado do `SET_FENCE`
  - a coleira ganhou janela de descoberta estendida para bancada e segunda janela RX antes do deep sleep
  - a coleira passou a registrar `RTR_PAGE_ACK_PREPARE`, `RTR_PAGE_TO_ACK_LATENCY`, `RTR_DISCOVERY_WINDOW_SECONDARY_OPEN` e `RTR_DISCOVERY_WINDOW_SECONDARY_CLOSE`
  - o `LoRaManager` da coleira passou a registrar `RTR_RAW_DOWNLINK_RX`, `RTR_RAW_DOWNLINK_DROP` e `RTR_RAW_DOWNLINK_ACCEPT`
  - foram adicionados testes host para prioridade do fast-path, métrica de deadline, política de segunda janela, raw drop reasons e consistência de status terminal
- validacao local desta rodada em 2026-04-20:
  - testes host `rtrv1_fast_path_priority_test`, `rtrv1_page_deadline_metrics_test`, `rtrv1_raw_drop_reason_test`, `rtrv1_secondary_window_policy_test` e `rtrv1_terminal_failure_status_test`: ok
  - `arduino-cli compile --config-file .tmp-arduino-cli.yaml --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`: ok
  - `arduino-cli compile --config-file .tmp-arduino-cli.yaml --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs coleira`: ok
- nova rodada aplicada em 2026-04-21:
  - o checklist externo `checklist_cirurgico_pre_teste_matriz_cloud_downlink_ia_codigo.md` foi implementado como verificacao automatizada em `tools/audit/check_matrix_cloud_pretest.py`
  - o script novo monta a tabela exigida pelo plano, separa matriz vs coleira e devolve conclusao binaria `ambiente pronto` vs `nao pronto`
  - a matriz ganhou sinais explicitos de preflight no boot:
    - `MATRIX_RUNTIME_ID`
    - `QUEUE_POLLING_CFG`
    - log resumido `Matrix cloud_preflight runtimeId=... cloudConfigured=... queuePollingConfigured=...`
  - o endpoint `/status` da matriz passou a expor:
    - `matrixRuntimeId`
    - `configuredMatrixId`
    - `cloudConfigured`
    - `queuePollingConfigured`
  - validacao local do novo checklist:
    - `python3 tools/audit/check_matrix_cloud_pretest.py`: ok
    - `python3 tools/audit/check_matrix_cloud_pretest.py --json`: ok
    - `python3 -m py_compile tools/audit/check_matrix_cloud_pretest.py`: ok
  - resultado objetivo desta verificacao local:
    - coleira: pronta
    - matriz: nao pronta para cloud/downlink neste workspace
    - bloqueadores: `DIAG_STAGE` efetivo em `0` e ausencia de `gateway-matriz/manual_settings.local.h`
    - menor passo pendente fora do repositorio versionado: criar/preencher `manual_settings.local.h` com `DIAG_STAGE=4` e credenciais reais
  - `arduino-cli compile --config-file .tmp-arduino-cli.yaml --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway`: ok
  - matriz: `Sketch uses 1405207 bytes (71%)`
  - matriz: `Global variables use 85924 bytes (26%)`
  - coleira: `Sketch uses 1169621 bytes (59%)`
  - coleira: `Global variables use 68632 bytes (20%)`
  - gateway comum: `Sketch uses 1936275 bytes (98%)`
  - gateway comum: `Global variables use 75476 bytes (23%)`
- verificacao adicional em 2026-04-21:
  - o plano externo `/Users/victoremannuel/Downloads/plano_cirurgico_impl_fastpath_page_rxstatus_codex.md` foi comparado novamente com o estado atual do repositorio
  - os itens centrais do plano seguem presentes no codigo atual:
    - fast-path de `RTR_PAGE` no ciclo do uplink aceito
    - defer/resume de `CLOUD_TX`
    - metricas `RTR_WAKE_TO_PAGE_LATENCY`
    - janela estendida e janela secundaria na coleira
    - logs `RTR_RAW_DOWNLINK_RX`, `RTR_RAW_DOWNLINK_DROP` e `RTR_RAW_DOWNLINK_ACCEPT`
    - fechamento terminal `failed` com `reason=page_timeout_final`
  - revalidacao host executada com `c++ -std=c++17 -I. -Ifirmware/tests/arduino_compat`:
    - `rtrv1_fast_path_priority_test`: ok
    - `rtrv1_terminal_failure_status_test`: ok
    - `rtrv1_page_deadline_metrics_test`: ok
    - `rtrv1_secondary_window_policy_test`: ok
    - `rtrv1_raw_drop_reason_test`: ok
  - conclusao desta verificacao: nenhuma lacuna material restante do plano foi encontrada no codigo local; nao foi necessario novo patch de implementacao nesta rodada

Historico adicional desta rodada:
- 2026-04-19: recebido plano cirúrgico externo para transporte LoRa confiável orientado a sessão
- 2026-04-19: recorte executado deliberadamente em `Fase 0 + Fase 1`, preservando o `RPv2` já implantado para `SET_FENCE`
- 2026-04-19: `RTRv1` foi introduzido como camada de controle interna sem reescrever o envelope `LoRaFrame`
- 2026-04-19: o fluxo atual ficou `RTR_PAGE -> RTR_PAGE_ACK -> RPV2 BEGIN/POINTS/COMMIT`, preparando a migração incremental para a sessão confiável completa do plano
- 2026-04-19: novo plano cirúrgico confirmou que o gargalo restante não era o `RPv2`, mas o `PAGE` single-shot da matriz
- 2026-04-19: a matriz foi migrada para wake orchestration assíncrono baseado em uplink aceito da coleira
- 2026-04-19: `SET_FENCE` vindo da fila cloud deixou de chamar o page bloqueante diretamente e passou a criar sessão pendente por alvo
- 2026-04-19: `PAGE_ACK` passou a ser correlacionado por `deviceId + sessionId + messageId` no loop principal
- 2026-04-19: a próxima evidência necessária saiu do escopo local e depende de bancada com logs reais do ciclo `wake hint -> page -> page ack -> rpv2`
- 2026-04-20: a rodada cirúrgica de rendezvous priorizou `RTR_PAGE` no mesmo ciclo do uplink aceito, sem reescrever o `RPv2` nem o envelope `LoRaFrame`
- 2026-04-20: a coleira ganhou observabilidade de RX bruto e tolerância extra via janela secundária antes do deep sleep
- 2026-04-20: o fechamento agregado do `SET_FENCE` passou a preservar o motivo terminal de falha em vez de publicar `failed` sem `reason`
- 2026-04-21: o checklist cirurgico pre-teste foi automatizado em script para evitar nova bancada invalida com matriz em perfil errado
- 2026-04-21: a observabilidade da matriz foi reforcada no boot e em `/status` para distinguir `cloudConfigured` de `queuePollingConfigured`
- 2026-04-21: verificado novamente contra o plano externo `plano_cirurgico_impl_fastpath_page_rxstatus_codex.md`; o repositorio atual permaneceu consistente com a implementacao descrita e os testes host-chave passaram sem novas mudancas
- 2026-04-25: rodada cirurgica de radio/cripto/page adicionou snapshot estruturado do ultimo `decrypt_failed` na matriz, exposto em `/status` e em log `LORA_RX_DECRYPT_FAIL_CONTEXT`
- 2026-04-25: a matriz passou a manter snapshot do ultimo ciclo `wake hint -> page -> ack/timeout`, com `lastPageOutcome`, `lastWakeHint*` e logs `RTR_WAKE_HINT_CAPTURED`, `RTR_PAGE_TX_CONTEXT` e `RTR_PAGE_TERMINAL_CONTEXT`
- 2026-04-25: a coleira ganhou contadores e snapshots de janela/discovery/raw downlink/page, expostos em `/status`, com logs `RTR_WINDOW_ARMED`, `RTR_WINDOW_CLOSED_CONTEXT`, `RTR_RAW_DOWNLINK_SEEN`, `RTR_RAW_DOWNLINK_REJECT_CONTEXT` e `RTR_PAGE_RX_CONTEXT`
- 2026-04-25: overrides de bancada opt-in foram adicionados na coleira para separar timing de radio/cripto sem alterar o default de producao: `RTR_BENCH_HOLD_AFTER_UPLINK_MS` e `RTR_BENCH_SECONDARY_WINDOW_MS`
- 2026-04-25: helper compartilhado `firmware/shared/rtr_diag_support.h` e teste host `rtr_diag_support_test.cpp` passaram junto com os testes existentes do wake/page
- 2026-04-25: a politica de page foi endurecida com deadline soft explicito para fast-path, deadline hard de ACK preservado, e retry por campanha com grace window (`PAGE_RETRY_GRACE_MS`) sem depender de novo uplink
- 2026-04-25: a coleira passou a segurar uma sleep grace window (`COLLAR_SLEEP_GRACE_MS`) antes do deep sleep para capturar a campanha de retry tardia, com logs `RTR_SLEEP_GRACE_HOLD` e `RTR_SLEEP_GRACE_WINDOW_CLOSE`
- 2026-04-25: `/status` da matriz agora expõe `lastWakeToPageLatencyMs`, `lastSoftDeadlineMs`, `lastSoftDeadlineMet` e `lastPageRetryAtMs`; `/status` da coleira expõe `sleepGraceWindowMs`, `sleepGraceHoldCount` e timestamps associados
- 2026-04-25: o gargalo dominante de `PAGE_ACK` persistente foi corrigido separando attempt em voo (`inFlightPage`) de retry agendado (`scheduledRetry`) dentro do orquestrador da matriz
- 2026-04-25: soft timeout deixou de apagar o contexto consumivel do attempt anterior; agora ele apenas agenda retry e move a sessao para `PAGING_RETRY_GRACE`, mantendo o ACK tardio elegivel ate o hard timeout
- 2026-04-25: a matriz passou a aceitar `RTR_PAGE_ACK` dentro da grace window com logs `RTR_PAGE_ACK_ACCEPTED_WITHIN_GRACE` e `RTR_PAGE_RETRY_CANCELLED_BY_ACK`, alem de expor em `/status` `inFlightPage*`, `retryPending`, `retryCampaignCount`, `lastAckMatchedInGrace` e `lastAckRejectedReason`
- 2026-04-25: a coleira ganhou logs explicitos de pre-start curto (`RTR_PRESTART_HOLD` e `RTR_PRESTART_TIMEOUT`) para separar espera de `BEGIN` do timeout longo de chunks
- 2026-04-25: o RX da matriz ganhou pre-filtro antes do decrypt para ruído bruto e padrões inválidos, separando `raw_noise_drop`, `pattern_drop`, `decrypt_attempt`, `decrypt_failed` e `accepted`
- 2026-04-25: a matriz agora prioriza `RTR_PAGE_ACK` no loop principal antes de `scopeMatchesBinding`, reduzindo a chance de o ACK válido ficar atrás de flood de ruído
- 2026-04-25: `/status` da matriz passou a expor `rawRxSeenCount`, `rawRxNoiseDropCount`, `rawRxInvalidPatternDropCount`, `rawRxDecryptAttemptCount`, `rawRxDecryptFailedCount`, `rawRxAcceptedCount`, `lastRawNoiseReason`, `lastRawPatternHex`, `lastRawCandidateLen`, `lastRawCandidateRssi` e `lastRawCandidateSnr`
- 2026-04-25: logs novos da matriz nesta fase: `LORA_RX_NOISE_DROP`, `LORA_RX_PATTERN_DROP`, `LORA_RX_DECRYPT_ATTEMPT`, `LORA_RX_DECRYPT_FAIL_CONTEXT`, `LORA_RX_ACCEPT_CONTEXT` e sumários throttled por janela
- 2026-04-25: o wake/page retry da matriz passou a ser explicitamente incremental por tick, com orçamento global pequeno, `feedWatchdogIfEnabled()` e `delay(1)` após avanço relevante ou budget hit
- 2026-04-25: o handoff `PAGE_ACKED -> SESSION_START_READY -> BEGIN` foi quebrado em ticks distintos, com `RTR_BEGIN_DISPATCH_DEFERRED` e `RTR_BEGIN_DISPATCH_START` antes do `executeFenceCommandRpv2Plan(...)`
- 2026-04-25: a matriz agora expõe em `/status` diagnóstico de wake loop: `lastWakeLoopStage`, `lastWakeLoopStageAtMs`, `lastWakeLoopStageSessionId`, `lastWakeLoopStageDeviceId`, `wakeLoopIterationCount`, `wakeLoopBudgetHitCount`, `wakeLoopYieldCount`, `lastSoftTimeoutAtMs`, `lastRetryScheduleAtMs` e `lastBeginDispatchAtMs`
- 2026-04-25: logs novos desta fase: `RTR_WAKE_LOOP_STAGE`, `RTR_WAKE_LOOP_BUDGET_HIT`, `RTR_WAKE_LOOP_YIELD`, `RTR_PAGE_SOFT_TIMEOUT_MARKED`, `RTR_RETRY_SCHEDULED_LIGHTWEIGHT`, `RTR_BEGIN_DISPATCH_DEFERRED` e `RTR_BEGIN_DISPATCH_START`
- 2026-04-25: corrigido o build break da matriz pós-rodada WDT-safe isolando com chaves o `case rtrwake::State::SESSION_IN_PROGRESS`, eliminando o cruzamento de inicialização de `sessionReason` sem alterar a semântica da execução

## Next step

### Validação da fase wake orchestration assíncrono (próxima rodada de bancada)

1. Regravar matriz e coleira com a rodada `RTRv1 + RPv2`
2. Repetir `SET_FENCE` pelo app/cloud e validar em bancada o handshake completo:
   - `QUEUE_COMMAND_LOADED`
   - `RTR_WAKE_SESSION_CREATED`
   - `RTR_PAGE_DEFERRED_WAITING_UPLINK` ou `paging_ready`
   - após uplink real da coleira:
   - `RTR_DEVICE_PRESENCE_UPDATE`
   - `RTR_WAKE_HINT_FROM_UPLINK`
   - `RTR_PAGE_READY_TO_SEND`
   - `RTR_PAGE_PLAN`
   - `RTR_PAGE_TX_OK`
   - `RTR_PAGE_RX`
   - `RTR_PAGE_ACK_TX`
   - `RTR_PAGE_ACK_RX`
   - `RTR_SESSION_MODE_ENTER`
   - `RTR_TO_RPV2_START`
   - sequência `RPV2_*`
3. Capturar `/status` da matriz e da coleira antes e depois do comando, com foco em:
   - matriz: `lastDecryptFail*`, `lastPageOutcome`, `lastWakeHint*`, `lastPageSentAtMs`, `lastPageAckDeadlineAtMs`
   - coleira: `rawDownlinkSeenCount`, `rawDownlinkRejectedCount`, `lastDownlinkDropReason`, `pageRxCount`, `lastPageRxAtMs`, `lastPageAckTxAtMs`
   - novos campos de deadline/policy:
   - matriz: `lastWakeToPageLatencyMs`, `lastSoftDeadlineMet`, `lastPageRetryAtMs`
   - coleira: `sleepGraceWindowMs`, `sleepGraceHoldCount`, `lastSleepGraceHoldAtMs`
   - novos campos de attempt persistente:
   - matriz: `inFlightPageValid`, `inFlightPageSessionId`, `inFlightPageMessageId`, `inFlightPageHardDeadlineAtMs`, `retryPending`, `retryAtMs`, `lastAckMatchedInGrace`, `lastAckRejectedReason`
   - novos campos de pre-filtro RX:
   - matriz: `rawRxSeenCount`, `rawRxNoiseDropCount`, `rawRxInvalidPatternDropCount`, `rawRxDecryptAttemptCount`, `rawRxDecryptFailedCount`, `rawRxAcceptedCount`, `lastRawNoiseReason`, `lastRawPatternHex`
   - novos campos de wake loop:
   - matriz: `lastWakeLoopStage`, `lastWakeLoopStageAtMs`, `lastWakeLoopStageSessionId`, `wakeLoopIterationCount`, `wakeLoopBudgetHitCount`, `wakeLoopYieldCount`, `lastSoftTimeoutAtMs`, `lastRetryScheduleAtMs`, `lastBeginDispatchAtMs`
4. Se a bancada ainda ficar inconclusiva por timing, habilitar temporariamente um dos overrides da coleira:
   - `RTR_BENCH_HOLD_AFTER_UPLINK_MS`
   - `RTR_BENCH_SECONDARY_WINDOW_MS`
   e registrar os logs `BENCH_WAKE_HOLD_ACTIVE` ou `BENCH_SECONDARY_WINDOW_OVERRIDE`
5. Confirmar que a coleira permanece acordada por wake lock e não entra em `deep sleep` antes do término ou timeout da sessão
6. Rodar nova validação de build da matriz em um ambiente onde o `arduino-cli` consiga concluir o fechamento final do compile, apenas para registrar evidência terminal de `ok` após o fix de escopo
6. Confirmar no backend:
   - `transport=radio_fence_v2`
   - `transportState=applied`
   - falha, se houver, com `reasonCode`/`reasonLabel` ligados ao page
7. Se ainda falhar, identificar se o próximo gargalo está em:
   - ausência de uplink útil após o comando
   - page não recebido pela coleira
   - page ack não correlacionado na matriz
   - handoff `PAGE_ACKED -> RPV2` não executado
   - substituição prematura do attempt em voo antes do `hardDeadlineAtMs`

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
