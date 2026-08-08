-- ============================================================================
-- MIGRATION 0022 — Friend Alert Sounds: reconcile public.alert_sounds with
-- the Flutter client's per-user/per-friend schema.
--
-- SCOPE: database schema only. No Edge Function, FCM, notification,
-- receiver, Hive, download, or chat-flow changes are made or implied by
-- this migration.
--
-- WHY THIS MIGRATION EXISTS
-- public.alert_sounds (created in pulse_messenger_module4.sql) is a global
-- admin catalog: id/display_name/audio_url/audio_checksum/audio_format/
-- audio_size_bytes/audio_duration_ms/is_default/sort_order/created_at/
-- updated_at/deleted_at. It has no owner_id, friend_id, scope, or alert_key.
--
-- lib/features/custom_alert/data/models/friend_alert_sound_model.dart,
-- method toSupabaseRow() (lines 95-109), builds and sends this row on every
-- create/rename/replace:
--   { owner_id, friend_id, scope, alert_key, display_name, audio_url,
--     checksum, format, file_size_bytes, duration_ms, cloudinary_public_id }
--
-- lib/features/custom_alert/data/datasources/alert_sound_remote_data_source.dart,
-- method saveSound() (line 99):
--   supabase.from('alert_sounds').upsert(row, onConflict: 'owner_id,alert_key')
--
-- Every one of owner_id, friend_id, scope, alert_key, checksum, format,
-- file_size_bytes, duration_ms, cloudinary_public_id is therefore REQUIRED
-- by already-shipped, unmodified Flutter code. This migration adds exactly
-- those columns, by those exact names, and nothing else. display_name and
-- audio_url already exist under the same names Flutter uses, so they are
-- left untouched.
--
-- BACKWARD COMPATIBILITY
-- The 3 admin catalog rows seeded in pulse_messenger_module8.sql (line 287)
-- have no owner_id/friend_id/scope/alert_key. Every new column below is
-- added NULLable with no default other than `id`, so those existing rows
-- remain valid without modification, and the existing admin-only write
-- policy continues to protect them. Nothing in Modules 1-8 is altered.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. NEW COLUMNS
--
-- All added NULLable (no NOT NULL) specifically so the 3 pre-existing
-- catalog rows (owner_id/friend_id/scope/alert_key = NULL for all of them)
-- remain valid with zero backfill required.
-- ----------------------------------------------------------------------------

alter table public.alert_sounds
  add column if not exists owner_id            uuid references public.users(id) on delete cascade,
  add column if not exists friend_id           uuid references public.users(id) on delete cascade,
  add column if not exists scope               text,
  add column if not exists alert_key           text,
  add column if not exists checksum            text,
  add column if not exists format              text,
  add column if not exists file_size_bytes     bigint,
  add column if not exists duration_ms         integer,
  add column if not exists cloudinary_public_id text;

comment on column public.alert_sounds.owner_id is
  'Supabase uuid of the user who created this Friend Alert Sound. NULL for the pre-existing global admin catalog rows (module4/module8) — those remain admin-managed, not owned by any single user. Written by FriendAlertSoundModel.toSupabaseRow() (owner_id).';
comment on column public.alert_sounds.friend_id is
  'Supabase uuid of the specific friend this sound applies to. NULL when scope = ''global'' (applies to all of owner_id''s friends) or for legacy catalog rows. Written by FriendAlertSoundModel.toSupabaseRow() (friend_id).';
comment on column public.alert_sounds.scope is
  '''global'' or ''friend'' — see friend_alert_sound_entity.dart FriendAlertSoundScope. NULL for legacy catalog rows, which predate this concept.';
comment on column public.alert_sounds.alert_key is
  'Client-generated stable id for a Friend Alert Sound (see FriendAlertSoundRepositoryImpl._generateAlertId), distinct from this table''s own `id` PK. Target column of the (owner_id, alert_key) upsert conflict key used by AlertSoundRemoteDataSourceImpl.saveSound().';
comment on column public.alert_sounds.checksum is
  'sha256 of the audio bytes, computed client-side (FriendAlertSoundRepositoryImpl.createSound). Distinct column from the pre-existing audio_checksum, which belongs to the unrelated admin catalog row shape and is left untouched.';
comment on column public.alert_sounds.format is
  'Audio file extension, e.g. m4a. Distinct column from the pre-existing audio_format for the same reason as checksum above.';
comment on column public.alert_sounds.file_size_bytes is
  'Distinct column from the pre-existing audio_size_bytes, same reasoning.';
comment on column public.alert_sounds.duration_ms is
  'Distinct column from the pre-existing audio_duration_ms, same reasoning.';
comment on column public.alert_sounds.cloudinary_public_id is
  'Cloudinary public_id, used by FriendAlertSoundRepositoryImpl to delete the asset on replace/delete. Never previously stored anywhere in this table.';


-- ----------------------------------------------------------------------------
-- 2. DEFAULT FOR id ON NEW ROWS
--
-- alert_sounds.id is `text primary key` with NO default (module4.sql:75).
-- FriendAlertSoundModel.toSupabaseRow() (data/models/friend_alert_sound_model.dart,
-- lines 95-109) never includes an `id` key in the row it sends — the model
-- treats `alert_key` as its identity, not `id`. Without a default, every
-- insert from this feature would fail on the `id` NOT NULL constraint
-- regardless of the (owner_id, alert_key) fix. pgcrypto is already enabled
-- (pulse_messenger_module1and 3.sql:15), so gen_random_uuid() is available;
-- cast to text to match the column's existing type (not changed, to avoid
-- touching the admin catalog's existing `id` values or the FK-parity
-- rationale documented in module4.sql for keeping id as text).
-- ----------------------------------------------------------------------------

alter table public.alert_sounds
  alter column id set default gen_random_uuid()::text;


-- ----------------------------------------------------------------------------
-- 3. CHECK CONSTRAINT ON scope
--
-- Mirrors FriendAlertSoundScope (global | friendSpecific -> 'global' | 'friend'
-- per friend_alert_sound_model.dart line 63/86). Allows NULL so legacy
-- catalog rows are unaffected.
-- ----------------------------------------------------------------------------

alter table public.alert_sounds
  add constraint alert_sounds_scope_check
  check (scope is null or scope in ('global', 'friend'));


-- ----------------------------------------------------------------------------
-- 4. UNIQUE CONSTRAINT REQUIRED BY upsert(onConflict: 'owner_id,alert_key')
--
-- alert_sound_remote_data_source.dart:99 —
--   supabase.from('alert_sounds').upsert(row, onConflict: 'owner_id,alert_key')
-- PostgREST/Postgres requires an actual unique constraint or unique index
-- on exactly these columns for ON CONFLICT to resolve; this is the direct
-- cause of the HTTP 400 (PGRST204 / "no unique or exclusion constraint
-- matching the ON CONFLICT specification").
--
-- Standard SQL NULL semantics mean rows with owner_id IS NULL (the legacy
-- catalog rows) never collide with each other or with real per-user rows
-- under this constraint, so no backfill or legacy-data change is needed.
-- ----------------------------------------------------------------------------

alter table public.alert_sounds
  add constraint alert_sounds_owner_id_alert_key_unique unique (owner_id, alert_key);


-- ----------------------------------------------------------------------------
-- 5. SUPPORTING INDEXES
--
-- Match the read patterns actually issued by AlertSoundRemoteDataSourceImpl:
--   getGlobalSounds:    .eq('owner_id', ownerId).eq('scope', 'global')
--   getFriendSounds:    .eq('owner_id', ownerId).eq('scope','friend').eq('friend_id', friendId)
--   fetchChangedSounds: .eq('owner_id', ownerId).gt('updated_at', since).order('updated_at')
-- ----------------------------------------------------------------------------

create index if not exists alert_sounds_owner_scope_idx
  on public.alert_sounds (owner_id, scope);

create index if not exists alert_sounds_owner_friend_idx
  on public.alert_sounds (owner_id, friend_id)
  where friend_id is not null;

create index if not exists alert_sounds_owner_updated_at_idx
  on public.alert_sounds (owner_id, updated_at);


-- ----------------------------------------------------------------------------
-- 6. RLS — add per-user policies alongside the existing ones
--
-- Existing policies (pulse_messenger_module7.sql:456-466), UNTOUCHED:
--   alert_sounds_select_authenticated : SELECT, to authenticated, using (true)
--   alert_sounds_write_admin          : ALL,    to authenticated, using/check (is_admin())
--
-- Per the task's "preserve compatibility with existing data" requirement,
-- alert_sounds_select_authenticated is intentionally left as-is (using
-- (true)) rather than narrowed — narrowing it risks breaking any existing
-- caller (Flutter or otherwise) that currently relies on reading every row,
-- and the task does not ask for read-visibility changes, only for the
-- schema/constraint mismatch causing the 400 to be fixed. Owner-scoped
-- filtering for Friend Alert Sounds is already done client-side via
-- .eq('owner_id', ownerId) in every read call listed above.
--
-- What IS added: alert_sounds_write_admin was ALL/is_admin()-only, which
-- would silently reject every ordinary user's INSERT/UPDATE — the exact
-- privilege gap that made this feature admin-catalog-only. A new
-- owner-scoped write policy is added so a user can write only their own
-- (owner_id = auth.uid()) rows; it cannot reach legacy catalog rows
-- (owner_id IS NULL never matches auth.uid()), so alert_sounds_write_admin's
-- protection of those rows is unchanged.
-- ----------------------------------------------------------------------------

drop policy if exists alert_sounds_owner_write on public.alert_sounds;
create policy alert_sounds_owner_write
  on public.alert_sounds
  for all
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());


-- ----------------------------------------------------------------------------
-- 7. updated_at TRIGGER
--
-- Already exists on this table (module4.sql:109-111, function
-- public.set_updated_at()) and is untouched — new columns are covered by
-- the same row-level trigger automatically. Nothing to add here.
-- ----------------------------------------------------------------------------

-- (intentionally no-op section — documented for completeness)

-- ============================================================================
-- END MIGRATION 0022
-- ============================================================================
