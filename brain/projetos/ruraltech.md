# Projeto: RuralTech

## Context

Monorepo de pecuária de precisão. Produto principal: coleiras ESP32 com geofence, condução de rebanho e telemetria, gerenciadas via app Flutter.

## Description

Sistema em 3 camadas físicas (coleira → gateway → cloud) com app de gestão. O app permite configurar cercas virtuais, planos de condução, visualizar telemetria em tempo real e auditar eventos das coleiras.

## Details

### Status atual (2026-04-11)

- Branch ativa: `audit/remove-firebase-complete` — remoção completa do Firebase em andamento
- Branch principal: `main`
- Stack atual: Supabase Auth + Postgres + Realtime + Edge Functions (sem Firebase)

### Módulos

- `app/` — Flutter, Supabase (Auth, Postgres, Realtime)
- `coleira/` — ESP32 firmware (geofence NVS, herding, telemetria, health diário)
- `gateway/` — ESP32 firmware (LoRa bridge local, API HTTP/WS porta 81)
- `gateway-matriz/` — Serviço de despacho LoRa central (stream RTDB + polling)
- `supabase/` — Edge Functions: `queue-lora-command`, `matrix-cloud`, `repair-firebase-mirrors`
- `firmware/shared/` — `command_contract.cpp` (contrato compartilhado C++/Dart)
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

## Related

[[visao-geral]]
[[regras-negocio]]
[[requisitos]]
[[modelagem-dados-supabase]]
[[uiux-telas]]
[[fluxos-comunicacao-ponta-a-ponta]]

#projetos #ruraltech 