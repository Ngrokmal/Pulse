/// Domain-level union of Agora RTC engine events, hand-rolled per Open
/// Decision #4 (no freezed/equatable) rather than the SDK's own event
/// shapes. This is what `AgoraRepository.engineEvents` emits — the
/// concrete `AgoraDataSource`/`AgoraRepositoryImpl` (not part of this
/// milestone) are responsible for translating raw `agora_rtc_engine`
/// callbacks into these, so nothing above the repository boundary ever
/// imports the Agora SDK.
abstract class AgoraEngineEvent {
  const AgoraEngineEvent();
}

/// The remote peer has joined the channel — this is what each client uses
/// to independently derive "the call is now Connected" (Phase 1 §1/§7),
/// rather than trusting a Supabase-asserted 'connected' status that doesn't
/// exist.
class AgoraUserJoined extends AgoraEngineEvent {
  final int remoteUid;
  const AgoraUserJoined(this.remoteUid);
}

/// The remote peer has left the channel (graceful leave, not necessarily a
/// connection failure).
class AgoraUserLeft extends AgoraEngineEvent {
  final int remoteUid;
  const AgoraUserLeft(this.remoteUid);
}

/// Media connection degraded/lost. Per Phase 1 §17/§18, this does NOT by
/// itself end the call — it drives a bounded "Reconnecting" window.
class AgoraConnectionLost extends AgoraEngineEvent {
  const AgoraConnectionLost();
}

/// Media connection recovered after a prior [AgoraConnectionLost].
class AgoraConnectionRestored extends AgoraEngineEvent {
  const AgoraConnectionRestored();
}

/// Agora's `onTokenPrivilegeWillExpire` callback fired — drives
/// `RefreshAgoraTokenUseCase` (Phase 1 §9), transparent to the user.
class AgoraTokenExpiringSoon extends AgoraEngineEvent {
  const AgoraTokenExpiringSoon();
}

/// An unrecoverable engine-level error.
class AgoraEngineError extends AgoraEngineEvent {
  final String message;
  const AgoraEngineError(this.message);
}
