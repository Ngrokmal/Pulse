-- ============================================================================
-- MODULE 4 OF N — Pulse Messenger Database Reconstruction
-- public.notifications | public.alert_sounds | Indexes | Constraints |
-- updated_at triggers
--
-- Depends on: MODULE 1 (public.users, public.set_updated_at()),
--             MODULE 2 (public.chats, public.messages).
-- Source of truth: verified STEP 1 report + prior Phase decisions only.
-- No RLS, no RPCs, no Edge Functions, no realtime publication, no admin
-- tables — as instructed.
-- Every inferred (non-100%-verified) decision is flagged inline with
-- "-- INFERRED".
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TABLE: public.notifications
-- ----------------------------------------------------------------------------

create table if not exists public.notifications (
  id            uuid primary key default gen_random_uuid(),
  recipient_id  uuid not null references public.users(id) on delete cascade,
  type          text not null,           -- INFERRED: kept free-form text, not enum — exact value set not confirmed by Step 1 (same rationale as users.gender in Module 1)
  title         text,
  body          text,
  data          jsonb not null default '{}'::jsonb,   -- INFERRED default; column itself confirmed
  chat_id       uuid references public.chats(id) on delete cascade,       -- INFERRED on delete behavior; nullable — not every notification is chat-scoped
  message_id    uuid references public.messages(id) on delete cascade,    -- INFERRED on delete behavior; nullable — not every notification is message-scoped
  is_read       boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

comment on table public.notifications is
  'Per-recipient notification feed. deleted_at is a soft-delete tombstone (NULL = visible). type is intentionally free-form text rather than an enum: the Step 1 report confirms the column but not a closed set of values.';

-- Feed fetch: .eq('recipient_id', me).order('created_at', desc)
create index if not exists notifications_recipient_created_at_idx
  on public.notifications (recipient_id, created_at desc);

-- Unread badge count: .eq('recipient_id', me).eq('is_read', false)
create index if not exists notifications_recipient_unread_idx
  on public.notifications (recipient_id) where is_read = false and deleted_at is null;

-- Soft-delete-aware feed fetch
create index if not exists notifications_not_deleted_idx
  on public.notifications (recipient_id, created_at desc) where deleted_at is null;

create index if not exists notifications_chat_id_idx
  on public.notifications (chat_id) where chat_id is not null;

create index if not exists notifications_message_id_idx
  on public.notifications (message_id) where message_id is not null;

drop trigger if exists set_updated_at on public.notifications;
create trigger set_updated_at
  before update on public.notifications
  for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- 2. TABLE: public.alert_sounds
--
-- INFERRED overall shape: messages.alert_id / alert_display_name /
-- alert_audio_url / alert_audio_checksum / alert_audio_format /
-- alert_audio_size_bytes / alert_audio_duration_ms (Module 2) are a
-- denormalized snapshot of a catalog row at send-time, so alert_sounds'
-- columns mirror that naming 1:1. messages.alert_id is `text`, so id is
-- kept `text` here for type parity — no FK is added from messages.alert_id
-- to alert_sounds.id since Module 2 is not being altered and no such FK was
-- confirmed in Step 1.
-- ----------------------------------------------------------------------------

create table if not exists public.alert_sounds (
  id                text primary key,     -- INFERRED type: matches messages.alert_id (text), not uuid
  display_name      text not null,
  audio_url         text not null,
  audio_checksum    text,
  audio_format      text,
  audio_size_bytes  bigint,
  audio_duration_ms integer,
  is_default        boolean not null default false,   -- INFERRED: supports a single "default alert sound" concept
  sort_order        integer not null default 0,        -- INFERRED: ordering for a selection UI
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,          -- INFERRED soft-delete: retiring a sound from the picker without breaking historical messages that reference its id
  constraint alert_sounds_audio_size_nonneg check (audio_size_bytes is null or audio_size_bytes >= 0),
  constraint alert_sounds_audio_duration_nonneg check (audio_duration_ms is null or audio_duration_ms >= 0)
);

comment on table public.alert_sounds is
  'INFERRED catalog table. Columns mirror the alert_* fields denormalized onto public.messages in Module 2. Not independently confirmed beyond that denormalization pattern.';

comment on column public.alert_sounds.is_default is
  'INFERRED. At most one row should be the default — enforced by alert_sounds_single_default_idx below.';

-- INFERRED: only one catalog row may be flagged as the default.
create unique index if not exists alert_sounds_single_default_idx
  on public.alert_sounds (is_default) where is_default = true;

-- INFERRED: prevent duplicate catalog entries pointing at the same audio file.
create unique index if not exists alert_sounds_audio_url_unique_idx
  on public.alert_sounds (audio_url);

-- Selection-picker listing: active sounds in display order.
create index if not exists alert_sounds_active_sort_idx
  on public.alert_sounds (sort_order) where deleted_at is null;

drop trigger if exists set_updated_at on public.alert_sounds;
create trigger set_updated_at
  before update on public.alert_sounds
  for each row execute function public.set_updated_at();

-- ============================================================================
-- END MODULE 4
-- ============================================================================
