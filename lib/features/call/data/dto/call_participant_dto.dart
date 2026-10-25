/// Raw wire shape describing a call participant, as it would come back
/// from a joined profile lookup (e.g. `users` table) alongside a
/// `call_sessions` row. Plain Dart, no Supabase import.
class CallParticipantDto {
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final int agoraUid;

  const CallParticipantDto({
    required this.userId,
    this.displayName,
    this.avatarUrl,
    required this.agoraUid,
  });

  factory CallParticipantDto.fromJson(Map<String, dynamic> json) {
    return CallParticipantDto(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      agoraUid: (json['agora_uid'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'agora_uid': agoraUid,
    };
  }
}
