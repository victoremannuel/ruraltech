begin;

select plan(11);

create extension if not exists pgtap with schema extensions;

do $$
declare
  owner_auth uuid := '11111111-1111-1111-1111-111111111111';
  linked_auth uuid := '22222222-2222-2222-2222-222222222222';
  other_auth uuid := '33333333-3333-3333-3333-333333333333';
  admin_auth uuid := '44444444-4444-4444-4444-444444444444';
begin
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_sso_user,
    is_anonymous
  )
  values
    (
      '00000000-0000-0000-0000-000000000000',
      owner_auth,
      'authenticated',
      'authenticated',
      'owner@example.com',
      'not-used',
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(),
      now(),
      false,
      false
    ),
    (
      '00000000-0000-0000-0000-000000000000',
      linked_auth,
      'authenticated',
      'authenticated',
      'linked@example.com',
      'not-used',
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(),
      now(),
      false,
      false
    ),
    (
      '00000000-0000-0000-0000-000000000000',
      other_auth,
      'authenticated',
      'authenticated',
      'other@example.com',
      'not-used',
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(),
      now(),
      false,
      false
    ),
    (
      '00000000-0000-0000-0000-000000000000',
      admin_auth,
      'authenticated',
      'authenticated',
      'admin@example.com',
      'not-used',
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(),
      now(),
      false,
      false
    )
  on conflict (id) do nothing;

  insert into public.profiles (auth_user_id, legacy_uid, email, role)
  values
    (owner_auth, 'owner-legacy', 'owner@example.com', 'user'),
    (linked_auth, 'linked-legacy', 'linked@example.com', 'user'),
    (other_auth, 'other-legacy', 'other@example.com', 'user'),
    (admin_auth, 'admin-legacy', 'admin@example.com', 'adm')
  on conflict (auth_user_id) do update
  set legacy_uid = excluded.legacy_uid,
      email = excluded.email,
      role = excluded.role;

  insert into public.rural_properties (
    id,
    name,
    owner_uid,
    created_by_uid,
    user_uids,
    property_scope_id
  )
  values (
    'prop-owner',
    'Propriedade Owner',
    'owner-legacy',
    'owner-legacy',
    array['linked-legacy']::text[],
    public.compute_property_scope_id('prop-owner')
  )
  on conflict (id) do update
  set owner_uid = excluded.owner_uid,
      created_by_uid = excluded.created_by_uid,
      user_uids = excluded.user_uids,
      property_scope_id = excluded.property_scope_id;

  insert into public.areas (
    id,
    owner_uid,
    property_id,
    updated_by_uid
  )
  values (
    'area-owner',
    'owner-legacy',
    'prop-owner',
    'owner-legacy'
  )
  on conflict (id) do update
  set owner_uid = excluded.owner_uid,
      property_id = excluded.property_id,
      updated_by_uid = excluded.updated_by_uid;

  insert into public.property_telemetry_latest (
    property_id,
    device_id,
    lat,
    lon,
    received_at_ms,
    payload
  )
  values (
    'prop-owner',
    '101',
    -16.6,
    -49.2,
    1712600000000,
    '{"deviceId":"101"}'::jsonb
  )
  on conflict (property_id, device_id) do update
  set lat = excluded.lat,
      lon = excluded.lon,
      received_at_ms = excluded.received_at_ms,
      payload = excluded.payload;

  insert into public.matrix_queue_keys (
    runtime_id,
    queue_key,
    writer_key,
    updated_at_ms,
    raw
  )
  values (
    'matrix-owner',
    'queue-secret',
    'writer-secret',
    1712600000000,
    '{"matrixRuntimeId":"matrix-owner"}'::jsonb
  )
  on conflict (runtime_id) do update
  set queue_key = excluded.queue_key,
      writer_key = excluded.writer_key,
      updated_at_ms = excluded.updated_at_ms,
      raw = excluded.raw;
end
$$;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);

select is(public.current_legacy_uid(), 'owner-legacy', 'owner resolves legacy uid');
select is(public.current_role(), 'user', 'owner resolves role');
select is((select count(*) from public.rural_properties), 1::bigint, 'owner can read own property');
select is((select count(*) from public.areas), 1::bigint, 'owner can read area under accessible property');
select is((select count(*) from public.property_telemetry_latest), 1::bigint, 'owner can read latest telemetry');
select is((select count(*) from public.matrix_queue_keys), 0::bigint, 'owner cannot read matrix queue keys');

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
select is((select count(*) from public.rural_properties), 1::bigint, 'linked user can read linked property');

select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
select is((select count(*) from public.rural_properties), 0::bigint, 'unrelated user cannot read property');
select is((select count(*) from public.property_telemetry_latest), 0::bigint, 'unrelated user cannot read telemetry');

select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
select is(public.is_admin(), true, 'admin role is recognized');
select is((select count(*) from public.matrix_queue_keys), 1::bigint, 'admin can read matrix queue keys');

select * from finish();
rollback;
