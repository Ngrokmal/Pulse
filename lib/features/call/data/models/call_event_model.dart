import '../../domain/entities/call_event_type.dart';

/// Data-layer model for one `call_events` audit-log row (Phase 1 §8.2).
/// No corresponding domain entity is defined for this milestone since no
/// usecase yet exposes raw event-log detail past the repository boundary —
/// `GetCallHistoryUseCase` returns `CallSessionEntity` rows, not events.
/// This model exists so the mapping shape is ready for whichever data-layer
/// milestone wires up Call History detail.
class CallEventModel {
  final String id;
  final String callId;
  final CallEventType eventType;
  final String? actorId;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  const CallEventModel({
    required this.id,
    required this.callId,
    required this.eventType,
    this.actorId,
    required this.createdAt,
    this.metadata,
  });

  factory CallEventModel.fromJson(Map<String, dynamic> json) {
    return CallEventModel(
      id: json['id'] as String,
      callId: json['call_id'] as String,
      eventType: CallEventType.values.firstWhere(
        (e) => e.name == json['event_type'],
        orElse: () => CallEventType.ended,
      ),
      actorId: json['actor_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'call_id': callId,
      'event_type': eventType.name,
      'actor_id': actorId,
      'created_at': createdAt.toIso8601String(),
      'metadata': metadata,
    };
  }
}
