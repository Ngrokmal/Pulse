import 'dart:io';

import '../entities/friend_alert_sound_entity.dart';

/// Repository for the Friend Alert Sounds creation/management flow
/// (record → preview → name → upload → Cloudinary → Firestore).
///
/// This is a NEW, additive repository — it does not replace or modify
/// [CustomAlertRepository] (custom_alert/domain/repositories/
/// custom_alert_repository.dart), which remains exactly as-is and continues
/// to own local cache/metadata for *receiving and playing* alert audio.
/// This repository owns the *creation and remote management* side, and its
/// implementation composes the existing:
///  - MediaRepository (Cloudinary upload/delete — chat/domain/repositories/
///    media_repository.dart)
///  - CustomAlertRepository (local metadata cache warm-up so a sound is
///    instantly playable right after creation, no redesign)
///  - a new AlertSoundRemoteDataSource (Firestore reads/writes only)
abstract class FriendAlertSoundRepository {
  /// Global sounds owned by [ownerUid] plus any friend-specific sounds
  /// owned by [ownerUid] that are scoped to [friendUid].
  Future<List<FriendAlertSoundEntity>> getSoundsForFriend({
    required String ownerUid,
    required String friendUid,
  });

  /// Records a new sound: uploads [audioFile] to Cloudinary, persists
  /// metadata to Firestore (global or scoped to [friendUid]), and warms the
  /// local playback cache via the existing CustomAlertRepository pipeline.
  Future<FriendAlertSoundEntity> createSound({
    required String ownerUid,
    required File audioFile,
    required String displayName,
    required int durationMs,
    String? friendUid, // null => global sound
  });

  Future<FriendAlertSoundEntity> renameSound({
    required FriendAlertSoundEntity sound,
    required String newDisplayName,
  });

  /// Replaces the audio of an existing sound (same alertId/displayName,
  /// new upload + new checksum) — re-uses createSound's upload/validate
  /// path, then overwrites the existing Firestore doc in place.
  Future<FriendAlertSoundEntity> replaceSoundAudio({
    required FriendAlertSoundEntity sound,
    required File audioFile,
    required int durationMs,
  });

  Future<void> deleteSound(FriendAlertSoundEntity sound);
}
