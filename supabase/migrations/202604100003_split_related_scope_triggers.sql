-- Split sync_related_scope into two dedicated functions to avoid polymorphic
-- field access on tables with different schemas (gateways has user_uids, collars does not).

-- 1. Function for gateways (has user_uids column)
create or replace function public.sync_gateway_scope()
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
  if new.user_uids is null then
    new.user_uids = '{}'::text[];
  end if;
  return new;
end;
$$;

-- 2. Function for collars (no user_uids column)
create or replace function public.sync_collar_scope()
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
  return new;
end;
$$;

-- 3. Re-bind triggers to dedicated functions
drop trigger if exists trg_gateways_related_scope on public.gateways;
create trigger trg_gateways_related_scope
before insert or update on public.gateways
for each row execute function public.sync_gateway_scope();

drop trigger if exists trg_collars_related_scope on public.collars;
create trigger trg_collars_related_scope
before insert or update on public.collars
for each row execute function public.sync_collar_scope();
