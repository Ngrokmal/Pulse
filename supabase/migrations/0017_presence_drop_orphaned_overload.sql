-- ============================================================================
-- 0017_presence_drop_orphaned_overload.sql
--
-- SECONDARY FINDING from the presence audit (NOT related to the unread-
-- count / push-notification bugs — those are fixed by 0016; this is a
-- separate, lower-severity drift issue found while verifying whether the
-- 0014/0015 presence migrations touched anything else).
--
-- 0014 created:
--   is_device_row_live(p_status public.device_presence_status_enum,
--                       p_last_heartbeat timestamptz)
-- 0015 then ran:
--   create or replace function public.is_device_row_live(
--     p_status text, p_last_heartbeat timestamptz) ...
--
-- `create or replace function` only replaces a function with an IDENTICAL
-- argument-type list. `device_presence_status_enum` and `text` are
-- different types, so 0015 did not replace 0014's function — it created a
-- second, overloaded one. Both now exist side by side.
--
-- recompute_user_presence() calls:
--   public.is_device_row_live(dp.status, dp.last_heartbeat)
-- where dp.status is public.device_presence_status_enum, so Postgres's
-- overload resolution picks the exact-type match — i.e. it is still
-- silently calling 0014's ORIGINAL function body (hardcoded "interval
-- '360 seconds'"), not 0015's version that reads from
-- presence_offline_timeout_seconds(). Confidence: 90% this is inert today
-- only because both bodies happen to hardcode/resolve to the same 360s
-- value — the moment someone changes presence_offline_timeout_seconds()
-- expecting it to be the single source of truth (exactly what 0015's own
-- comments promise), recompute_user_presence() will silently keep using
-- the stale 360s window while expire_stale_device_presence() (which calls
-- presence_offline_timeout_seconds() directly, not through the enum
-- overload) picks up the new value — the two can drift apart, which is
-- precisely what 0015 says it was trying to prevent.
--
-- FIX: drop the orphaned enum-typed overload so only 0015's text-typed,
-- constant-driven version exists, and update recompute_user_presence()'s
-- call site to pass status as text (::text cast) so it resolves to that
-- single remaining function. No table, RLS, RPC signature (client-facing),
-- or timing-value change — presence_set_status/presence_heartbeat and
-- their grants are untouched.
-- ============================================================================

drop function if exists public.is_device_row_live(public.device_presence_status_enum, timestamptz);

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
  'Rolls up public.device_presence into the single public.user_presence row for p_user_id: is_online = true iff at least one device row is currently live (is_device_row_live, read via presence_offline_timeout_seconds()). Called at the end of presence_set_status(), presence_heartbeat(), and expire_stale_device_presence() — never needs to be called directly by the client.';

-- ----------------------------------------------------------------------------
-- POST-INSTALL VERIFICATION — read-only, run manually
-- ----------------------------------------------------------------------------

-- Exactly one is_device_row_live overload should remain (text, timestamptz)
select p.proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
where p.proname = 'is_device_row_live';

-- ============================================================================
-- END 0017_presence_drop_orphaned_overload.sql
-- ============================================================================
