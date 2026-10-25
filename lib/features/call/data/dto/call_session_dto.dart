/// Raw wire shape of a `call_sessions` row (Phase 1 §7 — table not yet
/// created; this DTO's field names anticipate that schema so the mapping
/// layer is ready once it exists). Plain Dart, no Supabase import — the
/// concrete datasource (not part of this milestone) is what actually
/// produces/consumes these from `PostgrestFilterBuilder`/Realtime payloads.
class CallSessionDto {
  final String id;
  final String callerId;
  final String calleeId;
  final String channelName;
  final String callType; // 'audio' | 'video'
  final String status; // 'ringing' | 'accepted' | 'declined' | 'cancelled' | 'missed' | 'busy' | 'ended'
  final String createdAt;
  final String ringingStartedAt;
  final String? acceptedAt;
  final String? endedAt;
  final String? endReason;
  final int agoraUidCaller;
  final int agoraUidCallee;

  const CallSessionDto({
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

  factory CallSessionDto.fromJson(Map<String, dynamic> json) {
    return CallSessionDto(
      id: json['id'] as String,
      callerId: json['caller_id'] as String,
      calleeId: json['callee_id'] as String,
      channelName: json['channel_name'] as String,
      callType: json['call_type'] as String,
      status: json['status'] as String,
      createdAt: json['created_at'] as String,
      ringingStartedAt: json['ringing_started_at'] as String,
      acceptedAt: json['accepted_at'] as String?,
      endedAt: json['ended_at'] as String?,
      endReason: json['end_reason'] as String?,
      agoraUidCaller: (json['agora_uid_caller'] as num).toInt(),
      agoraUidCallee: (json['agora_uid_callee'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'caller_id': callerId,
      'callee_id': calleeId,
      'channel_name': channelName,
      'call_type': callType,
      'status': status,
      'created_at': createdAt,
      'ringing_started_at': ringingStartedAt,
      'accepted_at': acceptedAt,
      'ended_at': endedAt,
      'end_reason': endReason,
      'agora_uid_caller': agoraUidCaller,
      'agora_uid_callee': agoraUidCallee,
    };
  }
}
