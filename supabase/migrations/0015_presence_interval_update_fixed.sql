-- ============================================================================
-- MIGRATION 0015: Presence bandwidth reduction — 240s heartbeat / 360s
-- offline timeout
-- ============================================================================
--
-- OBJECTIVE: reduce presence-related bandwidth while keeping the multi-
-- device "online if ANY device is live" architecture from migration 0014
-- completely intact. Only the two timing knobs change:
--   heartbeat interval : 30s  -> 240s (4 min)  (client-side, see main.dart)
--   offline timeout    : 120s -> 360s (6 min)  (server-side, this file)
--
-- Everything else — device_presence's shape, presence_heartbeat's and
-- presence_set_status's write behavior, recompute_user_presence's
-- "online iff any device live" rollup, the RLS policies, the indexes — is
-- untouched.
--
-- MAGIC-NUMBER CLEANUP: the 120-second window used to be inlined directly
-- into `is_device_row_live` and `expire_stale_device_presence`. Both now
-- read it from `public.presence_offline_timeout_seconds()` below, so the
-- client's PresenceConstants.offlineTimeout and this function are the only
-- two places the value ever needs to change again. A matching
-- `public.presence_heartbeat_interval_seconds()` is added for the same
-- reason even though no SQL function currently branches on it (documented
-- expectations only — the timer itself lives in the client) — future SQL
-- that needs the expected heartbeat cadence (e.g. tuning the janitor
-- schedule below) has a single place to read it from instead of a fresh
-- hardcoded literal.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Shared constants (SQL has no true constants, so these are STABLE/
--    IMMUTABLE zero-argument functions the planner can inline).
-- ----------------------------------------------------------------------------

create or replace function public.presence_heartbeat_interval_seconds()
returns integer
language sql
immutable
as $$
  select 240;
$$;

comment on function public.presence_heartbeat_interval_seconds() is
  'Expected client heartbeat cadence in seconds (see lib/core/constants/presence_constants.dart PresenceConstants.heartbeatInterval). Documentation/tuning constant only — no server-side logic currently branches on this directly, since the timer itself is client-driven.';

create or replace function public.presence_offline_timeout_seconds()
returns integer
language sql
immutable
as $$
  select 360;
$$;

comment on function public.presence_offline_timeout_seconds() is
  'Single source of truth for how many seconds a device_presence row can go without a heartbeat before it is treated as offline. Used by is_device_row_live and expire_stale_device_presence so they can never drift apart. Mirrors lib/core/constants/presence_constants.dart PresenceConstants.offlineTimeout (360s / 6 min) — change both together.';

-- ----------------------------------------------------------------------------
-- 2. is_device_row_live: 120s -> presence_offline_timeout_seconds() (360s)
-- ----------------------------------------------------------------------------

create or replace function public.is_device_row_live(p_status text, p_last_heartbeat timestamptz)
returns boolean
language sql
stable
as $$
  select p_status = 'online'
    and p_last_heartbeat > (now() - make_interval(secs => public.presence_offline_timeout_seconds()));
$$;

comment on function public.is_device_row_live(text, timestamptz) is
  'True if a device_presence row counts as currently online: status = online AND last_heartbeat within the last presence_offline_timeout_seconds() (360s / 6 min). Centralizes the staleness window used by recompute_user_presence and expire_stale_device_presence so they can never drift apart.';

-- NOTE: switched from `immutable` to `stable` because the function body now
-- calls `now()` indirectly through presence_offline_timeout_seconds()'s
-- result being combined with now() at call time — `now()` itself is only
-- `stable` (constant within one transaction), not `immutable`, so this
-- function's own volatility category must not overstate its guarantees.
-- Callers (recompute_user_presence, expire_stale_device_presence) are
-- unaffected: both already call this inside ordinary SQL/plpgsql, which
-- works identically under `stable`.

-- ----------------------------------------------------------------------------
-- 3. expire_stale_device_presence: 120s -> presence_offline_timeout_seconds()
--    (360s). Sweep logic, users-affected rollup, and grants are unchanged.
-- ----------------------------------------------------------------------------

create or replace function public.expire_stale_device_presence()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
begin
  for v_uid in
    update public.device_presence
    set status = 'offline'
    where status = 'online'
      and last_heartbeat <= (now() - make_interval(secs => public.presence_offline_timeout_seconds()))
    returning user_id
  loop
    perform public.recompute_user_presence(v_uid);
  end loop;
end;
$$;

comment on function public.expire_stale_device_presence() is
  'Never leave a ghost-online device: any device row still marked online whose last_heartbeat is older than presence_offline_timeout_seconds() (360s / 6 min) is flipped offline and its user''s aggregate recomputed. Covers force-close, crash, and app-kill, none of which ever reach presence_set_status. Called opportunistically from presence_heartbeat and (when the pg_cron extension is available) on a schedule below.';

-- ----------------------------------------------------------------------------
-- 4. Table/function documentation touch-ups: refresh comments that quoted
--    the old 120s window so they stay accurate (no logic change here).
-- ----------------------------------------------------------------------------

comment on table public.device_presence is
  'Per-device presence. One row per (user_id, device_id). Client writes only via presence_heartbeat()/presence_set_status() RPCs (never a direct UPDATE) so is_online on public.user_presence can never be aggregated from anything except server-validated rows. A device is considered live only while status = ''online'' AND last_heartbeat is within presence_offline_timeout_seconds() (360s / 6 min — see is_device_row_live above) — a stale heartbeat is treated as offline even before expire_stale_device_presence() physically flips the row.';

comment on function public.presence_heartbeat(text) is
  'Client calls this every presence_heartbeat_interval_seconds() (240s / 4 min, foreground only) to keep its device row live, plus on-demand via PresenceActivityPinger on real user activity. Required architecture per Bug #1: presence is heartbeat-driven, never a single client-trusted boolean flip.';

-- ----------------------------------------------------------------------------
-- 5. Janitor (pg_cron) schedule: re-tuned, not just re-hardcoded, now that
--    the heartbeat interval itself is 8x longer. The old 30s schedule was
--    sized for a 30s heartbeat / 120s timeout (4 sweeps per timeout
--    window); keeping that same 3-4x-per-timeout-window ratio against the
--    new 360s timeout means every ~90s is comfortably frequent without
--    scanning far more often than the data can actually change — the
--    partial (status, last_heartbeat) index keeps each run cheap regardless.
--    presence_heartbeat's own opportunistic sweep (migration 0014, section
--    4) remains the primary self-healing path and is completely unaffected
--    by this schedule either way.
-- ----------------------------------------------------------------------------

do $outer$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
      from cron.job
      where jobname = 'expire-stale-device-presence';

    perform cron.schedule(
      'expire-stale-device-presence',
      '90 seconds',
      $cron$
select public.expire_stale_device_presence();
$cron$
    );
  end if;

exception
  when others then
    -- pg_cron present but scheduling failed for some project-specific
    -- reason (permissions, version) — non-fatal, heartbeat-driven sweep
    -- still covers correctness.
    null;
end;
$outer$;

-- ----------------------------------------------------------------------------
-- 6. Apply the new (looser) window immediately to existing rows: run one
--    sweep right now so any device that was already stale under the old
--    120s rule but would now legitimately still be "live" under the new
--    360s rule gets a chance to be re-evaluated the next time it
--    heartbeats, and so any row that's genuinely stale even under the new,
--    longer window is still flipped without waiting for the first
--    scheduled/opportunistic sweep after this migration runs.
-- ----------------------------------------------------------------------------

select public.expire_stale_device_presence();

-- ============================================================================
-- END MIGRATION 0015
-- ============================================================================
