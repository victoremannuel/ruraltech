# Task: Correcao LoRa e Panic Coleira Matriz 2026-04-17

#ruraltech
#tarefas

## Context

Implementar a rodada inicial do plano `plano_correcao_lora_panic_ruraltech.md` para estabilizar o enlace LoRa entre `coleira` e `gateway-matriz`, tornar incompatibilidades de firmware/protocolo explicitas e reduzir o risco do panic pos-TX na coleira sem alterar o frame binario `LoRaFrame`.

Continuidade em 2026-04-17 a partir do handoff `instrucoes_continuacao_impl_ia_ruraltech.md`, com foco exclusivo no bug remanescente da coleira apos o terceiro frame LoRa, assumindo como verdade operacional que o enlace principal voltou a funcionar e restringindo o escopo a:
- isolamento do panic no bloco de `pending events` versus caminho de deep sleep
- reducao de ruido de bancada causado pelo relay da matriz
- checkpoints cirurgicos e flags de bancada explicitas
- blindagem minima do acesso ao `union` de `EventRecord`

Continuidade em 2026-04-17 a partir do plano `plano_implementacao_deep_sleep_coleira_ia.md`, agora assumindo como fato que:
- o enlace LoRa esta funcional
- o envio de eventos pendentes esta funcional
- o panic remanescente esta concentrado na transicao para deep sleep

Escopo desta continuidade:
- adicionar API explicita de preparo do radio antes do sleep
- trocar a flag temporaria de loop por configuracao manual controlada
- orquestrar a sequencia final do loop com checkpoints minimos e delays configuraveis
- preservar a bancada inicial com deep sleep desligado via override local

Escopo desta iteracao:
- fase 1: matriz em bancada LoRa-only
- fase 2: `proto_version`, `key_id` e `radio_profile` expostos no boot e em `/status`
- fase 3: instrumentacao de TX/RX, `decrypt_or_hmac_failed`, `nonce_mismatch` e counters
- fase 4: endurecimento do caminho quente da coleira e reducao de persistencia imediata apos TX

## Action

- [x] Fixar `gateway-matriz/manual_settings.local.h` em `RT_MATRIX_DIAG_STAGE=1`, `RT_MATRIX_DISABLE_LORA_REPLAY_FOR_TESTS=1` e `RT_MATRIX_LOG_LEVEL=3`
- [x] Adicionar `LORA_PROTO_VERSION`, `LORA_KEY_ID` e `LORA_RADIO_PROFILE_ID` em `coleira/config.h` e `gateway-matriz/config.h`
- [x] Enriquecer boot/checklist da `coleira` com `fw`, `device_id`, `bindingReady`, `wifi_ota_enabled`, `proto_version`, `key_id` e `radio_profile`
- [x] Enriquecer boot/checklist da `gateway-matriz` com `diag_stage`, `diag_profile`, `anti_replay_mode`, `bindingReady`, `proto_version`, `key_id` e `radio_profile`
- [x] Expor em `/status` da `coleira` e da `gateway-matriz`: `protoVersion`, `keyId`, `radioProfileId` e counters LoRa
- [x] Instrumentar `coleira/LoRaManager.cpp` com log detalhado de TX e counters de `txFail`, `decryptFail`, `nonceMismatch`, `replayReject` e `lastAcceptedSeq`
- [x] Instrumentar `gateway-matriz/LoRaGateway.cpp` com log detalhado de `decrypt_failed`, validacao de `nonce_mismatch` e counters equivalentes
- [x] Validar `nonce` externo vs `frame.nonce` apos `decodePlain()` nas duas pontas, com descarte explicito
- [x] Reduzir persistencia quente da coleira no anti-replay downlink, trocando write-through por checkpoint em stride
- [x] Tirar a persistencia de `health_day` do trecho imediato pos-TX e deferir para antes do deep sleep
- [x] Adicionar checks de tamanho antes de serializar telemetria, `health_daily` e eventos LoRa
- [x] Adicionar checkpoints temporarios no loop principal da coleira para fechar contexto funcional do panic
- [x] Compilar `coleira` e `gateway-matriz` com `arduino-cli` e `PartitionScheme=min_spiffs`
- [x] Desabilitar temporariamente `GATEWAY_RELAY_ENABLED` na matriz para bancada LoRa pura
- [x] Adicionar flags temporarias de isolamento em `coleira/config.h`:
  - `DEBUG_DISABLE_DEEP_SLEEP=true`
  - `DEBUG_DISABLE_PENDING_EVENT_DRAIN=false`
- [x] Adicionar checkpoints cirurgicos na coleira:
  - `after_pending_event_send`
  - `after_pending_events_loop`
  - `before_deep_sleep_arm`
  - `before_deep_sleep_enter`
- [x] Logar no checkpoint pos-envio do evento pendente:
  - nome textual do evento
  - `pending.type`
  - `pending.d1`
  - `pending.d2`
  - `ev.payloadLen`
  - `ev.msgType`
  - `ev.seq`
- [x] Restringir leitura de `pending.payload.operationId` apenas aos eventos que realmente usam esse membro do `union`
- [x] Recompilar `coleira` e `gateway-matriz` apos a rodada de isolamento
- [x] Adicionar `RT_CFG_DEEP_SLEEP_ENABLED` em `coleira/manual_settings.h` com default de producao habilitado
- [x] Trocar `DEBUG_DISABLE_DEEP_SLEEP` por configuracao explicita em `coleira/config.h`:
  - `DEEP_SLEEP_ENABLED`
  - `DEEP_SLEEP_PREPARE_DELAY_MS`
  - `DEEP_SLEEP_ARM_DELAY_MS`
- [x] Preservar a bancada inicial com `RT_CFG_DEEP_SLEEP_ENABLED=false` em `coleira/manual_settings.local.h`
- [x] Expor API publica `prepareForDeepSleep()` em `coleira/LoRaManager.h`
- [x] Implementar `prepareForDeepSleep()` em `coleira/LoRaManager.cpp` com:
  - `finishTransmit()`
  - tentativa de `sleep()`
  - fallback para `standby()`
  - `CS` em nivel alto
  - delay curto de settle
  - logs minimos de sucesso/falha
- [x] Trocar a sequencia final do `loop()` para:
  - `before_deep_sleep_prepare`
  - `lora.prepareForDeepSleep()`
  - `after_deep_sleep_prepare`
  - `before_deep_sleep_arm`
  - `before_deep_sleep_start`
  - `esp_deep_sleep_start()`
- [x] Recompilar `coleira` e `gateway-matriz` apos a rodada de deep sleep
- [x] Ativar `RT_CFG_DEEP_SLEEP_ENABLED=true` no override local para preparar o Teste B real
- [x] Recompilar `coleira` e `gateway-matriz` com deep sleep real habilitado no override local
- [x] Religar o anti-replay de producao na matriz ainda em `DIAG_STAGE=1`, sem alterar relay, cloud ou firmware da coleira
- [x] Subir a matriz para `DIAG_STAGE=2`, mantendo anti-replay estrito, relay desligado e coleira sem novas mudancas
- [x] Preparar experimento controlado de relay na matriz, mantendo `DIAG_STAGE=2`, anti-replay estrito e cloud/backhaul fora desta rodada
- [x] Aplicar rollback minimo do relay na matriz apos reflexo indevido em bancada, mantendo `DIAG_STAGE=2` e anti-replay estrito
- [x] Preparar a matriz para cloud/backhaul sem relay em `DIAG_STAGE=4`, preservando anti-replay estrito e a coleira sem alteracoes

## Status

Fase de investigacao do panic: concluida.

Fase de estabilizacao LoRa-only: concluida.

Fase Stage2 local: concluida.

Relay controlado no cenario atual: reprovado.

Proxima fase: cloud/backhaul sem relay.

Concluido nesta rodada:
- firmware alterado em `coleira` e `gateway-matriz` sem mudar o layout binario de `LoRaFrame`
- builds locais aprovadas:
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs coleira`
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`
- a coleira agora expõe counters e checkpoints para diferenciar:
  - falha de decrypt/HMAC
  - `nonce_mismatch`
  - rejeicao de replay
  - falha de TX
- a matriz sobe explicitamente em perfil de bancada LoRa-only com anti-replay de testes desligado
- o relay da matriz foi desligado para evitar que a coleira receba de volta os próprios uplinks durante a bancada
- a coleira agora permite isolamento binario do panic:
  - com deep sleep desligado temporariamente
  - com dreno de eventos pendentes ligado/desligado por flag
- o caminho de eventos pendentes foi endurecido para evitar leitura indevida do membro `operationId` do `union` fora dos eventos de herding
- builds locais aprovadas apos a continuidade:
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs coleira`
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`
- a transicao para sleep agora tem rotina explicita de preparo do radio LoRa antes de `esp_deep_sleep_start()`
- o controle de sleep saiu da flag ad-hoc no loop e foi movido para configuracao manual com default de producao habilitado
- a bancada local foi mantida com `deep sleep` desligado via `manual_settings.local.h` para o teste A do plano
- o override local da coleira foi religado para `deep sleep` real, deixando o firmware pronto para executar o Teste B em bancada
- builds locais finais aprovadas com `RT_CFG_DEEP_SLEEP_ENABLED=true`:
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs coleira`
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`
- override local da matriz ajustado para `RT_MATRIX_DISABLE_LORA_REPLAY_FOR_TESTS=0`, preparando a rodada de validacao do anti-replay de producao ainda em `DIAG_STAGE=1`
- override local da matriz ajustado para `RT_MATRIX_DIAG_STAGE=2`, preservando `RT_MATRIX_DISABLE_LORA_REPLAY_FOR_TESTS=0` e `GATEWAY_RELAY_ENABLED=false`
- build local da matriz aprovada em `DIAG_STAGE=2`:
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`
- relay da matriz passou a aceitar override local dedicado, sem alterar a coleira nem reintroduzir cloud/backhaul
- override local da matriz ajustado para experimento controlado com relay ligado, preservando `DIAG_STAGE=2` e anti-replay estrito
- build local da matriz aprovada com relay preparado para bancada:
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`
- rollback minimo do relay aplicado na matriz, preservando `DIAG_STAGE=2`, anti-replay estrito e a coleira sem mudancas
- build local da matriz aprovada apos rollback do relay:
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`
- override local da matriz ajustado para `RT_MATRIX_DIAG_STAGE=4`, mantendo relay desligado e anti-replay estrito
- credenciais locais de backhaul/cloud permanecem preenchidas no override da matriz para a proxima validacao fisica
- build local da matriz aprovada em `DIAG_STAGE=4`:
  - `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`

### Evidencia objetiva - Teste B aprovado em bancada LoRa-only

Bloco consolidado conforme os logs de bancada referenciados pelo plano de fechamento desta task:

- `Teste B: PASSOU`
- `Perfil validado: diag-lora-only`
- `Deep sleep: funcional`
- `Guru Meditation: ausente`
- `Ultimo checkpoint alcancado: before_deep_sleep_start`
- `Reset observado apos sleep: DEEPSLEEP_RESET`
- `Wakeup saudavel: sim`
- `Uplinks aceitos pela matriz apos wakeup: sim`
- `Quantidade minima de ciclos completos observados: >= 5`
- Checkpoints observados: `before_deep_sleep_prepare` -> `after_deep_sleep_prepare` -> `before_deep_sleep_arm` -> `before_deep_sleep_start`
- Radio preparado com sucesso antes do sleep

### Evidencia objetiva - Stage2 local aprovado

- `Stage2 local: PASSOU`
- `Perfil validado: diag-lora-http`
- `HTTP local: OK`
- `LoRa com anti-replay estrito: OK`
- `Deep sleep da coleira durante stage 2: OK`
- `Guru Meditation: ausente`
- `Relay: ainda desligado nesta validacao`
- `Cloud/backhaul: ainda fora do escopo`

### Evidencia objetiva - relay controlado no cenario atual

- `Relay controlado: FALHOU`
- `Cenario validado: bancada atual com uma matriz e uma coleira`
- `Problema observado: reflexo indevido do uplink para a propria coleira`
- `Sintoma na matriz: retransmissao do mesmo frame recebido`
- `Sintoma na coleira: LoRa RX ignorado: unsupported_type=1`
- `Guru Meditation: ausente`
- `Deep sleep da coleira: preservado`
- `LoRa base: preservado`
- `Decisao: rollback minimo do relay aplicado`

### Evidencia objetiva - cloud/backhaul sem relay

- `Stage4 cloud/backhaul sem relay: PRONTO PARA VALIDACAO FISICA`
- `Perfil validado: diag-cloud-no-sd`
- `Relay: desligado`
- `Anti-replay: strict`
- `LoRa: compilacao preparada sem mudancas no contrato`
- `Deep sleep da coleira: preservado sem novas mudancas`
- `Backhaul: credenciais locais configuradas`
- `Cloud: NAO HOMOLOGADO POR FALTA DE BANCADA REAL NESTE AMBIENTE`
- `Guru Meditation: nao reavaliado nesta rodada local`
- `Quantidade de ciclos observados: 0 nesta rodada local`
- `Rollback necessario: nao`

### Causa raiz consolidada

O panic remanescente nao estava no enlace LoRa nem no dreno de eventos pendentes. A causa operacional ficou concentrada na transicao final para deep sleep. A mitigacao aplicada foi preparar explicitamente o radio LoRa antes do sleep, com sequencia controlada de `finishTransmit()`, `sleep()` ou fallback seguro, e checkpoints observaveis ate `esp_deep_sleep_start()`.

Historico:
- 2026-04-17: carregado contexto via brain/Graphify e revisado o plano anexo
- 2026-04-17: identificado que ja havia backtrace bruto salvo em `tools/audit/output/20260417_182851/serial_collar_raw.log`; o `ELF` atual nao bate com o SHA do panic salvo, entao a correção estrutural foi limitada ao que era seguro sem `addr2line` exato
- 2026-04-17: implementadas instrumentacoes e counters nas duas pontas
- 2026-04-17: mitigado risco no caminho quente da coleira com persistencia diferida do `health_day` e checkpoint de persistencia do anti-replay downlink
- 2026-04-17: adicionados checkpoints temporarios do loop para facilitar a proxima rodada de bancada e decodificacao do panic real
- 2026-04-17: handoff operacional restringiu a continuidade ao panic da coleira apos o terceiro frame LoRa
- 2026-04-17: relay da matriz desligado para bancada e adicionadas flags de isolamento para distinguir `pending events` de deep sleep
- 2026-04-17: adicionados checkpoints `after_pending_event_send`, `after_pending_events_loop`, `before_deep_sleep_arm` e `before_deep_sleep_enter`
- 2026-04-17: reforcado acesso seguro ao `union` de `EventRecord`, limitando `operationId` aos eventos que realmente usam esse membro
- 2026-04-17: plano de deep sleep consolidou que a causa remanescente estava na transicao final para sleep, nao no enlace LoRa nem no dreno de eventos
- 2026-04-17: adicionada API `lora.prepareForDeepSleep()` com `finishTransmit()`, `sleep()`, fallback `standby()` e settle curto antes do sleep
- 2026-04-17: o final do loop passou a usar sequencia explicita e observavel de pre-sleep com checkpoints `before_deep_sleep_prepare`, `after_deep_sleep_prepare`, `before_deep_sleep_arm` e `before_deep_sleep_start`
- 2026-04-17: a flag temporaria `DEBUG_DISABLE_DEEP_SLEEP` foi substituida por configuracao manual `RT_CFG_DEEP_SLEEP_ENABLED`, mantendo o override local desligado para a primeira validacao sem sleep
- 2026-04-17: plano final de deep sleep executado ate a etapa local verificavel neste ambiente; override local religado para `RT_CFG_DEEP_SLEEP_ENABLED=true`
- 2026-04-17: builds finais da coleira e da matriz passaram com o deep sleep real habilitado no override local
- 2026-04-17: a validacao fisica do Teste B permaneceu pendente por depender de flash e observacao serial em hardware real
- 2026-04-17: plano de fechamento consolidou a evidencia ja observada em bancada LoRa-only e moveu a task de investigacao para reintegracao gradual
- 2026-04-17: plano de reintegracao gradual aplicado ate a Fase 2 local; a unica mudanca de configuracao nesta rodada foi religar o anti-replay de producao da matriz mantendo `DIAG_STAGE=1` e relay desligado
- 2026-04-17: plano da fase stage 2 aplicado localmente; a matriz foi promovida para `DIAG_STAGE=2` sem alterar a coleira, mantendo anti-replay estrito e relay desligado
- 2026-04-17: compilacao local da matriz em `DIAG_STAGE=2` passou, deixando a rodada pronta para validacao fisica de `diag-lora-http`
- 2026-04-17: plano de proxima fase consolidou `Stage2 local` como aprovado com HTTP local validado manualmente e abriu a etapa de relay controlado
- 2026-04-17: relay da matriz foi preparado via override local dedicado, mantendo `DIAG_STAGE=2`, anti-replay estrito e a coleira sem alteracoes
- 2026-04-17: compilacao local da matriz passou com relay preparado; a aprovacao do relay segue pendente de bancada real
- 2026-04-18: a rodada de relay foi fechada como reprovada no cenario atual de bancada devido ao reflexo do uplink para a propria coleira
- 2026-04-18: rollback minimo do relay aplicado na matriz, preservando `DIAG_STAGE=2`, anti-replay estrito, LoRa base e deep sleep da coleira
- 2026-04-18: compilacao local da matriz apos rollback passou, deixando a proxima fase pronta para validacao de cloud/backhaul sem relay
- 2026-04-18: plano de cloud/backhaul sem relay aplicado localmente com promocao da matriz para `DIAG_STAGE=4`, mantendo relay desligado e anti-replay estrito
- 2026-04-18: credenciais locais de backhaul/cloud foram preservadas como configuradas no override da matriz; a homologacao funcional segue pendente de bancada real
- 2026-04-18: compilacao local da matriz em `DIAG_STAGE=4` passou, deixando a rodada pronta para validacao fisica de `diag-cloud-no-sd`
- 2026-04-21: aplicada blindagem cirurgica no caminho de uplink aceito da matriz para impedir eco LoRa em bancada quando o relay estiver habilitado
- 2026-04-21: `processAcceptedUplink()` da matriz passou a consultar `shouldRelayAcceptedUplink()` antes de chamar `relayFrameToPeerGateways()`
- 2026-04-21: uplinks aceitos de `TELEMETRY`, `EVENT`, `ACK`, `NACK` e `RTR_CONTROL` agora ficam bloqueados para relay com `reason=accepted_uplink_echo_guard`
- 2026-04-21: novo log de observabilidade adicionado na matriz: `RELAY_SUPPRESSED_UPLINK_ECHO`
- 2026-04-21: a correção foi guiada pela evidência já consolidada de `reflexo indevido do uplink para a propria coleira` e `unsupported_type=1`; o prompt externo citado pelo operador não foi encontrado no caminho informado durante esta rodada
- 2026-04-21: rodada seguinte endureceu o guardrail para todo TX LoRa da matriz, em vez de depender apenas do call site de relay dentro de `processAcceptedUplink()`
- 2026-04-21: criado `gateway-matriz/MatrixLoRaTxAudit.h` com enum explícito de razão de TX e regra pura `shouldAllowMatrixLoRaTx()`
- 2026-04-21: `sendLoRaJsonFrame()`, `sendLoRaBinaryFrame()` e `relayFrameToPeerGateways()` passaram a usar `sendMatrixLoRaFrame()` com auditoria central
- 2026-04-21: novos logs adicionados na matriz:
  - `LORA_UPLINK_ACCEPTED`
  - `LORA_TX_INTENT`
  - `LORA_TX_BLOCKED_UPLINK_ECHO`
  - `LORA_TX_COMMAND_DISPATCH`
  - `QUEUE_POLL_START`
- 2026-04-21: o call site real compatível com o eco residual continuou sendo o relay bruto que reaproveita `LoRaFrame relay = rx`, identificado pelo mesmo `seq` do uplink aparecer no `LoRa TX ok`
- 2026-04-21: testes host mínimos adicionados e aprovados para bloquear eco de uplink `TELEMETRY` e `EVENT`
- 2026-04-21: tentativa de `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz` voltou a ficar pendurada sem saída conclusiva neste host

Pendencias desta task:
- validar a matriz em `DIAG_STAGE=4` com relay desligado:
  - boot com `DIAG_PROFILE=diag-cloud-no-sd`
  - anti-replay estrito ativo
  - LoRa preservado
  - backhaul conectando ou conectado
  - cloud writer/queue sem erro fatal
- validar pelo menos 3 ciclos completos da coleira sem regressao de deep sleep durante stage 4
- confirmar homologacao de cloud/backhaul ou registrar limitacao real de credencial/ambiente
- discutir nova estrategia de relay apenas em trilha separada no futuro
- se houver regressao em qualquer etapa, executar rollback minimo sem remover o fix de `prepareForDeepSleep()`

## Next step

1. Validar em bancada a matriz agora em `DIAG_STAGE=4` com relay desligado
2. Confirmar boot `diag-cloud-no-sd`, Wi-Fi/backhaul, HTTP local e LoRa preservado
3. Confirmar cloud writer/queue funcional ou registrar limitacao real de credencial/ambiente
4. So depois discutir stage 5 ou qualquer nova estrategia de relay

## Related

[[projetos/ruraltech]]
[[arquitetura/fluxos-comunicacao-ponta-a-ponta]]
[[arquitetura/fluxo-comandos]]
