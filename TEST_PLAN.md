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

- `gateway-matriz` ainda estoura flash em compilacao com `min_spiffs`.
- esse item permanece como bloqueador tecnico ate estabilizacao.
