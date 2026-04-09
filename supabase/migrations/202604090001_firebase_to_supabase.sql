create extension if not exists pgcrypto;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create or replace function public.compute_property_scope_id(property_id text)
returns text
language sql
immutable
as $$
  select upper(substr(encode(digest(lower(trim(coalesce(property_id, ''))), 'sha256'), 'hex'), 1, 16));
$$;

create table if not exists public.profiles (
  auth_user_id uuid primary key references auth.users (id) on delete cascade,
  legacy_uid text not null unique,
  email text unique,
  role text not null default 'user',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint profiles_role_check check (role in ('user', 'adm', 'admin'))
);

create table if not exists public.user_push_tokens (
  id uuid primary key default gen_random_uuid(),
  legacy_uid text not null,
  platform text not null,
  token text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (platform, token)
);

create table if not exists public.rural_properties (
  id text primary key default gen_random_uuid()::text,
  name text not null,
  points jsonb not null default '[]'::jsonb,
  owner_uid text not null,
  created_by_uid text not null,
  updated_by_uid text,
  user_uids text[] not null default '{}'::text[],
  property_scope_id text not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.areas (
  id text primary key default gen_random_uuid()::text,
  owner_uid text not null,
  property_id text references public.rural_properties (id) on delete cascade,
  user_uids text[] not null default '{}'::text[],
  perimeter jsonb not null default '[]'::jsonb,
  linked_device_ids text[] not null default '{}'::text[],
  updated_by_uid text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.gateways (
  id text primary key default gen_random_uuid()::text,
  gateway_id text unique,
  owner_uid text,
  name text not null,
  status text not null default 'offline',
  host text,
  property_id text references public.rural_properties (id) on delete set null,
  user_uids text[] not null default '{}'::text[],
  wifi_ota_enabled boolean not null default true,
  position jsonb,
  is_matrix boolean not null default false,
  property_scope_id text,
  binding_ready boolean not null default false,
  supports_scoped_lora boolean not null default false,
  runtime_status jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.collars (
  id text primary key,
  device_id text not null unique,
  owner_uid text,
  name text not null,
  status text not null default 'unknown',
  property_id text references public.rural_properties (id) on delete set null,
  gateway_id text references public.gateways (id) on delete set null,
  position jsonb,
  wifi_ota_enabled boolean not null default true,
  property_scope_id text,
  binding_ready boolean not null default false,
  supports_scoped_lora boolean not null default false,
  runtime_status jsonb not null default '{}'::jsonb,
  telemetry_received_at_ms bigint,
  position_received_at_ms bigint,
  health_received_at_ms bigint,
  health_gps_day_key integer,
  health_flags integer,
  health_uptime_sec integer,
  health_temperature_deci_c integer,
  health_satellites integer,
  health_hdop_centi integer,
  health_i2c_devices integer,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.fences (
  device_id text primary key references public.collars (id) on delete cascade,
  owner_uid text not null,
  points jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.herding_plans (
  device_id text primary key references public.collars (id) on delete cascade,
  owner_uid text not null,
  phases jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.events (
  id text primary key default gen_random_uuid()::text,
  owner_uid text,
  property_id text references public.rural_properties (id) on delete set null,
  device_id text,
  gateway_id text,
  type text,
  event_type text,
  polygon_kind text,
  origin_doc_type text,
  origin_doc_id text,
  received_at_ms bigint,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.herding_operations (
  id text primary key default gen_random_uuid()::text,
  property_id text not null references public.rural_properties (id) on delete cascade,
  owner_uid text not null,
  requested_by_uid text not null,
  requested_by_role text not null default 'user',
  status text not null,
  target_polygon jsonb not null default '[]'::jsonb,
  selected_device_ids text[] not null default '{}'::text[],
  notify_user_ids text[] not null default '{}'::text[],
  device_statuses jsonb not null default '{}'::jsonb,
  matrix_gateway_id text,
  created_area_id text,
  lora_command_id text,
  area_promotion_requested boolean not null default true,
  client_failure_reason text,
  property_scope_id text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.property_telemetry_latest (
  property_id text not null references public.rural_properties (id) on delete cascade,
  device_id text not null,
  lat double precision,
  lon double precision,
  received_at_ms bigint,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (property_id, device_id)
);

create table if not exists public.property_telemetry_history (
  property_id text not null references public.rural_properties (id) on delete cascade,
  device_id text not null,
  history_id text not null,
  day_key text not null,
  lat double precision,
  lon double precision,
  received_at_ms bigint,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (property_id, device_id, history_id)
);

create table if not exists public.property_health_latest (
  property_id text not null references public.rural_properties (id) on delete cascade,
  device_id text not null,
  health_received_at_ms bigint,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (property_id, device_id)
);

create table if not exists public.property_health_history (
  property_id text not null references public.rural_properties (id) on delete cascade,
  device_id text not null,
  history_id text not null,
  day_key text not null,
  health_received_at_ms bigint,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (property_id, device_id, history_id)
);

create table if not exists public.property_events (
  property_id text not null references public.rural_properties (id) on delete cascade,
  day_key text not null,
  event_id text not null,
  device_id text,
  gateway_id text,
  event_type text,
  lat double precision,
  lon double precision,
  position_received_at_ms bigint,
  received_at_ms bigint,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (property_id, day_key, event_id)
);

create table if not exists public.property_commands (
  property_id text not null references public.rural_properties (id) on delete cascade,
  command_id text not null,
  command text,
  status text,
  property_scope_id text,
  matrix_gateway_id text,
  requested_by_uid text,
  requested_by_role text,
  created_at_ms bigint,
  updated_at_ms bigint,
  expires_at_ms bigint,
  polygon_kind text,
  origin_doc_type text,
  origin_doc_id text,
  target_device_ids text[] not null default '{}'::text[],
  target_gateway_ids text[] not null default '{}'::text[],
  device_results jsonb not null default '{}'::jsonb,
  reason text,
  payload jsonb not null default '{}'::jsonb,
  raw jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (property_id, command_id)
);

create table if not exists public.property_command_events (
  property_id text not null references public.rural_properties (id) on delete cascade,
  day_key text not null,
  event_id text not null,
  command_id text,
  device_id text,
  status text,
  received_at_ms bigint,
  payload jsonb not null default '{}'::jsonb,
  raw jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (property_id, day_key, event_id)
);

create table if not exists public.matrix_bindings (
  runtime_id text primary key,
  property_id text,
  property_scope_id text,
  matrix_gateway_id text,
  enabled boolean not null default false,
  updated_at_ms bigint,
  raw jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.matrix_queue_keys (
  runtime_id text primary key,
  queue_key text,
  writer_key text,
  updated_at_ms bigint,
  raw jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.matrix_command_queues (
  runtime_id text not null,
  queue_key text not null,
  command_id text not null,
  created_at_ms bigint,
  expires_at_ms bigint,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (runtime_id, queue_key, command_id)
);

create table if not exists public.matrix_command_results (
  runtime_id text not null,
  command_id text not null,
  updated_at_ms bigint,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (runtime_id, command_id)
);

create index if not exists idx_profiles_legacy_uid on public.profiles (legacy_uid);
create index if not exists idx_profiles_email on public.profiles (email);
create index if not exists idx_push_tokens_legacy_uid on public.user_push_tokens (legacy_uid);
create index if not exists idx_rural_properties_user_uids on public.rural_properties using gin (user_uids);
create index if not exists idx_areas_property_id on public.areas (property_id);
create index if not exists idx_areas_user_uids on public.areas using gin (user_uids);
create index if not exists idx_gateways_property_id on public.gateways (property_id);
create index if not exists idx_gateways_user_uids on public.gateways using gin (user_uids);
create index if not exists idx_collars_property_id on public.collars (property_id);
create index if not exists idx_collars_gateway_id on public.collars (gateway_id);
create index if not exists idx_events_property_id_created_at on public.events (property_id, created_at desc);
create index if not exists idx_events_owner_uid_created_at on public.events (owner_uid, created_at desc);
create index if not exists idx_herding_operations_property_id on public.herding_operations (property_id, updated_at desc);
create index if not exists idx_herding_operations_notify_user_ids on public.herding_operations using gin (notify_user_ids);
create index if not exists idx_pt_history_property_device_day on public.property_telemetry_history (property_id, device_id, day_key);
create index if not exists idx_ph_history_property_device_day on public.property_health_history (property_id, device_id, day_key);
create index if not exists idx_property_events_property_day on public.property_events (property_id, day_key, received_at_ms desc);
create index if not exists idx_property_commands_property_updated on public.property_commands (property_id, updated_at_ms desc);
create index if not exists idx_property_command_events_property_day on public.property_command_events (property_id, day_key, received_at_ms desc);
create index if not exists idx_matrix_bindings_property on public.matrix_bindings (property_id);
create index if not exists idx_matrix_queues_runtime_queue on public.matrix_command_queues (runtime_id, queue_key, created_at_ms asc);

create or replace function public.sync_property_scope()
returns trigger
language plpgsql
as $$
begin
  if new.id is not null and coalesce(new.property_scope_id, '') = '' then
    new.property_scope_id = public.compute_property_scope_id(new.id);
  end if;
  if new.user_uids is null then
    new.user_uids = '{}'::text[];
  end if;
  return new;
end;
$$;

create or replace function public.sync_related_scope()
returns trigger
language plpgsql
as $$
begin
  if new.property_id is not null then
    select property_scope_id into new.property_scope_id
    from public.rural_properties
    where id = new.property_id;
  else
    new.property_scope_id = null;
  end if;
  if pg_typeof(new) = 'public.gateways'::regtype and new.user_uids is null then
    new.user_uids = '{}'::text[];
  end if;
  return new;
end;
$$;

drop trigger if exists trg_profiles_touch_updated_at on public.profiles;
create trigger trg_profiles_touch_updated_at
before update on public.profiles
for each row execute function public.touch_updated_at();

drop trigger if exists trg_push_tokens_touch_updated_at on public.user_push_tokens;
create trigger trg_push_tokens_touch_updated_at
before update on public.user_push_tokens
for each row execute function public.touch_updated_at();

drop trigger if exists trg_rural_properties_scope on public.rural_properties;
create trigger trg_rural_properties_scope
before insert or update on public.rural_properties
for each row execute function public.sync_property_scope();

drop trigger if exists trg_rural_properties_touch_updated_at on public.rural_properties;
create trigger trg_rural_properties_touch_updated_at
before update on public.rural_properties
for each row execute function public.touch_updated_at();

drop trigger if exists trg_areas_touch_updated_at on public.areas;
create trigger trg_areas_touch_updated_at
before update on public.areas
for each row execute function public.touch_updated_at();

drop trigger if exists trg_gateways_related_scope on public.gateways;
create trigger trg_gateways_related_scope
before insert or update on public.gateways
for each row execute function public.sync_related_scope();

drop trigger if exists trg_gateways_touch_updated_at on public.gateways;
create trigger trg_gateways_touch_updated_at
before update on public.gateways
for each row execute function public.touch_updated_at();

drop trigger if exists trg_collars_related_scope on public.collars;
create trigger trg_collars_related_scope
before insert or update on public.collars
for each row execute function public.sync_related_scope();

drop trigger if exists trg_collars_touch_updated_at on public.collars;
create trigger trg_collars_touch_updated_at
before update on public.collars
for each row execute function public.touch_updated_at();

drop trigger if exists trg_events_touch_updated_at on public.events;
create trigger trg_events_touch_updated_at
before update on public.events
for each row execute function public.touch_updated_at();

drop trigger if exists trg_herding_operations_touch_updated_at on public.herding_operations;
create trigger trg_herding_operations_touch_updated_at
before update on public.herding_operations
for each row execute function public.touch_updated_at();

drop trigger if exists trg_property_commands_touch_updated_at on public.property_commands;
create trigger trg_property_commands_touch_updated_at
before update on public.property_commands
for each row execute function public.touch_updated_at();

drop trigger if exists trg_matrix_bindings_touch_updated_at on public.matrix_bindings;
create trigger trg_matrix_bindings_touch_updated_at
before update on public.matrix_bindings
for each row execute function public.touch_updated_at();

drop trigger if exists trg_matrix_queue_keys_touch_updated_at on public.matrix_queue_keys;
create trigger trg_matrix_queue_keys_touch_updated_at
before update on public.matrix_queue_keys
for each row execute function public.touch_updated_at();

drop trigger if exists trg_matrix_command_queues_touch_updated_at on public.matrix_command_queues;
create trigger trg_matrix_command_queues_touch_updated_at
before update on public.matrix_command_queues
for each row execute function public.touch_updated_at();

drop trigger if exists trg_matrix_command_results_touch_updated_at on public.matrix_command_results;
create trigger trg_matrix_command_results_touch_updated_at
before update on public.matrix_command_results
for each row execute function public.touch_updated_at();

create or replace function public.current_legacy_uid()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.legacy_uid
  from public.profiles p
  where p.auth_user_id = auth.uid();
$$;

create or replace function public.current_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select p.role
      from public.profiles p
      where p.auth_user_id = auth.uid()
    ),
    'user'
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_role() in ('adm', 'admin');
$$;

create or replace function public.has_property_access(property_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.is_admin(), false)
    or exists (
      select 1
      from public.rural_properties rp
      where rp.id = property_id
        and (
          rp.owner_uid = public.current_legacy_uid()
          or rp.created_by_uid = public.current_legacy_uid()
          or public.current_legacy_uid() = any (rp.user_uids)
        )
    );
$$;

alter table public.profiles enable row level security;
alter table public.user_push_tokens enable row level security;
alter table public.rural_properties enable row level security;
alter table public.areas enable row level security;
alter table public.gateways enable row level security;
alter table public.collars enable row level security;
alter table public.fences enable row level security;
alter table public.herding_plans enable row level security;
alter table public.events enable row level security;
alter table public.herding_operations enable row level security;
alter table public.property_telemetry_latest enable row level security;
alter table public.property_telemetry_history enable row level security;
alter table public.property_health_latest enable row level security;
alter table public.property_health_history enable row level security;
alter table public.property_events enable row level security;
alter table public.property_commands enable row level security;
alter table public.property_command_events enable row level security;
alter table public.matrix_bindings enable row level security;
alter table public.matrix_queue_keys enable row level security;
alter table public.matrix_command_queues enable row level security;
alter table public.matrix_command_results enable row level security;

drop policy if exists profiles_select_self on public.profiles;
create policy profiles_select_self on public.profiles
for select
to authenticated
using (auth.uid() = auth_user_id or public.is_admin());

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
for insert
to authenticated
with check (auth.uid() = auth_user_id or public.is_admin());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
for update
to authenticated
using (auth.uid() = auth_user_id or public.is_admin())
with check (auth.uid() = auth_user_id or public.is_admin());

drop policy if exists push_tokens_owner on public.user_push_tokens;
create policy push_tokens_owner on public.user_push_tokens
for all
to authenticated
using (legacy_uid = public.current_legacy_uid() or public.is_admin())
with check (legacy_uid = public.current_legacy_uid() or public.is_admin());

drop policy if exists rural_properties_read on public.rural_properties;
create policy rural_properties_read on public.rural_properties
for select
to authenticated
using (public.has_property_access(id));

drop policy if exists rural_properties_write on public.rural_properties;
create policy rural_properties_write on public.rural_properties
for all
to authenticated
using (public.has_property_access(id) or public.is_admin())
with check (public.has_property_access(id) or public.is_admin());

drop policy if exists areas_access on public.areas;
create policy areas_access on public.areas
for all
to authenticated
using (property_id is not null and public.has_property_access(property_id))
with check (property_id is not null and public.has_property_access(property_id));

drop policy if exists gateways_access on public.gateways;
create policy gateways_access on public.gateways
for all
to authenticated
using ((property_id is not null and public.has_property_access(property_id)) or public.is_admin())
with check ((property_id is not null and public.has_property_access(property_id)) or public.is_admin());

drop policy if exists collars_access on public.collars;
create policy collars_access on public.collars
for all
to authenticated
using ((property_id is not null and public.has_property_access(property_id)) or owner_uid = public.current_legacy_uid() or public.is_admin())
with check ((property_id is not null and public.has_property_access(property_id)) or owner_uid = public.current_legacy_uid() or public.is_admin());

drop policy if exists fences_access on public.fences;
create policy fences_access on public.fences
for all
to authenticated
using (exists (select 1 from public.collars c where c.id = fences.device_id and ((c.property_id is not null and public.has_property_access(c.property_id)) or c.owner_uid = public.current_legacy_uid() or public.is_admin())))
with check (exists (select 1 from public.collars c where c.id = fences.device_id and ((c.property_id is not null and public.has_property_access(c.property_id)) or c.owner_uid = public.current_legacy_uid() or public.is_admin())));

drop policy if exists herding_plans_access on public.herding_plans;
create policy herding_plans_access on public.herding_plans
for all
to authenticated
using (exists (select 1 from public.collars c where c.id = herding_plans.device_id and ((c.property_id is not null and public.has_property_access(c.property_id)) or c.owner_uid = public.current_legacy_uid() or public.is_admin())))
with check (exists (select 1 from public.collars c where c.id = herding_plans.device_id and ((c.property_id is not null and public.has_property_access(c.property_id)) or c.owner_uid = public.current_legacy_uid() or public.is_admin())));

drop policy if exists events_access on public.events;
create policy events_access on public.events
for all
to authenticated
using ((property_id is not null and public.has_property_access(property_id)) or owner_uid = public.current_legacy_uid() or public.is_admin())
with check ((property_id is not null and public.has_property_access(property_id)) or owner_uid = public.current_legacy_uid() or public.is_admin());

drop policy if exists herding_operations_access on public.herding_operations;
create policy herding_operations_access on public.herding_operations
for all
to authenticated
using (public.has_property_access(property_id) or public.current_legacy_uid() = any (notify_user_ids) or public.is_admin())
with check (public.has_property_access(property_id) or public.current_legacy_uid() = any (notify_user_ids) or public.is_admin());

drop policy if exists property_telemetry_latest_access on public.property_telemetry_latest;
create policy property_telemetry_latest_access on public.property_telemetry_latest
for select
to authenticated
using (public.has_property_access(property_id));

drop policy if exists property_telemetry_history_access on public.property_telemetry_history;
create policy property_telemetry_history_access on public.property_telemetry_history
for select
to authenticated
using (public.has_property_access(property_id));

drop policy if exists property_health_latest_access on public.property_health_latest;
create policy property_health_latest_access on public.property_health_latest
for select
to authenticated
using (public.has_property_access(property_id));

drop policy if exists property_health_history_access on public.property_health_history;
create policy property_health_history_access on public.property_health_history
for select
to authenticated
using (public.has_property_access(property_id));

drop policy if exists property_events_access on public.property_events;
create policy property_events_access on public.property_events
for select
to authenticated
using (public.has_property_access(property_id));

drop policy if exists property_commands_access on public.property_commands;
create policy property_commands_access on public.property_commands
for select
to authenticated
using (public.has_property_access(property_id));

drop policy if exists property_command_events_access on public.property_command_events;
create policy property_command_events_access on public.property_command_events
for select
to authenticated
using (public.has_property_access(property_id));

drop policy if exists matrix_bindings_admin_only on public.matrix_bindings;
create policy matrix_bindings_admin_only on public.matrix_bindings
for select
to authenticated
using (public.is_admin());

drop policy if exists matrix_queue_keys_admin_only on public.matrix_queue_keys;
create policy matrix_queue_keys_admin_only on public.matrix_queue_keys
for select
to authenticated
using (public.is_admin());

drop policy if exists matrix_command_queues_admin_only on public.matrix_command_queues;
create policy matrix_command_queues_admin_only on public.matrix_command_queues
for select
to authenticated
using (public.is_admin());

drop policy if exists matrix_command_results_admin_only on public.matrix_command_results;
create policy matrix_command_results_admin_only on public.matrix_command_results
for select
to authenticated
using (public.is_admin());

alter publication supabase_realtime add table public.rural_properties;
alter publication supabase_realtime add table public.areas;
alter publication supabase_realtime add table public.gateways;
alter publication supabase_realtime add table public.collars;
alter publication supabase_realtime add table public.herding_operations;
alter publication supabase_realtime add table public.property_telemetry_latest;
alter publication supabase_realtime add table public.property_telemetry_history;
alter publication supabase_realtime add table public.property_health_latest;
alter publication supabase_realtime add table public.property_health_history;
alter publication supabase_realtime add table public.property_events;
alter publication supabase_realtime add table public.property_commands;
alter publication supabase_realtime add table public.property_command_events;
