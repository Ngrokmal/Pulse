/// Raw wire shape of the `generate-agora-token` Edge Function's response
/// (Phase 1 §3.2/§9 — function not yet created; this DTO anticipates its
/// response shape: `{ token, uid, channel, expires_at, app_id }`).
class AgoraTokenDto {
  final String token;
  final int uid;
  final String channel;
  final String expiresAt;
  final String appId;

  const AgoraTokenDto({
    required this.token,
    required this.uid,
    required this.channel,
    required this.expiresAt,
    required this.appId,
  });

  factory AgoraTokenDto.fromJson(Map<String, dynamic> json) {
    return AgoraTokenDto(
      token: json['token'] as String,
      uid: (json['uid'] as num).toInt(),
      channel: json['channel'] as String,
      expiresAt: json['expires_at'] as String,
      appId: json['app_id'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'uid': uid,
      'channel': channel,
      'expires_at': expiresAt,
      'app_id': appId,
    };
  }
}
