-- ============================================================================
-- 0018_presence_lastseen_selfheal_fix.sql
--
-- SYMPTOM: last_seen never updates — stays frozen at an old timestamp even
-- after repeated app open/close cycles.
--
-- ROOT CAUSE
-- ----------
-- 0014, section 9, runs (no error handling at all):
--
--     create extension if not exists pg_cron with schema extensions;
--     ...
--     select cron.schedule('presence_expire_stale_devices', '* * * * *', ...);
--
-- On Supabase specifically, installing pg_cron with `schema extensions` is a
-- documented footgun: the extension can report as "active" while its grants
-- on the `cron` schema/`cron.job` table are never actually wired up (Supabase
-- CLI issue #1591), and Supabase's own SQL-editor guidance is to install it
-- with `schema pg_catalog` instead, not `schema extensions` (supabase/
-- supabase issue #27062) — using `extensions` there routinely raises a
-- schema/permission error or leaves `cron.schedule(...)` failing with
-- "permission denied for schema cron" right after.
--
-- Because 0014 has no BEGIN/EXCEPTION guard around this block, a failure
-- here does not fail *just* the cron schedule — a Supabase migration file
-- runs as one transaction, so an uncaught error at section 9 rolls back the
-- ENTIRE file, including sections 4-7 defined earlier in the same
-- transaction: `device_presence`, `recompute_user_presence`,
-- `presence_set_status`, `presence_heartbeat`. That silently takes down
-- every presence RPC the client calls — `_rethrowMapped` in
-- ProfileRemoteDataSourceImpl then swallows every one of those failures, so
-- app-open, app-close, and the periodic heartbeat all silently no-op.
-- `last_seen` is only ever written once, at signup, by
-- `handle_new_auth_user()` (Module 1) — with every subsequent RPC failing,
-- it can never move again. This is exactly the reported symptom.
--
-- (0015's own cron section already learned this lesson — it wraps its
-- `cron.schedule` call in `exception when others then null`. Section 9 of
-- 0014, which runs first, never got the same treatment.)
--
-- FIX — two independent, additive layers, neither touching Flutter, RLS,
-- table shapes, or any existing RPC signature:
--
--   1. Re-run the pg_cron bootstrap defensively: `pg_catalog` schema (the
--      schema Supabase's own guidance actually recommends), wrapped so ANY
--      failure here — extension unavailable, dashboard-only install
--      required, grants broken from a previous bad install, project tier
--      restrictions — is caught and logged, never propagated. This can
--      never again take the rest of a migration down with it.
--
--   2. Presence must not depend on pg_cron working at all. `0015`'s own
--      comment on `presence_heartbeat` already *claims* "Called
--      opportunistically from presence_heartbeat" for the stale-device
--      sweep — that call was never actually added to the function body.
--      This migration adds it for real: `presence_heartbeat()` now also
--      piggybacks a call to `expire_stale_device_presence()`, throttled via
--      a tiny one-row `presence_sweep_state` table so it runs at most once
--      per `presence_offline_timeout_seconds()` (360s) cluster-wide,
--      regardless of how many devices are heartbeating. Every actively used
--      device already calls `presence_heartbeat()` every
--      `presence_heartbeat_interval_seconds()` (240s), so as long as at
--      least one signed-in user's app is open anywhere, stale devices keep
--      getting swept and `last_seen` keeps moving — with zero dependency on
--      pg_cron ever being scheduled correctly.
--
-- Idempotent and safely re-runnable: CREATE TABLE/POLICY/FUNCTION IF NOT
-- EXISTS / OR REPLACE throughout, DO-block guarded cron bootstrap.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Throttle table for the opportunistic (non-cron) sweep.
-- Single row, updated only inside presence_heartbeat() below (SECURITY
-- DEFINER) — no client access needed, so RLS is enabled with no policies at
-- all (same "no INSERT/UPDATE policy, only SECURITY DEFINER functions touch
-- this" pattern already used for device_presence in 0014).
-- ----------------------------------------------------------------------------

create table if not exists public.presence_sweep_state (
  id            smallint primary key default 1,
  last_swept_at timestamptz not null default (now() - interval '1 hour'),
  constraint presence_sweep_state_singleton check (id = 1)
);

comment on table public.presence_sweep_state is
  'Single-row throttle for the opportunistic (non-cron) stale-device sweep piggybacked on presence_heartbeat() — see 0018. Not read or written by the client; SECURITY DEFINER functions only.';

insert into public.presence_sweep_state (id, last_swept_at)
values (1, now() - interval '1 hour')
on conflict (id) do nothing;

alter table public.presence_sweep_state enable row level security;
-- No policies: every access goes through SECURITY DEFINER functions, which
-- bypass RLS as the function owner — matching device_presence's own
-- "no INSERT/UPDATE policy at all" pattern from 0014.


-- ----------------------------------------------------------------------------
-- 2. presence_heartbeat(): unchanged write behavior (device_presence upsert
--    + recompute_user_presence), PLUS the opportunistic sweep piggyback.
--    Signature, grants, and everything ProfileRemoteDataSourceImpl already
--    calls remain byte-for-byte identical from the client's point of view.
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

  -- Opportunistic self-heal (0018): piggyback the stale-device sweep on an
  -- ordinary heartbeat, throttled to at most once per
  -- presence_offline_timeout_seconds() (360s) cluster-wide, so presence
  -- never depends on pg_cron being installed/scheduled correctly. Cheap:
  -- this UPDATE only actually claims the sweep and runs it once every
  -- ~6 minutes no matter how many devices heartbeat in that window.
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
  'Liveness heartbeat for this device (PresenceConstants.heartbeatInterval = 240s, plus PresenceActivityPinger on-activity refresh). Upserts device_presence.last_heartbeat = now(), status = online, then rolls the caller''s user_presence row up via recompute_user_presence(). Also opportunistically runs expire_stale_device_presence() at most once per presence_offline_timeout_seconds() (throttled via presence_sweep_state) so stale devices/last_seen keep self-healing even if pg_cron is never scheduled (see 0018). A device that stops calling this goes stale and is swept here (or by the pg_cron job, if available) after PresenceConstants.offlineTimeout (360s).';

grant execute on function public.presence_heartbeat(text) to authenticated;


-- ----------------------------------------------------------------------------
-- 3. Re-bootstrap pg_cron defensively (schema pg_catalog, per Supabase's own
--    guidance, not `extensions`), fully wrapped so any failure here is
--    caught and never rolls back anything else. This is now purely a
--    "nice-to-have, faster than the 240s heartbeat cadence" optimization —
--    section 2 above is what actually guarantees correctness.
-- ----------------------------------------------------------------------------

do $outer$
begin
  begin
    create extension if not exists pg_cron with schema pg_catalog;
  exception when others then
    raise notice 'presence: pg_cron extension unavailable/not installable from a migration (%). Presence still self-heals via presence_heartbeat''s opportunistic sweep (0018) — this only means the sweep runs on-demand (<= 6 min after presence_heartbeat_interval_seconds() traffic) rather than on a fixed schedule.', sqlerrm;
  end;

  begin
    if exists (select 1 from pg_extension where extname = 'pg_cron') then
      if exists (select 1 from cron.job where jobname = 'presence_expire_stale_devices') then
        perform cron.unschedule('presence_expire_stale_devices');
      end if;

      perform cron.schedule(
        'presence_expire_stale_devices',
        '* * * * *',
        $cron$select public.expire_stale_device_presence();$cron$
      );
    end if;
  exception when others then
    raise notice 'presence: pg_cron is installed but scheduling failed (%). Non-fatal — see presence_heartbeat''s opportunistic sweep (0018).', sqlerrm;
  end;
end;
$outer$;


-- ----------------------------------------------------------------------------
-- POST-INSTALL VERIFICATION — read-only, run manually
-- ----------------------------------------------------------------------------

-- 1. presence_sweep_state has exactly one row
select count(*) as row_count from public.presence_sweep_state;

-- 2. presence_heartbeat still has the exact signature the client calls
select p.proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
where p.proname = 'presence_heartbeat';

-- 3. Is pg_cron actually working right now? (informational only — presence
--    correctness no longer depends on this being true)
select jobname, schedule, active
from cron.job
where jobname = 'presence_expire_stale_devices';

-- 4. Manually force one sweep + confirm any genuinely stale device flips
--    offline and its user's last_seen moves to "now" immediately (run,
--    then check a known-stale test user's user_presence row):
-- select public.expire_stale_device_presence();
-- select user_id, is_online, last_seen, updated_at from public.user_presence where user_id = '<test-uid>';

-- ============================================================================
-- END 0018_presence_lastseen_selfheal_fix.sql
-- ============================================================================
