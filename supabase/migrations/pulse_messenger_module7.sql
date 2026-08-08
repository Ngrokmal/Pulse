-- ============================================================================
-- MODULE 7 OF N — Pulse Messenger Database Reconstruction
-- Row Level Security | Policies | Security & Permission Helper Functions
--
-- Depends on: MODULE 1 (public.users, public.user_settings,
--             public.user_presence), MODULE 2 (public.chats,
--             public.chat_members, public.messages), MODULE 3
--             (public.friendships, public.blocked_users), MODULE 4
--             (public.notifications, public.alert_sounds), MODULE 5
--             (public.reports, public.user_ban_history,
--             public.user_warnings, public.admin_action_logs).
--
-- DISCLOSURE: is_admin() has no confirmed schema backing — no admin/role
-- column or table exists anywhere in Modules 1-5, and this module is not
-- permitted to redesign the schema (e.g. by adding a users.is_admin
-- column). It is implemented against a Supabase JWT app_metadata claim
-- instead — see the function below. Flag this for re-verification against
-- the real Step 1 report if an actual admin mechanism turns up.
--
-- Recursive-evaluation avoidance: is_chat_member() / is_chat_admin() are
-- SECURITY DEFINER, so when a chat_members (or chats) policy calls them,
-- the internal lookup against chat_members runs as the function owner and
-- is not itself subject to the calling policy — this is what prevents the
-- chat_members SELECT policy from recursing into itself.
--
-- No RPCs, no Edge Functions, no realtime publication — as instructed.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. SECURITY / PERMISSION HELPER FUNCTIONS
-- ----------------------------------------------------------------------------

-- INFERRED: no admin flag/table exists in the confirmed schema. Backed by
-- the Supabase-standard pattern of a boolean claim in the JWT's
-- app_metadata (settable only by service-role / the Supabase Admin API,
-- never by the user themselves), rather than adding a column.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (auth.jwt() -> 'app_metadata' ->> 'is_admin')::boolean,
    false
  );
$$;

comment on function public.is_admin() is
  'INFERRED. No admin column/table is confirmed anywhere in Modules 1-5. Checks the boolean app_metadata.is_admin claim on the caller''s JWT instead, since app_metadata can only be set by a service-role/admin API call, never by the user. Re-verify against the real Step 1 report if an actual admin mechanism (e.g. a role table) is later recovered.';

create or replace function public.is_chat_member(p_chat_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.chat_members cm
    where cm.chat_id = p_chat_id
      and cm.user_id = auth.uid()
      and cm.left_at is null
  );
$$;

comment on function public.is_chat_member(uuid) is
  'True if the caller is an active (left_at is null) member of p_chat_id. SECURITY DEFINER so policies on public.chat_members can call this without recursively re-evaluating themselves.';

create or replace function public.is_chat_admin(p_chat_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.chat_members cm
    where cm.chat_id = p_chat_id
      and cm.user_id = auth.uid()
      and cm.left_at is null
      and cm.role = 'admin'
  );
$$;

comment on function public.is_chat_admin(uuid) is
  'True if the caller is an active member of p_chat_id with role = admin. SECURITY DEFINER for the same recursion-avoidance reason as is_chat_member().';


-- ----------------------------------------------------------------------------
-- 2. ENABLE ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------

alter table public.users             enable row level security;
alter table public.user_settings     enable row level security;
alter table public.user_presence     enable row level security;
alter table public.chats             enable row level security;
alter table public.chat_members      enable row level security;
alter table public.messages          enable row level security;
alter table public.friendships       enable row level security;
alter table public.blocked_users     enable row level security;
alter table public.notifications     enable row level security;
alter table public.reports           enable row level security;
alter table public.user_ban_history  enable row level security;
alter table public.user_warnings     enable row level security;
alter table public.admin_action_logs enable row level security;
alter table public.alert_sounds      enable row level security;


-- ----------------------------------------------------------------------------
-- 3. POLICIES: public.users
--
-- Row-level only: this cannot redact individual columns (e.g. email,
-- phone, fcm_token) from the "public profile" read policy — true field-
-- level redaction would require a view or column privileges, which is a
-- schema addition out of scope for this module. -- INFERRED caveat
-- No INSERT policy: rows are created only by handle_new_auth_user()
-- (SECURITY DEFINER, Module 1), which bypasses RLS as table owner.
-- No DELETE policy: not specified by the rules; denied by default.
-- ----------------------------------------------------------------------------

drop policy if exists users_select_authenticated on public.users;
create policy users_select_authenticated
  on public.users
  for select
  to authenticated
  using (true);

drop policy if exists users_update_own on public.users;
create policy users_update_own
  on public.users
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());


-- ----------------------------------------------------------------------------
-- 4. POLICIES: public.user_settings — owner only
-- No INSERT/DELETE policy: rows are created only by
-- handle_new_auth_user() (SECURITY DEFINER); not specified for client use.
-- ----------------------------------------------------------------------------

drop policy if exists user_settings_select_own on public.user_settings;
create policy user_settings_select_own
  on public.user_settings
  for select
  to authenticated
  using (owner_id = auth.uid());

drop policy if exists user_settings_update_own on public.user_settings;
create policy user_settings_update_own
  on public.user_settings
  for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());


-- ----------------------------------------------------------------------------
-- 5. POLICIES: public.user_presence
-- Read: any authenticated user. Write: owner only.
-- No INSERT/DELETE policy: rows are created only by
-- handle_new_auth_user() (SECURITY DEFINER).
-- ----------------------------------------------------------------------------

drop policy if exists user_presence_select_authenticated on public.user_presence;
create policy user_presence_select_authenticated
  on public.user_presence
  for select
  to authenticated
  using (true);

drop policy if exists user_presence_update_own on public.user_presence;
create policy user_presence_update_own
  on public.user_presence
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());


-- ----------------------------------------------------------------------------
-- 6. POLICIES: public.chats
-- INSERT check is INFERRED: allows a caller to create a chat where they are
-- either the group creator, or creator_id is null (the direct-chat shape
-- from Module 2). UPDATE policy (chat admins only) is INFERRED and added
-- because leaving it unspecified would deny group rename/photo updates
-- entirely once RLS is enabled. No DELETE policy: not specified; denied.
-- ----------------------------------------------------------------------------

drop policy if exists chats_select_active_members on public.chats;
create policy chats_select_active_members
  on public.chats
  for select
  to authenticated
  using (public.is_chat_member(id));

drop policy if exists chats_insert_authorized on public.chats;
create policy chats_insert_authorized
  on public.chats
  for insert
  to authenticated
  with check (creator_id is null or creator_id = auth.uid());   -- INFERRED

drop policy if exists chats_update_chat_admins on public.chats;
create policy chats_update_chat_admins                          -- INFERRED
  on public.chats
  for update
  to authenticated
  using (public.is_chat_admin(id))
  with check (public.is_chat_admin(id));


-- ----------------------------------------------------------------------------
-- 7. POLICIES: public.chat_members
-- Not individually itemized in the Module 7 rules, but required since the
-- table is in the "create policies for" list. INSERT/UPDATE shapes are
-- INFERRED: self-insert covers a creator adding their own first membership
-- row (avoids a chicken-and-egg problem with is_chat_admin() on a chat
-- that doesn't have any members yet); admin-insert/update covers adding or
-- managing other members. No DELETE policy: membership ends via the
-- left_at soft-leave column (Module 2), not row deletion.
-- ----------------------------------------------------------------------------

drop policy if exists chat_members_select_fellow_members on public.chat_members;
create policy chat_members_select_fellow_members
  on public.chat_members
  for select
  to authenticated
  using (public.is_chat_member(chat_id));

drop policy if exists chat_members_insert_self_or_admin on public.chat_members;
create policy chat_members_insert_self_or_admin                 -- INFERRED
  on public.chat_members
  for insert
  to authenticated
  with check (user_id = auth.uid() or public.is_chat_admin(chat_id));

drop policy if exists chat_members_update_own on public.chat_members;
create policy chat_members_update_own                           -- INFERRED
  on public.chat_members
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists chat_members_update_admin on public.chat_members;
create policy chat_members_update_admin                         -- INFERRED
  on public.chat_members
  for update
  to authenticated
  using (public.is_chat_admin(chat_id))
  with check (public.is_chat_admin(chat_id));


-- ----------------------------------------------------------------------------
-- 8. POLICIES: public.messages
-- UPDATE/DELETE restricted to sender only, exactly as specified. Note: this
-- means recipient-side state (delivered/read receipts) cannot be written
-- directly onto a message row by the recipient under this policy set — the
-- existing schema's per-member state lives on chat_members instead
-- (unread_count), which is updated via its own owner policy above; a
-- dedicated status-transition path, if the app needs one, is an RPC and
-- explicitly out of scope for this module. -- INFERRED reasoning only, the
-- sender-only rule itself is exactly as specified.
-- ----------------------------------------------------------------------------

drop policy if exists messages_select_chat_members on public.messages;
create policy messages_select_chat_members
  on public.messages
  for select
  to authenticated
  using (public.is_chat_member(chat_id));

drop policy if exists messages_insert_chat_members on public.messages;
create policy messages_insert_chat_members
  on public.messages
  for insert
  to authenticated
  with check (public.is_chat_member(chat_id) and sender_id = auth.uid());

drop policy if exists messages_update_sender_only on public.messages;
create policy messages_update_sender_only
  on public.messages
  for update
  to authenticated
  using (sender_id = auth.uid())
  with check (sender_id = auth.uid());

drop policy if exists messages_delete_sender_only on public.messages;
create policy messages_delete_sender_only
  on public.messages
  for delete
  to authenticated
  using (sender_id = auth.uid());


-- ----------------------------------------------------------------------------
-- 9. POLICIES: public.friendships
-- ----------------------------------------------------------------------------

drop policy if exists friendships_select_participants on public.friendships;
create policy friendships_select_participants
  on public.friendships
  for select
  to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

drop policy if exists friendships_insert_requester on public.friendships;
create policy friendships_insert_requester
  on public.friendships
  for insert
  to authenticated
  with check (requester_id = auth.uid());

drop policy if exists friendships_update_addressee_only on public.friendships;
create policy friendships_update_addressee_only
  on public.friendships
  for update
  to authenticated
  using (addressee_id = auth.uid())
  with check (addressee_id = auth.uid());

drop policy if exists friendships_delete_participants on public.friendships;
create policy friendships_delete_participants
  on public.friendships
  for delete
  to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());


-- ----------------------------------------------------------------------------
-- 10. POLICIES: public.blocked_users — owner (blocker) only
-- The blocked party has no visibility into rows where they are blocked_id,
-- consistent with "owner only".
-- ----------------------------------------------------------------------------

drop policy if exists blocked_users_all_owner on public.blocked_users;
create policy blocked_users_all_owner
  on public.blocked_users
  for all
  to authenticated
  using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid());


-- ----------------------------------------------------------------------------
-- 11. POLICIES: public.notifications — owner (recipient) only
-- INSERT is scoped to recipient_id = auth.uid() for defense-in-depth
-- (a user may only ever create a notification addressed to themselves via
-- this path); server-side creation of notifications for other users is
-- expected to go through a SECURITY DEFINER path (e.g. a future RPC or
-- trigger), which bypasses RLS as table owner regardless of this policy.
-- -- INFERRED
-- ----------------------------------------------------------------------------

drop policy if exists notifications_all_owner on public.notifications;
create policy notifications_all_owner
  on public.notifications
  for all
  to authenticated
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());


-- ----------------------------------------------------------------------------
-- 12. POLICIES: public.reports
-- UPDATE (admin only) is INFERRED and added because the report lifecycle
-- (open/reviewing/resolved, Module 5) has no path to progress under RLS
-- without it. No DELETE policy: not specified; denied by default.
-- ----------------------------------------------------------------------------

drop policy if exists reports_insert_authenticated on public.reports;
create policy reports_insert_authenticated
  on public.reports
  for insert
  to authenticated
  with check (reporter_id = auth.uid());

drop policy if exists reports_select_own on public.reports;
create policy reports_select_own
  on public.reports
  for select
  to authenticated
  using (reporter_id = auth.uid());

drop policy if exists reports_select_admin on public.reports;
create policy reports_select_admin
  on public.reports
  for select
  to authenticated
  using (public.is_admin());

drop policy if exists reports_update_admin on public.reports;
create policy reports_update_admin                              -- INFERRED
  on public.reports
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());


-- ----------------------------------------------------------------------------
-- 13. POLICIES: admin-only tables
-- public.user_ban_history / public.user_warnings / public.admin_action_logs.
-- admin_action_logs additionally has a database-level trigger (Module 5,
-- trg_admin_action_logs_no_update) blocking UPDATE/DELETE outright even for
-- admins — this policy governs SELECT/INSERT visibility, the trigger
-- remains the enforcement of "immutable, never updated after insert."
-- ----------------------------------------------------------------------------

drop policy if exists user_ban_history_all_admin on public.user_ban_history;
create policy user_ban_history_all_admin
  on public.user_ban_history
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists user_warnings_all_admin on public.user_warnings;
create policy user_warnings_all_admin
  on public.user_warnings
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists admin_action_logs_all_admin on public.admin_action_logs;
create policy admin_action_logs_all_admin
  on public.admin_action_logs
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());


-- ----------------------------------------------------------------------------
-- 14. POLICIES: public.alert_sounds
--
-- CONFLICT NOTE -- INFERRED RESOLUTION: the rule as given ("Alert Sounds:
-- Owner only") assumes a per-user ownership concept, but public.alert_sounds
-- (Module 4) has no owner_id/created_by column — it was built as a shared
-- catalog referenced by public.messages.alert_id, and adding an ownership
-- column now would be a schema redesign, which this module is not
-- permitted to do. Resolved as: the catalog is readable by any
-- authenticated user (required for every user to be able to pick/display
-- an alert sound), and "owner" is treated as the catalog's admin owner —
-- i.e. only admins may write to it. Flag for re-verification if a real
-- per-user alert_sounds ownership model is recovered from Step 1.
-- ----------------------------------------------------------------------------

drop policy if exists alert_sounds_select_authenticated on public.alert_sounds;
create policy alert_sounds_select_authenticated                 -- INFERRED
  on public.alert_sounds
  for select
  to authenticated
  using (true);

drop policy if exists alert_sounds_write_admin on public.alert_sounds;
create policy alert_sounds_write_admin                          -- INFERRED
  on public.alert_sounds
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ============================================================================
-- END MODULE 7
-- ============================================================================
