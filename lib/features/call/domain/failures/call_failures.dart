import '../../../../core/errors/failures.dart';

/// Call-module-specific [Failure] subclasses, extending the project's
/// shared `core/errors/failures.dart` base — per Open Decision #3, the
/// call module uses `Either<Failure, T>` throughout, the same base type
/// `FriendRepository` already returns, rather than introducing a separate
/// `CallFailure` root type. Generic cases (e.g. no network) reuse the
/// existing `NetworkFailure` from core; only call-specific cases are
/// defined here.

/// The referenced `call_sessions` row doesn't exist (or is no longer
/// visible under RLS, which for an authenticated participant should be
/// equivalent to "doesn't exist").
class CallNotFoundFailure extends Failure {
  const CallNotFoundFailure([super.message = 'This call no longer exists.']);
}

/// The current user is neither the caller nor callee on this call, or is
/// otherwise not permitted to perform the requested action on it.
class CallPermissionFailure extends Failure {
  const CallPermissionFailure([
    super.message = 'You do not have permission to perform this action on this call.',
  ]);
}

/// `InitiateCallUseCase`'s friend-check failed — the callee is not a
/// friend of the caller (Phase 1 §4.3/§11).
class CallNotFriendFailure extends Failure {
  const CallNotFriendFailure([super.message = 'You can only call friends.']);
}

/// The callee is already on another live call (Phase 1 §12).
class CalleeBusyFailure extends Failure {
  const CalleeBusyFailure([super.message = 'This user is currently on another call.']);
}

/// The current user already has a live call in progress — guards against
/// starting a second `CallCubit`/call while one is active (Phase 1 §5.1).
class CallAlreadyActiveFailure extends Failure {
  const CallAlreadyActiveFailure([super.message = 'You already have an active call.']);
}

/// The busy-race guard (Open Decision #7 / the DB-level unique partial
/// index) rejected this call attempt because a live call already exists
/// between this pair of users, created concurrently by the other side.
class CallRaceLostFailure extends Failure {
  const CallRaceLostFailure([
    super.message = 'A call between you and this user was already starting.',
  ]);
}

/// Malformed or otherwise invalid input to a call-module usecase/repository
/// call (e.g. inconsistent ids), distinct from a business-rule rejection.
class CallValidationFailure extends Failure {
  const CallValidationFailure(super.message);
}

/// Fetching/refreshing an Agora token failed (Edge Function error,
/// authorization mismatch, etc. — Phase 1 §9/§21).
class AgoraTokenFailure extends Failure {
  const AgoraTokenFailure([
    super.message = 'Failed to obtain a call credential. Please try again.',
  ]);
}

/// A failure originating from the Agora RTC engine itself (init, join,
/// leave, or a toggle call) — as opposed to a Supabase/signaling failure.
class AgoraEngineFailure extends Failure {
  const AgoraEngineFailure(super.message);
}

/// MILESTONE 5: the OS denied microphone (or, for a video call, camera)
/// permission, so the engine was never joined. Distinct from
/// [CallPermissionFailure], which is about call-record authorization, not
/// device hardware access.
class CallDevicePermissionFailure extends Failure {
  const CallDevicePermissionFailure([
    super.message = 'Microphone and camera access is required for calls. Please enable it in Settings.',
  ]);
}

/// Fallback for an error that doesn't map to any of the above — kept
/// distinct from the core catch-all so call-module error logs are
/// identifiable as such.
class UnknownCallFailure extends Failure {
  const UnknownCallFailure([super.message = 'Something went wrong with the call.']);
}
