-- ============================================================================
-- 0023_call_sessions_and_events.sql
--
-- MILESTONE 4 PART A — Call module backend: schema, RLS, busy-race
-- handling, Realtime publication. Companion Edge Function
-- (supabase/functions/generate-agora-token) covers Agora token
-- mint/renewal; not part of this SQL file.
--
-- SOURCE OF TRUTH: this migration is written strictly against the already-
-- shipped, unmodified data layer from the previous milestones —
--   lib/features/call/data/dto/call_session_dto.dart
--   lib/features/call/data/models/call_event_model.dart
--   lib/features/call/domain/entities/call_status.dart
--   lib/features/call/domain/entities/call_type.dart
--   lib/features/call/domain/entities/call_event_type.dart
--   lib/features/call/data/datasources/call_remote_datasource_impl.dart
--   lib/features/call/data/datasources/call_realtime_datasource_impl.dart
--   lib/features/call/data/repositories/call_repository_impl.dart
-- Every column name, enum value, and RLS-relevant read/write pattern below
-- traces back to one of those files — no new columns/values are invented
-- beyond what that code already sends/expects on the wire.
--
-- Depends on: MODULE 1 (public.users, public.set_updated_at(),
-- pgcrypto), MODULE 8 (supabase_realtime publication already created).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. ENUM TYPES
--
-- Member names used verbatim as the wire value in every DTO above (Dart
-- enum `.name` — e.g. CallType.video.name == 'video'), so these must match
-- exactly, letter-for-letter, including case.
-- ----------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type where typname = 'call_type_enum') then
    create type public.call_type_enum as enum ('audio', 'video');
  end if;
end$$;

-- CallStatus enum (call_status.dart): ringing, accepted, declined,
-- cancelled, missed, busy, ended.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'call_status_enum') then
    create type public.call_status_enum as enum
      ('ringing', 'accepted', 'declined', 'cancelled', 'missed', 'busy', 'ended');
  end if;
end$$;

-- CallEventType enum (call_event_type.dart): rang, accepted, declined,
-- cancelled, missed, busy, ended. Note this is a DIFFERENT set from
-- call_status_enum (it has 'rang' where call_status_enum has 'ringing') —
-- kept as its own type rather than reusing call_status_enum, matching the
-- domain layer's explicit separation of the two.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'call_event_type_enum') then
    create type public.call_event_type_enum as enum
      ('rang', 'accepted', 'declined', 'cancelled', 'missed', 'busy', 'ended');
  end if;
end$$;


-- ----------------------------------------------------------------------------
-- 2. TABLE: public.call_sessions
--
-- Column-for-column against CallSessionDto.fromJson/toJson
-- (call_session_dto.dart) — every field there has an exact-name column
-- here, no more, no less. agora_uid_caller/agora_uid_callee are `integer`
-- (not bigint): CallRepositoryImpl.agoraUidFromUserId masks its FNV-1a
-- hash into `hash & 0x7FFFFFFF`, i.e. 0..2147483647, which is exactly
-- Postgres `integer`'s positive range — no overflow risk.
-- ----------------------------------------------------------------------------

create table if not exists public.call_sessions (
  id                  uuid primary key default gen_random_uuid(),
  caller_id           uuid not null references public.users(id) on delete cascade,
  callee_id           uuid not null references public.users(id) on delete cascade,
  channel_name        text not null,
  call_type           public.call_type_enum not null,
  status              public.call_status_enum not null default 'ringing',
  created_at          timestamptz not null default now(),
  ringing_started_at  timestamptz not null default now(),
  accepted_at         timestamptz,
  ended_at            timestamptz,
  end_reason          text,
  agora_uid_caller    integer not null,
  agora_uid_callee    integer not null,
  constraint call_sessions_no_self_call check (caller_id <> callee_id),
  constraint call_sessions_channel_name_not_blank check (length(trim(channel_name)) > 0)
);

comment on table public.call_sessions is
  'One row per 1:1 audio/video call attempt (Milestone 4 Part A). Written by CallRemoteDataSourceImpl.createCallSession (insert) / updateCallStatus (update) — see call_repository_impl.dart for the full caller/callee-driven status-transition contract. Read via CallRealtimeDataSourceImpl''s two Postgres Changes subscriptions (insert-filtered-by-callee_id for incoming calls, update-filtered-by-id for status changes) plus plain select for getCallHistory.';
comment on column public.call_sessions.channel_name is
  'Agora channel name, client-generated as ''call_<uuid>'' (CallRepositoryImpl.createCall). Also passed to generate-agora-token and cross-checked there against this row.';
comment on column public.call_sessions.ringing_started_at is
  'Set once at insert (default now()), never updated — distinct from created_at only in that a future schema revision could theoretically re-ring an existing row; current client code never does that, so today the two are always equal. Kept as its own column because CallSessionDto already models it as such.';
comment on column public.call_sessions.end_reason is
  'Free-text reason set by CallRemoteDataSourceImpl.updateCallStatus alongside a terminal status: ''declined_by_callee'' | ''callee_busy'' | ''cancelled_by_caller'' | ''timeout'' | caller-supplied endCall reason (default ''ended''). Not an enum: EndCallUseCase''s endReason is caller-supplied free text (see CallCubit.endCall), so a closed set would reject legitimate values.';
comment on column public.call_sessions.agora_uid_caller is
  'Deterministic numeric Agora uid for caller_id on this call, computed client-side by CallRepositoryImpl.agoraUidFromUserId and sent as part of the insert (not server-derived) — generate-agora-token re-validates the requested uid against this column rather than trusting the request body alone.';
comment on column public.call_sessions.agora_uid_callee is
  'Same as agora_uid_caller, for callee_id.';

-- Supports CallRealtimeDataSourceImpl.subscribeToIncomingCalls' underlying
-- row shape (`.eq('callee_id', userId)` + status='ringing' filtered
-- client-side on the realtime payload) and any future non-realtime
-- "do I have a ringing call" query.
create index if not exists call_sessions_callee_status_idx
  on public.call_sessions (callee_id, status);

create index if not exists call_sessions_caller_status_idx
  on public.call_sessions (caller_id, status);

-- Supports CallRemoteDataSourceImpl.getCallHistory:
--   .or('caller_id.eq.$userId,callee_id.eq.$userId').order('created_at', ascending: false)
-- plus its cursor pagination (.lt('created_at', cursor)).
create index if not exists call_sessions_caller_created_idx
  on public.call_sessions (caller_id, created_at desc);

create index if not exists call_sessions_callee_created_idx
  on public.call_sessions (callee_id, created_at desc);

-- ----------------------------------------------------------------------------
-- 2a. BUSY-RACE HANDLING, PART 1 — same-pair concurrent insert
--
-- Referenced throughout the (already-shipped) Dart layer as "Open Decision
-- #7" / "the busy-race guard" — CallRepositoryImpl.createCall explicitly
-- catches Postgres error code 23505 from this exact index and maps it to
-- CallRaceLostFailure:
--   "A call between you and this user was already starting."
-- A unique index violation is the only Postgres error class that reports
-- as 23505, so this MUST be a real unique index (not the broader trigger
-- guard added in 2b below, which uses a different error path — see that
-- section's note on why the two are kept deliberately separate).
--
-- least/greatest-pair technique, same as friendships_unique_pair_idx
-- (pulse_messenger_module1and 3.sql) and direct_chats_unique_pair_idx
-- (0021_direct_chat_pair_uniqueness.sql) — partial on "live" statuses only,
-- so a pair can freely start a new call once their previous one has
-- reached a terminal status.
-- ----------------------------------------------------------------------------

create unique index if not exists call_sessions_live_pair_unique_idx
  on public.call_sessions (least(caller_id, callee_id), greatest(caller_id, callee_id))
  where status in ('ringing', 'accepted');

-- ----------------------------------------------------------------------------
-- 2b. BUSY-RACE HANDLING, PART 2 — either participant already on a
-- DIFFERENT live call
--
-- 2a alone only stops a duplicate row for the SAME pair. It does nothing
-- to stop caller A from ringing callee C while A (or C) is already live on
-- a call with someone else entirely — the exact scenario
-- CalleeBusyFailure/CallAlreadyActiveFailure (call_failures.dart) and
-- MarkCallBusyUseCase's doc comment ("checked client-side on incoming-call
-- receipt, and re-validated server-side") describe. This trigger is that
-- server-side re-validation.
--
-- Deliberately excludes the same-pair case (see the `and not (...)` guard
-- below) so it never races ahead of / shadows 2a's unique-index violation
-- for that specific scenario — CallRepositoryImpl's 23505 -> 
-- CallRaceLostFailure mapping must keep seeing a real unique-index error
-- for same-pair conflicts. For the different-pair case there is no
-- equivalent typed-failure mapping in the current client
-- (_mapPostgrestFailure only special-cases 23505 and PGRST116), so it
-- surfaces there as UnknownCallFailure(<this trigger's message>) — a
-- correct rejection, just not yet under its own Failure subtype. Fixing
-- that mapping is a Dart-layer change and explicitly out of scope for this
-- backend-only milestone.
--
-- Concurrency: two inserts for overlapping-but-different pairs (e.g.
-- A->B and A->C, both involving A) could otherwise both read "no live
-- call found" before either commits. Serialized with a pair of
-- transaction-scoped advisory locks, always acquired in the same
-- (least, greatest) order regardless of which side is caller vs callee,
-- so two concurrent inserts can never deadlock against each other.
-- ----------------------------------------------------------------------------

create or replace function public.call_sessions_guard_busy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  low_id  uuid := least(new.caller_id, new.callee_id);
  high_id uuid := greatest(new.caller_id, new.callee_id);
  conflict_count integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(low_id::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(high_id::text, 0));

  select count(*) into conflict_count
  from public.call_sessions cs
  where cs.status in ('ringing', 'accepted')
    and (cs.caller_id in (new.caller_id, new.callee_id) or cs.callee_id in (new.caller_id, new.callee_id))
    and not (
      least(cs.caller_id, cs.callee_id) = low_id
      and greatest(cs.caller_id, cs.callee_id) = high_id
    );

  if conflict_count > 0 then
    raise exception 'One of the participants is already on another call.'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

comment on function public.call_sessions_guard_busy() is
  'BEFORE INSERT guard on call_sessions: rejects a new ringing call if caller_id or callee_id already appears (as either role) on a different live (ringing/accepted) call. See section 2b above for why this is intentionally separate from the 2a unique index. security definer + fixed search_path so it can read call_sessions regardless of the inserting user''s own RLS visibility into other users'' calls (a caller must not be able to see callee''s unrelated call rows via SELECT, but this check still needs to know they exist).';

drop trigger if exists call_sessions_guard_busy on public.call_sessions;
create trigger call_sessions_guard_busy
  before insert on public.call_sessions
  for each row execute function public.call_sessions_guard_busy();


-- ----------------------------------------------------------------------------
-- 3. TABLE: public.call_events
--
-- Column-for-column against CallEventModel.fromJson/toJson
-- (call_event_model.dart) and CallRemoteDataSourceImpl.insertCallEvent's
-- insert payload (call_id, event_type, actor_id, metadata).
-- ----------------------------------------------------------------------------

create table if not exists public.call_events (
  id          uuid primary key default gen_random_uuid(),
  call_id     uuid not null references public.call_sessions(id) on delete cascade,
  event_type  public.call_event_type_enum not null,
  actor_id    uuid references public.users(id) on delete set null,
  metadata    jsonb,
  created_at  timestamptz not null default now()
);

comment on table public.call_events is
  'Append-only audit log for one call''s lifecycle events (Milestone 4 Part A). Written by CallRemoteDataSourceImpl.insertCallEvent, fired (fire-and-forget, unawaited) from every CallRepositoryImpl mutation method. No delete/update path exists anywhere in the Dart layer — treat this table as insert-only.';
comment on column public.call_events.actor_id is
  'Nullable: MarkCallMissedUseCase''s insertCallEvent call passes no actorId (a timeout has no human actor) — on delete set null (not cascade), matching call_sessions.caller_id/callee_id''s own cascade choice being deliberately different: losing the acting user should not delete the audit trail entry itself, only anonymize who performed it.';

create index if not exists call_events_call_id_created_idx
  on public.call_events (call_id, created_at);

create index if not exists call_events_actor_id_idx
  on public.call_events (actor_id) where actor_id is not null;


-- ----------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------

alter table public.call_sessions enable row level security;
alter table public.call_events   enable row level security;

-- --- call_sessions ---------------------------------------------------------

-- Every read in the Dart layer (getCallHistory, getCallSession, both
-- Realtime subscriptions) is naturally scoped to "a call I'm on" — this is
-- the single policy that makes all of them work without further narrowing.
drop policy if exists call_sessions_select_participant on public.call_sessions;
create policy call_sessions_select_participant
  on public.call_sessions
  for select
  to authenticated
  using (auth.uid() = caller_id or auth.uid() = callee_id);

-- CallRepositoryImpl.createCall always inserts with caller_id =
-- supabase.auth.currentUser!.id (read straight off the session, not
-- caller-suppliable) — the callee never inserts this row, only the caller.
drop policy if exists call_sessions_insert_caller on public.call_sessions;
create policy call_sessions_insert_caller
  on public.call_sessions
  for insert
  to authenticated
  with check (auth.uid() = caller_id);

-- updateCallStatus is called by whichever side is acting: the callee for
-- respondToCall (accept/decline/busy), the caller for cancelCall, either
-- side for endCall, and the caller-side ringing timeout for markMissed —
-- so both participants need UPDATE, and the check clause forbids either of
-- them from reassigning the row to a different caller_id/callee_id pair
-- (which nothing in the Dart layer ever needs to do).
drop policy if exists call_sessions_update_participant on public.call_sessions;
create policy call_sessions_update_participant
  on public.call_sessions
  for update
  to authenticated
  using (auth.uid() = caller_id or auth.uid() = callee_id)
  with check (auth.uid() = caller_id or auth.uid() = callee_id);

-- No delete policy: nothing in the Dart layer ever deletes a call_sessions
-- row, so the RLS default (deny) is the correct, intentional behavior.

-- --- call_events -------------------------------------------------------

-- No current usecase reads call_events directly, but a policy is defined
-- now (rather than left to "default deny forever") so a future Call
-- History detail view has a ready, correctly-scoped read path without a
-- further migration — scoped to the same two participants as the parent
-- call_sessions row.
drop policy if exists call_events_select_participant on public.call_events;
create policy call_events_select_participant
  on public.call_events
  for select
  to authenticated
  using (
    exists (
      select 1 from public.call_sessions cs
      where cs.id = call_events.call_id
        and (auth.uid() = cs.caller_id or auth.uid() = cs.callee_id)
    )
  );

-- insertCallEvent (call_remote_datasource_impl.dart) sends actorId as
-- either supabase.auth.currentUser?.id (i.e. auth.uid() itself) or null
-- (the markMissed/timeout case) — never a third party's id — and always
-- for a call_id the inserting user is a participant of.
drop policy if exists call_events_insert_participant on public.call_events;
create policy call_events_insert_participant
  on public.call_events
  for insert
  to authenticated
  with check (
    (actor_id is null or actor_id = auth.uid())
    and exists (
      select 1 from public.call_sessions cs
      where cs.id = call_events.call_id
        and (auth.uid() = cs.caller_id or auth.uid() = cs.callee_id)
    )
  );

-- No update/delete policy: call_events is insert-only from the Dart layer
-- (see table comment above) — default deny is correct.


-- ----------------------------------------------------------------------------
-- 5. REALTIME PUBLICATION
--
-- Same idempotent add-if-missing technique as pulse_messenger_module8.sql
-- section 1/2. Only call_sessions is added — call_events has no Realtime
-- subscriber anywhere in the Dart layer (CallRealtimeDataSource only ever
-- subscribes to call_sessions), so adding it would be dead publication
-- surface with no consumer.
-- ----------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'call_sessions'
  ) then
    alter publication supabase_realtime add table public.call_sessions;
  end if;
end$$;

-- REPLICA IDENTITY FULL so UPDATE payloads (subscribeToCallStatus) include
-- the full new row regardless of which columns changed — mirrors module8's
-- rationale for the other realtime-consumed tables. CallSessionDto.fromJson
-- is applied to payload.newRecord, which Realtime only populates fully
-- when the table's replica identity includes every column being read.
alter table public.call_sessions replica identity full;


-- ============================================================================
-- POST-INSTALL VERIFICATION — read-only, run manually
-- ============================================================================

-- Both new tables exist with RLS on (2 rows expected, rowsecurity = true):
select relname, relrowsecurity
from pg_class
where relname in ('call_sessions', 'call_events') and relnamespace = 'public'::regnamespace;

-- Busy-race unique index is in place (1 row expected):
select indexname from pg_indexes
where schemaname = 'public' and indexname = 'call_sessions_live_pair_unique_idx';

-- Busy-guard trigger is attached (1 row expected):
select tgname from pg_trigger
where tgrelid = 'public.call_sessions'::regclass and tgname = 'call_sessions_guard_busy';

-- call_sessions is realtime-enabled (1 row expected):
select tablename from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'call_sessions';

-- ============================================================================
-- END 0023_call_sessions_and_events.sql
-- ============================================================================
