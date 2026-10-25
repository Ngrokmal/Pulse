-- ============================================================================
-- 0016_fix_increment_unread_counts.sql
--
-- ROOT CAUSE (unread count stuck + push notifications silent):
--
-- ChatRepositoryImpl._sendTextMessageRemote / sendMediaMessage / send
-- MessageWithAlert (lib/features/chat/data/repositories/chat_repository_
-- impl.dart) and GroupOfflineQueueService's sendMessage handler
-- (lib/features/chat/data/services/group_offline_queue_service.dart) both
-- call:
--
--     supabase.rpc('increment_unread_counts',
--                   params: {'p_chat_id': ..., 'p_sender_id': ...})
--
-- and, for the direct-chat path, iterate the RPC's returned user-id list to
-- fire PushNotificationSenderService.sendChatMessageNotification for each
-- affected member — i.e. the push fan-out is downstream of, and gated on,
-- this RPC call succeeding.
--
-- `public.increment_unread_counts` does not exist anywhere in this
-- project's SQL (Modules 1-8, 0013, 0014, 0015 all checked — no CREATE
-- FUNCTION, no reference at all). Calling a non-existent RPC makes
-- PostgREST return "Could not find the function public.increment_unread_
-- counts(p_chat_id, p_sender_id) in the schema cache" (PGRST202) on every
-- single send.
--
-- That failure is swallowed silently:
--   - _sendTextMessageRemote wraps the whole queued block (insert + chats
--     update + this RPC + the push loop) in a try/catch whose catch branch
--     only flips the local Hive row to failed/failed — by design (RULE 4),
--     since sendMessage() has already returned to its caller and there is
--     no UI-level try/catch left to surface the error to.
--   - GroupOfflineQueueService's handler runs inside OfflineQueueManager,
--     which itself catches/retries queued operations without surfacing a
--     raw PostgrestException to the UI.
--
-- Net effect: the message itself still sends (the insert happens before
-- the RPC call), so chat looks "normal", but unread_count is never
-- incremented (bug 1) and the push-notification loop — which only runs
-- with the RPC's return value — never executes (bug 2). Both reported
-- symptoms are explained by this single missing function; nothing in the
-- 0014/0015 presence migrations touches chat_members, messages, or any
-- notification path, so the presence work is exonerated by this audit.
--
-- FIX: define `increment_unread_counts` as the atomic, security-definer
-- RPC the client already expects: one UPDATE that increments unread_count
-- for every ACTIVE member of the chat other than the sender, returning the
-- affected member ids so the caller can fan out push notifications from
-- the same round trip (matching the code comments in both call sites,
-- which already describe this exact contract).
--
-- SECURITY: chat_members has no policy letting a user UPDATE another
-- member's row (chat_members_update_own is `user_id = auth.uid()` only;
-- chat_members_update_admin requires is_chat_admin) — an ordinary sender
-- is neither, so this must run SECURITY DEFINER to bypass RLS, exactly
-- like is_chat_member()/is_chat_admin() already do for the same table.
-- To avoid opening that up to abuse, the function pins p_sender_id to
-- auth.uid() (a caller can never increment counts "as" someone else) and
-- requires the caller to actually be an active member of p_chat_id via the
-- existing is_chat_member() helper before touching any row.
-- ============================================================================

create or replace function public.increment_unread_counts(
  p_chat_id uuid,
  p_sender_id uuid
)
returns uuid[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_affected uuid[];
begin
  if auth.uid() is null then
    raise exception 'increment_unread_counts: no authenticated user';
  end if;

  -- A caller can only ever increment counts as themselves — prevents a
  -- malicious/buggy client from passing an arbitrary p_sender_id to bump
  -- other members' unread counts on someone else's behalf.
  if p_sender_id <> auth.uid() then
    raise exception 'increment_unread_counts: p_sender_id must match the authenticated user';
  end if;

  -- Caller must actually be an active member of the chat they're sending
  -- into (mirrors messages_insert_chat_members / is_chat_member usage
  -- elsewhere) — SECURITY DEFINER bypasses RLS below, so this check is
  -- the only gate standing between an authenticated user and every other
  -- chat's chat_members rows.
  if not public.is_chat_member(p_chat_id) then
    raise exception 'increment_unread_counts: caller is not an active member of %', p_chat_id;
  end if;

  with updated as (
    update public.chat_members
    set unread_count = unread_count + 1
    where chat_id = p_chat_id
      and user_id <> p_sender_id
      and left_at is null
    returning user_id
  )
  select coalesce(array_agg(user_id), array[]::uuid[])
  into v_affected
  from updated;

  return v_affected;
end;
$$;

comment on function public.increment_unread_counts(uuid, uuid) is
  'Atomically increments unread_count for every active (left_at is null) member of p_chat_id other than p_sender_id, in a single UPDATE (no client-side read-modify-write, so concurrent senders can never lose an increment). Returns the affected member user_ids so callers can fan out push notifications from the same round trip. Backs ChatRepositoryImpl (_sendTextMessageRemote, sendMediaMessage, sendMessageWithAlert) and GroupOfflineQueueService''s sendMessage handler. SECURITY DEFINER because senders have no RLS grant to update other members'' chat_members rows; p_sender_id is pinned to auth.uid() and membership is re-checked via is_chat_member() to prevent abuse.';

grant execute on function public.increment_unread_counts(uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- POST-INSTALL VERIFICATION — read-only, run manually
-- ----------------------------------------------------------------------------

-- Function exists with the expected signature
select p.proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
where p.proname = 'increment_unread_counts';

-- ============================================================================
-- END 0016_fix_increment_unread_counts.sql
-- ============================================================================
