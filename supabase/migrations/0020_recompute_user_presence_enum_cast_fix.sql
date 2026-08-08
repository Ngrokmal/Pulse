-- ============================================================================
-- 0020_recompute_user_presence_enum_cast_fix.sql
--
-- Production's live public.is_device_row_live has signature
-- (p_status device_presence_status_enum, p_last_heartbeat timestamptz) —
-- confirmed via:
--
--   select p.proname, pg_get_function_identity_arguments(p.oid) as args
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.proname = 'is_device_row_live';
--
--   -> is_device_row_live | p_status device_presence_status_enum,
--                           p_last_heartbeat timestamp with time zone
--
-- This is enum-typed, not text-typed. public.recompute_user_presence(uuid)
-- currently calls it as:
--
--   public.is_device_row_live(dp.status::text, dp.last_heartbeat)
--
-- The explicit ::text cast forces PostgreSQL to look for an overload
-- (text, timestamptz), which does not exist live, producing:
--
--   function public.is_device_row_live(text, timestamp with time zone)
--   does not exist
--
-- Fix: remove ONLY the ::text cast so the call matches the live enum-typed
-- signature. dp.status is already public.device_presence_status_enum at
-- the source (public.device_presence.status), so no cast is needed at all.
--
-- Nothing else in this function is changed. No overload is created. No
-- other function, table, RLS policy, trigger, cron job, or RPC is touched.
-- ============================================================================

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
  'Rolls up public.device_presence into the single public.user_presence row for p_user_id: is_online = true iff at least one device row is currently live via the canonical is_device_row_live(text, timestamptz). Called at the end of presence_set_status(), presence_heartbeat(), and expire_stale_device_presence() — never needs to be called directly by the client.';


-- ----------------------------------------------------------------------------
-- POST-INSTALL VERIFICATION — read-only, run manually
-- ----------------------------------------------------------------------------

-- 1. recompute_user_presence(uuid) still exists with the same signature.
select p.proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'recompute_user_presence';

-- 2. Confirm every live caller of is_device_row_live() now passes the enum,
--    not text. This inspects the compiled function source for each caller;
--    a caller is "clean" if it does NOT contain '::text' immediately before
--    the call, i.e. it matches on '.status,' rather than '.status::text,'.
select p.proname,
       (position('is_device_row_live(dp.status::text' in pg_get_functiondef(p.oid)) > 0
         or position('is_device_row_live(status::text' in pg_get_functiondef(p.oid)) > 0
       ) as still_casts_to_text
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and pg_get_functiondef(p.oid) ilike '%is_device_row_live(%';
-- recompute_user_presence should now show still_casts_to_text = false.
-- If expire_stale_device_presence appears here with still_casts_to_text =
-- true, it was NOT touched by this migration (per your instructions) and
-- is a separate, likely-still-broken caller — see note above.

-- ============================================================================
-- END 0020_recompute_user_presence_enum_cast_fix.sql
-- ============================================================================
