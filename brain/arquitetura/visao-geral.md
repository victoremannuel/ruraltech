# Architecture: RuralTech — Visão Geral

## Overview

Sistema de pecuária de precisão com coleiras inteligentes, gateways LoRa e app móvel.

## Components

- **app/** — Flutter + Supabase (Auth, Postgres, Realtime, Edge Functions) [[uiux-telas]] [[stack-tecnologico]]
- **coleira/** — Firmware ESP32: telemetria GPS, geofence NVS, herding, health diário, segurança animal [[regras-negocio]]
- **gateway/** — Firmware ESP32: bridge LoRa ↔ HTTP/WS porta 81, fila de comandos local [[fluxo-comandos]]
- **gateway-matriz/** — Serviço central: stream RTDB + polling fallback, despacho LoRa [[fluxos-comunicacao-ponta-a-ponta]]
- **supabase/** — Edge Functions (`queue-lora-command`, `matrix-cloud`) + migrations + Postgres [[modelagem-dados-supabase]] [[migracao-supabase]]
- **firmware/shared/** — Contrato de comandos compartilhado (command_contract.cpp) [[padroes-implementacao]]
- **contracts/messages/** — Fixtures JSON de contrato app ↔ firmware [[convencoes-codigo]]

## Flow

```
App → Supabase Edge Function queue-lora-command
    → Supabase property_commands + RTDB matrixCommandQueues
    → Matriz: stream RTDB (prioritário) + polling (fallback)
    → LoRa → Coleira
    → ACK/NACK + polygon_apply_result
    → Supabase propertyEvents + propertyCommandEvents
    → App Realtime (log auditável com preview SVG)
```

## Technologies

- ESP32 (Arduino/IDF), LoRa SX127x
- Flutter (Dart, Material 3)
- Supabase: Auth, Postgres, Realtime, Edge Functions (Deno)
- Contrato de comandos em C++/Dart compartilhado

## Related

[[fluxo-comandos]]
[[fluxos-comunicacao-ponta-a-ponta]]
[[modelagem-dados-supabase]]
[[regras-negocio]]
[[requisitos]]
[[uiux-telas]]
[[stack-tecnologico]]
[[convencoes-codigo]]
[[padroes-implementacao]]

#arquitetura #ruraltech 