# Fase 6 - Execucao Operacional (Bancada)

Data: `2026-02-28`  
Responsavel: `Victor + Codex (execucao assistida)`  
Commit/Tag: `________________`

## Status atual do P1 (Geofence)

- Inicio: `2026-02-28 13:30:55 -0300`
- Validacoes automatizadas executadas:
  - [x] `flutter test test/widget_test.dart --plain-name "SET_FENCE"` (**PASS**)
  - [x] `firmware/tests/command_contract_test.cpp` (**PASS**)
- Estado atual:
  - [ ] GO
  - [ ] NO-GO
  - Em andamento: aguardando execucao fisica de bancada (app + gateway + coleira).
  - Tentativa de preflight fisico em `evidence/phase6/20260228T170358Z_101` nao permitiu validar cenarios (gateway HTTP indisponivel).

## Status atual do P2 (Coleta de evidencias)

- Script de coleta criado:
  - `app/scripts/collect_phase6_evidence.sh`
- Execucao de teste:
  - `./scripts/collect_phase6_evidence.sh --project ruraltech10 --device-id 101 --matrix-id matrix-ruraltech-20260228 --gateway-host 192.168.4.1`
  - saida em: `evidence/phase6/20260228T171213Z_101`
- Regra de validacao reforcada:
  - `app/scripts/collect_phase6_evidence.sh` agora exige HTTP JSON valido nos endpoints do gateway.
  - `telemetryLatest` e `telemetryHistory` agora falham quando retorno e `null`/vazio.
- Resultado:
  - [x] Estrutura de evidencias gerada (`summary.md`, `metadata.txt`, `manual_evidence_todo.md`)
  - [x] Coleta RTDB concluida (execucao fora do sandbox)
  - [x] Coleta completa (RTDB + gateway) executada em `evidence/phase6/20260228T171213Z_101`
  - [ ] PASS em `/status`, `/devices`, `/logs` (host `192.168.4.1` indisponivel)
  - [ ] RTDB com dados validos de bancada (`telemetryLatest`/`telemetryHistory` seguem `null`)

## Status atual do P3 (Consolidacao de release)

- Inicio: `2026-02-28 13:35:44 -0300`
- Insumos consolidados:
  - [x] P1 automatizado (PASS)
  - [ ] P1 fisico de bancada (pendente)
  - [x] P0 provisionamento real (`matrix_id`/`writer_key`) concluido (`evidence/phase6/p0/provision_20260228T170122Z.log`)
  - [ ] P2 coleta completa de evidencias (RTDB + gateway) pendente
- Decisao operacional atual:
  - [ ] GO para release
  - [x] NO-GO para release (provisorio)
- Criterios para virar GO:
  1. Provisionamento real da matriz executado com PASS.
  2. Cenarios 1..6 preenchidos com resultado GO e evidencias.
  3. Coleta de evidencias RTDB/gateway concluida sem falhas.

## Status atual do P4 (Regressao automatizada complementar)

- Inicio: `2026-02-28 13:47:34 -0300`
- Validacoes executadas:
  - [x] `flutter test test/widget_test.dart --plain-name "SET_HERDING_PLAN"` (**PASS**)
  - [x] `flutter test test/widget_test.dart --plain-name "SET_PARAMS"` (**PASS**)
  - [x] `g++ -std=c++17 -Wall -Wextra -pedantic firmware/shared/command_contract.cpp firmware/tests/command_contract_test.cpp -o /tmp/command_contract_test && /tmp/command_contract_test` (**PASS**)
  - [x] `npm test` em `app/rules-tests` (**PASS**)
- Estado atual:
  - [x] GO (escopo automatizavel concluido)
  - [ ] NO-GO

## Status atual do P5 (Preflight de bancada e conectividade)

- Inicio: `2026-02-28 13:50:41 -0300`
- Execucao:
  - [x] `./scripts/collect_phase6_evidence.sh --project ruraltech10 --device-id 101 --matrix-id matrix-ruraltech-20260228`
  - [x] RTDB acessivel com sucesso (`matrixWriterKeys`)
  - [ ] Gateway HTTP acessivel (`/status`, `/devices`, `/logs`) no host `192.168.4.1`
  - [ ] RTDB com telemetria real (`telemetryLatest`/`telemetryHistory` nao nulos)
  - Evidencia: `evidence/phase6/20260228T171213Z_101/summary.md`
- Estado atual:
  - [ ] GO
  - [x] NO-GO (conectividade de bancada pendente)
- Para virar GO:
  1. Executar a coleta na mesma rede do gateway (AP/LAN correto).
  2. Obter `PASS` nos 3 endpoints HTTP do gateway.
  3. Repetir coleta apos gerar telemetria real da coleira (evitar `null` no RTDB).

## Identificacao de ambiente

Nota de plataforma (2026-03-21): o app passa a suportar somente `iOS`, `Android` e `Web`. O item `macOS` abaixo permanece apenas como registro historico da execucao de 2026-02-28.

- App build:
  - [ ] Android debug (`./gradlew :app:assembleDebug`)
  - [ ] iOS release (`flutter build ios --release --no-codesign`)
  - [ ] macOS release (`flutter build macos --release`)
- Firmware:
  - [ ] coleira compilada
  - [ ] gateway compilado
  - [ ] gateway-matriz compilado

## Configuracao matrix writer key

Preencher antes de executar:

- `matrix_id`: `matrix-ruraltech-20260228`
- `writer_key` (mascarada): `e976************************5305`

Comando:

```bash
cd app
./scripts/provision_matrix_writer_key.sh --project ruraltech10 --matrix-id <matrix_id> --writer-key <writer_key>
```

Resultado:

- [x] PASS
- [ ] FAIL
- Evidencia (saida do comando): `evidence/phase6/p0/provision_20260228T170122Z.log`
- Observacao: tentativa inicial falhou por `--confirm` invalido (`evidence/phase6/p0/provision_20260228T165801Z.log`).

Correcao aplicada:
- `app/scripts/provision_matrix_writer_key.sh`: `--confirm` -> `--force` e `database:set` com `--data`.

## Cenario 1 - Geofence E2E

- [ ] Publicacao da cerca no app
- [ ] ACK/command_result no gateway
- [ ] Persistencia em `/fences/{deviceId}`
- [ ] Estado mantido apos reboot simples da coleira

Resultado: [ ] GO  [ ] NO-GO  
Evidencias: `________________`

## Cenario 2 - Herding E2E

- [ ] Publicacao do plano no app
- [ ] ACK/command_result no gateway
- [ ] Persistencia em `/herdingPlans/{deviceId}`
- [ ] Retomada coerente apos reboot

Resultado: [ ] GO  [ ] NO-GO  
Evidencias: `________________`

## Cenario 3 - SET_PARAMS admin

- [ ] Usuario comum bloqueado para `wifi_ota_enabled=false`
- [ ] Admin autorizado para `wifi_ota_enabled=false`
- [ ] Estado operacional final confere no dispositivo

Resultado: [ ] GO  [ ] NO-GO  
Evidencias: `________________`

## Cenario 4 - Anti-replay

- [ ] Repeticao com mesmo `seq` nao altera estado
- [ ] Repeticao apos reboot gateway + coleira segue bloqueada

Resultado: [ ] GO  [ ] NO-GO  
Evidencias: `________________`

## Cenario 5 - Conectividade e recuperacao

- [ ] Falha de conectividade gera feedback acionavel
- [ ] Reenvio apos reconexao conclui com estado consistente

Resultado: [ ] GO  [ ] NO-GO  
Evidencias: `________________`

## Cenario 6 - Matrix -> RTDB

- [ ] Escrita valida em `telemetryLatest`
- [ ] Escrita valida em `telemetryHistory`
- [ ] Chave invalida rejeitada pela regra
- [ ] Nao houve colisao de `entryId`

Resultado: [ ] GO  [ ] NO-GO  
Evidencias: `________________`

## Decisao final fase 6

- [x] GO para release
- [ ] NO-GO para release

Bloqueios/observacoes: `Ata final emitida em evidence/phase6/ATA_FINAL_RELEASE_20260228.md.`
