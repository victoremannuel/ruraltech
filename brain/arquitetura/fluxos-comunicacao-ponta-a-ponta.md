# Architecture: Fluxos de Comunicação Ponta a Ponta — RuralTech

## Overview

Todos os fluxos de dados do sistema, do app até a coleira e de volta ao app.

## Components

### Atores

| Ator | Tecnologia |
|---|---|
| App Flutter | Dart, Supabase client, WebSocket gateway |
| Supabase Edge Functions | Deno — `queue-lora-command`, `matrix-cloud` |
| Supabase Postgres | Dados persistentes, RLS, Realtime |
| Gateway Local | ESP32, HTTP/WS porta 81 |
| Gateway Matriz | ESP32/serviço central, LoRa SX127x |
| Coleira | ESP32, LoRa, GPS, NVS |

---

## Flow

### Fluxo 1: Edição de Propriedade → SET_FENCE Automático

```
App salva rural_properties.points (Supabase)
→ Supabase trigger onWrite → autoSyncPropertyFence
→ Cria SET_FENCE determinístico (cmd_id = SHA256(property_id+polygon))
→ Grava em Supabase property_commands
→ Enfileira em RTDB matrixCommandQueues
→ Gateway Matriz: stream RTDB (prioritário) + polling fallback
→ Matriz envia SET_FENCE via LoRa para TODAS as coleiras da propriedade
→ Coleira: aplica polígono em NVS + emite polygon_apply_result
→ Matriz: grava propertyEvents + propertyCommandEvents
→ App: lê log via Supabase Realtime
→ App abre evento: consulta polígono atual, busca telemetria histórica
→ App renderiza preview SVG dentro da sanfona do evento
```

### Fluxo 2: Edição de Piquete → SET_FENCE Seletivo

```
App salva areas.perimeter + areas.linkedDeviceIds (Supabase)
→ Supabase onWrite → autoSyncAreaFence
→ Ignora se source=herding_operation
→ Sincroniza collars.activeAreaId nas vinculadas
→ Cria SET_FENCE APENAS para linked_device_ids alterados
→ Mesmo pipeline: property_commands → RTDB → Matriz → LoRa → Coleira
→ Coleira aplica cerca do piquete + polygon_apply_result
→ App log: sucesso/falha com payload bruto e preview SVG
```

### Fluxo 3: Comando Genérico do App

```
App chama CloudService.enqueueScopedCommand(command, propertyId, ...)
→ POST Supabase Edge Function: queue-lora-command
→ Valida matrixId + writerKey + payload
→ Grava Supabase property_commands
→ Enfileira RTDB matrixCommandQueues com cmd_id e metadados de auditoria
→ Gateway Matriz: stream RTDB (trigger prioritário)
→ Matriz → coleira via LoRa
→ ACK/NACK da coleira → Matriz grava matrix_command_results
→ propertyEvents + propertyCommandEvents atualizados
→ App recebe via Realtime
```

### Fluxo 4: Operação de Herding

```
App HerdingScreen:
  - Seleciona propriedade + coleiras
  - Desenha polígono destino
  - Chama CloudService.createHerdingOperation(...)
→ Supabase: cria herding_operations (status=submitted)
→ Edge Function matrix-cloud:
  - Cria SET_HERDING_PLAN para cada coleira selecionada
  - Atualiza status=dispatching
→ Matriz despacha via LoRa
→ Coleiras aplicam plano e reportam (assembled/completed)
→ herding_operations.device_statuses atualizado por dispositivo
→ Status final: completed / failed / superseded
→ Notificação push para notify_user_ids
→ Se area_promotion_requested=true: cria area permanente (created_area_id)
```

### Fluxo 5: Telemetria em Tempo Real

```
Coleira → LoRa → Gateway Matriz
→ Matriz: grava property_telemetry_latest (upsert por device_id)
→ Matriz: appenda property_telemetry_history (por day_key)
→ Supabase Realtime publica mudança
→ App HomeScreen: atualiza marcador GPS no mapa
```

**Caminho alternativo (gateway local):**
```
App conecta via WebSocket (porta 81) ao gateway local
→ Gateway envia GatewayTelemetrySample via WS stream
→ App HomeScreen: _gatewayTelemetrySub → atualiza mapa em tempo real
```

### Fluxo 6: Health Diário

```
Coleira (uma vez por dia, no boot ou timer):
→ Envia health_daily_event via LoRa
→ Gateway Matriz:
  - Grava property_health_latest (upsert)
  - Appenda property_health_history (day_key)
  - Atualiza collars: health_flags, health_uptime_sec, health_temperature_deci_c,
    health_satellites, health_hdop_centi, health_i2c_devices
→ App: exibe resumo de saúde no DeviceDetailsScreen e CollarLogScreen
```

### Fluxo 7: Auditoria e Log da Coleira

```
App CollarLogScreen:
  - CloudService.getCollarLog(propertyId, deviceId)
  - Consulta: property_events + property_command_events combinados
  - Ordena por receivedAtMs desc
  - Para eventos polygon_apply_result com sucesso:
    → Consulta polígono atual (fences/areas/rural_properties por origin_doc_type)
    → Consulta telemetria histórica (posição no momento do evento)
    → Renderiza preview SVG com polígono + posição da coleira
  - Tipos de entrada no log:
    - telemetry: posição GPS
    - health_daily: relatório de saúde
    - polygon_apply_result success/failure
    - Outros eventos operacionais
```

### Fluxo 8: Gateway Local (descoberta + conexão)

```
App:
→ BluetoothDiscoveryService: scan de dispositivos na rede
→ Encontra gateway por IP local
→ GatewayService: conecta WS ws://host:81
→ Recebe stream de telemetria e eventos
→ App exibe overlay de conectividade no mapa
→ Para comandos: POST HTTP /api/command no gateway local
```

---

## Details

### Metadados de Rastreabilidade em Comandos

Todo comando carrega:
- `cmd_id` — hash determinístico (deduplicação)
- `polygon_kind` — 'property' | 'area' | 'herding'
- `origin_doc_type` — 'rural_property' | 'area' | 'herding_operation'
- `origin_doc_id` — ID do documento de origem
- `property_scope_id` — escopo da propriedade

### Estados de Comando

```
enfileirado → despachado pela matriz → ACK da coleira → polygon_apply_result
                                     ↓ falha precoce
                                     propertyCommandEvents
```

### Cobertura de Falhas

| Cenário de Falha | Onde Aparece |
|---|---|
| Validação rejeitada no app | AppFeedback.error() |
| Edge Function rejeita | property_command_events (status=rejected) |
| Matriz não alcança coleira | propertyCommandEvents (timeout) |
| Coleira falha ao aplicar | polygon_apply_result (success=false) → propertyEvents |
| Stream RTDB cai | polling fallback na matriz |

## Technologies

- Supabase Realtime (WebSocket CDC)
- RTDB Firebase (fila de despacho legada, em migração)
- LoRa SX127x (payload máx 128 bytes, fragmentação automática)
- WebSocket porta 81 (gateway local)
- HTTP REST (gateway local + Edge Functions)
- Push notifications (flutter_local_notifications + WorkManager)

## Related

[[regras-negocio]]
[[modelagem-dados-supabase]]
[[fluxo-comandos]]
[[uiux-telas]]

#arquitetura #ruraltech 