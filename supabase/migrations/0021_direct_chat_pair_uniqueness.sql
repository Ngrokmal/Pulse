-- ============================================================================
-- 0021_direct_chat_pair_uniqueness.sql
--
-- ROOT CAUSE: ensureDirectChatExists (chat_repository_impl.dart) only
-- prevents duplicate direct chats via a client-side check-then-insert
-- (_findExistingDirectChatId SELECT, then chats.insert if nothing found).
-- That is not atomic. Two concurrent calls for the same user pair — e.g.
-- FriendRepositoryImpl.acceptFriendRequest firing on one device at the
-- same moment the other user's profile screen "Message" button fires
-- ensureDirectChatExists on theirs — can both pass the "not found" check
-- before either insert lands, producing two separate `chats` rows (each
-- type='direct') for the same two users.
--
-- Unlike public.friendships, public.chats does not store the member pair
-- directly — membership lives in the separate chat_members join table —
-- so friendships_unique_pair_idx's technique can't be applied to `chats`
-- as-is. This migration adds the minimum needed to apply the exact same
-- technique: two columns on `chats`, populated only for type='direct'
-- rows, holding the pair in a canonical (least, greatest) order, plus a
-- partial unique index on them — same least/greatest-unique-index pattern
-- as friendships_unique_pair_idx (pulse_messenger_module1and 3.sql:579-580).
--
-- PRODUCTION SAFETY (fixed from a prior draft of this migration): the
-- unique index must NOT be created until (a) every existing direct chat
-- has been backfilled, AND (b) any pre-existing duplicate pairs have been
-- merged away. An earlier draft created the index first and backfilled
-- after, which trivially "succeeded" at CREATE UNIQUE INDEX time (the
-- column was still all-NULL) but then made the backfill UPDATE itself
-- fail with a unique violation the moment it reached a second row for an
-- already-duplicated pair. This version does backfill + dedup first, then
-- creates the index last, once the column is guaranteed conflict-free.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Step 1: add the columns (nullable, no index yet — safe on any table size,
-- no table rewrite, no lock beyond the brief one ALTER TABLE ADD COLUMN
-- already takes).
-- ----------------------------------------------------------------------------
alter table public.chats
  add column if not exists direct_member_low  uuid references public.users(id) on delete set null,
  add column if not exists direct_member_high uuid references public.users(id) on delete set null;

comment on column public.chats.direct_member_low is
  'Only populated for type=direct chats: least(member_a, member_b) by uuid ordering. Together with direct_member_high, guarantees exactly one direct chat per unordered user pair via direct_chats_unique_pair_idx — mirrors friendships_unique_pair_idx''s least/greatest technique, applied here because (unlike friendships) chats does not store its members as columns on the row itself. on delete set null (not cascade), matching creator_id/last_message_sender_id: a deleted user must not take the whole chat/message history down with them for the other, still-active participant.';

comment on column public.chats.direct_member_high is
  'Only populated for type=direct chats: greatest(member_a, member_b) by uuid ordering. See direct_member_low.';

-- ----------------------------------------------------------------------------
-- Step 2: backfill for every existing direct chat, BEFORE any index exists.
-- ----------------------------------------------------------------------------
update public.chats c
set direct_member_low  = least(m.member_a, m.member_b),
    direct_member_high = greatest(m.member_a, m.member_b)
from (
  select chat_id,
         (array_agg(user_id order by user_id asc))[1] as member_a,
         (array_agg(user_id order by user_id asc))[2] as member_b
  from public.chat_members
  where left_at is null
  group by chat_id
  having count(*) = 2
) m
where c.id = m.chat_id
  and c.type = 'direct'
  and c.direct_member_low is null;

-- ----------------------------------------------------------------------------
-- Step 3: DEDUPLICATE any pre-existing duplicate direct-chat pairs BEFORE
-- creating the unique index. Nothing is silently dropped: for each
-- duplicate group, one "keeper" chat survives (the earliest-created one —
-- deterministic and re-runnable), and every "loser" chat's messages and
-- unread counts are merged onto it before the loser row is removed.
-- ----------------------------------------------------------------------------
create temporary table _direct_chat_dedup_map on commit drop as
select
  c.id as loser_id,
  first_value(c.id) over (
    partition by c.direct_member_low, c.direct_member_high
    order by c.created_at asc, c.id asc
  ) as keeper_id
from public.chats c
where c.type = 'direct'
  and c.direct_member_low is not null;

-- Only rows that are NOT their own group's keeper are actual "losers".
delete from _direct_chat_dedup_map where loser_id = keeper_id;

-- 3a: reassign every loser's messages onto its keeper — message history
-- is preserved, just merged into the surviving conversation. Safe: the
-- keeper has the exact same two members (same direct_member_low/high),
-- so no RLS/visibility change for either participant, and messages.id
-- (client-generated uuid) is the only unique constraint on that table —
-- there is no (chat_id, ...) uniqueness for this reassignment to violate.
update public.messages m
set chat_id = d.keeper_id
from _direct_chat_dedup_map d
where m.chat_id = d.loser_id;

-- 3b: carry the newest loser's last_message forward onto the keeper if it
-- is more recent than the keeper's own, so the merged conversation always
-- reflects the true latest message. Pre-aggregates across ALL of this
-- keeper's losers first (not a direct multi-row UPDATE...FROM) because a
-- keeper can have more than one loser — a plain UPDATE...FROM with
-- multiple matching source rows for the same target row does not
-- guarantee picking the maximum, it picks one arbitrarily.
with newest_loser_message as (
  select distinct on (d.keeper_id)
    d.keeper_id,
    lo.last_message,
    lo.last_message_at,
    lo.last_message_sender_id,
    lo.updated_at
  from _direct_chat_dedup_map d
  join public.chats lo on lo.id = d.loser_id
  where lo.last_message_at is not null
  order by d.keeper_id, lo.last_message_at desc
)
update public.chats k
set last_message = nl.last_message,
    last_message_at = nl.last_message_at,
    last_message_sender_id = nl.last_message_sender_id,
    updated_at = greatest(k.updated_at, nl.updated_at)
from newest_loser_message nl
where k.id = nl.keeper_id
  and (k.last_message_at is null or nl.last_message_at > k.last_message_at);

-- 3c: fold each loser's per-user unread_count into the keeper's matching
-- chat_members row, so a duplicate chat's unread badge isn't silently
-- lost for either participant. Pre-aggregates (SUM) across ALL of this
-- keeper's losers per user first, for the same reason as 3b above — a
-- keeper with multiple losers must have their unread_counts summed
-- together, not have only one of them arbitrarily applied.
with loser_unread as (
  select d.keeper_id, lm.user_id, sum(lm.unread_count) as total_unread
  from _direct_chat_dedup_map d
  join public.chat_members lm on lm.chat_id = d.loser_id
  group by d.keeper_id, lm.user_id
)
update public.chat_members km
set unread_count = km.unread_count + lu.total_unread
from loser_unread lu
where km.chat_id = lu.keeper_id
  and km.user_id = lu.user_id;

-- 3d: delete the loser chats. This cascades to their now-merged-away
-- chat_members rows (chat_members.chat_id is on delete cascade from
-- chats) and to any notifications referencing them (notifications.chat_id
-- is on delete cascade — Module 4). Accepted, minor, and explicitly
-- called out: old notifications pointing at a duplicate/glitch chat are
-- cleaned up along with it rather than reassigned — reassigning a
-- notification's chat_id after the fact would misrepresent which
-- conversation it was actually about.
delete from public.chats where id in (select loser_id from _direct_chat_dedup_map);

-- ----------------------------------------------------------------------------
-- Step 4: NOW create the unique index — every existing direct chat has
-- been backfilled and every duplicate pair has been merged away, so this
-- is guaranteed conflict-free regardless of what production data looked
-- like before this migration ran.
-- ----------------------------------------------------------------------------
create unique index if not exists direct_chats_unique_pair_idx
  on public.chats (direct_member_low, direct_member_high)
  where type = 'direct';

-- ============================================================================
-- POST-INSTALL VERIFICATION — read-only, run manually
-- ============================================================================

-- No duplicate direct-chat pairs should remain (0 rows expected):
select direct_member_low, direct_member_high, count(*)
from public.chats
where type = 'direct' and direct_member_low is not null
group by direct_member_low, direct_member_high
having count(*) > 1;

-- Every direct chat with exactly 2 active members should now have both
-- columns populated (0 rows expected):
select c.id
from public.chats c
where c.type = 'direct'
  and c.direct_member_low is null
  and (select count(*) from public.chat_members cm where cm.chat_id = c.id and cm.left_at is null) = 2;

-- ============================================================================
-- END 0021_direct_chat_pair_uniqueness.sql
-- ============================================================================
