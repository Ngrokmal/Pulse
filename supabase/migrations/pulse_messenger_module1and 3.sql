-- ============================================================================
-- MODULE 1 OF N — Pulse Messenger Database Reconstruction
-- Extensions | Enum Types | public.users | public.user_settings |
-- public.user_presence | Indexes | Constraints | on_auth_user_created trigger
--
-- Source of truth: verified STEP 1 report only. No Flutter re-scan performed.
-- Every inferred (non-100%-verified) decision is flagged inline with
-- "-- INFERRED".
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. EXTENSIONS
-- ----------------------------------------------------------------------------

create extension if not exists pgcrypto;   -- gen_random_uuid()
create extension if not exists pg_trgm;    -- reserved for Module (search_users RPC) later; harmless to enable now, idempotent


-- ----------------------------------------------------------------------------
-- 2. CUSTOM ENUM TYPES
-- Postgres has no native "CREATE TYPE IF NOT EXISTS" — guarded via DO blocks
-- so this file is safely re-runnable.
-- ----------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type where typname = 'verification_status_enum') then
    create type public.verification_status_enum as enum ('verified', 'pending', 'notVerified');
  end if;
end$$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'ban_type_enum') then
    create type public.ban_type_enum as enum ('temporary', 'permanent');
  end if;
end$$;

-- Reused across user_settings.profile_privacy / last_seen_visibility /
-- online_status_visibility — all three confirmed to share the exact same
-- three string values ('public','friendsOnly','private') in the Flutter code.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'privacy_option_enum') then
    create type public.privacy_option_enum as enum ('public', 'friendsOnly', 'private');
  end if;
end$$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'friend_request_privacy_enum') then
    create type public.friend_request_privacy_enum as enum ('everyone', 'friendsOfFriends', 'nobody');
  end if;
end$$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'theme_mode_enum') then
    create type public.theme_mode_enum as enum ('system', 'light', 'dark');
  end if;
end$$;


-- ----------------------------------------------------------------------------
-- 3. SHARED UTILITY FUNCTION — auto-advance `updated_at`
--
-- Required for Module 1: the Flutter app's delta-sync logic (profile,
-- presence) filters with `.gt('updated_at', cursor)` and NEVER sends
-- `updated_at` itself on UPDATE — so the database must advance it
-- automatically or every delta sync in the app silently stops working.
-- ----------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;


-- ----------------------------------------------------------------------------
-- 4. TABLE: public.users
-- ----------------------------------------------------------------------------

create table if not exists public.users (
  id                  uuid primary key references auth.users(id) on delete cascade,
  username            text not null,
  display_name        text,
  full_name           text,
  bio                 text,
  location            text,
  gender              text,                                   -- nullable free text, per decision #6
  birthday            date,                                   -- INFERRED: type not confirmed by client, "birthday" assumed DATE
  phone               text,
  email               text not null,                          -- confirmed NOT NULL by code comment
  website             text,
  avatar_url          text,
  avatar_public_id    text,
  cover_url           text,
  cover_public_id     text,
  friends_count       integer not null default 0,
  groups_count        integer not null default 0,
  verification_status public.verification_status_enum not null default 'notVerified',  -- decision #5
  is_banned           boolean not null default false,
  is_disabled         boolean not null default false,
  ban_type            public.ban_type_enum,
  ban_expires_at      timestamptz,
  banned_at           timestamptz,
  disabled_at         timestamptz,
  fcm_token           text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint users_friends_count_nonneg check (friends_count >= 0),
  constraint users_groups_count_nonneg check (groups_count >= 0)
);

comment on table public.users is
  'Core profile row. One row per auth.users row, created automatically by on_auth_user_created.';
comment on column public.users.fcm_token is
  'Current Firebase Cloud Messaging device token. Written client-side by FcmTokenSyncService; read server-side only by the send-push-notification Edge Function via service-role key.';

-- Functional uniqueness on username, case-insensitive — confirmed by code
-- comment ("unique index on lower(username)") and 23505 -> UsernameTakenException mapping.
create unique index if not exists users_username_lower_unique_idx
  on public.users (lower(username));

-- INFERRED: email uniqueness mirrors auth.users.email uniqueness; not
-- explicitly proven by any single Dart query, but a duplicate email would
-- desync from Supabase Auth (which is itself unique on email).
create unique index if not exists users_email_unique_idx
  on public.users (email);

create index if not exists users_updated_at_idx
  on public.users (updated_at);

create index if not exists users_is_banned_idx
  on public.users (is_banned) where is_banned = true;

create index if not exists users_is_disabled_idx
  on public.users (is_disabled) where is_disabled = true;

drop trigger if exists set_updated_at on public.users;
create trigger set_updated_at
  before update on public.users
  for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- 5. TABLE: public.user_settings
-- ----------------------------------------------------------------------------

create table if not exists public.user_settings (
  owner_id                    uuid primary key references public.users(id) on delete cascade,
  notifications_enabled       boolean not null default true,
  profile_privacy             public.privacy_option_enum not null default 'public',
  last_seen_visibility        public.privacy_option_enum not null default 'public',
  online_status_visibility    public.privacy_option_enum not null default 'public',
  friend_request_privacy      public.friend_request_privacy_enum not null default 'everyone',
  theme_mode                  public.theme_mode_enum not null default 'system',
  enter_to_send                boolean not null default true,
  read_receipts_enabled        boolean not null default true,
  typing_indicator_enabled     boolean not null default true,
  auto_download_images         boolean not null default true,
  auto_download_videos         boolean not null default true,
  auto_download_files          boolean not null default true,
  media_wifi_only              boolean not null default false,
  updated_at                   timestamptz not null default now()
);

comment on table public.user_settings is
  'Owner-only settings row. One-to-one with users. Created automatically by on_auth_user_created; never inserted by the client.';

drop trigger if exists set_updated_at on public.user_settings;
create trigger set_updated_at
  before update on public.user_settings
  for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- 6. TABLE: public.user_presence
-- ----------------------------------------------------------------------------

create table if not exists public.user_presence (
  user_id     uuid primary key references public.users(id) on delete cascade,
  is_online   boolean not null default false,
  last_seen   timestamptz,
  updated_at  timestamptz not null default now()
);

comment on table public.user_presence is
  'Readable-by-any-authenticated-user presence row. One-to-one with users. Created automatically by on_auth_user_created; never inserted by the client (client only ever UPDATEs it).';

create index if not exists user_presence_updated_at_idx
  on public.user_presence (updated_at);

drop trigger if exists set_updated_at on public.user_presence;
create trigger set_updated_at
  before update on public.user_presence
  for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- 7. TRIGGER: on_auth_user_created
--
-- Confirmed by multiple code comments to create matching rows in ALL THREE
-- tables above the instant a Supabase Auth signup succeeds. Reads
-- raw_user_meta_data->>'username' / ->>'full_name', matching exactly the
-- signUp(data: {...}) payload sent by AuthRemoteDataSourceImpl.
-- ----------------------------------------------------------------------------

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_username text;
  v_full_name text;
begin
  v_full_name := coalesce(new.raw_user_meta_data->>'full_name', '');

  -- INFERRED fallback: the app always sends 'username' in signUp() metadata
  -- in normal operation, but a NOT NULL column needs a safe default for any
  -- row created without it (e.g. a future OAuth provider) rather than
  -- failing the whole auth.users insert.
  v_username := lower(coalesce(
    nullif(new.raw_user_meta_data->>'username', ''),
    split_part(new.email, '@', 1) || '_' || substr(new.id::text, 1, 8)
  ));

  insert into public.users (id, email, username, full_name, display_name)
  values (new.id, new.email, v_username, v_full_name, v_full_name)
  on conflict (id) do nothing;

  insert into public.user_settings (owner_id)
  values (new.id)
  on conflict (owner_id) do nothing;

  insert into public.user_presence (user_id, is_online, last_seen)
  values (new.id, false, now())
  on conflict (user_id) do nothing;

  return new;
end;
$$;

comment on function public.handle_new_auth_user() is
  'Backs the on_auth_user_created trigger. Provisions public.users / public.user_settings / public.user_presence for every new auth.users row. security definer required: auth.users is owned by supabase_auth_admin, not the invoking role.';

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ============================================================================
-- END MODULE 1
-- ============================================================================

-- ============================================================================
-- MODULE 2 OF N — Pulse Messenger Database Reconstruction
-- Enum Types (messaging) | public.chats | public.chat_members |
-- public.messages | Indexes | Constraints | Triggers
--
-- Depends on: MODULE 1 (public.users, public.set_updated_at()).
-- Source of truth: verified STEP 1 report + your Phase-1 decisions only.
-- No RLS, no notifications, no friendships, no RPCs — as instructed.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ENUM TYPES (messaging domain)
-- ----------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type where typname = 'chat_type_enum') then
    create type public.chat_type_enum as enum ('direct', 'group');
  end if;
end$$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'chat_member_role_enum') then
    create type public.chat_member_role_enum as enum ('admin', 'member');
  end if;
end$$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'message_status_enum') then
    -- Confirmed values only: 'sending'/'failed' are LOCAL-ONLY client states
    -- (Hive), never persisted to Postgres (see statusRank map: sent=0,
    -- delivered=1, read=2). Deliberately excluded from the DB enum.
    create type public.message_status_enum as enum ('sent', 'delivered', 'read');
  end if;
end$$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'message_type_enum') then
    create type public.message_type_enum as enum ('text', 'image', 'video', 'file', 'voice');
  end if;
end$$;


-- ----------------------------------------------------------------------------
-- 2. TABLE: public.chats
-- ----------------------------------------------------------------------------

create table if not exists public.chats (
  id                      uuid primary key default gen_random_uuid(),
  type                    public.chat_type_enum not null,
  name                    text,                                    -- group only
  creator_id              uuid references public.users(id) on delete set null,   -- group only; null for direct chats
  group_photo_url         text,                                    -- group only
  group_photo_public_id   text,                                    -- group only (Cloudinary)
  last_message            text,
  last_message_at         timestamptz,
  last_message_sender_id  uuid references public.users(id) on delete set null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

comment on table public.chats is
  'Both direct (1:1) and group chats live here, distinguished by type. name/creator_id/group_photo_* are only ever populated by the client for type=group rows.';

create index if not exists chats_type_idx
  on public.chats (type);

create index if not exists chats_updated_at_idx
  on public.chats (updated_at);

-- Supports ChatListRemoteDataSourceImpl.fetchChangedDirectChats:
-- .eq('type','direct').gt('updated_at', since)
create index if not exists chats_type_updated_at_idx
  on public.chats (type, updated_at);

drop trigger if exists set_updated_at on public.chats;
create trigger set_updated_at
  before update on public.chats
  for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- 3. TABLE: public.chat_members
-- Composite primary key (chat_id, user_id) — CONFIRMED by explicit code
-- comment ("chat_members' primary key is (chat_id, user_id)") and by the
-- upsert onConflict: 'chat_id,user_id' pattern. No surrogate id column.
-- ----------------------------------------------------------------------------

create table if not exists public.chat_members (
  chat_id           uuid not null references public.chats(id) on delete cascade,
  user_id           uuid not null references public.users(id) on delete cascade,
  role              public.chat_member_role_enum not null default 'member',
  unread_count      integer not null default 0,
  is_typing         boolean not null default false,
  typing_updated_at timestamptz,
  joined_at         timestamptz not null default now(),
  left_at           timestamptz,
  -- updated_at: NOT explicitly confirmed present in the live schema —
  -- GroupDeltaRemoteDataSource defensively falls back to a full snapshot if
  -- Postgrest reports it missing (42703). Added here for schema-wide
  -- consistency and because its presence can only help (the client's
  -- fallback path simply never triggers) — never hurt.
  updated_at        timestamptz not null default now(),           -- INFERRED
  primary key (chat_id, user_id),
  constraint chat_members_unread_count_nonneg check (unread_count >= 0)
);

comment on table public.chat_members is
  'Membership + per-member chat state (role, unread count, typing indicator). left_at is a soft-leave tombstone: NULL = active member. Composite PK (chat_id, user_id) confirmed from client code comments.';

-- Confirmed pattern: "partial indexes built around left_at is null" per
-- is_chat_member()/is_chat_admin() code comments.
create index if not exists chat_members_active_by_chat_idx
  on public.chat_members (chat_id) where left_at is null;

create index if not exists chat_members_active_by_user_idx
  on public.chat_members (user_id) where left_at is null;

create index if not exists chat_members_user_id_idx
  on public.chat_members (user_id);

-- Supports streamTypingUserIds: .eq('chat_id', x).eq('is_typing', true)
create index if not exists chat_members_typing_idx
  on public.chat_members (chat_id) where is_typing = true;

drop trigger if exists set_updated_at on public.chat_members;
create trigger set_updated_at
  before update on public.chat_members
  for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- 4. TABLE: public.messages
-- ----------------------------------------------------------------------------

create table if not exists public.messages (
  id                       uuid primary key,        -- client-generated (uuid v4), NOT server-default
  chat_id                  uuid not null references public.chats(id) on delete cascade,
  sender_id                uuid references public.users(id) on delete cascade,  -- INFERRED: cascade chosen for schema consistency; see Module 2 notes
  text                     text not null default '',
  status                   public.message_status_enum not null default 'sent',
  type                     public.message_type_enum not null default 'text',
  media_url                text,
  thumbnail_url            text,
  file_name                text,
  file_size_bytes          bigint,                   -- INFERRED precision (bigint over int, safe headroom)
  mime_type                text,
  duration_ms              integer,
  width                    integer,
  height                   integer,
  waveform                 double precision[],       -- INFERRED array type for List<double>
  alert_id                 text,
  alert_display_name       text,
  alert_audio_url          text,
  alert_audio_checksum     text,
  alert_audio_format       text,
  alert_audio_size_bytes   bigint,                   -- INFERRED precision
  alert_audio_duration_ms  integer,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  deleted_at               timestamptz,              -- decision #2: EXISTS
  constraint messages_file_size_nonneg check (file_size_bytes is null or file_size_bytes >= 0),
  constraint messages_alert_size_nonneg check (alert_audio_size_bytes is null or alert_audio_size_bytes >= 0)
);

comment on table public.messages is
  'id is client-generated (uuid v4) and sent explicitly on insert — never server-defaulted. status only ever advances sent -> delivered -> read (enforced client-side via statusRank, not by a DB constraint here). deleted_at is a soft-delete tombstone per decision #2; note ChatRemoteDataSourceImpl.deleteMessage() currently performs a HARD delete, so deleted_at is populated only by paths that explicitly choose to soft-delete (e.g. a future trigger/RPC), not by the app''s current deleteMessage() call.';

create index if not exists messages_chat_id_created_at_idx
  on public.messages (chat_id, created_at, id);

-- Supports both direct-chat and group-chat delta sync:
-- .or('created_at.gt.cursor,updated_at.gt.cursor')
create index if not exists messages_chat_id_updated_at_idx
  on public.messages (chat_id, updated_at);

create index if not exists messages_sender_id_idx
  on public.messages (sender_id);

create index if not exists messages_not_deleted_idx
  on public.messages (chat_id, created_at) where deleted_at is null;

drop trigger if exists set_updated_at on public.messages;
create trigger set_updated_at
  before update on public.messages
  for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- 5. TRIGGER: keep users.groups_count in sync -- INFERRED
--
-- Not directly confirmed in the Step 1 report (unlike trg_sync_friends_count,
-- which IS confirmed by name). However users.groups_count is a real,
-- client-read column (admin + profile screens) with no client-side write
-- path anywhere — exactly the same situation friends_count was in before its
-- trigger. Added here for functional parity; safe to remove later if a
-- different mechanism is discovered.
-- ----------------------------------------------------------------------------

create or replace function public.sync_groups_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_chat_type public.chat_type_enum;
  v_old_active boolean;
  v_new_active boolean;
begin
  -- Resolve chat type once (group-chat membership is what counts).
  select type into v_chat_type
  from public.chats
  where id = coalesce(new.chat_id, old.chat_id);

  if v_chat_type is distinct from 'group' then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    if new.left_at is null then
      update public.users set groups_count = groups_count + 1 where id = new.user_id;
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    if old.left_at is null then
      update public.users set groups_count = greatest(groups_count - 1, 0) where id = old.user_id;
    end if;
    return old;
  end if;

  -- UPDATE: only groups_count-relevant when left_at transitions.
  v_old_active := old.left_at is null;
  v_new_active := new.left_at is null;

  if v_old_active and not v_new_active then
    update public.users set groups_count = greatest(groups_count - 1, 0) where id = new.user_id;
  elsif not v_old_active and v_new_active then
    update public.users set groups_count = groups_count + 1 where id = new.user_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sync_groups_count on public.chat_members;
create trigger trg_sync_groups_count
  after insert or update of left_at or delete on public.chat_members
  for each row execute function public.sync_groups_count();

-- ============================================================================
-- END MODULE 2
-- ============================================================================
-- ============================================================================
-- MODULE 3 OF N — Pulse Messenger Database Reconstruction
-- Enum Types (friendship domain) | public.friendships | public.blocked_users |
-- Indexes | Constraints | trg_sync_friends_count | helper functions
--
-- Depends on: MODULE 1 (public.users, public.set_updated_at()).
-- Source of truth: verified STEP 1 report + prior Phase decisions only.
-- No RLS, no notifications, no RPCs unless strictly required — as instructed.
-- Every inferred (non-100%-verified) decision is flagged inline with
-- "-- INFERRED".
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ENUM TYPES (friendship domain)
-- ----------------------------------------------------------------------------

-- INFERRED: Step 1 confirmed the existence of trg_sync_friends_count (by
-- name) and users.friends_count as a client-read column, but did not confirm
-- the exact set of friendship states. 'pending' / 'accepted' / 'declined'
-- is the minimal set that supports: send request -> pending, accept ->
-- accepted (fires the count trigger), reject -> declined. Unfriending an
-- existing 'accepted' row is modeled as a DELETE, not a status transition
-- (see trg_sync_friends_count below), so no 'removed' state is needed.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'friendship_status_enum') then
    create type public.friendship_status_enum as enum ('pending', 'accepted', 'declined');
  end if;
end$$;


-- ----------------------------------------------------------------------------
-- 2. TABLE: public.friendships
--
-- Directional request row (requester_id -> addressee_id), matching the
-- composite-PK-no-surrogate-id style already established for chat_members.
-- A single row represents the relationship regardless of direction once
-- accepted; friendships_unique_pair_idx (below) prevents a mirrored duplicate
-- row (B->A) from ever coexisting with an existing (A->B) row. -- INFERRED
-- ----------------------------------------------------------------------------

create table if not exists public.friendships (
  requester_id  uuid not null references public.users(id) on delete cascade,
  addressee_id  uuid not null references public.users(id) on delete cascade,
  status        public.friendship_status_enum not null default 'pending',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  responded_at  timestamptz,                          -- INFERRED: set when status leaves 'pending'; not confirmed by Step 1
  primary key (requester_id, addressee_id),
  constraint friendships_no_self_friend check (requester_id <> addressee_id)
);

comment on table public.friendships is
  'Directional friend-request row. requester_id sent the request to addressee_id. status starts pending and moves to accepted or declined; an existing accepted friendship is dissolved by DELETing the row (see trg_sync_friends_count), not by a further status transition. friendships_unique_pair_idx guarantees at most one row per unordered user pair.';

comment on column public.friendships.responded_at is
  'INFERRED. Timestamp of the accept/decline action. Not explicitly confirmed by Step 1; safe additive column, populate via application/trigger logic when status leaves pending.';

-- INFERRED: enforce a single relationship row per unordered pair so that a
-- reverse request (B->A) cannot be created while (A->B) already exists.
create unique index if not exists friendships_unique_pair_idx
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

-- Supports "incoming requests" / "my friends where I'm the addressee":
-- .eq('addressee_id', me).eq('status', 'pending'|'accepted')
create index if not exists friendships_addressee_status_idx
  on public.friendships (addressee_id, status);

-- Supports "outgoing requests" / "my friends where I'm the requester":
-- .eq('requester_id', me).eq('status', 'pending'|'accepted')
create index if not exists friendships_requester_status_idx
  on public.friendships (requester_id, status);

create index if not exists friendships_status_idx
  on public.friendships (status);

drop trigger if exists set_updated_at on public.friendships;
create trigger set_updated_at
  before update on public.friendships
  for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- 3. TABLE: public.blocked_users
--
-- Directional, independent of friendships — blocking does not require (or
-- imply removal of) a prior friendship row; that cleanup, if any, is
-- application/RPC logic and out of scope for this module. -- INFERRED
-- ----------------------------------------------------------------------------

create table if not exists public.blocked_users (
  blocker_id  uuid not null references public.users(id) on delete cascade,
  blocked_id  uuid not null references public.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocked_users_no_self_block check (blocker_id <> blocked_id)
);

comment on table public.blocked_users is
  'Directional block: blocker_id has blocked blocked_id. No status/updated_at — a block either exists or is removed (DELETE) by the client. Independent of public.friendships.';

-- Composite PK already indexes (blocker_id, blocked_id) for "did I block X"
-- lookups. This index supports the reverse check ("has X blocked me").
create index if not exists blocked_users_blocked_id_idx
  on public.blocked_users (blocked_id);


-- ----------------------------------------------------------------------------
-- 4. TRIGGER: keep users.friends_count synchronized
--
-- trg_sync_friends_count / sync_friends_count() — name confirmed by Step 1
-- (referenced by name in the Step 1 report / Module 2 notes). Mirrors the
-- shape of sync_groups_count() from Module 2: symmetric +/-1 on both sides
-- of the relationship, floored at 0, driven off status transitions into/out
-- of 'accepted' plus DELETE of an accepted row (unfriend).
-- ----------------------------------------------------------------------------

create or replace function public.sync_friends_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    -- INFERRED: friendships are expected to always be created as 'pending'
    -- by the client, but this branch is included for completeness in case a
    -- row is ever inserted directly as 'accepted'.
    if new.status = 'accepted' then
      update public.users set friends_count = friends_count + 1 where id = new.requester_id;
      update public.users set friends_count = friends_count + 1 where id = new.addressee_id;
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    if old.status = 'accepted' then
      update public.users set friends_count = greatest(friends_count - 1, 0) where id = old.requester_id;
      update public.users set friends_count = greatest(friends_count - 1, 0) where id = old.addressee_id;
    end if;
    return old;
  end if;

  -- UPDATE: only friends_count-relevant when status transitions into or out
  -- of 'accepted'.
  if old.status is distinct from 'accepted' and new.status = 'accepted' then
    update public.users set friends_count = friends_count + 1 where id = new.requester_id;
    update public.users set friends_count = friends_count + 1 where id = new.addressee_id;
  elsif old.status = 'accepted' and new.status is distinct from 'accepted' then
    update public.users set friends_count = greatest(friends_count - 1, 0) where id = new.requester_id;
    update public.users set friends_count = greatest(friends_count - 1, 0) where id = new.addressee_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sync_friends_count on public.friendships;
create trigger trg_sync_friends_count
  after insert or update of status or delete on public.friendships
  for each row execute function public.sync_friends_count();


-- ----------------------------------------------------------------------------
-- 5. HELPER FUNCTIONS required by the friendship system
--
-- Plain SQL functions (not RPCs exposed for client RPC-style calls; these
-- exist to be reused by future triggers/RLS policies so that friendship-pair
-- logic — order-independent lookups — is written once). -- INFERRED
-- ----------------------------------------------------------------------------

create or replace function public.are_users_friends(user_a uuid, user_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.friendships f
    where f.status = 'accepted'
      and (
        (f.requester_id = user_a and f.addressee_id = user_b) or
        (f.requester_id = user_b and f.addressee_id = user_a)
      )
  );
$$;

comment on function public.are_users_friends(uuid, uuid) is
  'INFERRED helper. True if user_a and user_b have an accepted friendship row in either direction.';

create or replace function public.is_user_blocked(p_blocker uuid, p_blocked uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.blocked_users b
    where b.blocker_id = p_blocker
      and b.blocked_id = p_blocked
  );
$$;

comment on function public.is_user_blocked(uuid, uuid) is
  'INFERRED helper. True if p_blocker has blocked p_blocked. Directional — check both argument orders where mutual-block semantics matter.';

-- ============================================================================
-- END MODULE 3
-- ============================================================================
