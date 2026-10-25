-- ============================================================================
-- MODULE 6 OF N — Pulse Messenger Database Reconstruction
-- RPCs: search_users | get_user_inbox | get_mutual_friends_count |
--       get_friend_request_privacy
--
-- Depends on: MODULE 1 (public.users, public.user_settings,
--             public.friend_request_privacy_enum, pg_trgm extension),
--             MODULE 2 (public.chats, public.chat_members, public.messages),
--             MODULE 3 (public.friendships).
--
-- DISCLOSURE: none of these four function bodies could be reproduced
-- verbatim in this session — no exact recovered SQL for them was available
-- to copy from. Every body below is a conservative reconstruction built
-- only from confirmed schema (Modules 1-3), confirmed index shapes, and the
-- behavioral requirements given in this prompt. Non-trivial choices within
-- each function are individually flagged "-- INFERRED"; treat the whole
-- module as reconstructed pending re-verification against the real Step 1
-- migration if one turns up.
--
-- No RLS, no policies, no realtime publication, no Edge Functions, no
-- extra helper functions beyond what each RPC strictly needs.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. FUNCTION: public.search_users
--
-- INFERRED body. Combines ILIKE substring matching with pg_trgm similarity
-- so it degrades gracefully without a dedicated trigram index (none exists
-- yet — pg_trgm was enabled in Module 1 "reserved for search_users RPC").
-- A `gin_trgm_ops` index on username/display_name would materially speed
-- this up but is NOT created here — this module is scoped to functions
-- only, per instruction. -- INFERRED
-- ----------------------------------------------------------------------------

create or replace function public.search_users(
  p_query text,
  p_limit integer default 20
)
returns table (
  id                    uuid,
  username              text,
  display_name          text,
  avatar_url            text,
  verification_status   public.verification_status_enum
)
language sql
stable
security definer        -- INFERRED: global search must see all users regardless of relationship; matches the DEFINER pattern already used by cross-user trigger functions in Modules 1-2
set search_path = public
as $$
  select
    u.id,
    u.username,
    u.display_name,
    u.avatar_url,
    u.verification_status
  from public.users u
  where u.id <> auth.uid()                              -- exclude current user, per requirement
    and u.is_disabled = false                            -- INFERRED: exclude disabled accounts from search
    and u.is_banned = false                               -- INFERRED: exclude banned accounts from search
    and (
      u.username ilike '%' || p_query || '%'
      or u.display_name ilike '%' || p_query || '%'
      or u.username % p_query
      or coalesce(u.display_name, '') % p_query
    )
  order by
    greatest(
      similarity(u.username, p_query),
      similarity(coalesce(u.display_name, ''), p_query)
    ) desc,
    u.username asc
  limit greatest(coalesce(p_limit, 20), 0);
$$;

comment on function public.search_users(text, integer) is
  'INFERRED reconstruction. ILIKE + pg_trgm similarity search over username/display_name, excluding the caller, disabled, and banned accounts. Recommend adding a gin_trgm_ops index on lower(username) and lower(display_name) in a future module for performance at scale.';


-- ----------------------------------------------------------------------------
-- 2. FUNCTION: public.get_user_inbox
--
-- INFERRED body. Returns one row per active chat membership of the caller,
-- with last-message state read straight off public.chats (already
-- denormalized there per Module 2), the caller's own unread_count from
-- public.chat_members, a resolved display name/avatar (group fields for
-- type='group', the other participant's profile for type='direct'), and a
-- jsonb array of active member summaries.
-- ----------------------------------------------------------------------------

create or replace function public.get_user_inbox(
  p_since timestamptz default null,
  p_limit integer default 50
)
returns table (
  chat_id            uuid,
  type               public.chat_type_enum,
  name               text,
  avatar_url         text,
  last_message       text,
  last_message_at    timestamptz,
  last_message_sender_id uuid,
  unread_count       integer,
  chat_updated_at    timestamptz,
  members            jsonb
)
language sql
stable
security definer        -- INFERRED: must read other participants' profile/membership rows within a shared chat
set search_path = public
as $$
  select
    c.id as chat_id,
    c.type,
    coalesce(c.name, other.display_name, other.username) as name,        -- INFERRED: direct-chat name falls back to the other member's profile
    coalesce(c.group_photo_url, other.avatar_url) as avatar_url,          -- INFERRED: direct-chat avatar falls back to the other member's avatar
    c.last_message,
    c.last_message_at,
    c.last_message_sender_id,
    cm.unread_count,
    greatest(c.updated_at, cm.updated_at) as chat_updated_at,
    coalesce(mem.members, '[]'::jsonb) as members
  from public.chat_members cm
  join public.chats c
    on c.id = cm.chat_id
  left join lateral (
    select ou.display_name, ou.username, ou.avatar_url
    from public.chat_members ocm
    join public.users ou on ou.id = ocm.user_id
    where ocm.chat_id = c.id
      and ocm.user_id <> auth.uid()
      and ocm.left_at is null
      and c.type = 'direct'
    limit 1
  ) other on true
  left join lateral (
    select jsonb_agg(jsonb_build_object(
             'user_id', mu.id,
             'username', mu.username,
             'display_name', mu.display_name,
             'avatar_url', mu.avatar_url,
             'role', mcm.role
           )) as members
    from public.chat_members mcm
    join public.users mu on mu.id = mcm.user_id
    where mcm.chat_id = c.id
      and mcm.left_at is null
  ) mem on true
  where cm.user_id = auth.uid()
    and cm.left_at is null
    and (p_since is null or greatest(c.updated_at, cm.updated_at) > p_since)
  order by c.last_message_at desc nulls last
  limit greatest(coalesce(p_limit, 50), 0);
$$;

comment on function public.get_user_inbox(timestamptz, integer) is
  'INFERRED reconstruction. Uses chat_members_active_by_user_idx (chat_id) where left_at is null for the driving scan, and public.chats.last_message* (Module 2 denormalization) instead of joining public.messages. Member summaries and the direct-chat name/avatar fallback are inferred shapes, not confirmed field names from Step 1.';


-- ----------------------------------------------------------------------------
-- 3. FUNCTION: public.get_mutual_friends_count
--
-- Counts only status = 'accepted' friendship rows on both sides; pending
-- and declined rows are ignored, per requirement.
-- ----------------------------------------------------------------------------

create or replace function public.get_mutual_friends_count(
  p_user_a uuid,
  p_user_b uuid
)
returns integer
language sql
stable
security definer        -- INFERRED: must read friendship rows between two other users, neither of which may be the caller
set search_path = public
as $$
  with friends_a as (
    select case when f.requester_id = p_user_a then f.addressee_id else f.requester_id end as friend_id
    from public.friendships f
    where f.status = 'accepted'
      and (f.requester_id = p_user_a or f.addressee_id = p_user_a)
  ),
  friends_b as (
    select case when f.requester_id = p_user_b then f.addressee_id else f.requester_id end as friend_id
    from public.friendships f
    where f.status = 'accepted'
      and (f.requester_id = p_user_b or f.addressee_id = p_user_b)
  )
  select count(*)::integer
  from friends_a a
  join friends_b b using (friend_id);
$$;

comment on function public.get_mutual_friends_count(uuid, uuid) is
  'Uses friendships_requester_status_idx / friendships_addressee_status_idx (Module 3) to resolve each side''s accepted-friend set before intersecting. Return type INTEGER per requirement.';


-- ----------------------------------------------------------------------------
-- 4. FUNCTION: public.get_friend_request_privacy
--
-- Returns the raw enum value as stored — the same
-- public.friend_request_privacy_enum ('everyone' | 'friendsOfFriends' |
-- 'nobody') defined in Module 1, which is exactly the string set the
-- Flutter client's enum mapping expects.
-- ----------------------------------------------------------------------------

create or replace function public.get_friend_request_privacy(
  p_user_id uuid
)
returns public.friend_request_privacy_enum
language sql
stable
security definer        -- INFERRED: caller must be able to read another user's setting when deciding whether to show a "send friend request" action
set search_path = public
as $$
  select us.friend_request_privacy
  from public.user_settings us
  where us.owner_id = p_user_id;
$$;

comment on function public.get_friend_request_privacy(uuid) is
  'Direct lookup by primary key (owner_id) on public.user_settings. Returns NULL if p_user_id has no settings row.';

-- ============================================================================
-- END MODULE 6
-- ============================================================================
