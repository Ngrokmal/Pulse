-- ============================================================================
-- 0019_presence_canonical_fix.sql
--
-- ROOT CAUSE (confirmed against every file in supabase/migrations/, not
-- guessed):
--
-- Supabase applies migrations in plain lexicographic filename order. The
-- Module files that create the prerequisites for presence —
--   pulse_messenger_module1and 3.sql   (public.users, public.user_presence,
--                                        public.set_updated_at())
-- — have NO numeric/timestamp prefix. ASCII sorts digits before letters, so
-- "0013_..." < "0018_..." < "pulse_messenger_module1and 3.sql". On any
-- environment where migrations run in filename order (a fresh `supabase db
-- push`/`db reset`, which is exactly what this "Database Reconstruction"
-- project is for), the actual execution order is:
--
--   0013, 0014, 0015, 0016, 0017, 0018, module1and3, module4..8
--
-- i.e. the exact REVERSE of the dependency order every one of those files
-- declares in its own header ("Depends on: public.users, ...").
--
-- Cascading failure this causes:
--   1. 0014 section 2: `create table public.device_presence (... user_id
--      uuid not null references public.users(id) ...)` fails outright —
--      public.users does not exist yet. Postgres runs each migration file
--      in one transaction, so ALL of 0014 rolls back: no device_presence
--      table, no is_device_row_live(enum,timestamptz), no presence_*
--      functions of any kind survive.
--   2. 0015 section 3 does `create or replace function
--      expire_stale_device_presence() ... update public.device_presence
--      set status = 'offline' ...`. PL/pgSQL resolves identifiers in its
--      body at CREATE FUNCTION time (plpgsql.check_function_bodies is on by
--      default), so this fails too because public.device_presence still
--      doesn't exist — which rolls back the WHOLE of 0015, including
--      sections 1-2 that had already (successfully, in isolation) defined
--      presence_offline_timeout_seconds() and
--      is_device_row_live(text, timestamptz). That text-typed overload
--      never actually lands in the database.
--   3. 0017 and 0018 fail the same way (both reference public.device_
--      presence in a plpgsql body), for the same reason.
--
-- End state in any environment where this ordering bug fires: NEITHER
-- is_device_row_live overload exists at all — which is exactly the
-- production error:
--   function public.is_device_row_live(text, timestamp with time zone)
--   does not exist
-- PostgREST/Flutter calls presence_heartbeat(p_device_id) -> (would-be)
-- recompute_user_presence() -> is_device_row_live(text, timestamptz), and
-- there is nothing there to call.
--
-- REQUIRED COMPANION FIX (outside SQL, do this too):
--   Rename the module files so they sort before 0013, e.g.:
--     0001_pulse_messenger_module1and3.sql
--     0002_pulse_messenger_module4.sql
--     0003_pulse_messenger_module5.sql
--     0004_pulse_messenger_module6.sql
--     0005_pulse_messenger_module7.sql
--     0006_pulse_messenger_module8.sql
--   (module1and3.sql's own filename has a stray space — "module1and 3.sql"
--   — fix that at the same time.) This is what makes a FUTURE fresh
--   `db reset`/`db push` apply in the right order. It does not, by itself,
--   fix a database that has already been built out of order — that's what
--   the rest of this file does, defensively, for the CURRENT database.
--
-- THIS FILE does not assume 0014-0018 ran, partially ran, or ran at all.
-- It brings the database to the correct end state from any of those
-- starting points in one shot:
--   - Verifies true prerequisites (public.users, public.user_presence,
--     public.set_updated_at()) actually exist and stops with a clear error
--     naming the missing piece if not — the one thing this file legitimately
--     cannot self-heal.
--   - (Re)creates public.device_presence, its indexes, RLS exactly as 0014
--     defined them (no table-shape change).
--   - (Re)creates presence_offline_timeout_seconds() = 360,
--     presence_heartbeat_interval_seconds() = 240 (0015's values, unchanged).
--   - Drops EVERY existing overload of is_device_row_live (enum-typed,
--     text-typed, or anything else left over from a partial run) and
--     creates exactly ONE canonical function:
--       public.is_device_row_live(p_status text, p_last_heartbeat timestamptz)
--   - Updates every caller (recompute_user_presence,
--     expire_stale_device_presence) to call that exact signature via an
--     explicit ::text cast at the call site.
--   - Recreates presence_set_status(text, text) and presence_heartbeat(text)
--     byte-identical in signature/name to what Flutter already calls
--     (rpc('presence_set_status', {p_device_id, p_status}) /
--     rpc('presence_heartbeat', {p_device_id})) — zero Dart changes needed.
--   - Keeps 0018's opportunistic self-heal sweep piggybacked on
--     presence_heartbeat() (throttled via presence_sweep_state), so presence
--     stays correct even if pg_cron is never scheduled.
--   - Re-bootstraps pg_cron defensively, fully wrapped so it can never take
--     the rest of this migration down (the exact failure mode that caused
--     all of this).
--
-- Multi-device architecture, RLS policies, RPC names, the 240s/360s timing
-- values, and the client-facing surface are all UNCHANGED from 0014/0015/
-- 0018's design — this file only fixes how reliably that design actually
-- gets installed.
--
-- Idempotent and safely re-runnable: every CREATE is IF NOT EXISTS / OR
-- REPLACE, every DROP is IF EXISTS, guarded DO blocks throughout.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 0. Hard prerequisite check. If these are missing, no amount of
--    defensiveness in this file can safely proceed — stop with a clear
--    message instead of failing later with a confusing error.
-- ----------------------------------------------------------------------------

do $prereq$
begin
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public' and c.relname = 'users') then
    raise exception 'presence fix aborted: public.users does not exist. Run the Module 1 migration (pulse_messenger_module1and3.sql, renamed to sort before 0013) first.';
  end if;

  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public' and c.relname = 'user_presence') then
    raise exception 'presence fix aborted: public.user_presence does not exist. Run the Module 1 migration first.';
  end if;

  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'set_updated_at') then
    raise exception 'presence fix aborted: public.set_updated_at() does not exist. Run the Module 1 migration first.';
  end if;
end;
$prereq$;


-- ----------------------------------------------------------------------------
-- 1. ENUM TYPE + TABLE: public.device_presence (unchanged shape from 0014)
-- ----------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type where typname = 'device_presence_status_enum') then
    create type public.device_presence_status_enum as enum ('online', 'offline');
  end if;
end$$;

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

create index if not exists device_presence_online_heartbeat_idx
  on public.device_presence (last_heartbeat)
  where status = 'online';

drop trigger if exists set_updated_at on public.device_presence;
create trigger set_updated_at
  before update on public.device_presence
  for each row execute function public.set_updated_at();

alter table public.device_presence enable row level security;

drop policy if exists device_presence_select_own on public.device_presence;
create policy device_presence_select_own
  on public.device_presence
  for select
  to authenticated
  using (user_id = auth.uid());


-- ----------------------------------------------------------------------------
-- 2. Shared timing constants (0015's values, unchanged): 240s heartbeat /
--    360s offline timeout.
-- ----------------------------------------------------------------------------

create or replace function public.presence_heartbeat_interval_seconds()
returns integer
language sql
immutable
as $$
  select 240;
$$;

comment on function public.presence_heartbeat_interval_seconds() is
  'Expected client heartbeat cadence in seconds (lib/core/constants/presence_constants.dart PresenceConstants.heartbeatInterval). Documentation/tuning constant only.';

create or replace function public.presence_offline_timeout_seconds()
returns integer
language sql
immutable
as $$
  select 360;
$$;

comment on function public.presence_offline_timeout_seconds() is
  'Single source of truth for how many seconds a device_presence row can go without a heartbeat before it is treated as offline. Used by is_device_row_live and expire_stale_device_presence so they can never drift apart. Mirrors PresenceConstants.offlineTimeout (360s / 6 min).';


-- ----------------------------------------------------------------------------
-- 3. CANONICAL FUNCTION: public.is_device_row_live(text, timestamptz)
--
-- Drop every overload that may exist from any prior partial run — enum-
-- typed (0014), text-typed (0015), or anything else — then create exactly
-- one. This is what makes the migration safe to run no matter which of
-- 0014/0015/0017 (if any) previously succeeded.
-- ----------------------------------------------------------------------------

do $drop_overloads$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'is_device_row_live'
  loop
    execute format('drop function %s', r.sig);
  end loop;
end;
$drop_overloads$;

create function public.is_device_row_live(p_status text, p_last_heartbeat timestamptz)
returns boolean
language sql
stable
as $$
  select p_status = 'online'
    and p_last_heartbeat > (now() - make_interval(secs => public.presence_offline_timeout_seconds()));
$$;

comment on function public.is_device_row_live(text, timestamptz) is
  'Canonical, single-overload definition. True if a device_presence row counts as currently online: status = online AND last_heartbeat within the last presence_offline_timeout_seconds() (360s / 6 min). Centralizes the staleness window used by recompute_user_presence and expire_stale_device_presence so they can never drift apart. (0019: consolidated from the enum-typed/text-typed overload split introduced by 0014/0015.)';


-- ----------------------------------------------------------------------------
-- 4. FUNCTION: public.recompute_user_presence(uuid)
--    Calls the canonical function with an explicit ::text cast so overload
--    resolution can never again pick anything but the one function from
--    section 3.
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
      and public.is_device_row_live(dp.status::text, dp.last_heartbeat)
  ) into v_is_online;

  update public.user_presence
  set is_online = v_is_online,
      last_seen = case when v_is_online then last_seen else now() end
  where user_id = p_user_id;
end;
$$;

comment on function public.recompute_user_presence(uuid) is
  'Rolls up public.device_presence into the single public.user_presence row for p_user_id: is_online = true iff at least one device row is currently live via the canonical is_device_row_live(text, timestamptz). Called at the end of presence_set_status(), presence_heartbeat(), and expire_stale_device_presence() — never needs to be called directly by the client.';


-- ----------------------------------------------------------------------------
-- 5. RPC: public.presence_set_status(p_device_id text, p_status text)
--    Byte-identical name/signature to what Flutter calls
--    (rpc('presence_set_status', {p_device_id, p_status})).
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
-- 6. Throttle table for the opportunistic (non-cron) sweep (0018, unchanged).
-- ----------------------------------------------------------------------------

create table if not exists public.presence_sweep_state (
  id            smallint primary key default 1,
  last_swept_at timestamptz not null default (now() - interval '1 hour'),
  constraint presence_sweep_state_singleton check (id = 1)
);

comment on table public.presence_sweep_state is
  'Single-row throttle for the opportunistic (non-cron) stale-device sweep piggybacked on presence_heartbeat(). Not read or written by the client; SECURITY DEFINER functions only.';

insert into public.presence_sweep_state (id, last_swept_at)
values (1, now() - interval '1 hour')
on conflict (id) do nothing;

alter table public.presence_sweep_state enable row level security;
-- No policies: every access goes through SECURITY DEFINER functions only.


-- ----------------------------------------------------------------------------
-- 7. RPC: public.presence_heartbeat(p_device_id text)
--    Byte-identical name/signature to what Flutter calls
--    (rpc('presence_heartbeat', {p_device_id})). Includes 0018's
--    opportunistic self-heal sweep so presence never depends on pg_cron
--    being scheduled correctly.
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
  v_should_sweep boolean := false;
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

  update public.presence_sweep_state
  set last_swept_at = now()
  where id = 1
    and last_swept_at <= now() - make_interval(secs => public.presence_offline_timeout_seconds())
  returning true into v_should_sweep;

  if v_should_sweep then
    perform public.expire_stale_device_presence();
  end if;
end;
$$;

comment on function public.presence_heartbeat(text) is
  'Liveness heartbeat for this device (PresenceConstants.heartbeatInterval = 240s, plus PresenceActivityPinger on-activity refresh). Upserts device_presence.last_heartbeat = now(), status = online, then rolls the caller''s user_presence row up via recompute_user_presence(). Also opportunistically runs expire_stale_device_presence() at most once per presence_offline_timeout_seconds() so stale devices/last_seen self-heal even without pg_cron. A device that stops calling this goes stale and is swept here (or by pg_cron, if available) after PresenceConstants.offlineTimeout (360s).';

grant execute on function public.presence_heartbeat(text) to authenticated;


-- ----------------------------------------------------------------------------
-- 8. FUNCTION: public.expire_stale_device_presence()
--    Calls the canonical is_device_row_live(text, timestamptz) directly.
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
      and not public.is_device_row_live(status::text, last_heartbeat)
    returning user_id
  loop
    if not (v_user_id = any(v_seen)) then
      v_seen := array_append(v_seen, v_user_id);
      perform public.recompute_user_presence(v_user_id);
    end if;
  end loop;
end;
$$;

comment on function public.expire_stale_device_presence() is
  'Sweeps device_presence for rows stuck online past the 360s offline timeout (canonical is_device_row_live) and flips them offline, then rolls up every affected user via recompute_user_presence(). Crash/force-close/OS-kill safety net for devices that stop heartbeating without ever calling presence_set_status(false). Run opportunistically from presence_heartbeat() and (when available) by pg_cron below.';


-- ----------------------------------------------------------------------------
-- 9. pg_cron: best-effort only, fully wrapped so a failure here can NEVER
--    again roll back the functions above (the exact bug this file fixes).
--    Presence correctness does not depend on this succeeding.
-- ----------------------------------------------------------------------------

do $outer$
begin
  begin
    create extension if not exists pg_cron with schema pg_catalog;
  exception when others then
    raise notice 'presence: pg_cron extension unavailable (%). Presence still self-heals via presence_heartbeat''s opportunistic sweep.', sqlerrm;
  end;

  begin
    if exists (select 1 from pg_extension where extname = 'pg_cron') then
      if exists (select 1 from cron.job where jobname in ('presence_expire_stale_devices', 'expire-stale-device-presence')) then
        perform cron.unschedule(jobid) from cron.job
        where jobname in ('presence_expire_stale_devices', 'expire-stale-device-presence');
      end if;

      perform cron.schedule(
        'presence_expire_stale_devices',
        '* * * * *',
        $cron$select public.expire_stale_device_presence();$cron$
      );
    end if;
  exception when others then
    raise notice 'presence: pg_cron installed but scheduling failed (%). Non-fatal — opportunistic sweep still covers correctness.', sqlerrm;
  end;
end;
$outer$;


-- ----------------------------------------------------------------------------
-- POST-INSTALL VERIFICATION — read-only, run manually
-- ----------------------------------------------------------------------------

-- 1. Exactly ONE is_device_row_live overload should exist, signature (text, timestamp with time zone)
select p.proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
where p.proname = 'is_device_row_live';

-- 2. All required presence objects exist
select expected.kind, expected.name
from (values
  ('table',    'device_presence'),
  ('table',    'presence_sweep_state'),
  ('function', 'is_device_row_live'),
  ('function', 'recompute_user_presence'),
  ('function', 'presence_set_status'),
  ('function', 'presence_heartbeat'),
  ('function', 'expire_stale_device_presence')
) as expected(kind, name)
where (expected.kind = 'table' and not exists (
        select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
        where c.relname = expected.name))
   or (expected.kind = 'function' and not exists (
        select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
        where p.proname = expected.name));
-- Empty result = all present.

-- ============================================================================
-- END 0019_presence_canonical_fix.sql
-- ============================================================================
