-- Tabela de notificações pendentes para entrega via Supabase Realtime (foreground)
-- e WorkManager polling (background Android).
-- iOS também recebe via APNs direto, mas é registrado aqui como fallback.

create table public.pending_notifications (
  id uuid primary key default gen_random_uuid(),
  legacy_uid text not null,
  title text,
  body text,
  data jsonb not null default '{}'::jsonb,
  delivered boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.pending_notifications enable row level security;

create policy pending_notifications_owner on public.pending_notifications
  for all using (
    legacy_uid = public.current_legacy_uid()
    or public.is_admin()
  );

-- Habilitar Realtime para entrega em foreground
alter publication supabase_realtime add table public.pending_notifications;

create index idx_pending_notifications_uid_created
  on public.pending_notifications (legacy_uid, created_at desc);

-- TTL: limpeza automática de notificações entregues com mais de 7 dias (pg_cron opcional)
-- Se pg_cron estiver disponível:
-- select cron.schedule('cleanup-pending-notifications', '0 3 * * *',
--   $$delete from public.pending_notifications where delivered = true and created_at < now() - interval '7 days'$$);
