-- Corrige política RLS de pending_notifications:
-- Remove política "for all" que permitia usuários autenticados fazerem INSERT.
-- INSERT/UPDATE/DELETE restrito a service_role; usuário autenticado só faz SELECT dos próprios.

drop policy if exists pending_notifications_owner on public.pending_notifications;

create policy pending_notifications_select on public.pending_notifications
  for select
  to authenticated
  using (
    legacy_uid = public.current_legacy_uid()
    or public.is_admin()
  );
