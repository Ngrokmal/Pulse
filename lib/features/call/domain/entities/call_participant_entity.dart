/// Local or remote participant's call-related UI state. Used by both the
/// local user (before/after joining) and the remote peer once connected.
///
/// Mute/camera state here is sourced from Agora engine events, not from
/// Supabase — see Phase 1 §6 ("why signaling and media-state are
/// separate"). This entity is the domain-level shape either side of that
/// boundary converges on.
class CallParticipantEntity {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int agoraUid;
  final bool isMuted;
  final bool isCameraOn;

  const CallParticipantEntity({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.agoraUid,
    this.isMuted = false,
    this.isCameraOn = true,
  });

  CallParticipantEntity copyWith({
    String? userId,
    String? displayName,
    String? avatarUrl,
    int? agoraUid,
    bool? isMuted,
    bool? isCameraOn,
  }) {
    return CallParticipantEntity(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      agoraUid: agoraUid ?? this.agoraUid,
      isMuted: isMuted ?? this.isMuted,
      isCameraOn: isCameraOn ?? this.isCameraOn,
    );
  }
}
