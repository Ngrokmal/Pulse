-- PHASE 4C FIX (Home chat list stuck on "No conversation yet")
--
-- ROOT CAUSE: `public.get_user_inbox` was deployed with signature
--   get_user_inbox(p_since timestamptz, p_limit integer)
-- (no p_user_id) and returned columns
--   chat_id, members, chat_updated_at
--
-- Flutter (ChatListRemoteDataSourceImpl.fetchUserInbox) calls:
--   rpc('get_user_inbox', params: {p_user_id, p_since, p_limit})
-- and ChatListRepositoryImpl / ChatListItemModel.fromSupabaseRow read the
-- result as: id, chat_members, updated_at, last_message,
-- last_message_at, last_message_sender_id, name, group_photo_url.
--
-- Calling a 3-arg RPC against a 2-arg function definition is not a partial
-- match in Postgres/PostgREST — there is no overload with a `p_user_id`
-- parameter, so PostgREST returns a "Could not find the function" error.
-- ChatListRepositoryImpl.runDelta() catches every exception from
-- fetchUserInbox (by design, so a transient network error can't leak a raw
-- exception into the Home UI — see its catch block) and silently falls
-- back to emitting whatever's already cached (empty on a first-ever
-- login). That is why the UI shows "No conversation yet" after a ~15-20s
-- timeout instead of a visible error: the real error is a schema mismatch,
-- not a network/timeout problem, but it presents identically to the user.
--
-- Even if the parameter list were fixed, the old column names (chat_id /
-- members / chat_updated_at) would still make every row fail Dart's
-- `row['id']`, `row['chat_members']`, `row['updated_at']` reads (null),
-- so this migration fixes BOTH the signature and the column names in one
-- change, matching what ChatListRemoteDataSourceImpl / ChatListRepositoryImpl
-- / ChatListItemModel already (correctly) expect on the Dart side — no
-- Dart changes are required for this bug.
--
-- Drop the old 2-arg overload first: `create or replace function` cannot
-- change a function's parameter list, only its body, so leaving the old
-- signature in place would leave two overloads of get_user_inbox coexisting
-- (the broken old one still resolvable by any caller that omits p_user_id).
drop function if exists public.get_user_inbox(timestamptz, integer);

create or replace function public.get_user_inbox(
  p_user_id uuid,
  p_since timestamptz,
  p_limit integer default 100
)
returns table (
  id uuid,
  name text,
  group_photo_url text,
  last_message text,
  last_message_at timestamptz,
  last_message_sender_id uuid,
  updated_at timestamptz,
  chat_members jsonb
)
language sql
stable
-- security invoker (the default) is deliberate, not an oversight: this
-- keeps the function subject to the same `is_chat_member` RLS policy that
-- already gates `chats`/`chat_members` for the plain PostgREST select in
-- fetchChangedDirectChats. That means even a caller that passes a
-- mismatched p_user_id can never see another user's chats — RLS still
-- keys off auth.uid() from the caller's own JWT, independent of whatever
-- p_user_id was passed in. p_user_id is only used to pick the caller's
-- OWN unread_count in the embedded chat_members payload below, never to
-- decide row visibility.
security invoker
set search_path = public
as $$
  select
    c.id,
    c.name,
    c.group_photo_url,
    c.last_message,
    c.last_message_at,
    c.last_message_sender_id,
    c.updated_at,
    -- Nested chat_members payload shaped exactly like the PostgREST
    -- embedded-resource select used elsewhere (`chat_members(user_id,
    -- unread_count)`), because ChatListRepositoryImpl.buildDirectChatModel
    -- and _otherMemberSupabaseId both decode row['chat_members'] as a
    -- List<Map<String, dynamic>> of {user_id, unread_count} regardless of
    -- whether the row came from the plain select or this RPC.
    (
      select jsonb_agg(jsonb_build_object('user_id', cm2.user_id, 'unread_count', cm2.unread_count))
      from public.chat_members cm2
      where cm2.chat_id = c.id
    ) as chat_members
  from public.chats c
  where c.type = 'direct'
    and c.updated_at > p_since
    and exists (
      select 1
      from public.chat_members cm
      where cm.chat_id = c.id
        and cm.user_id = p_user_id
    )
  order by c.updated_at asc
  limit p_limit;
$$;

grant execute on function public.get_user_inbox(uuid, timestamptz, integer) to authenticated;
