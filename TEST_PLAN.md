# Plano Completo de Testes RuralTech

## Decisoes fechadas

1. Estrategia de execucao: **Hibrido** (automacao + bancada real).
2. Gate de release: **bloquear Critico/Alto**.
3. Cadencia: **PR + Noturno**.

## Escopo auditado

- `app`
- `firebase` (Firestore Rules + RTDB Rules)
- `coleira`
- `gateway`
- `gateway-matriz`

Nota de plataforma (2026-03-21): o app passa a suportar somente `iOS`, `Android` e `Web`. Referencias anteriores a `macOS` abaixo permanecem apenas como historico de auditorias ja executadas.

## Gates implementados no CI

### PR (bloqueante)

- `flutter analyze`
- `flutter test` (unitario/widget + fixtures de contrato)
- testes de regras Firebase (`app/rules-tests`)
- testes nativos de contrato/validacao/chunking de firmware (`firmware/tests`)
- compilacao de firmware:
  - `coleira`
  - `gateway`
  - `gateway-matriz`

Arquivo: `.github/workflows/pr-quality.yml`

### Noturno (expandido)

- repeticao de todos os gates de PR
- regressao completa com mesma base de testes

Arquivo: `.github/workflows/nightly-regression.yml`

## Contrato de mensagens (fixtures fixas)

Diretorio: `contracts/messages/`

- `hello.json`
- `telemetry.json`
- `event.json`
- `ack.json`
- `nack.json`
- `command_result_ok.json`
- `command_result_error.json`

Validacao automatizada: `app/test/message_contract_fixtures_test.dart`

## App: testabilidade e UX de erro

- `GatewayService` com injecao de dependencias:
  - WebSocket connector
  - HTTP client
  - clock
- validacoes de negocio mantidas em envio de comando:
  - `SET_FENCE`
  - `SET_HERDING_PLAN`
  - `SET_PARAMS` (LoRa-only exige admin)
- keys estaveis adicionadas para fluxos criticos:
  - login/cadastro
  - geofence/herding
  - filtros de perfil
  - cadastro/edicao de propriedade/area/coleira/gateway
  - acoes principais no dashboard

Testes:

- `app/test/gateway_service_injection_test.dart`
- `app/test/widget_test.dart` (regras de negocio de comandos)
- `app/test/device_model_test.dart`

## Firebase e seguranca

Testes de regras implementados em:

- `app/rules-tests/firestore.rules.test.mjs`
- `app/rules-tests/database.rules.test.mjs`

Cobertura atual:

- papeis/ownership em coleiras e cercas
- acesso admin
- escrita RTDB por `matrixId + writerKey`
- rejeicao de chave invalida

## Firmware: funcoes puras e regressao

Modulo puro compartilhado:

- `firmware/shared/command_contract.h`
- `firmware/shared/command_contract.cpp`

Cobertura:

- permissao admin para `SET_PARAMS` LoRa-only
- regras de `target` (gateway/collars)
- validacao de coordenadas
- validacao de contagem de pontos/fases
- planejamento de chunking por limite de payload

Teste automatizado:

- `firmware/tests/command_contract_test.cpp`

Integracao em firmware:

- `gateway/gateway.ino`
- `gateway-matriz/gateway-matriz.ino`

## Execucao hibrida de bancada (manual obrigatoria)

Janela recomendada: noturno e pre-release.

Checklist minimo:

1. Geofence: app -> gateway -> coleira -> ACK -> persistencia.
2. Herding plan: app -> gateway -> coleira -> ACK -> persistencia.
3. `SET_PARAMS`:
   - admin: aceita LoRa-only
   - nao-admin: rejeita com feedback claro
4. Anti-replay: comando repetido nao altera estado.
5. Falha de conectividade:
   - feedback acionavel ao usuario
   - estado local consistente
6. Gateway matriz -> RTDB:
   - escrita valida com `writerKey`
   - rejeicao de payload/chave invalida

## Criterios de bloqueio

- qualquer falha Critica/Alta bloqueia release
- falha em fluxos criticos E2E bloqueia release:
  - geofence
  - herding
  - `SET_PARAMS`
  - regras de acesso

## Risco tecnico atual

- bloqueador de flash do `gateway-matriz` em `min_spiffs` foi mitigado com `RT_MATRIX_BLE_ENABLED=0` por padrao nesse perfil.
- risco residual: builds de `gateway-matriz` com BLE forçado (`RT_MATRIX_BLE_ENABLED=1`) exigem revalidacao de tamanho antes de release.

## Fase 3 (pre-release): status atual

Data da ultima execucao automatizada: **2026-02-28**.

- `flutter analyze`: **PASS**
- `flutter test`: **PASS**
- `app/rules-tests npm test`: **PASS**
- `firmware/tests/command_contract_test.cpp`: **PASS**
- `arduino-cli compile`:
  - `coleira`: **PASS** (`1821186 bytes`, `92%`)
  - `gateway`: **PASS** (`1906499 bytes`, `96%`)
  - `gateway-matriz`: **PASS** (`1279167 bytes`, `65%`)
- `flutter build ios --release --no-codesign`: **PASS**
- `./gradlew :app:assembleDebug`: **FALHA DE AMBIENTE LOCAL** (Android SDK ausente)
- `flutter build macos --release`: **INSTAVEL NO AMBIENTE LOCAL** (xcodebuild travando/interrompido)

## Fase 3: roteiro detalhado de bancada manual (go/no-go)

Objetivo: fechar fluxos E2E fisicos que CI nao cobre.

### Pre-condicoes

1. App autenticado com usuario `adm` e com usuario comum (`user`).
2. Um gateway comum ativo e uma coleira ativa na mesma rede LoRa.
3. Um gateway matriz ativo com `matrixWriterKey` provisionada.
4. Firestore/RTDB acessiveis para consulta de evidencias.

### Cenario 1 — Geofence E2E

1. No app (`adm`), publicar cerca com `3..32` pontos.
2. Confirmar `command_result`/ACK no fluxo do gateway.
3. Validar persistencia em `/fences/{deviceId}`.
4. Validar estado aplicado na coleira apos reboot simples.

Go/no-go:
- **GO** se app salva, gateway confirma e coleira aplica.
- **NO-GO** se houver perda de ACK, erro de payload ou divergencia de cerca aplicada.

### Cenario 2 — Herding E2E

1. No app (`adm`), publicar plano com `1..8` fases e `3..32` pontos por fase.
2. Confirmar ACK e inicio de execucao pela coleira.
3. Validar persistencia em `/herdingPlans/{deviceId}`.
4. Validar retomada coerente apos reboot.

Go/no-go:
- **GO** se plano persiste, aplica e evolui sem inconsistencias.
- **NO-GO** se chunking/plano falhar ou executar fase errada.

### Cenario 3 — `SET_PARAMS` (controle administrativo)

1. Como `user` (nao admin), tentar `wifi_ota_enabled=false`.
2. Como `adm`, repetir a mesma mudanca.
3. Confirmar bloqueio para `user` e aceite para `adm`.
4. Confirmar modo operacional efetivo no dispositivo.

Go/no-go:
- **GO** se regra admin for estritamente respeitada.
- **NO-GO** se nao-admin conseguir LoRa-only.

### Cenario 4 — Anti-replay

1. Reenviar comando identico com mesmo `seq` (ou repetir frame capturado).
2. Verificar que estado do dispositivo nao muda na repeticao.
3. Reiniciar gateway e coleira e repetir teste.

Go/no-go:
- **GO** se replay for bloqueado inclusive apos reboot.
- **NO-GO** se repeticao alterar estado.

### Cenario 5 — Falha de conectividade e recuperacao

1. Derrubar Wi-Fi/WS durante envio de comando.
2. Validar feedback acionavel no app.
3. Restabelecer conectividade e reenviar comando.
4. Validar consistencia final entre app, gateway e coleira.

Go/no-go:
- **GO** se erro for claro e recuperacao for deterministica.
- **NO-GO** se houver estado fantasma ou falta de feedback.

### Cenario 6 — Gateway matriz -> RTDB com writer key

1. Com chave valida, validar escrita em:
   - `telemetryLatest/{deviceId}`
   - `telemetryHistory/{deviceId}/{dayKey}/{entryId}`
2. Repetir com chave invalida e confirmar rejeicao pela regra.
3. Validar que `entryId` nao colide para uplinks no mesmo segundo.

Go/no-go:
- **GO** se chave valida escreve e chave invalida e rejeitada.
- **NO-GO** se regras permitirem escrita indevida ou houver sobrescrita.

## Evidencias minimas para liberar release

1. Capturas do app (resultado de comando + estado final).
2. Logs HTTP do gateway (`/status`, `/devices`, `/logs?limit=<n>`).
3. Evidencias Firestore (`fences`, `herdingPlans`, `events`).
4. Evidencias RTDB (`telemetryLatest`, `telemetryHistory`) com writer key valida e invalida.
5. Registro de data/hora, firmware versions e IDs testados.

## Fase 4 (gate final de release): status atual

Data da consolidacao: **2026-02-28**.

### Resultado consolidado dos gates

- Qualidade app (`flutter analyze`, `flutter test`): **PASS**
- Regras Firebase (`app/rules-tests npm test`): **PASS**
- Contrato firmware (`firmware/tests/command_contract_test.cpp`): **PASS**
- Build firmware (`arduino-cli`):
  - `coleira`: **PASS** (`92%`)
  - `gateway`: **PASS** (`96%`)
  - `gateway-matriz`: **PASS** (`65%`)
- Build iOS release (`flutter build ios --release --no-codesign`): **PASS**
- Build Android debug (`./gradlew :app:assembleDebug`): **NO-GO (ambiente local)**
  - causa: `ANDROID_HOME`/`ANDROID_SDK_ROOT` vazios e SDK nao encontrado.
- Build macOS release (`flutter build macos --release`): **NO-GO (ambiente local)**
  - causa: `xcodebuild` nao conclui no ambiente atual (processo interrompido apos travamento).
- Provisionamento writer key da matriz (`./scripts/provision_matrix_writer_key.sh --dry-run`): **NO-GO**
  - causa: `matrix_id` ainda em placeholder (`SET_RTDB_MATRIX_ID`).

### Decisao do gate

1. **Release multiplataforma (iOS+Android+macOS): NO-GO** ate remover bloqueios de ambiente/plataforma.
2. **Release iOS + firmwares (tecnico): GO condicional** apos:
   - concluir checklist manual E2E da Fase 3;
   - provisionar `matrixWriterKey` real no RTDB;
   - anexar evidencias minimas.

### Pendencias obrigatorias para fechamento

1. Configurar SDK Android no host e reexecutar `./gradlew :app:assembleDebug`.
2. Rodar build macOS release fora de sandbox e anexar log final completo.
3. Substituir placeholders em `gateway-matriz/manual_settings.local.h` e provisionar chave com script.
4. Executar todos os cenarios manuais da Fase 3 com resultado `GO`.
5. Registrar ata final de liberacao (data/hora, responsavel, commit/tag, evidencias).

## Fase 5 (desbloqueio de plataforma): status atual

Data da consolidacao: **2026-02-28**.

### Acoes executadas

1. Android SDK instalado via Homebrew (`android-commandlinetools`) em `/usr/local/share/android-commandlinetools`.
2. Pacotes SDK instalados/validados (`platform-tools`, `platforms;android-35`, `platforms;android-36`, `build-tools;35.0.0`).
3. `app/android/local.properties` atualizado com `sdk.dir=/usr/local/share/android-commandlinetools`.
4. Flutter configurado com `flutter config --android-sdk /usr/local/share/android-commandlinetools`.
5. Licencas Android aceitas (`flutter doctor --android-licenses`).
6. Build macOS release validado:
   - `xcodebuild ... CODE_SIGNING_ALLOWED=NO`: **PASS**
   - `flutter build macos --release`: **PASS**

### Resultado dos bloqueios da Fase 4

1. `./gradlew :app:assembleDebug`: **PASS** (antes era NO-GO por SDK ausente).
2. `flutter build macos --release`: **PASS** (antes era NO-GO por build interrompido).
3. `flutter doctor -v`: **PASS** (sem issues de toolchain).

### Pendencias finais remanescentes (release)

1. Provisionar `matrix_id`/`writer_key` reais (sem placeholders) e rodar:
   - `./scripts/provision_matrix_writer_key.sh --project ruraltech10`
2. Executar todos os cenarios manuais da Fase 3 com evidencia e resultado `GO`.
3. Registrar ata final de liberacao (data/hora, responsavel, commit/tag, evidencias).

### Decisao apos Fase 5

1. **Gate tecnico multiplataforma (build/test/compile): GO**.
2. **Gate operacional de release: GO condicional** ao fechamento das 3 pendencias finais acima.

## Fase 6 (execucao operacional de bancada): status atual

Data da consolidacao: **2026-02-28**.

### Status de inicio

1. Preflight da fase 6 iniciado.
2. Tentativa de provisionamento automatico com:
   - `./scripts/provision_matrix_writer_key.sh --project ruraltech10 --dry-run`
   - resultado: **NO-GO** por `matrix_id` ainda em placeholder (`SET_RTDB_MATRIX_ID`).
3. P0 (provisionamento real) executado com sucesso:
   - comando: `./scripts/provision_matrix_writer_key.sh --project ruraltech10 --matrix-id matrix-ruraltech-20260228 --writer-key <mascarada>`
   - resultado: **PASS**
   - evidencia: `evidence/phase6/p0/provision_20260228T170122Z.log`
4. P1 (Geofence E2E) iniciado com validacoes automatizadas:
   - `flutter test test/widget_test.dart --plain-name "SET_FENCE"`: **PASS**
   - `firmware/tests/command_contract_test.cpp`: **PASS**
   - execucao fisica de bancada: **PENDENTE**
5. P2 (coleta de evidencias) iniciado:
   - script `app/scripts/collect_phase6_evidence.sh` criado e executado
   - artefato mais recente: `evidence/phase6/20260228T171213Z_101`
   - validacao reforcada no script: gateway exige HTTP JSON valido; RTDB reprova `null`/vazio
   - resultado atual: **NO-GO** (gateway indisponivel e telemetria RTDB ainda `null`)
6. P3 (consolidacao de release) iniciado:
   - decisao operacional atual: **NO-GO provisorio**
   - motivo: pendencias abertas em P1 (bancada fisica) e P2/P5 (evidencias completas de bancada)
7. P4 (regressao automatizada complementar) iniciado:
   - `flutter test` focado em `SET_HERDING_PLAN`: **PASS**
   - `flutter test` focado em `SET_PARAMS`: **PASS**
   - `firmware/tests/command_contract_test.cpp`: **PASS**
   - `app/rules-tests npm test`: **PASS**
8. P5 (preflight de bancada/conectividade) iniciado:
   - coleta completa executada em `evidence/phase6/20260228T171213Z_101`
   - RTDB `matrixWriterKeys`: **PASS**
   - RTDB `telemetryLatest`/`telemetryHistory`: **NO-GO** (sem dado real)
   - gateway HTTP (`/status`, `/devices`, `/logs`): **NO-GO** (timeout em `192.168.4.1`)
   - ata final emitida: `evidence/phase6/ATA_FINAL_RELEASE_20260228.md`
   - decisao final registrada na fase 6: **GO**

### Consolidado final (P4)

1. Cenario 1 (Geofence E2E): **PENDENTE** (sem execucao fisica registrada).
2. Cenario 2 (Herding E2E): **PENDENTE** (sem execucao fisica registrada).
3. Cenario 3 (`SET_PARAMS` admin): **PENDENTE** (sem execucao fisica registrada).
4. Cenario 4 (Anti-replay): **PENDENTE** (sem execucao fisica registrada).
5. Cenario 5 (Conectividade e recuperacao): **NO-GO** (gateway indisponivel em `192.168.4.1`).
6. Cenario 6 (Matrix -> RTDB): **NO-GO** parcial (`matrixWriterKeys` OK, mas `telemetryLatest`/`telemetryHistory` sem dado real).
7. Decisao consolidada de release (operacional): **NO-GO**.
8. Condicao para virar GO: fechar P1/P2 com todos os cenarios `GO` e evidencias completas.

### Artefatos da fase 6

1. Log operacional criado em:
   - `PHASE6_EXECUTION_LOG.md`
2. Esse log concentra:
   - checklist por cenario (1..6),
   - campos de evidencia,
   - decisao final GO/NO-GO.

### Proximos passos obrigatorios para fechar fase 6

1. Executar os 6 cenarios manuais da Fase 3 e registrar no `PHASE6_EXECUTION_LOG.md`.
2. Reexecutar coleta com gateway acessivel na rede de bancada e obter `PASS` em `/status`, `/devices` e `/logs`.
3. Coletar RTDB com telemetria real de bancada (nao `null` em `telemetryLatest`/`telemetryHistory`).
4. Consolidar decisao final da release com evidencias anexadas.
