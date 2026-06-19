# Projeto: RuralTech

## Context

Monorepo de pecuária de precisão. Produto principal: coleiras ESP32 com geofence, condução de rebanho e telemetria, gerenciadas via app Flutter.

## Description

Sistema em 3 camadas físicas (coleira → gateway → cloud) com app de gestão. O app permite configurar cercas virtuais, planos de condução, visualizar telemetria em tempo real e auditar eventos das coleiras.

## Details

### Status atual (2026-04-19)

- Branch ativa: `fix/comandos/app-to-coleira` — implementação do protocolo RPv2 para SET_FENCE
- Branch principal: `main`
- Stack atual: Supabase Auth + Postgres + Realtime + Edge Functions; despacho cloud da matriz ainda usa `matrixId + writerKey` e fila RT
- **Protocolo RPv2**: Implementado e testado localmente (validação de bancada pendente)

### Módulos

- `app/` — Flutter, Supabase (Auth, Postgres, Realtime)
- `coleira/` — ESP32 firmware (geofence NVS, herding, telemetria, health diário, protocolo RPv2)
- `gateway/` — ESP32 firmware (LoRa bridge local, API HTTP/WS porta 81)
- `gateway-matriz/` — Serviço de despacho LoRa central (stream RTDB + polling, protocolo RPv2 para SET_FENCE)
- `supabase/` — Edge Functions: `queue-lora-command`, `matrix-cloud`, `admin-repair-cloud-state`, `poll-notifications`, `send-push`
- `firmware/shared/` — `command_contract.cpp` + `radio_proto_v2_*` (contrato compartilhado C++/Dart + protocolo binário)
- `contracts/messages/` — Fixtures JSON de contratos app ↔ firmware

### Papéis de usuário

- `user` — Acesso a propriedades onde está listado em `user_uids`
- `adm`/`admin` — Acesso total; pode alterar `wifi_ota_enabled=false` (modo LoRa-only)

### Testes

- `flutter test` — testes Flutter (app/)
- `npm test` — regressão de regras (app/rules-tests/)
- `supabase test db --local` — pgTAP RLS policies
- `command_contract_test.cpp` — contrato firmware compilado com g++
- `arduino-cli compile` — coleira, gateway, gateway-matriz
- `rpv2_*_test.cpp` — testes nativos do protocolo RPv2 (codec, CRC, planner)

### Comandos úteis de firmware

- Descobrir porta USB: `arduino-cli board list`
- Compilar coleira: `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs coleira`
- Gravar coleira: `arduino-cli upload -p <PORTA_USB> --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs coleira`
- Compilar matriz: `arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`
- Gravar matriz: `arduino-cli upload -p <PORTA_USB> --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs gateway-matriz`
- Monitor serial: `arduino-cli monitor -p <PORTA_USB> -c baudrate=115200`

## Related

[[visao-geral]]
[[regras-negocio]]
[[requisitos]]
[[modelagem-dados-supabase]]
[[uiux-telas]]
[[fluxos-comunicacao-ponta-a-ponta]]
[[protocolo-rpv2]]
[[stack-tecnologico]]
[[convencoes-codigo]]
[[padroes-implementacao]]
[[migracao-supabase]]

#projetos #ruraltech 
