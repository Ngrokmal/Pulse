import '../entities/call_session_entity.dart';
import '../entities/call_status.dart';
import '../repositories/call_repository.dart';
import 'end_call_usecase.dart';
import 'mark_call_missed_usecase.dart';

/// MILESTONE 6 addition. Production safety net for exactly the gap the
/// Data Layer's `markMissed` docstring already flagged but never
/// implemented: "or via the defensive stale-row reconciliation on next app
/// open."
///
/// `CallCubit.kRingingTimeout` (Milestone 3) only fires while the caller's
/// `CallCubit` instance is alive and its `Timer` is actually ticking —
/// neither is true once the app is backgrounded long enough for the OS to
/// suspend it, or killed outright. Without this usecase a call left in
/// that state stays 'ringing' (or 'accepted' but never actually connected,
/// e.g. a mid-join crash) forever: the callee's incoming-call UI is gone,
/// nothing is listening for a status change on either side anymore, and
/// the row permanently pollutes call history as a phantom live call.
///
/// Invoked from `IncomingCallListenerCubit` — once on `start(userId)`
/// (covers cold/terminated-app launch) and again on every
/// `AppLifecycleState.resumed` via `reconcileOnResume()` (covers
/// background/foreground) — rather than introducing a new singleton
/// coordinator, since that cubit is already the app-wide "what's my
/// call-related state" owner (Milestone 3).
///
/// Deliberately reuses [CallRepository.getCallHistory] (already fetches
/// the current user's own calls, newest first) instead of adding a new
/// datasource query — the most recent page is enough to catch anything
/// realistically left stale by a background/kill gap; a call further back
/// than that is not "stale", it's just old and already terminal.
class ReconcileStaleCallsUseCase {
  final CallRepository repository;
  final MarkCallMissedUseCase markCallMissedUseCase;
  final EndCallUseCase endCallUseCase;

  const ReconcileStaleCallsUseCase({
    required this.repository,
    required this.markCallMissedUseCase,
    required this.endCallUseCase,
  });

  /// Matches `CallCubit.kRingingTimeout` — a 'ringing' row older than this,
  /// with no status change having reached us, is assumed to be exactly the
  /// scenario above (caller's timer never got to fire).
  static const Duration ringingStaleAfter = Duration(seconds: 45);

  /// A generous safety-net window for a call stuck 'accepted' — i.e. the
  /// callee answered but the pair never reached (or never recorded)
  /// 'ended', most plausibly because one side crashed/was killed mid-call.
  /// Deliberately much longer than any real call is expected to run, so
  /// this never races a genuinely long, healthy, still-connected call.
  static const Duration connectedStaleAfter = Duration(hours: 6);

  Future<void> call(String userId) async {
    final result = await repository.getCallHistory(userId: userId, limit: 20);
    await result.fold(
      (_) async {
        // No network / auth failure fetching history — nothing to
        // reconcile against right now. Not fatal: the next resume/cold
        // start tries again, and normal realtime updates aren't affected
        // either way.
      },
      (page) async {
        final now = DateTime.now();
        for (final session in page.items) {
          await _reconcileOne(session, userId: userId, now: now);
        }
      },
    );
  }

  Future<void> _reconcileOne(
    CallSessionEntity session, {
    required String userId,
    required DateTime now,
  }) async {
    try {
      if (session.status == CallStatus.ringing &&
          session.callerId == userId &&
          now.difference(session.ringingStartedAt) > ringingStaleAfter) {
        // Only the caller side reconciles a stale 'ringing' row — mirrors
        // `CallCubit.kRingingTimeout`, which is caller-only by design, so
        // this doesn't introduce a new write path the callee never had.
        await markCallMissedUseCase.call(session.id);
      } else if (session.status == CallStatus.accepted &&
          session.acceptedAt != null &&
          now.difference(session.acceptedAt!) > connectedStaleAfter) {
        // Either participant may end a connected call (Phase 1 §7), so no
        // caller/callee restriction here.
        await endCallUseCase.call(callId: session.id, endReason: 'stale_reconciled');
      }
    } catch (_) {
      // One row failing to reconcile (e.g. a race with a genuine
      // in-flight status change) must not stop the rest of the page from
      // being checked.
    }
  }
}
