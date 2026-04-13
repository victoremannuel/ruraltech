# Task: Auditoria e Fechamento do Fluxo App → Coleira v2.4.0

#ruraltech
#tarefas

## Context

Fechar, padronizar e auditar o fluxo de propagação de comandos de polígonos e condução no RuralTech, garantindo que toda alteração relevante iniciada no app chegue de forma confiável à coleira, seja aplicada localmente, persista em armazenamento local e gere trilha de auditoria ponta a ponta.

Plano completo baseado em: `ruraltech_plano_implementacao_auditoria_fluxo_app_coleira.md`

## Action

### Frente 1 — Padronização do contrato de propagação de polígonos
- [x] Verificar que `queue-lora-command` já enriquece payloads com `polygon_kind`, `origin_doc_type`, `origin_doc_id`
- [x] Confirmar contrato em `_shared/supabase.ts`
- [ ] Garantir que geofence direta também envia `businessRef` completo (Fase 5)

### Frente 2 — Auto-sync de polígono da fazenda
- [x] Criar `supabase/functions/auto-sync-property-fence/index.ts`
  - canonicalização e hash SHA-256 de polígono
  - hash determinístico de target set
  - `commandId` determinístico: `AUTO_PROPERTY_FENCE:{propertyId}:{polygonHash}:{targetSetHash}`
  - resolução de matriz e coleiras aptas
  - verificação de idempotência
  - persistência em `property_commands`, `property_command_events`, `matrix_command_queues`
  - bypass se polígono não mudou
  - auditoria de falhas sem derrubar a gravação do documento
- [ ] Criar trigger/webhook de banco para disparar a function quando `rural_properties.points` muda (Fase 3)

### Frente 3 — Auto-sync de piquete/área e vínculo operacional
- [x] Criar `supabase/functions/auto-sync-area-fence/index.ts`
  - canonicalização e hash de perímetro
  - detecção de mudança em `perimeter` e em `linked_device_ids`
  - bypass para `source = herding_operation`
  - atualização do espelho `active_area_id` em cada coleira vinculada
  - limpeza de `active_area_id` em coleiras removidas do vínculo
  - validação de coleiras contra a propriedade
  - `commandId` determinístico: `AUTO_AREA_FENCE:{areaId}:{perimeterHash}:{targetSetHash}`
  - persistência em `property_commands`, `property_command_events`, `matrix_command_queues`
- [ ] Criar migração SQL com campo `active_area_id` em `collars` (Fase 3)
- [ ] Criar trigger/webhook de banco para disparar a function quando `areas.perimeter` ou `linked_device_ids` muda

### Frente 4 — App: UX, acompanhamento e rastreabilidade
- [ ] Expandir `CloudService` com `streamLatestCommandForOrigin` e `getLatestCommandForOrigin`
- [ ] Padronizar estados visíveis: salvo → sincronizando → enfileirado → distribuindo → parcialmente aplicado → aplicado / falhou / expirado
- [ ] Adaptar telas de propriedade e área para mostrar sincronização automática

### Frente 5 — GeofenceScreen: metadados de origem
- [ ] Atualizar `GeofenceScreen` para enviar `businessRef`, `polygon_kind`, `origin_doc_type`, `origin_doc_id`
- [ ] Mostrar status real do comando após enfileeirar

### Frente 6 — Migração SQL
- [ ] Migração: `active_area_id` em `collars`
- [ ] Migração: campos de auditoria `last_polygon_command_id`, `last_polygon_origin_doc_type`, `last_polygon_origin_doc_id` em `collars` (opcional)
- [ ] Webhook/trigger: `rural_properties` → `auto-sync-property-fence`
- [ ] Webhook/trigger: `areas` → `auto-sync-area-fence`

### Frente 7 — Testes
- [ ] Testes unitários para `auto-sync-property-fence`
- [ ] Testes unitários para `auto-sync-area-fence`
- [ ] Teste E2E-01: editar fazenda → confirmar propagação até coleira
- [ ] Teste E2E-02: editar área → confirmar propagação seletiva
- [ ] Teste E2E-03: arrebanhamento continua funcionando
- [ ] Teste E2E-04: falha por escopo incorreto
- [ ] Teste E2E-05: falha de persistência local na coleira

## Status

✅ **Implementação concluída** — 2026-04-11

### Concluído

- [x] `auto-sync-property-fence` criado (`supabase/functions/auto-sync-property-fence/index.ts`)
  - canonicalização e hash SHA-256 de polígono
  - `commandId` determinístico: `AUTO_PROPERTY_FENCE:{propertyId}:{polygonHash}:{targetSetHash}`
  - idempotência (verifica `property_commands` antes de inserir)
  - resolução de matriz e coleiras aptas
  - auditoria de falhas em `property_command_events`
- [x] `auto-sync-area-fence` criado (`supabase/functions/auto-sync-area-fence/index.ts`)
  - bypass para `source = herding_operation`
  - espelho `active_area_id` em `collars` (atualização e limpeza)
  - `commandId` determinístico: `AUTO_AREA_FENCE:{areaId}:{perimeterHash}:{targetSetHash}`
  - validação de coleiras contra a propriedade
  - limpeza de `active_area_id` em coleiras removidas do vínculo
- [x] Migração SQL `202604110002_auto_sync_collar_fields.sql`
  - `active_area_id` em `collars`
  - `last_polygon_command_id`, `last_polygon_origin_doc_type`, `last_polygon_origin_doc_id` em `collars`
  - campo `source` em `areas` para bypass de herding
  - trigger `trg_property_points_notify` → `pg_notify('property_points_changed')`
  - trigger `trg_area_fence_notify` → `pg_notify('area_fence_changed')`
  - índices: `idx_property_commands_origin`, `idx_property_commands_device_results`, `idx_collars_active_area_id`, `idx_property_events_device_id`
- [x] `CloudService` expandido com:
  - `getLatestCommandForOrigin(propertyId, originDocType, originDocId)`
  - `streamLatestCommandForOrigin(propertyId, originDocType, originDocId)`
  - `commandStatusLabel(status)` — converte status em mensagem amigável
- [x] `GeofenceScreen` atualizada:
  - envia `polygon_kind: "manualFence"`, `origin_doc_type: "manualFence"`, `origin_doc_id`, `businessRef`
  - rastreia `_lastCommandId` após enfileeirar
  - exibe `StreamBuilder` com status em tempo real do comando
  - indicador de progresso e cor por estado (enfileirado / aplicado / falhou)

### Pendente (próximas iterações)

- [ ] Configurar webhooks no Supabase Dashboard para chamar as edge functions via `pg_notify`
- [ ] Testes automatizados unitários e de integração
- [ ] Validação E2E manual (E2E-01 a E2E-05)
- [ ] Adaptar telas de propriedade e área para mostrar "Sincronizando..." após salvar
- [ ] Documentação técnica final

## Next step

1. No Supabase Dashboard → Database → Webhooks: criar webhook para `rural_properties` → `auto-sync-property-fence` e para `areas` → `auto-sync-area-fence`
2. Executar testes E2E manuais
3. Adaptar `rural_property_editor_screen.dart` e `area_editor_screen.dart` para usar `streamLatestCommandForOrigin`

## Related

[[arquitetura/requisitos]]
[[decisoes/migracao-supabase]]
[[projetos/ruraltech]]
