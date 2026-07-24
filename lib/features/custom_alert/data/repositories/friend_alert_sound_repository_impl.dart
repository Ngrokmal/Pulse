import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../chat/domain/repositories/media_repository.dart';
import '../../domain/entities/alert_audio_metadata_entity.dart';
import '../../domain/entities/friend_alert_sound_entity.dart';
import '../../domain/repositories/custom_alert_repository.dart';
import '../../domain/repositories/friend_alert_sound_repository.dart';
import '../datasources/alert_sound_remote_data_source.dart';

/// Implements the create/manage side of Friend Alert Sounds by composing
/// three already-existing/already-added pieces — no new upload pipeline,
/// no new cache pipeline, no new download pipeline:
///
///  1. MediaRepository (existing) — Cloudinary upload/delete, unchanged.
///  2. CustomAlertRepository (existing) — local cache warm-up via
///     ensureAudioCached, so a sound the user just recorded is instantly
///     playable/previewable without a network round trip.
///  3. AlertSoundRemoteDataSource (new, this feature) — Firestore
///     read/write only, no business logic.
class FriendAlertSoundRepositoryImpl implements FriendAlertSoundRepository {
  static const String _cloudinaryFolder = 'alert_sounds';
  static const String _cloudinaryResourceType = 'video'; // short audio clips — same as voice messages

  final AlertSoundRemoteDataSource remoteDataSource;
  final MediaRepository mediaRepository;
  final CustomAlertRepository customAlertRepository;

  const FriendAlertSoundRepositoryImpl({
    required this.remoteDataSource,
    required this.mediaRepository,
    required this.customAlertRepository,
  });

  @override
  Future<List<FriendAlertSoundEntity>> getSoundsForFriend({
    required String ownerUid,
    required String friendUid,
  }) async {
    final results = await Future.wait([
      remoteDataSource.getGlobalSounds(ownerUid),
      remoteDataSource.getFriendSounds(ownerUid: ownerUid, friendUid: friendUid),
    ]);
    return [...results[0], ...results[1]];
  }

  @override
  Future<FriendAlertSoundEntity> createSound({
    required String ownerUid,
    required File audioFile,
    required String displayName,
    required int durationMs,
    String? friendUid,
  }) async {
    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty) {
      throw ServerException(message: 'Alert sound name cannot be empty.');
    }
    if (durationMs <= 0 || durationMs > 5000) {
      throw ServerException(message: 'Alert sounds must be between 1 and 5 seconds.');
    }

    final generatedAlertId = _generateAlertId(ownerUid);

    final upload = await mediaRepository.uploadVoice(file: audioFile, folder: _cloudinaryFolder);

    final bytes = await audioFile.readAsBytes();
    final checksum = sha256.convert(bytes).toString();
    final format = _formatFromPath(audioFile.path);

    final metadata = AlertAudioMetadata(
      alertId: generatedAlertId,
      displayName: trimmedName,
      audioUrl: upload.secureUrl,
      checksum: checksum,
      format: format,
      fileSizeBytes: bytes.length,
      durationMs: durationMs,
      createdAt: DateTime.now(),
    );

    final sound = FriendAlertSoundEntity(
      metadata: metadata,
      ownerUid: ownerUid,
      scope: friendUid == null ? FriendAlertSoundScope.global : FriendAlertSoundScope.friendSpecific,
      friendUid: friendUid,
      cloudinaryPublicId: upload.publicId,
    );

    await remoteDataSource.saveSound(sound);

    // Warm the existing local playback cache so Preview/Play in the bottom
    // sheet is instant right after creation — reuses ensureAudioCached
    // exactly as the receiver-side FCM flow does.
    try {
      await customAlertRepository.ensureAudioCached(metadata);
    } catch (_) {
      // Non-fatal: the sound is already saved remotely and will be cached
      // on first receive/play, same fallback behavior as the FCM path.
    }

    return sound;
  }

  @override
  Future<FriendAlertSoundEntity> renameSound({
    required FriendAlertSoundEntity sound,
    required String newDisplayName,
  }) async {
    final trimmedName = newDisplayName.trim();
    if (trimmedName.isEmpty) {
      throw ServerException(message: 'Alert sound name cannot be empty.');
    }

    final renamed = FriendAlertSoundEntity(
      metadata: AlertAudioMetadata(
        alertId: sound.alertId,
        displayName: trimmedName,
        audioUrl: sound.metadata.audioUrl,
        checksum: sound.metadata.checksum,
        format: sound.metadata.format,
        fileSizeBytes: sound.metadata.fileSizeBytes,
        durationMs: sound.metadata.durationMs,
        createdAt: sound.metadata.createdAt,
      ),
      ownerUid: sound.ownerUid,
      scope: sound.scope,
      friendUid: sound.friendUid,
      cloudinaryPublicId: sound.cloudinaryPublicId,
    );

    await remoteDataSource.saveSound(renamed);
    return renamed;
  }

  @override
  Future<FriendAlertSoundEntity> replaceSoundAudio({
    required FriendAlertSoundEntity sound,
    required File audioFile,
    required int durationMs,
  }) async {
    if (durationMs <= 0 || durationMs > 5000) {
      throw ServerException(message: 'Alert sounds must be between 1 and 5 seconds.');
    }

    // Upload new audio first; only delete the old Cloudinary asset once the
    // new one is confirmed, so a failed upload never leaves the sound with
    // no playable audio at all.
    final upload = await mediaRepository.uploadVoice(file: audioFile, folder: _cloudinaryFolder);
    final bytes = await audioFile.readAsBytes();
    final checksum = sha256.convert(bytes).toString();
    final format = _formatFromPath(audioFile.path);

    final replaced = FriendAlertSoundEntity(
      metadata: AlertAudioMetadata(
        alertId: sound.alertId,
        displayName: sound.displayName,
        audioUrl: upload.secureUrl,
        checksum: checksum,
        format: format,
        fileSizeBytes: bytes.length,
        durationMs: durationMs,
        createdAt: DateTime.now(),
      ),
      ownerUid: sound.ownerUid,
      scope: sound.scope,
      friendUid: sound.friendUid,
      cloudinaryPublicId: upload.publicId,
    );

    await remoteDataSource.saveSound(replaced);

    // Old cached audio under the same alertId is now stale (different
    // checksum) — evict via the existing cache manager so the next
    // play/ensureAudioCached re-downloads the new file rather than
    // serving/validating against the old bytes.
    try {
      await customAlertRepository.evictAudioCache(sound.alertId);
      await customAlertRepository.ensureAudioCached(replaced.metadata);
    } catch (_) {}

    if (sound.cloudinaryPublicId != null) {
      try {
        await mediaRepository.deleteMedia(
          publicId: sound.cloudinaryPublicId!,
          resourceType: _cloudinaryResourceType,
        );
      } catch (_) {
        // Best-effort cleanup — orphaned Cloudinary asset is not user-facing.
      }
    }

    return replaced;
  }

  @override
  Future<void> deleteSound(FriendAlertSoundEntity sound) async {
    await remoteDataSource.deleteSound(sound);

    try {
      await customAlertRepository.evictAudioCache(sound.alertId);
    } catch (_) {}

    if (sound.cloudinaryPublicId != null) {
      try {
        await mediaRepository.deleteMedia(
          publicId: sound.cloudinaryPublicId!,
          resourceType: _cloudinaryResourceType,
        );
      } catch (_) {
        // Best-effort cleanup, mirrors MediaRepositoryImpl.deleteMedia's
        // existing non-blocking cleanup pattern used elsewhere in the app.
      }
    }
  }

  String _generateAlertId(String ownerUid) {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'alert_${ownerUid}_$now';
  }

  String _formatFromPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ext.isEmpty ? 'm4a' : ext;
  }
}
