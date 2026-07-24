import 'alert_audio_metadata_entity.dart';

/// Friend Alert Sounds (Premium Social Feature).
///
/// Wraps the existing [AlertAudioMetadata] entity (unchanged — reused as-is,
/// see custom_alert/domain/entities/alert_audio_metadata_entity.dart) with
/// the ownership/scope information needed to persist it remotely in
/// Firestore and resolve it per-friend at send time. This is additive: the
/// existing entity, its local cache pipeline (AudioCacheManager /
/// AudioDownloadManager / AudioValidationService), and every usecase that
/// already consumes [AlertAudioMetadata] are untouched.
///
/// Scope rules:
/// - [FriendAlertSoundScope.global]: usable when messaging any friend.
/// - [FriendAlertSoundScope.friendSpecific]: usable only in chats with
///   [friendUid] (e.g. a sound named "Wake Up" that only exists for one
///   specific friend).
enum FriendAlertSoundScope { global, friendSpecific }

class FriendAlertSoundEntity {
  final AlertAudioMetadata metadata;
  final String ownerUid;
  final FriendAlertSoundScope scope;
  final String? friendUid; // non-null only when scope == friendSpecific
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
