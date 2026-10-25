import 'alert_audio_metadata_entity.dart';

enum FriendAlertSoundScope { global, friendSpecific }

class FriendAlertSoundEntity {
  final AlertAudioMetadata metadata;
  final String ownerUid;
  final FriendAlertSoundScope scope;
  final String? friendUid;
  final String? cloudinaryPublicId;

  const FriendAlertSoundEntity({
    required this.metadata,
    required this.ownerUid,
    required this.scope,
    this.friendUid,
    this.cloudinaryPublicId,
  });

  String get alertId => metadata.alertId;
  String get displayName => metadata.displayName;

  bool get isGlobal => scope == FriendAlertSoundScope.global;

  bool usableFor(String candidateFriendUid) {
    return isGlobal || friendUid == candidateFriendUid;
  }
}
