# Architecture: RuralTech — Visão Geral

## Overview

Sistema de pecuária de precisão com coleiras inteligentes, gateways LoRa e app móvel.

## Components

- **app/** — Flutter + Supabase (Auth, Postgres, Realtime, Edge Functions)
- **coleira/** — Firmware ESP32: telemetria GPS, geofence NVS, herding, health diário, segurança animal, protocolo RPv2 binário
- **gateway/** — Firmware ESP32: bridge LoRa ↔ HTTP/WS porta 81, fila de comandos local
- **gateway-matriz/** — Serviço central: stream RTDB + polling fallback, despacho LoRa, protocolo RPv2 para SET_FENCE
- **supabase/** — Edge Functions (`queue-lora-command`, `matrix-cloud`) + migrations + Postgres
- **firmware/shared/** — Contrato de comandos compartilhado (command_contract.cpp, radio_proto_v2_*)
- **contracts/messages/** — Fixtures JSON de contrato app ↔ firmware

## Flow

### SET_FENCE via RPv2 (binário)

```
App → Supabase Edge Function queue-lora-command
    → Supabase property_commands + RTDB matrixCommandQueues
    → Matriz: stream RTDB (prioritário) + polling (fallback)
    → Matriz normaliza payload → planner RPv2 calcula chunks por bytes reais
    → Sessão binária RPv2: BEGIN → POINTS → COMMIT (LoRa)
    → Coleira: valida CRC, persiste em staging, aplica se OK
    → ACK/NACK binário por etapa + APPLY_STATUS final
    → Supabase propertyEvents + propertyCommandEvents (transport=radio_fence_v2)
    → App Realtime (log auditável com preview SVG)
```

### Comandos legados (JSON textual)

```
App → Supabase Edge Function queue-lora-command
    → Supabase property_commands + RTDB matrixCommandQueues
    → Matriz: stream RTDB (prioritário) + polling (fallback)
    → LoRa JSON → Coleira
    → ACK/NACK + polygon_apply_result
    → Supabase propertyEvents + propertyCommandEvents
    → App Realtime (log auditável com preview SVG)
```

## Technologies

- ESP32 (Arduino/IDF), LoRa SX127x
- Flutter (Dart, Material 3)
- Supabase: Auth, Postgres, Realtime, Edge Functions (Deno)
- Contrato de comandos em C++/Dart compartilhado
- Protocolo RPv2 binário para SET_FENCE (CRC32, FNV-1a 64, sessão BEGIN/POINTS/COMMIT)

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