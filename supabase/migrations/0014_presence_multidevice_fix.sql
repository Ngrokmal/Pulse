-- ============================================================================
-- 0014_presence_multidevice_fix.sql
--
-- ROOT CAUSE: lib/core/constants/presence_constants.dart, lib/main.dart,
-- lib/core/services/device_id_service.dart, lib/core/services/
-- presence_activity_pinger.dart and lib/features/profile/data/datasources/
-- profile_remote_data_source.dart already assume a fully-built multi-device
-- presence layer: a `public.device_presence` table, an
-- `is_device_row_live()` helper, an `expire_stale_device_presence()` sweep,
-- and two client-facing RPCs — `presence_set_status(p_device_id, p_status)`
-- and `presence_heartbeat(p_device_id)`. Those objects are referenced by
-- name in Dart comments (crediting `0014_presence_and_unread_fix.sql` /
-- `0015_presence_interval_update.sql`) but do not exist anywhere in this
-- project's SQL (Modules 1-8, 0013) — only the single-row rollup table
-- `public.user_presence` (Module 1) exists. Every `presence_set_status` /
-- `presence_heartbeat` RPC call from the app is therefore currently failing
-- with "Could not find the function" (PostgREST), which is why presence
-- never updates: the periodic heartbeat (main.dart), the activity pinger,
-- and every foreground/background transition all silently error out and
-- get swallowed by `_rethrowMapped`/`unawaited`.
--
-- THIS FILE builds the missing multi-device layer UNDER the existing
-- architecture rather than replacing it:
--   - public.user_presence (Module 1) remains the one-row-per-user rollup
--     the client reads/subscribes to (fetchPresenceRow(s), SharedPresence-
--     Manager's `user_presence` Realtime channel) — UNCHANGED, not touched.
--   - public.device_presence (NEW) is the one-row-per-device-install table
--     RPCs write to, keyed by DeviceIdService's per-install uuid — never
--     read directly by the client.
--   - Every RPC that mutates a device row finishes by recomputing that
--     user's `user_presence.is_online` from ALL of their device rows
--     ("any device online => user online"), so the existing rollup/Realtime
--     path the client already listens on keeps working unmodified.
--   - A pg_cron sweep expires devices whose heartbeat has gone stale
--     (>360s, PresenceConstants.offlineTimeout) so a crash/force-close/
--     killed-by-OS device is detected without that device ever calling in
--     again.
--
-- Depends on: public.users, public.user_presence, public.set_updated_at()
-- (Module 1). Idempotent and safely re-runnable: CREATE TABLE/INDEX IF NOT
-- EXISTS, CREATE OR REPLACE FUNCTION, DROP POLICY/TRIGGER IF EXISTS before
-- CREATE, DO-block guarded CREATE TYPE, guarded pg_cron (re)schedule.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. ENUM TYPE: public.device_presence_status_enum
-- Matches this project's established enum convention (verification_status_
-- enum, privacy_option_enum, friendship_status_enum, etc.) rather than a
-- bare boolean, so the RPCs can validate the client's 'online'/'offline'
-- string the same way every other enum-backed column in this schema does.
-- ----------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type where typname = 'device_presence_status_enum') then
    create type public.device_presence_status_enum as enum ('online', 'offline');
  end if;
end$$;


-- ----------------------------------------------------------------------------
-- 2. TABLE: public.device_presence
--
-- One row per physical install (DeviceIdService's per-install uuid v4),
-- NOT per user — the same device_id can belong to different user_id over
-- the install's lifetime (DeviceIdService is deliberately never cleared on
-- sign-out), so user_id is updated in place by presence_set_status /
-- presence_heartbeat on every call rather than being immutable.
-- ----------------------------------------------------------------------------

create table if not exists public.device_presence (
  device_id       text primary key,
  user_id         uuid not null references public.users(id) on delete cascade,
  status          public.device_presence_status_enum not null default 'offline',
  last_heartbeat  timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.device_presence is
  'One row per physical app install (DeviceIdService, per-install uuid v4). Written only by presence_set_status() / presence_heartbeat() / expire_stale_device_presence() (all SECURITY DEFINER) — never inserted/updated directly by the client. Backs the public.user_presence rollup: recompute_user_presence() derives is_online as "any live device row for this user".';

create index if not exists device_presence_user_id_idx
  on public.device_presence (user_id);

-- Speeds up expire_stale_device_presence()'s sweep: it only ever needs
-- rows currently marked 'online', so a partial index keeps the scan small
-- regardless of how many total device rows accumulate over time.
create index if not exists device_presence_online_heartbeat_idx
  on public.device_presence (last_heartbeat)
  where status = 'online';

drop trigger if exists set_updated_at on public.device_presence;
create trigger set_updated_at
  before update on public.device_presence
  for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY: public.device_presence
-- Read: caller's own device rows only (diagnostic use — the client never
-- queries this table today, only the RPCs below write to it). No INSERT/
-- UPDATE/DELETE policy at all: every mutation goes exclusively through the
-- SECURITY DEFINER RPCs below, which bypass RLS as the function owner —
-- matching this project's existing pattern for user_presence/user_settings
-- rows created only by handle_new_auth_user().
-- ----------------------------------------------------------------------------

alter table public.device_presence enable row level security;

drop policy if exists device_presence_select_own on public.device_presence;
create policy device_presence_select_own
  on public.device_presence
  for select
  to authenticated
  using (user_id = auth.uid());


-- ----------------------------------------------------------------------------
-- 4. HELPER FUNCTION: public.is_device_row_live()
-- Single source of truth for "is this device row currently live" so the
-- 360-second offline-timeout window (PresenceConstants.offlineTimeout) is
-- defined in exactly one place and can never drift between
-- recompute_user_presence() and expire_stale_device_presence().
-- ----------------------------------------------------------------------------

create or replace function public.is_device_row_live(
  p_status public.device_presence_status_enum,
  p_last_heartbeat timestamptz
)
returns boolean
language sql
stable
as $$
  select p_status = 'online' and p_last_heartbeat >= now() - interval '360 seconds';
$$;

comment on function public.is_device_row_live(public.device_presence_status_enum, timestamptz) is
  'True if a device_presence row counts as currently live: status = online AND last_heartbeat within the 360s offline timeout (PresenceConstants.offlineTimeout). Single source of truth for that window — used by both recompute_user_presence() and expire_stale_device_presence().';


-- ----------------------------------------------------------------------------
-- 5. FUNCTION: public.recompute_user_presence(p_user_id uuid)
-- Rolls a user's device_presence rows up into their ONE public.user_presence
-- row: is_online = true iff ANY device row is currently live ("any device
-- online => user online" — multi-device requirement). last_seen is
-- refreshed to now() whenever the rollup lands on offline, so "last seen"
-- always reflects the most recent moment a device was confirmed live.
-- SECURITY DEFINER: writes public.user_presence for a user_id that is not
-- necessarily auth.uid() (e.g. when called from the service-role cron
-- sweep), so it must bypass user_presence_update_own's `user_id = auth.uid()`
-- policy the same way handle_new_auth_user() already bypasses RLS elsewhere.
-- ----------------------------------------------------------------------------

create or replace function public.recompute_user_presence(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_online boolean;
begin
  select exists (
    select 1
    from public.device_presence dp
    where dp.user_id = p_user_id
      and public.is_device_row_live(dp.status, dp.last_heartbeat)
  ) into v_is_online;

  update public.user_presence
  set is_online = v_is_online,
      last_seen = case when v_is_online then last_seen else now() end
  where user_id = p_user_id;
end;
$$;

comment on function public.recompute_user_presence(uuid) is
  'Rolls up public.device_presence into the single public.user_presence row for p_user_id: is_online = true iff at least one device row is currently live (is_device_row_live). Called at the end of presence_set_status(), presence_heartbeat(), and expire_stale_device_presence() — never needs to be called directly by the client.';


-- ----------------------------------------------------------------------------
-- 6. RPC: public.presence_set_status(p_device_id text, p_status text)
-- Backs ProfileRemoteDataSourceImpl.upsertPresence -> rpc('presence_set_
-- status', {p_device_id, p_status}) — explicit foreground/background/sign-
-- out transitions. Pinned to auth.uid() server-side (never trusts a
-- supabaseUid argument from the client), matching the Dart-side doc that
-- "a single client can only ever speak for its OWN device row".
-- ----------------------------------------------------------------------------

create or replace function public.presence_set_status(
  p_device_id text,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_status public.device_presence_status_enum;
begin
  if v_uid is null then
    raise exception 'presence_set_status: no authenticated user';
  end if;

  begin
    v_status := p_status::public.device_presence_status_enum;
  exception when invalid_text_representation then
    raise exception 'presence_set_status: invalid status %', p_status;
  end;

  insert into public.device_presence (device_id, user_id, status, last_heartbeat)
  values (p_device_id, v_uid, v_status, now())
  on conflict (device_id) do update
    set user_id        = excluded.user_id,
        status          = excluded.status,
        last_heartbeat  = excluded.last_heartbeat;

  perform public.recompute_user_presence(v_uid);
end;
$$;

comment on function public.presence_set_status(text, text) is
  'Explicit per-device online/offline transition (app foreground/background, sign-out). Upserts this device''s device_presence row pinned to auth.uid(), then rolls the caller''s user_presence row up via recompute_user_presence(). Backs ProfileRemoteDataSourceImpl.upsertPresence.';

grant execute on function public.presence_set_status(text, text) to authenticated;


-- ----------------------------------------------------------------------------
-- 7. RPC: public.presence_heartbeat(p_device_id text)
-- Backs ProfileRemoteDataSourceImpl.heartbeatPresence -> rpc('presence_
-- heartbeat', {p_device_id}) — the periodic Timer in main.dart (every
-- PresenceConstants.heartbeatInterval = 240s) plus PresenceActivityPinger's
-- activity-triggered refresh. Always marks the device 'online': a device
-- that can still call this RPC is, by definition, alive right now.
-- ----------------------------------------------------------------------------

create or replace function public.presence_heartbeat(
  p_device_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'presence_heartbeat: no authenticated user';
  end if;

  insert into public.device_presence (device_id, user_id, status, last_heartbeat)
  values (p_device_id, v_uid, 'online', now())
  on conflict (device_id) do update
    set user_id        = excluded.user_id,
        status          = 'online',
        last_heartbeat  = excluded.last_heartbeat;

  perform public.recompute_user_presence(v_uid);
end;
$$;

comment on function public.presence_heartbeat(text) is
  'Liveness heartbeat for this device (PresenceConstants.heartbeatInterval = 240s, plus PresenceActivityPinger on-activity refresh). Upserts device_presence.last_heartbeat = now(), status = online, then rolls the caller''s user_presence row up via recompute_user_presence(). A device that stops calling this goes stale and is swept by expire_stale_device_presence() after PresenceConstants.offlineTimeout (360s).';

grant execute on function public.presence_heartbeat(text) to authenticated;


-- ----------------------------------------------------------------------------
-- 8. FUNCTION: public.expire_stale_device_presence()
-- Crash/force-close/battery-optimization-kill safety net: a device that
-- stops heartbeating never calls presence_set_status(false) either, so
-- without this sweep it would stay 'online' forever. Flips every device
-- row whose heartbeat has gone stale (>360s) to 'offline', then rolls up
-- every affected user exactly once each. Intended to run only via the
-- pg_cron job below (or a service-role call) — not granted to
-- authenticated, since a client has no legitimate reason to sweep other
-- users' devices.
-- ----------------------------------------------------------------------------

create or replace function public.expire_stale_device_presence()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_seen uuid[] := array[]::uuid[];
begin
  for v_user_id in
    update public.device_presence
    set status = 'offline'
    where status = 'online'
      and not public.is_device_row_live(status, last_heartbeat)
    returning user_id
  loop
    -- A single sweep can touch several stale devices for the same user;
    -- recompute once per user rather than once per stale device row.
    if not (v_user_id = any(v_seen)) then
      v_seen := array_append(v_seen, v_user_id);
      perform public.recompute_user_presence(v_user_id);
    end if;
  end loop;
end;
$$;

comment on function public.expire_stale_device_presence() is
  'Sweeps device_presence for rows stuck online past the 360s offline timeout (is_device_row_live) and flips them offline, then rolls up every affected user via recompute_user_presence(). Crash/force-close/OS-kill safety net for devices that stop heartbeating without ever calling presence_set_status(false). Scheduled every minute by pg_cron below — not a client-facing RPC.';


-- ----------------------------------------------------------------------------
-- 9. SCHEDULE: pg_cron sweep, every minute
-- 60s cadence comfortably resolves the 360s timeout window without a
-- device ever appearing "stuck online" for more than ~1 extra minute.
-- Guarded unschedule-then-schedule so re-running this file never leaves a
-- duplicate job registered.
-- ----------------------------------------------------------------------------

create extension if not exists pg_cron with schema extensions;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'presence_expire_stale_devices') then
    perform cron.unschedule('presence_expire_stale_devices');
  end if;
end$$;

select cron.schedule(
  'presence_expire_stale_devices',
  '* * * * *',
  $$select public.expire_stale_device_presence();$$
);


-- ----------------------------------------------------------------------------
-- 10. POST-INSTALL VERIFICATION — read-only, run manually
-- ----------------------------------------------------------------------------

-- 10.1 Required objects exist
select expected.kind, expected.name
from (values
  ('table',    'device_presence'),
  ('function', 'is_device_row_live'),
  ('function', 'recompute_user_presence'),
  ('function', 'presence_set_status'),
  ('function', 'presence_heartbeat'),
  ('function', 'expire_stale_device_presence')
) as expected(kind, name)
where (expected.kind = 'table' and not exists (
        select 1 from pg_class c
        join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
        where c.relname = expected.name
      ))
   or (expected.kind = 'function' and not exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
        where p.proname = expected.name
      ));

-- 10.2 RLS enabled on device_presence
select relname
from pg_class c
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
where c.relname = 'device_presence'
  and c.relrowsecurity is not true;

-- 10.3 Cron job registered
select jobname, schedule, active
from cron.job
where jobname = 'presence_expire_stale_devices';

-- ============================================================================
-- END 0014_presence_multidevice_fix.sql
-- ============================================================================
