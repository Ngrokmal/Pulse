import 'call_participant_entity.dart';
import 'call_session_entity.dart';

/// The full domain-level state snapshot a call-lifecycle owner (the future
/// `CallCubit` — presentation layer, out of scope for this milestone) would
/// hold. Defined here, in domain, because it's a plain data snapshot with
/// no Flutter/Bloc dependency of its own; the Cubit itself, its `CallState`
/// wrapper, and all UI are explicitly excluded from this milestone.
///
/// Hand-rolled per Open Decision #4 (no freezed/equatable), matching the
/// rest of the app's `ChatState`-style plain-class approach.
enum CallPhase {
  idle,
  calling,
  ringingIncoming,
  accepted,
  connecting,
  connected,
  reconnecting,
  ended,
}

class CallStateEntity {
  final CallPhase phase;
  final CallSessionEntity? session;
  final CallParticipantEntity? localParticipant;
  final CallParticipantEntity? remoteParticipant;
  final Duration elapsed;
  final String? errorMessage;

  const CallStateEntity({
    required this.phase,
    this.session,
    this.localParticipant,
    this.remoteParticipant,
    this.elapsed = Duration.zero,
    this.errorMessage,
  });

  const CallStateEntity.idle()
      : phase = CallPhase.idle,
        session = null,
        localParticipant = null,
        remoteParticipant = null,
        elapsed = Duration.zero,
        errorMessage = null;

  CallStateEntity copyWith({
    CallPhase? phase,
    CallSessionEntity? session,
    CallParticipantEntity? localParticipant,
    CallParticipantEntity? remoteParticipant,
    Duration? elapsed,
    String? errorMessage,
  }) {
    return CallStateEntity(
      phase: phase ?? this.phase,
      session: session ?? this.session,
      localParticipant: localParticipant ?? this.localParticipant,
      remoteParticipant: remoteParticipant ?? this.remoteParticipant,
      elapsed: elapsed ?? this.elapsed,
      errorMessage: errorMessage,
    );
  }
}
