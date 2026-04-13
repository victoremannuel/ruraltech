-- Fix sync_related_scope trigger: use TG_TABLE_NAME instead of pg_typeof(new)
-- for polymorphic trigger that runs on both gateways and collars.
-- In PL/pgSQL, pg_typeof(NEW) returns the composite type OID but field access
-- like new.user_uids still fails at runtime on tables that don't have that column.

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
  if TG_TABLE_NAME = 'gateways' and new.user_uids is null then
    new.user_uids = '{}'::text[];
  end if;
  return new;
end;
$$;
