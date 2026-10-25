-- ============================================================================
-- MODULE 8 OF N (FINAL) — Pulse Messenger Database Reconstruction
-- Realtime Publication | Deferred Indexes | Validation & Integrity Queries |
-- Optional Dev Seed Data | Migration Execution Order |
-- Post-Install Verification Checklist
--
-- Depends on: MODULES 1-7 (all tables, triggers, functions, RLS policies).
-- No new tables. No schema redesign. Read this whole module before running
-- it — Sections 5 and 6 are read-only checks / opt-in dev data, not
-- unconditional DDL.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. REALTIME PUBLICATION CONFIGURATION
--
-- Defensive create: on a Supabase-managed project `supabase_realtime`
-- already exists and this is a no-op; included for portability to a
-- plain self-hosted Postgres 16 instance. -- INFERRED
-- ----------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end$$;


-- ----------------------------------------------------------------------------
-- 2. ALTER PUBLICATION — add required tables (idempotent)
--
-- ADD TABLE errors if the table is already a publication member, so each
-- table is guarded individually via pg_publication_tables before adding.
-- ----------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'users',
    'user_presence',
    'friendships',
    'chats',
    'chat_members',
    'messages',
    'notifications',
    'reports',
    'alert_sounds'
  ]
  loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end$$;

-- INFERRED best practice: REPLICA IDENTITY FULL so UPDATE/DELETE realtime
-- payloads include full old row values (needed for client-side cache
-- reconciliation on these tables — e.g. a message's old status, a chat
-- member's old unread_count, a friendship's old status). Not explicitly
-- requested; recommended Supabase Realtime practice for tables whose
-- changes are consumed by streaming client logic.
do $$
declare
  t text;
begin
  foreach t in array array[
    'users',
    'user_presence',
    'friendships',
    'chats',
    'chat_members',
    'messages',
    'notifications',
    'reports',
    'alert_sounds'
  ]
  loop
    execute format('alter table public.%I replica identity full', t);
  end loop;
end$$;


-- ----------------------------------------------------------------------------
-- 3. FINAL INDEXES INTENTIONALLY DEFERRED FROM PRIOR MODULES
--
-- Only one deferral was flagged across Modules 1-7: Module 6's
-- search_users() comment explicitly deferred a trigram index, since Module
-- 6 was scoped to functions only. Created now, matching the exact columns
-- search_users() filters/orders on (raw username / display_name, not
-- lower()) so the planner can actually use them for the ILIKE and `%`
-- predicates already in that function.
-- ----------------------------------------------------------------------------

create index if not exists users_username_trgm_idx
  on public.users using gin (username gin_trgm_ops);

create index if not exists users_display_name_trgm_idx
  on public.users using gin (display_name gin_trgm_ops)
  where display_name is not null;


-- ----------------------------------------------------------------------------
-- 4. DATABASE VALIDATION SQL — run manually, read-only
-- Every query below returns rows only when it finds a problem; an empty
-- result set means that check passed. None of these mutate data.
-- ----------------------------------------------------------------------------

-- 4.1 Orphaned polymorphic references (reports.target_id / target_id in
-- admin_action_logs have no DB-level FK by design — this is the only place
-- an "orphan foreign key" can actually occur in this schema, since every
-- real FK is enforced by Postgres itself and cannot be orphaned).
select r.id, r.target_type, r.target_id
from public.reports r
where r.target_type = 'user'
  and not exists (select 1 from public.users u where u.id = r.target_id);

select r.id, r.target_type, r.target_id
from public.reports r
where r.target_type = 'message'
  and not exists (select 1 from public.messages m where m.id = r.target_id);

select r.id, r.target_type, r.target_id
from public.reports r
where r.target_type = 'chat'
  and not exists (select 1 from public.chats c where c.id = r.target_id);

select l.id, l.target_type, l.target_id
from public.admin_action_logs l
where l.target_type = 'user'
  and l.target_id is not null
  and not exists (select 1 from public.users u where u.id = l.target_id);

-- 4.2 Duplicate friendships (should be impossible given
-- friendships_unique_pair_idx from Module 3 — this is a defense-in-depth
-- sanity check, e.g. for data loaded outside that constraint).
select least(requester_id, addressee_id) as user_a,
       greatest(requester_id, addressee_id) as user_b,
       count(*) as row_count
from public.friendships
group by 1, 2
having count(*) > 1;

-- 4.3 Invalid friends_count (users.friends_count vs actual accepted rows)
with actual as (
  select user_id, count(*) as actual_friends
  from (
    select requester_id as user_id from public.friendships where status = 'accepted'
    union all
    select addressee_id as user_id from public.friendships where status = 'accepted'
  ) f
  group by user_id
)
select u.id, u.friends_count as stored_count, coalesce(a.actual_friends, 0) as actual_count
from public.users u
left join actual a on a.user_id = u.id
where u.friends_count <> coalesce(a.actual_friends, 0);

-- 4.4 Invalid groups_count (users.groups_count vs actual active group
-- memberships)
with actual as (
  select cm.user_id, count(*) as actual_groups
  from public.chat_members cm
  join public.chats c on c.id = cm.chat_id
  where c.type = 'group'
    and cm.left_at is null
  group by cm.user_id
)
select u.id, u.groups_count as stored_count, coalesce(a.actual_groups, 0) as actual_count
from public.users u
left join actual a on a.user_id = u.id
where u.groups_count <> coalesce(a.actual_groups, 0);

-- 4.5 Broken notification references (real FKs already prevent this;
-- included as a sanity check for pre-constraint or bulk-loaded data)
select n.id, n.chat_id
from public.notifications n
where n.chat_id is not null
  and not exists (select 1 from public.chats c where c.id = n.chat_id);

select n.id, n.message_id
from public.notifications n
where n.message_id is not null
  and not exists (select 1 from public.messages m where m.id = n.message_id);

-- 4.6 Chat membership consistency — direct chats must have exactly 2
-- active members; group chats must have at least 1 active member.
select c.id, c.type, count(cm.user_id) filter (where cm.left_at is null) as active_members
from public.chats c
left join public.chat_members cm on cm.chat_id = c.id
group by c.id, c.type
having (c.type = 'direct' and count(cm.user_id) filter (where cm.left_at is null) <> 2)
    or (c.type = 'group'  and count(cm.user_id) filter (where cm.left_at is null) = 0);

-- 4.7 unread_count consistency — flags memberships whose stored
-- unread_count exceeds the total number of (non-deleted) messages ever
-- sent in that chat, which is not possible for a legitimately-derived
-- count. (There is no confirmed per-member "last read" cursor column in
-- this schema, so a tighter check against actual unread messages cannot be
-- expressed here — this is a loose upper-bound sanity check only.) -- INFERRED
select cm.chat_id, cm.user_id, cm.unread_count, msg_totals.total_messages
from public.chat_members cm
join (
  select chat_id, count(*) as total_messages
  from public.messages
  where deleted_at is null
  group by chat_id
) msg_totals on msg_totals.chat_id = cm.chat_id
where cm.unread_count > msg_totals.total_messages;

-- 4.8 Trigger existence
select expected.trigger_name, expected.table_name
from (values
  ('set_updated_at', 'users'),
  ('set_updated_at', 'user_settings'),
  ('set_updated_at', 'user_presence'),
  ('set_updated_at', 'chats'),
  ('set_updated_at', 'chat_members'),
  ('set_updated_at', 'messages'),
  ('set_updated_at', 'friendships'),
  ('set_updated_at', 'notifications'),
  ('set_updated_at', 'alert_sounds'),
  ('set_updated_at', 'user_ban_history'),
  ('on_auth_user_created', 'users'),          -- lives on auth.users; table_name shown for readability only, see note below
  ('trg_sync_groups_count', 'chat_members'),
  ('trg_sync_friends_count', 'friendships'),
  ('trg_admin_action_logs_no_update', 'admin_action_logs')
) as expected(trigger_name, table_name)
where not exists (
  select 1
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  where t.tgname = expected.trigger_name
    and not t.tgisinternal
);
-- Note: on_auth_user_created fires on auth.users, not public.users; the
-- table_name column above is illustrative only and not joined against.

-- 4.9 RLS enabled on required tables
select expected.table_name
from (values
  ('users'), ('user_settings'), ('user_presence'), ('chats'),
  ('chat_members'), ('messages'), ('friendships'), ('blocked_users'),
  ('notifications'), ('reports'), ('user_ban_history'), ('user_warnings'),
  ('admin_action_logs'), ('alert_sounds')
) as expected(table_name)
join pg_class c on c.relname = expected.table_name
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
where c.relrowsecurity is not true;

-- 4.10 Required functions exist
select expected.function_name
from (values
  ('set_updated_at'), ('handle_new_auth_user'), ('sync_groups_count'),
  ('sync_friends_count'), ('are_users_friends'), ('is_user_blocked'),
  ('search_users'), ('get_user_inbox'), ('get_mutual_friends_count'),
  ('get_friend_request_privacy'), ('prevent_admin_action_logs_mutation'),
  ('is_admin'), ('is_chat_member'), ('is_chat_admin')
) as expected(function_name)
where not exists (
  select 1
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
  where p.proname = expected.function_name
);


-- ----------------------------------------------------------------------------
-- 5. OPTIONAL SEED DATA FOR DEVELOPMENT
--
-- OPT-IN, DEV-ONLY. Not wrapped in an environment check (plain SQL has no
-- reliable way to detect "dev vs prod" on its own) — run this section
-- manually against a development database only. Limited to
-- public.alert_sounds: it is the one table in this schema with no
-- dependency on a real auth.users signup, so it is the only table that can
-- be safely seeded without fabricating fake auth identities. -- INFERRED
-- ----------------------------------------------------------------------------

insert into public.alert_sounds (id, display_name, audio_url, audio_format, is_default, sort_order)
values
  ('default_chime',  'Default Chime',  'https://cdn.example.com/alert-sounds/default_chime.mp3',  'mp3', true,  0),
  ('soft_bell',       'Soft Bell',      'https://cdn.example.com/alert-sounds/soft_bell.mp3',       'mp3', false, 1),
  ('marimba',          'Marimba',        'https://cdn.example.com/alert-sounds/marimba.mp3',         'mp3', false, 2),
  ('classic_ring',    'Classic Ring',    'https://cdn.example.com/alert-sounds/classic_ring.mp3',    'mp3', false, 3)
on conflict (id) do nothing;


-- ============================================================================
-- 6. MIGRATION EXECUTION ORDER
--
-- Run strictly in this order against a fresh database — each module
-- depends on objects created by the ones before it:
--
--   1. Module 1 — extensions, base enums, set_updated_at(), public.users,
--                  public.user_settings, public.user_presence,
--                  on_auth_user_created trigger
--   2. Module 2 — messaging enums, public.chats, public.chat_members,
--                  public.messages, sync_groups_count() + trigger
--   3. Module 3 — friendship enum, public.friendships,
--                  public.blocked_users, sync_friends_count() + trigger,
--                  are_users_friends(), is_user_blocked()
--   4. Module 4 — public.notifications, public.alert_sounds
--   5. Module 5 — report/ban/warning enums, public.reports,
--                  public.user_ban_history, public.user_warnings,
--                  public.admin_action_logs,
--                  prevent_admin_action_logs_mutation() + trigger
--   6. Module 6 — search_users(), get_user_inbox(),
--                  get_mutual_friends_count(), get_friend_request_privacy()
--   7. Module 7 — is_admin(), is_chat_member(), is_chat_admin(),
--                  RLS enablement + all policies
--   8. Module 8 (this file) — realtime publication, deferred trigram
--                  indexes, validation queries, optional dev seed data
--
-- Each module's DDL is written with IF NOT EXISTS / OR REPLACE / DROP...IF
-- EXISTS guards, so re-running the full sequence against a database that
-- already has some or all modules applied is safe.
-- ============================================================================


-- ============================================================================
-- 7. POST-INSTALL VERIFICATION CHECKLIST
--
-- Manual / integration-level checks — these exercise trigger and RLS
-- behavior end-to-end and cannot be fully expressed as a single read-only
-- SQL query the way Section 4 is. Where a Section 4 query supports the
-- check, it's referenced by number.
--
-- [ ] Authentication trigger works
--     Sign up a new user via Supabase Auth -> confirm exactly one row each
--     appears in public.users, public.user_settings, public.user_presence
--     with matching id/owner_id/user_id. (See 4.10 for handle_new_auth_user
--     existence; trigger existence itself is in 4.8.)
--
-- [ ] Friend requests work
--     Insert a public.friendships row as requester -> confirm status
--     defaults to 'pending' and only requester_id/addressee_id can select
--     it (friendships_select_participants, Module 7).
--
-- [ ] Friend accept updates both users
--     As the addressee, update the row's status to 'accepted' -> confirm
--     both requester's and addressee's users.friends_count increase by 1
--     (trg_sync_friends_count). Cross-check with 4.3.
--
-- [ ] friends_count stays synchronized
--     Delete an accepted friendships row (unfriend) -> confirm both
--     users.friends_count decrease by 1 and never go below 0. Cross-check
--     with 4.3 after each mutation.
--
-- [ ] Group join/leave updates groups_count
--     Insert a chat_members row (left_at null) on a type='group' chat ->
--     confirm groups_count +1 for that user; set left_at -> confirm -1.
--     Cross-check with 4.4.
--
-- [ ] Direct chat works
--     Create a type='direct' chat with exactly 2 chat_members rows ->
--     confirm both members can select the chat and each other's messages;
--     a third, non-member user cannot. Cross-check with 4.6.
--
-- [ ] Group chat works
--     Create a type='group' chat, add multiple members with roles ->
--     confirm only the admin can update the chat row or other members'
--     rows (chats_update_chat_admins, chat_members_update_admin).
--
-- [ ] Notifications work
--     Insert a notifications row with recipient_id = a real user -> confirm
--     only that recipient can select/update/delete it
--     (notifications_all_owner, Module 7).
--
-- [ ] Realtime events work
--     Subscribe to each table added in Section 2 (users, user_presence,
--     friendships, chats, chat_members, messages, notifications, reports,
--     alert_sounds) -> confirm INSERT/UPDATE/DELETE events arrive with full
--     old-row data on UPDATE/DELETE (REPLICA IDENTITY FULL, Section 2).
--
-- [ ] RLS policies work correctly
--     As an authenticated non-admin user, confirm: cannot read another
--     user's user_settings/notifications/blocked_users; cannot update
--     another user's users row; cannot read admin-only tables
--     (user_ban_history, user_warnings, admin_action_logs). As an admin
--     (app_metadata.is_admin = true), confirm reports/admin tables become
--     readable. Cross-check RLS enablement itself with 4.9.
-- ============================================================================

-- ============================================================================
-- END MODULE 8 — DATABASE RECONSTRUCTION COMPLETE
-- ============================================================================
