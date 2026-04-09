# AGENTS.md

## 1. Visao Geral do Projeto

**Nome:** RuralTech**Objetivo:** Monitorar e conduzir rebanho com coleiras inteligentes, gateways LoRa e app Flutter.**Dominio de negocio:** Pecuaria de precisao (geofence, herding por fases, telemetria, eventos criticos, operacao offline-first).**Principais responsabilidades do sistema:**

- Permitir envio de comandos do app para coleiras via gateway (`SET_FENCE`, `SET_HERDING_PLAN`, `SET_PARAMS`, `PING`).
- Coletar telemetria/eventos da rede LoRa e disponibilizar para app e Firebase.
- Aplicar regras de seguranca animal na coleira mesmo sem conectividade.
- Controlar modo operacional Wi-Fi/OTA vs LoRa-only com regra administrativa.
- Garantir rastreabilidade por contratos de mensagem e logs locais com hash chain.

Resumo tecnico (max. 10 linhas):

> Monorepo com 3 camadas principais: app (`Flutter + Firebase`), firmware de borda (`ESP32` para coleira/gateway/gateway-matriz) e contratos compartilhados.
> O app usa `Provider`, `Firebase Auth`, `Firestore` e `Realtime Database`.
> Gateways expoem API HTTP (`/status`, `/devices`, `/logs`) e WebSocket na porta `81`.
> A rede LoRa usa payload maximo de `128 bytes` com fragmentacao automatica para comandos grandes.
> Validacoes de negocio de comandos existem no app e no modulo C++ compartilhado (`firmware/shared/command_contract.*`).
> CI em GitHub Actions executa analise/testes Flutter, testes de rules Firebase, testes de contrato C++ e compilacao dos 3 firmwares.

---

## 2. Stack Tecnologico

### Monorepo (visao geral)

- Linguagem principal: Dart (app) + C++ Arduino (firmware) + JSON (contratos) + JS Node (rules tests)
- CI/CD: GitHub Actions (`pr-quality.yml`, `nightly-regression.yml`)
- Infraestrutura: Firebase + dispositivos ESP32 (LoRa, Wi-Fi AP, OTA, SD)

### `app/` (Flutter)

- Linguagem principal: Dart 3.3+
- Framework: Flutter (Material 3)
- Banco de dados: Firebase Firestore + Firebase Realtime Database
- ORM: N/A (SDK oficial Firebase)
- Testes: `flutter_test` (unit/widget/fixtures)
- Linter/Formatter: `flutter_lints` + `flutter analyze` + `dart format`
- CI/CD: job `Flutter Analyze + Test` + `Flutter Regression`
- Infraestrutura: Firebase Auth/Firestore/RTDB, WebSocket com gateway

### `coleira/`, `gateway/`, `gateway-matriz/` (firmware ESP32)

- Linguagem principal: C++ (Arduino)
- Framework: Arduino Core ESP32
- Banco de dados: NVS/EEPROM (coleira), SD card (logs gateway)
- Testes: contrato C++ compilado com `g++` em `firmware/tests`
- Linter/Formatter: compilacao com `-Wall -Wextra -pedantic` no teste de contrato
- CI/CD: `arduino-cli compile` para os 3 sketches
- Infraestrutura: ESP32 Dev Module, LoRa (RadioLib), OTA, APIs locais HTTP/WS

### `app/rules-tests/`

- Linguagem principal: Node.js (ESM)
- Framework de teste: Node test runner + `@firebase/rules-unit-testing`
- Objetivo: validar `firestore.rules` e `database.rules.json` com emuladores

---

## 3. Arquitetura

### Padrao arquitetural

- Monorepo multi-servico com contratos compartilhados.
- App Flutter em camadas simples (`screens` + `services` + `models`).
- Firmware modular por responsabilidade (radio, API, seguranca, sensores, persistencia).
- Contrato de comandos centralizado em modulo C++ compartilhado.

### Estrutura de pastas

```txt
ruraltech/
  app/
    lib/
      config/
      models/
      screens/
      services/
      utils/
      widgets/
    test/
    rules-tests/
  coleira/
  gateway/
  gateway-matriz/
  firmware/
    shared/
    tests/
  contracts/
    messages/
  temp/
  .github/workflows/
```

Papel dos diretorios:

- `app/lib`: UI e regras de negocio do app.
- `app/test`: testes Flutter (inclui validacao de contrato e regras de comando).
- `app/rules-tests`: testes automatizados de seguranca Firebase (Firestore/RTDB).
- `coleira`: firmware da coleira (telemetria, geofence, herding, seguranca animal).
- `gateway`: firmware gateway local (LoRa <-> app via HTTP/WS).
- `gateway-matriz`: gateway central (LoRa <-> app + integracao RTDB/writerKey).
- `firmware/shared`: validacoes de contrato reutilizadas entre firmwares.
- `firmware/tests`: testes nativos de contrato/fragmentacao.
- `contracts/messages`: fixtures JSON que definem o contrato app <-> firmwares.
- `temp`: area padrao para artefatos temporarios locais do monorepo (compilacao, logs, saidas de testes e diagnosticos).
- `.github/workflows`: gates de qualidade de PR e regressao noturna.

---

## 4. Convencoes Obrigatorias

### Codigo

- Manter tipagem explicita e validações defensivas (especialmente payloads de comando e coordenadas).
- Nao introduzir `dynamic`/`Map` sem validacao de schema no app.
- Em firmware, preferir tipos de largura fixa (`uint8_t`, `uint16_t`, etc.).
- Funcoes devem manter responsabilidade unica e nomes semanticos.
- Constantes de limite devem ser centralizadas (`maxLoraPayloadBytes`, `maxPolygonPoints`, etc.).
- Regras de negocio devem retornar motivo claro (`reason`) quando houver rejeicao.

### Imports

- App Flutter: preferir imports de pacote (`package:ruraltech_app/...`) fora do mesmo modulo.
- Evitar acoplamento por imports profundos e referencias cruzadas desnecessarias.
- Firmware: headers locais por modulo (`*.h`) e contrato compartilhado via `firmware/shared`.

### Erros e retorno

- Nao usar falhas silenciosas para regras de negocio.
- Em comandos app/firmware, sempre produzir retorno estruturado (`ok` + `reason`) via `command_result`/`ACK`/`NACK`.
- Mensagens de erro devem indicar causa acionavel (ex.: `invalid_device_id`, `admin_required_for_lora_only`).

### Arquivos temporarios

- Todo artefato temporario local gerado durante o trabalho no monorepo deve ser salvo em `temp/`.
- Exemplos: arquivos de compilacao temporarios, logs, dumps, relatorios intermediarios e saidas de testes executados localmente.
- Evitar espalhar esses arquivos em `app/`, `firmware/`, raiz do repo ou outras pastas fora de `temp/`, salvo quando uma ferramenta exigir caminho fixo.

---

## 5. Padroes de Implementacao

### Criacao de novos endpoints/comandos (gateway e app)

- Validar payload antes de qualquer IO/rede.
- Manter compatibilidade com contratos em `contracts/messages/`.
- Para comandos acima de `128 bytes`, usar fragmentacao (`chunked`) seguindo padrao atual.
- Publicar resultado no WebSocket com formato `command_result`.
- Para alteracoes de modo operacional (`wifi_ota_enabled=false`), exigir marcador administrativo.

### Acesso a banco (Firebase)

- Somente `FirebaseService` deve concentrar acesso Firestore/RTDB no app.
- `screens/widgets` nao devem acessar Firestore/RTDB diretamente.
- Operacoes multiplas devem usar batch/transacao quando necessario.
- Sempre normalizar referencias (`DocumentReference`, path string, uid bruto) antes de persistir.

---

## 6. Testes

- Toda feature/alteracao deve incluir ou atualizar testes da camada impactada.
- Priorizar testes de comportamento observavel (entrada/saida), nao detalhes internos.
- Mocks apenas para dependencias externas (WebSocket/HTTP/clock/Firebase).
- Suite minima de auditoria por impacto:
  - App: `flutter analyze` e `flutter test` em `app/`
  - Regras Firebase: `npm test` em `app/rules-tests/`
  - Contrato firmware: compilacao/execucao de `firmware/tests/command_contract_test.cpp`
  - Firmware: compilacao `arduino-cli` de `coleira`, `gateway`, `gateway-matriz`

Exemplo de padrao (Dart):

```dart
group('GatewayService business rules', () {
  test('blocks LoRa-only SET_PARAMS without admin marker', () {})
})
```

---

## 7. Seguranca

- Nunca commitar segredos (`manual_settings.local.h`, chaves, credenciais).
- Nao logar dados sensiveis (senhas, writer keys, tokens).
- Validar autenticacao/autorizacao pelas rules (`firestore.rules`, `database.rules.json`).
- Sanitizar inputs de coordenadas, IDs e payload JSON.
- Respeitar principio de menor privilegio:
  - `wifi_ota_enabled=false` requer origem administrativa.
  - Escrita anonima no RTDB so com `matrixId + writerKey` validos.

---

## 8. Performance

- Respeitar limite LoRa de `128 bytes` por frame.
- Evitar N+1 no Firestore; preferir queries consolidadas e merge por chave.
- Usar batch em operacoes de escrita em massa.
- Em descoberta de rede local, manter processamento em lotes (`batch probing`).
- Em listagens no gateway (`/devices`, `/logs`), manter limite (`?limit=<n>`).

---

## 9. Regras Especificas do Projeto

- Toda implementacao ou alteracao deve rodar auditoria das funcionalidades impactadas para garantir sucesso E2E no requisito de negocio.
- IDs LoRa de coleira devem ser numericos e maiores que zero.
- `SET_FENCE`: `3..32` pontos.
- `SET_HERDING_PLAN`: `1..8` fases, com `3..32` pontos por fase.
- `SET_PARAMS` com `wifi_ota_enabled=false` exige admin (`requested_by_role=adm|admin` ou `requested_by_admin=true`).
- Contratos JSON em `contracts/messages/` sao baseline de regressao e nao podem ser quebrados sem atualizar testes.
- Regras de acesso Firebase devem permanecer alinhadas com papeis (`adm` vs `user`) e ownership.
- Telemetria deve manter coordenadas validas e timestamps coerentes (`receivedAt`/`receivedAtMs`).
- CRÍTICO: **Sempre levar em consideração a capacidade que a ESP32 tem de armazenar o firmware (ou seja, o tamanho do firmware não pode estourar a capacidade da placa)**

---

## 10. O que o agente NAO deve fazer

- Nao alterar contratos publicos de mensagem sem atualizar fixtures e testes.
- Nao introduzir novas dependencias de firmware sem avaliar impacto de flash/memoria.
- Nao mudar `rules` do Firebase sem incluir teste de regressao em `app/rules-tests`.
- Nao commitar arquivos locais de segredos (`manual_settings.local.h`, chaves de producao).
- Nao bypassar validacoes de seguranca/admin para comandos criticos.
- Nao desativar gates de CI (`flutter analyze`, `flutter test`, `rules tests`, `firmware compile`).
- Nao criar artefatos temporarios locais fora de `temp/` sem necessidade tecnica.
- NÃO DEVE NARRAR O QUE ESTIVER FAZENDO
- NÃO DEVE DAR RESUMOS LONGOS

## 11. O que o agente DEVE fazer

- DEVE AO FINAL COLOCAR UM RESUMO CURTO DO QUE FOI FEITO, COM FRASES OBJETIVAS E DIRETAS.
