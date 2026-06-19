-- Migração: campos de auditoria de polígono em collars e configuração de webhooks
-- para auto-sync de property-fence e area-fence.
--
-- Fase 1: adicionar active_area_id e campos de auditoria de polígono em collars
-- Fase 2: adicionar campo source em areas (para bypass de herding_operation)
-- Fase 3: criar notificações de banco para disparar edge functions via pg_notify
--         (os webhooks reais são configurados no Supabase Dashboard ou via CLI)

-- ---------------------------------------------------------------------------
-- Fase 1: campos em collars
-- ---------------------------------------------------------------------------

alter table public.collars
  add column if not exists active_area_id text,
  add column if not exists last_polygon_command_id text,
  add column if not exists last_polygon_origin_doc_type text,
  add column if not exists last_polygon_origin_doc_id text;

comment on column public.collars.active_area_id
  is 'Espelho operacional: ID da área/piquete atualmente vinculada a esta coleira. Atualizado pelo auto-sync-area-fence.';

comment on column public.collars.last_polygon_command_id
  is 'ID do último comando SET_FENCE aplicado a esta coleira.';

comment on column public.collars.last_polygon_origin_doc_type
  is 'Tipo do documento de origem do último SET_FENCE (ruralProperty, area, manualFence).';

comment on column public.collars.last_polygon_origin_doc_id
  is 'ID do documento de origem do último SET_FENCE.';

-- ---------------------------------------------------------------------------
-- Fase 2: campo source em areas (para bypass herding_operation)
-- ---------------------------------------------------------------------------

alter table public.areas
  add column if not exists source text;

comment on column public.areas.source
  is 'Origem da última atualização. Se "herding_operation", o auto-sync-area-fence não propaga para evitar conflito com condução ativa.';

-- ---------------------------------------------------------------------------
-- Fase 3: função de notificação para auto-sync de rural_properties
-- ---------------------------------------------------------------------------

create or replace function public.notify_property_points_changed()
returns trigger
language plpgsql
as $$
begin
  -- Só dispara se os pontos realmente mudaram (comparação JSON canônica)
  if (TG_OP = 'INSERT') or (new.points::text is distinct from old.points::text) then
    perform pg_notify(
      'property_points_changed',
      json_build_object(
        'type', TG_OP,
        'table', 'rural_properties',
        'record', row_to_json(new),
        'old_record', case when TG_OP = 'UPDATE' then row_to_json(old) else null end
      )::text
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_property_points_notify on public.rural_properties;
create trigger trg_property_points_notify
after insert or update of points on public.rural_properties
for each row execute function public.notify_property_points_changed();

-- ---------------------------------------------------------------------------
-- Fase 4: função de notificação para auto-sync de areas
-- ---------------------------------------------------------------------------

create or replace function public.notify_area_fence_changed()
returns trigger
language plpgsql
as $$
begin
  -- Dispara se perimeter ou linked_device_ids mudou
  if (TG_OP = 'INSERT') or
     (new.perimeter::text is distinct from old.perimeter::text) or
     (new.linked_device_ids::text is distinct from old.linked_device_ids::text) then
    perform pg_notify(
      'area_fence_changed',
      json_build_object(
        'type', TG_OP,
        'table', 'areas',
        'record', row_to_json(new),
        'old_record', case when TG_OP = 'UPDATE' then row_to_json(old) else null end
      )::text
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_area_fence_notify on public.areas;
create trigger trg_area_fence_notify
after insert or update of perimeter, linked_device_ids on public.areas
for each row execute function public.notify_area_fence_changed();

-- ---------------------------------------------------------------------------
-- Fase 5: índices para consultas de auditoria por origem
-- ---------------------------------------------------------------------------

-- Último comando por origem (property)
create index if not exists idx_property_commands_origin
  on public.property_commands (property_id, origin_doc_type, origin_doc_id, created_at_ms desc)
  where origin_doc_type is not null;

-- Último comando por coleira (via device_results)
-- Nota: device_results é JSONB; índice GIN para consultas de chave
create index if not exists idx_property_commands_device_results
  on public.property_commands using gin (device_results);

-- active_area_id para lookups rápidos de coleiras por área
create index if not exists idx_collars_active_area_id
  on public.collars (active_area_id)
  where active_area_id is not null;

-- Eventos por device_id para rastreabilidade
create index if not exists idx_property_events_device_id
  on public.property_events (device_id, received_at_ms desc)
  where device_id is not null;
