# Architecture: Modelagem de Dados — Supabase

## Overview

Schema Postgres do Supabase com 21 tabelas, RLS em todas, Realtime em 12.

## Components

### Usuários e Autenticação

#### `profiles`
| Campo | Tipo | Notas |
|---|---|---|
| auth_user_id | uuid PK | FK auth.users |
| legacy_uid | text UNIQUE | UID legado (Firebase/interno) |
| email | text UNIQUE | |
| role | text | 'user' \| 'adm' \| 'admin' |
| created_at / updated_at | timestamptz | auto |

#### `user_push_tokens`
| Campo | Tipo | Notas |
|---|---|---|
| id | uuid PK | |
| legacy_uid | text | |
| platform | text | iOS/Android |
| token | text | push token |
| metadata | jsonb | |

---

### Domínio Rural

#### `rural_properties`
| Campo | Tipo | Notas |
|---|---|---|
| id | text PK | uuid gerado |
| name | text | nome da fazenda |
| points | jsonb | array de {lat, lon} |
| owner_uid | text | dono |
| created_by_uid | text | criador |
| updated_by_uid | text | último editor |
| user_uids | text[] | usuários com acesso (GIN index) |
| property_scope_id | text | SHA256(id)[0:16] upper — auto via trigger |

#### `areas`
| Campo | Tipo | Notas |
|---|---|---|
| id | text PK | |
| owner_uid | text | |
| property_id | text FK rural_properties | cascade delete |
| perimeter | jsonb | array de {lat, lon} |
| linked_device_ids | text[] | coleiras vinculadas ao piquete |
| user_uids | text[] | |
| updated_by_uid | text | |

#### `gateways`
| Campo | Tipo | Notas |
|---|---|---|
| id | text PK | |
| gateway_id | text UNIQUE | ID do hardware |
| owner_uid / name | text | |
| status | text | 'online' \| 'offline' |
| host | text | IP local |
| property_id | text FK rural_properties | |
| user_uids | text[] | |
| wifi_ota_enabled | boolean | |
| position | jsonb | {lat, lon} |
| is_matrix | boolean | é gateway matriz? |
| property_scope_id | text | auto via trigger |
| binding_ready | boolean | |
| supports_scoped_lora | boolean | |
| runtime_status | jsonb | status runtime |

#### `collars`
| Campo | Tipo | Notas |
|---|---|---|
| id | text PK | |
| device_id | text UNIQUE | ID numérico LoRa |
| owner_uid / name / status | text | |
| property_id | text FK rural_properties | |
| gateway_id | text FK gateways | |
| position | jsonb | {lat, lon} |
| wifi_ota_enabled | boolean | |
| property_scope_id | text | auto trigger |
| binding_ready / supports_scoped_lora | boolean | |
| runtime_status | jsonb | |
| telemetry_received_at_ms | bigint | último timestamp telemetria |
| position_received_at_ms | bigint | último timestamp posição |
| health_received_at_ms | bigint | último health diário |
| health_gps_day_key | integer | chave do dia do health |
| health_flags | integer | bitmask de flags de saúde |
| health_uptime_sec | integer | uptime em segundos |
| health_temperature_deci_c | integer | temperatura × 10 (decigraus) |
| health_satellites | integer | satélites GPS visíveis |
| health_hdop_centi | integer | HDOP × 100 |
| health_i2c_devices | integer | dispositivos I2C detectados |

**Health flags (bitmask):**
| Flag | Bit | Significado |
|---|---|---|
| wifiOtaEnabled | 0 | Wi-Fi OTA ativo |
| otaModeActive | 1 | OTA em execução |
| gpsUartReady | 2 | UART GPS pronto |
| gpsNmeaSeen | 3 | NMEA recebido |
| gpsFixValid | 4 | Fix GPS válido |
| mpuReady | 5 | IMU MPU pronto |
| mlxReady | 6 | Sensor MLX pronto |
| storageReady | 7 | SD/NVS OK |
| loRaReady | 8 | LoRa pronto |
| lastLoRaTxOk | 9 | Último TX LoRa OK |
| fallbackSchedule | 10 | Em modo fallback |

---

### Cercas e Planos

#### `fences`
| Campo | Tipo | Notas |
|---|---|---|
| device_id | text PK FK collars | |
| owner_uid | text | |
| points | jsonb | array de {lat, lon} |
| updated_at | timestamptz | |

#### `herding_plans`
| Campo | Tipo | Notas |
|---|---|---|
| device_id | text PK FK collars | |
| owner_uid | text | |
| phases | jsonb | array de {phase, points[]} |
| updated_at | timestamptz | |

---

### Operações de Condução

#### `herding_operations`
| Campo | Tipo | Notas |
|---|---|---|
| id | text PK | |
| property_id | text FK rural_properties | |
| owner_uid / requested_by_uid | text | |
| requested_by_role | text | role de quem solicitou |
| status | text | submitted→dispatching→awaiting_assembly→requested→completed/failed/superseded |
| target_polygon | jsonb | polígono destino |
| selected_device_ids | text[] | coleiras selecionadas |
| notify_user_ids | text[] | usuários a notificar |
| device_statuses | jsonb | status por device_id |
| matrix_gateway_id | text | gateway matriz usada |
| created_area_id | text | área criada (opcional) |
| lora_command_id | text | |
| area_promotion_requested | boolean | promover a área permanente? |
| client_failure_reason | text | |
| property_scope_id | text | |

---

### Telemetria

#### `property_telemetry_latest`
| Campo | Tipo | Notas |
|---|---|---|
| property_id + device_id | PK composta | |
| lat / lon | double | posição atual |
| received_at_ms | bigint | |
| payload | jsonb | dados brutos |

#### `property_telemetry_history`
| Campo | Tipo | Notas |
|---|---|---|
| property_id + device_id + history_id | PK composta | |
| day_key | text | YYYYMMDD |
| lat / lon | double | |
| received_at_ms | bigint | |
| payload | jsonb | |

#### `property_health_latest`
| Campo | Tipo | Notas |
|---|---|---|
| property_id + device_id | PK composta | |
| health_received_at_ms | bigint | |
| payload | jsonb | |

#### `property_health_history`
| Campo | Tipo | Notas |
|---|---|---|
| property_id + device_id + history_id | PK composta | |
| day_key | text | |
| health_received_at_ms | bigint | |
| payload | jsonb | |

---

### Eventos e Comandos

#### `events`
| Campo | Tipo | Notas |
|---|---|---|
| id | text PK | |
| owner_uid / property_id / device_id / gateway_id | text | |
| type / event_type / polygon_kind | text | |
| origin_doc_type / origin_doc_id | text | rastreabilidade |
| received_at_ms | bigint | |
| payload | jsonb | |

#### `property_events`
| Campo | Tipo | Notas |
|---|---|---|
| property_id + day_key + event_id | PK composta | |
| device_id / gateway_id / event_type | text | |
| lat / lon | double | |
| received_at_ms | bigint | |
| payload | jsonb | |

#### `property_commands`
| Campo | Tipo | Notas |
|---|---|---|
| property_id + command_id | PK composta | |
| command | text | SET_FENCE / SET_HERDING_PLAN / SET_PARAMS / PING |
| status | text | |
| property_scope_id / matrix_gateway_id | text | |
| requested_by_uid / requested_by_role | text | |
| created_at_ms / updated_at_ms / expires_at_ms | bigint | |
| polygon_kind / origin_doc_type / origin_doc_id | text | rastreabilidade |
| target_device_ids / target_gateway_ids | text[] | |
| device_results | jsonb | resultado por device |
| reason | text | motivo de rejeição |
| payload / raw | jsonb | |

#### `property_command_events`
| Campo | Tipo | Notas |
|---|---|---|
| property_id + day_key + event_id | PK composta | |
| command_id / device_id / status | text | |
| received_at_ms | bigint | |
| payload / raw | jsonb | |

---

### Infraestrutura Matriz

#### `matrix_bindings`
| Campo | Tipo | Notas |
|---|---|---|
| runtime_id | text PK | |
| property_id / property_scope_id / matrix_gateway_id | text | |
| enabled | boolean | |
| updated_at_ms | bigint | |
| raw | jsonb | |

#### `matrix_queue_keys`
| Campo | Tipo | Notas |
|---|---|---|
| runtime_id | text PK | |
| queue_key / writer_key | text | chaves de fila RTDB |
| updated_at_ms | bigint | |

#### `matrix_command_queues`
| Campo | Tipo | Notas |
|---|---|---|
| runtime_id + queue_key + command_id | PK composta | |
| created_at_ms / expires_at_ms | bigint | |
| payload | jsonb | |

#### `matrix_command_results`
| Campo | Tipo | Notas |
|---|---|---|
| runtime_id + command_id | PK composta | |
| updated_at_ms | bigint | |
| payload | jsonb | |

---

## Flow

### Funções e Triggers

| Função | Papel |
|---|---|
| `touch_updated_at()` | Atualiza `updated_at` em todo update |
| `compute_property_scope_id(id)` | SHA256(id)[0:16] upper — hash determinístico |
| `sync_property_scope()` | Trigger INSERT/UPDATE em rural_properties — popula `property_scope_id` |
| `sync_related_scope()` | Trigger em gateways e collars — herda `property_scope_id` da propriedade |
| `current_legacy_uid()` | Retorna `legacy_uid` do usuário autenticado |
| `current_role()` | Retorna role do usuário autenticado |
| `is_admin()` | Verifica role `adm` ou `admin` |
| `has_property_access(id)` | Verifica ownership ou membership na propriedade |

### RLS Policies

| Tabela | Política |
|---|---|
| profiles | Apenas próprio perfil ou admin |
| user_push_tokens | Apenas próprio `legacy_uid` ou admin |
| rural_properties | `has_property_access(id)` |
| areas / gateways / collars | `has_property_access(property_id)` |
| fences / herding_plans | Via JOIN com collars |
| events / herding_operations | Por property ou owner_uid |
| telemetry / health / property_events / property_commands | Apenas SELECT; requer `has_property_access` |
| matrix_* | Apenas admin (SELECT) |

### Realtime (tabelas publicadas)

`rural_properties`, `areas`, `gateways`, `collars`, `herding_operations`,
`property_telemetry_latest`, `property_telemetry_history`,
`property_health_latest`, `property_health_history`,
`property_events`, `property_commands`, `property_command_events`

## Technologies

- Supabase Postgres (pg 15+)
- Row Level Security (RLS) em todas as 21 tabelas
- Supabase Realtime em 12 tabelas
- Índices GIN em arrays de IDs
- SHA256 para `property_scope_id` determinístico

## Related

[[ruraltech]]
[[regras-negocio]]
[[fluxos-comunicacao-ponta-a-ponta]]
[[requisitos]]
[[visao-geral]]

#arquitetura #ruraltech 