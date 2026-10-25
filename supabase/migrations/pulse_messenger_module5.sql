-- ============================================================================
-- MODULE 5 OF N — Pulse Messenger Database Reconstruction
-- public.reports | public.user_ban_history | public.user_warnings |
-- public.admin_action_logs | Indexes | Constraints | Triggers
--
-- Depends on: MODULE 1 (public.users, public.set_updated_at(),
--             public.ban_type_enum).
-- Source of truth: verified STEP 1 report + prior Phase decisions only.
-- No RLS, no RPCs, no Edge Functions, no realtime publication — as
-- instructed.
-- Every inferred (non-100%-verified) decision is flagged inline with
-- "-- INFERRED".
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ENUM TYPES
-- ----------------------------------------------------------------------------

-- Report lifecycle — confirmed set: open / reviewing / resolved.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'report_status_enum') then
    create type public.report_status_enum as enum ('open', 'reviewing', 'resolved');
  end if;
end$$;

-- Ban record lifecycle — confirmed set: active / lifted.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'ban_status_enum') then
    create type public.ban_status_enum as enum ('active', 'lifted');
  end if;
end$$;

-- Note: public.ban_type_enum ('temporary', 'permanent') already exists from
-- Module 1 and is reused as-is below — not redefined here.


-- ----------------------------------------------------------------------------
-- 2. TABLE: public.reports
--
-- target_id is intentionally polymorphic (no foreign key) since it may
-- point at users, messages, or chats depending on target_type — an actual
-- FK would only ever be valid for one of those targets.
-- ----------------------------------------------------------------------------

create table if not exists public.reports (
  id                uuid primary key default gen_random_uuid(),
  reporter_id       uuid references public.users(id) on delete set null,   -- INFERRED on delete behavior: preserve the report as an audit record even if the reporting account is later deleted
  target_type       text not null,        -- INFERRED: kept free-form text (mirrors notifications.type) — exact closed set not reproducible here; enforced at the app layer
  target_id         uuid not null,        -- polymorphic — deliberately NOT a foreign key (see note above)
  reason            text,
  description       text,
  status            public.report_status_enum not null default 'open',
  reviewed_by       uuid references public.users(id) on delete set null,   -- INFERRED: admin who actioned the report
  resolution_notes  text,                 -- INFERRED
  resolved_at       timestamptz,          -- INFERRED
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.reports is
  'Polymorphic user report. target_id has no foreign key by design (target_type determines which table it references); referential integrity for target_id is an application-layer concern.';

comment on column public.reports.target_type is
  'INFERRED as free-form text. The confirmed values used by the Flutter app were not reproducible in this session — enforce the closed set at the application layer (e.g. a CHECK constraint added once the exact values are re-verified).';

create index if not exists reports_status_idx
  on public.reports (status);

create index if not exists reports_target_idx
  on public.reports (target_type, target_id);

create index if not exists reports_reporter_id_idx
  on public.reports (reporter_id);

-- Admin queue: open/reviewing reports ordered by age.
create index if not exists reports_open_created_at_idx
  on public.reports (created_at) where status in ('open', 'reviewing');

drop trigger if exists set_updated_at on public.reports;
create trigger set_updated_at
  before update on public.reports
  for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- 3. TABLE: public.user_ban_history
-- ----------------------------------------------------------------------------

create table if not exists public.user_ban_history (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.users(id) on delete cascade,
  ban_type     public.ban_type_enum not null,
  status       public.ban_status_enum not null default 'active',
  reason       text,
  banned_by    uuid references public.users(id) on delete set null,   -- INFERRED: admin who issued the ban
  lifted_by    uuid references public.users(id) on delete set null,   -- INFERRED: admin who lifted the ban
  banned_at    timestamptz not null default now(),
  expires_at   timestamptz,     -- INFERRED, mirrors users.ban_expires_at from Module 1; null for permanent bans
  lifted_at    timestamptz,     -- INFERRED
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint user_ban_history_temp_requires_expiry
    check (ban_type <> 'temporary' or expires_at is not null),   -- INFERRED consistency rule
  constraint user_ban_history_permanent_no_expiry
    check (ban_type <> 'permanent' or expires_at is null)        -- INFERRED consistency rule
);

comment on table public.user_ban_history is
  'One row per ban action against a user. status active/lifted tracks whether the ban currently applies; users.is_banned / ban_type / ban_expires_at (Module 1) remain the source of truth for enforcement — this table is the historical record.';

create index if not exists user_ban_history_user_id_idx
  on public.user_ban_history (user_id);

create index if not exists user_ban_history_active_idx
  on public.user_ban_history (user_id) where status = 'active';

create index if not exists user_ban_history_created_at_idx
  on public.user_ban_history (created_at);

drop trigger if exists set_updated_at on public.user_ban_history;
create trigger set_updated_at
  before update on public.user_ban_history
  for each row execute function public.set_updated_at();


-- ----------------------------------------------------------------------------
-- 4. TABLE: public.user_warnings
--
-- One row per warning action. Immutable history — no updated_at column and
-- no set_updated_at trigger, by design (there is nothing on a warning that
-- should ever change after issuance).
-- ----------------------------------------------------------------------------

create table if not exists public.user_warnings (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users(id) on delete cascade,
  reason      text,
  issued_by   uuid references public.users(id) on delete set null,   -- INFERRED: admin who issued the warning
  created_at  timestamptz not null default now()
);

comment on table public.user_warnings is
  'Immutable per-action warning record. No updated_at column by design — a warning is never edited after issuance, only ever inserted.';

create index if not exists user_warnings_user_id_idx
  on public.user_warnings (user_id);

create index if not exists user_warnings_created_at_idx
  on public.user_warnings (created_at);


-- ----------------------------------------------------------------------------
-- 5. TABLE: public.admin_action_logs
--
-- Immutable audit log. admin_id/target_id are nullable with on delete set
-- null so the log entry itself survives deletion of the actor or a
-- polymorphic target row. target_id has no foreign key for the same
-- polymorphism reason as public.reports.target_id.
-- ----------------------------------------------------------------------------

create table if not exists public.admin_action_logs (
  id           uuid primary key default gen_random_uuid(),
  admin_id     uuid references public.users(id) on delete set null,   -- INFERRED: nullable so the audit row outlives the admin account
  action_type  text not null,       -- INFERRED: free-form text, exact closed set not reproducible here
  target_type  text,                -- INFERRED: polymorphic, mirrors public.reports.target_type
  target_id    uuid,                -- polymorphic — deliberately NOT a foreign key (see note above)
  details      jsonb not null default '{}'::jsonb,   -- INFERRED
  created_at   timestamptz not null default now()
);

comment on table public.admin_action_logs is
  'Immutable audit trail of admin actions. No updated_at column, and mutation is blocked at the database level by trg_admin_action_logs_immutable below — rows may only ever be inserted, never updated or deleted through normal access.';

comment on column public.admin_action_logs.target_id is
  'Polymorphic — no foreign key by design (target_type determines which table it references), matching public.reports.target_id.';

create index if not exists admin_action_logs_admin_id_idx
  on public.admin_action_logs (admin_id);

create index if not exists admin_action_logs_created_at_idx
  on public.admin_action_logs (created_at);

create index if not exists admin_action_logs_target_idx
  on public.admin_action_logs (target_type, target_id) where target_id is not null;

-- INFERRED: database-level enforcement of "immutable, never updated after
-- insert" — not explicitly requested as a mechanism, but implements the
-- stated requirement rather than relying on convention alone.
create or replace function public.prevent_admin_action_logs_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'public.admin_action_logs is append-only: % is not permitted', tg_op;
end;
$$;

drop trigger if exists trg_admin_action_logs_no_update on public.admin_action_logs;
create trigger trg_admin_action_logs_no_update
  before update or delete on public.admin_action_logs
  for each row execute function public.prevent_admin_action_logs_mutation();

-- ============================================================================
-- END MODULE 5
-- ============================================================================
