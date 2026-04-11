# Architecture: RuralTech — Visão Geral

## Overview

Sistema de pecuária de precisão com coleiras inteligentes, gateways LoRa e app móvel.

## Components

- **app/** — Flutter + Supabase (Auth, Postgres, Realtime, Edge Functions)
- **coleira/** — Firmware ESP32: telemetria GPS, geofence NVS, herding, health diário, segurança animal
- **gateway/** — Firmware ESP32: bridge LoRa ↔ HTTP/WS porta 81, fila de comandos local
- **gateway-matriz/** — Serviço central: stream RTDB + polling fallback, despacho LoRa
- **supabase/** — Edge Functions (`queue-lora-command`, `matrix-cloud`) + migrations + Postgres
- **firmware/shared/** — Contrato de comandos compartilhado (command_contract.cpp)
- **contracts/messages/** — Fixtures JSON de contrato app ↔ firmware

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