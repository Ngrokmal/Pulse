import '../../domain/entities/call_status.dart';

/// Immutable snapshot handed to [CallEndedScreen] once a [CallCubit] has
/// finished and been closed. Deliberately a plain summary rather than
/// keeping the (now-finished) cubit around — [CallEndedScreen] has nothing
/// left to call on it.
class CallEndSummary {
  final String? peerDisplayName;
  final String? peerAvatarUrl;
  final CallStatus? status;
  final Duration duration;
  final String? errorMessage;

  const CallEndSummary({
    this.peerDisplayName,
    this.peerAvatarUrl,
    this.status,
    this.duration = Duration.zero,
    this.errorMessage,
  });

  bool get wasConnected => duration > Duration.zero;

  /// Short, human-readable headline for the end reason.
  String get headline {
    if (errorMessage != null) return 'Call failed';
    switch (status) {
      case CallStatus.declined:
        return 'Call declined';
      case CallStatus.cancelled:
        return 'Call cancelled';
      case CallStatus.missed:
        return 'No answer';
      case CallStatus.busy:
        return 'User is busy';
      case CallStatus.accepted:
      case CallStatus.ended:
        return wasConnected ? 'Call ended' : 'Call ended';
      case CallStatus.ringing:
      case null:
        return 'Call ended';
    }
  }
}
