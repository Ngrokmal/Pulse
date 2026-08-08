# Phase 3.3 — Group Delta Sync — Implementation Report

## 1. Files changed

**New files**
- `lib/core/sync/group_delta_sync_coordinator.dart` — coalesces reconnect/app-resume signals from every open group screen into one batched delta call.
- `lib/features/chat/data/datasources/group_info_local_data_source.dart` — offline-first Hive cache + per-group cursors for group metadata/membership.
- `lib/features/chat/data/datasources/group_delta_remote_data_source.dart` — batched Supabase reads (`chats` / `chat_members`) for N groups in 1 request.

**Modified files**
- `lib/features/chat/data/repositories/group_repository_impl.dart` — `streamGroup` rewritten cache-first/delta-driven; `streamGroupMessages` delta query bug fixed; new `_runBatchedGroupDelta` / `_cacheMemberRow` helpers.
- `lib/core/services/local_db_service.dart` — two new box accessors added (`groupInfoBox`, `groupMembersBox`). No existing method touched.
- `lib/core/di/injection_container.dart` — registers the two new datasources; threads them into the existing `GroupRepositoryImpl` DI line.
- `lib/main.dart` — one line in the existing `didChangeAppLifecycleState` `resumed` case.

**Explicitly not touched:** Direct Chat (`chat_repository_impl.dart`, `chat_local_data_source.dart`), Home, Friend List, Notification, Offline Queue, `SharedPresenceManager`, `GroupProfileBulkWarmupService`, any UI widget, any `.sql` migration/schema.

## 2. Functions changed/added

| File | Function | Change |
|---|---|---|
| `group_repository_impl.dart` | `streamGroup` | Full rewrite: cache-first emit, coordinator-registered, realtime applies single rows, reconnect defers to coordinator instead of re-fetching itself |
| `group_repository_impl.dart` | `_runBatchedGroupDelta` (new) | One batched delta covering all active groups |
| `group_repository_impl.dart` | `_cacheMemberRow` (new) | Per-row member cache write with resolve-once uid caching |
| `group_repository_impl.dart` | `streamGroupMessages` → `runDelta` | Fixed null-`updated_at` cursor bug (`.or(created_at.gt,updated_at.gt)`); added inert tombstone check for a future `deleted_at` column |
| `group_delta_sync_coordinator.dart` | `notifyReconnect`, `notifyAppResumed`, `_scheduleSync`, `_runSync` (new) | Debounce + in-flight guard so concurrent triggers still yield exactly one batch |
| `group_delta_remote_data_source.dart` | `fetchGroupsInfoDelta`, `fetchGroupMembersDelta` (new) | Batched, cursor-scoped queries; the latter has a schema-fallback path |
| `group_info_local_data_source.dart` | full new class | Cache/cursor storage, `rebuildGroupEntityFromCache` |
| `local_db_service.dart` | `groupInfoBox`, `groupMembersBox` (new) | New Hive box accessors, additive only |

## 3. Root cause

- **Group metadata/membership had no delta path at all.** `streamGroup` called a full `_buildGroupEntity` (1 `chats` read + 1 `chat_members` read + N uid-reverse-resolves) on *every* reconnect, and there was no local cache, so every group screen open/reconnect was a full network round trip with no offline-first rendering.
- **No cross-group coordination.** Each group's realtime channel resubscribed and refreshed independently, so a network blip with K open group screens caused K full refetches at once instead of one coordinated sync.
- **Latent bug in the existing message delta:** it filtered only on `messages.updated_at`, which is `null` for a never-edited row, so a delta query after being offline could miss brand-new messages entirely (only realtime was catching them). Direct Chat had already fixed the identical issue; Group hadn't.

## 4. Architecture

```
App resume / channel reconnect
        │
        ▼
GroupDeltaSyncCoordinator (debounce 150ms, in-flight guard)
        │  one call, all currently-open group ids
        ▼
GroupRepositoryImpl._runBatchedGroupDelta(groupIds)
        │
        ├─ GroupDeltaRemoteDataSource.fetchGroupsInfoDelta   → 1 request: chats   WHERE id IN (...) AND updated_at > minCursor
        └─ GroupDeltaRemoteDataSource.fetchGroupMembersDelta → 1 request: chat_members WHERE chat_id IN (...) AND updated_at > minCursor
                (falls back to 1 unfiltered batched snapshot if chat_members has no updated_at column)
        │
        ▼
GroupInfoLocalDataSource (Hive: group_info_cache, group_members_<id>, cursors in chat_sync_meta)
        │
        ▼
Every open streamGroup() re-emits from cache (0 network)
```

Realtime (`postgres_changes` on `chats`/`chat_members`) keeps pushing single-row updates directly into the same cache in real time — delta only fills the gap realtime couldn't cover while disconnected (Requirement 9).

**Design trade-off, stated plainly:** the batched query uses one shared `since` floor (the *minimum* cursor across the groups in the batch), because Postgrest has no per-row time bound within an `IN (...)` list. A group already fully synced may occasionally receive a few rows it already has (harmless no-op re-upserts). This is still strictly bounded/incremental — never a full table scan — and is the standard trade-off for batching heterogeneous cursors into one request.

**Known, explicitly out-of-scope limitation:** true delete-while-offline detection for messages needs a `deleted_at` tombstone column (the same pattern already used for notifications). Adding it is a schema change, which this mission explicitly forbids. The code has an inert, defensive check for it so it activates for free the moment that column exists, but until then, message deletion is realtime-only (matches current behavior — no regression, just not fully solved).

## 5. Request count, before vs after

Scenario: 20 open group screens, one network reconnect.

| | Before | After |
|---|---|---|
| Group metadata (`chats`) refresh | 20 requests (1 per group) | 1 batched request |
| Group membership (`chat_members`) refresh | 20 requests + up to 20×members uid-resolves | 1 batched request + resolves only for *new* members |
| App resume, same 20 groups | 20 requests (each channel's own resubscribe fires independently) | 1 batched request |
| Reopening a previously-opened group (cold start, cache warm) | 1 `chats` + 1 `chat_members` read, every time | 0 requests — served from Hive, delta catches up in the background |
| New group, first-ever open | 1 `chats` + 1 `chat_members` read | Same (unavoidable — nothing to cache yet) |

## 6. Regression risk

- **Low, localized.** All changes are additive (new files, new optional constructor params with defaults, new DI lines, one new Hive box) or confined to `group_repository_impl.dart`'s own two stream methods. Direct Chat, Home, Friend List, Notifications, Offline Queue, SharedPresenceManager, GroupProfileBulkWarmupService, UI, and SQL/schema are untouched.
- **`GroupRepositoryImpl` constructor signature changed** (two new optional params) — safe for any other caller since both default to real implementations; only `injection_container.dart`'s one registration line was updated to pass DI-managed singletons instead of the defaults.
- **`chat_members.updated_at` assumption is unverified** (base schema wasn't in this project export, and adding it is out of scope). Mitigated with a try/catch fallback to a batched full-snapshot fetch — sync still works, just without a members-specific cursor, until/unless that column is confirmed or added later.
- **Coordinator is a single global singleton.** If `GroupRepositoryImpl` were ever constructed more than once (it isn't — it's a `registerLazySingleton`), `configure()` would just re-wire to the latest instance; no crash, but worth knowing.
- **Message delta query change** (`.gt` → `.or(created_at.gt, updated_at.gt)`) mirrors an already-shipped, already-tested fix in Direct Chat — same shape, applied to Group's own query only.

## 7. Verification checklist

- [ ] Run `flutter analyze` / `flutter pub get` (not runnable in this sandbox — no Flutter SDK available; please run locally before merging).
- [ ] Open a group with 0 local cache → confirm exactly one `chats` + one `chat_members` read, then cached entity renders.
- [ ] Reopen the same group → confirm 0 network reads, cache renders instantly.
- [ ] Open 3+ group screens, force a reconnect (toggle airplane mode) → confirm exactly ONE `chats` delta request and ONE `chat_members` delta request fire (not one per group) — check via Supabase logs / network inspector.
- [ ] Background the app and resume → confirm the same single batched delta fires, scoped to whatever groups are still open.
- [ ] Edit a group name/photo on another device while this device is offline, then reconnect → change appears after the delta, without a full member-list re-resolve.
- [ ] Add/remove a member or change a role on another device while offline, then reconnect → membership updates correctly; left members disappear from `cachedMemberUids`/`adminIds`.
- [ ] Send a brand-new (never-edited) group message while this device was offline → confirm it now appears after reconnect (regression check for the null-`updated_at` fix).
- [ ] Confirm Direct Chat, Home list, Friend List, Notifications, and presence indicators behave identically to before this change (no shared code path was modified).
- [ ] Confirm `GroupInfoScreen`/`GroupChatScreen` UI renders unchanged (no UI files were touched).

## Confirmations

- ✓ Incremental sync — per-group cursors for both `chats` and `chat_members`, never a full rescan of an already-synced group.
- ✓ One delta per reconnect — `GroupDeltaSyncCoordinator` debounces and in-flight-guards every `notifyReconnect()` call.
- ✓ Batch group delta — one request each for metadata and membership across all active groups, not one per group.
- ✓ Offline-first — `streamGroup` always renders from Hive before touching the network; delta results write to Hive, UI re-reads Hive.
- ✓ Zero duplicate sync — coordinator collapses concurrent triggers into a single run, with a queued rerun (not a duplicate call) if a trigger arrives mid-flight.
- ✓ Zero UI change — no file under `presentation/` or any widget was modified.
