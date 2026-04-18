# Architecture: Fluxo de Comandos e Auditoria

## Overview

Pipeline ponta a ponta para envio de comandos do app para coleiras e auditoria dos resultados.

## Components

| Papel | Implementação |
|---|---|
| Origem do comando | App Flutter / trigger onWrite no Supabase |
| Validação | Supabase Edge Function `queue-lora-command` |
| Persistência | Supabase `property_commands` |
| Fila cloud | RTDB `matrixCommandQueues` |
| Despacho | Matriz via stream RTDB (prioritário) + polling (fallback) |
| Transporte físico | LoRa (máx 128 bytes, fragmentação automática) |
| Confirmação | Coleira emite `polygon_apply_result` + ACK/NACK |
| Auditoria | Supabase `property_events`, `property_commands`, `property_command_events` |

## Flow

### Auto SET_FENCE (propriedade)

```
App salva rural_properties.points (Supabase)
→ Trigger onWrite → autoSyncPropertyFence
→ Cria SET_FENCE com cmd_id determinístico (SHA256)
→ Supabase property_commands + RTDB matrixCommandQueues
→ Matriz → Coleira via LoRa
→ Coleira: aplica NVS + emite polygon_apply_result
→ Supabase property_events → App log com preview SVG
```

### Auto SET_FENCE (piquete)

```
App salva areas.perimeter + linkedDeviceIds (Supabase)
→ Trigger onWrite → autoSyncAreaFence
→ Ignora source=herding_operation
→ Cria SET_FENCE só para linkedDeviceIds alterados
→ Mesmo pipeline de despacho
```

## Details

- `cmd_id`, `polygon_kind`, `origin_doc_type`, `origin_doc_id` acompanham o payload para rastreabilidade
- Falhas precoces (antes de chegar na coleira) aparecem em `property_command_events`
- Sucesso de gravação é confirmado pela coleira via `polygon_apply_result`
- App combina `property_events` + `property_command_events` para cobrir todos os cenários de falha
- `property_scope_id` = SHA256(property_id)[0:16] upper — escopo determinístico

## Related

[[ruraltech]]
[[visao-geral]]
[[fluxos-comunicacao-ponta-a-ponta]]
[[modelagem-dados-supabase]]
[[regras-negocio]]

#arquitetura #ruraltech