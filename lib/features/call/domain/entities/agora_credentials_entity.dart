/// Everything needed to join an Agora channel, minted server-side by the
/// (not-yet-created) `generate-agora-token` Edge Function. The Agora App
/// Certificate itself never appears here or anywhere client-side — see
/// Phase 1 §9/§21.
class AgoraCredentialsEntity {
  final String appId;
  final String token;
  final String channelName;
  final int uid;
  final DateTime expiresAt;

  const AgoraCredentialsEntity({
    required this.appId,
    required this.token,
    required this.channelName,
    required this.uid,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
