import 'call_status.dart';
import 'call_type.dart';

/// Single source of truth (domain-level) for one call's signaling lifecycle.
/// Pure Dart — no Supabase/Agora types leak in here. Mirrors
/// `public.call_sessions` conceptually, but this entity is what the rest of
/// the app (usecases, Cubits) actually works with; the raw row shape lives
/// in `CallSessionDto` (data layer) instead.
class CallSessionEntity {
  final String id;
  final String callerId;
  final String calleeId;
  final String channelName;
  final CallType callType;
  final CallStatus status;
  final DateTime createdAt;
  final DateTime ringingStartedAt;
  final DateTime? acceptedAt;
  final DateTime? endedAt;
  final String? endReason;

  /// Deterministic numeric Agora uid assigned to the caller for this call.
  final int agoraUidCaller;

  /// Deterministic numeric Agora uid assigned to the callee for this call.
  final int agoraUidCallee;

  const CallSessionEntity({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.channelName,
    required this.callType,
    required this.status,
    required this.createdAt,
    required this.ringingStartedAt,
    this.acceptedAt,
    this.endedAt,
    this.endReason,
    required this.agoraUidCaller,
    required this.agoraUidCallee,
  });

  /// True while the call is still 'ringing' or 'accepted' — i.e. not yet in
  /// a terminal state. Mirrors the busy-race guard's notion of a "live"
  /// call (Phase 1 §12/§22, Open Decision #7).
  bool get isLive => status == CallStatus.ringing || status == CallStatus.accepted;

  bool get isTerminal => !isLive;

  /// The Agora uid assigned to [userId] on this call, or null if [userId]
  /// is neither the caller nor the callee.
  int? agoraUidFor(String userId) {
    if (userId == callerId) return agoraUidCaller;
    if (userId == calleeId) return agoraUidCallee;
    return null;
  }

  /// The other participant's id, relative to [userId]. Returns null if
  /// [userId] is neither participant.
  String? otherParticipantId(String userId) {
    if (userId == callerId) return calleeId;
    if (userId == calleeId) return callerId;
    return null;
  }

  CallSessionEntity copyWith({
    String? id,
    String? callerId,
    String? calleeId,
    String? channelName,
    CallType? callType,
    CallStatus? status,
    DateTime? createdAt,
    DateTime? ringingStartedAt,
    DateTime? acceptedAt,
    DateTime? endedAt,
    String? endReason,
    int? agoraUidCaller,
    int? agoraUidCallee,
  }) {
    return CallSessionEntity(
      id: id ?? this.id,
      callerId: callerId ?? this.callerId,
      calleeId: calleeId ?? this.calleeId,
      channelName: channelName ?? this.channelName,
      callType: callType ?? this.callType,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      ringingStartedAt: ringingStartedAt ?? this.ringingStartedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      endedAt: endedAt ?? this.endedAt,
      endReason: endReason ?? this.endReason,
      agoraUidCaller: agoraUidCaller ?? this.agoraUidCaller,
      agoraUidCallee: agoraUidCallee ?? this.agoraUidCallee,
    );
  }
}
