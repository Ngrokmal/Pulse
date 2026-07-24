import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/alert_audio_metadata_model.dart';
import '../../domain/entities/friend_alert_sound_entity.dart';

/// Firestore structure (additive — no existing collection touched):
///
///   users/{ownerUid}/alertSounds/{alertId}
///     — global sounds, usable in any chat this user starts.
///
///   users/{ownerUid}/friendAlertSounds/{friendUid}/sounds/{alertId}
///     — sounds scoped to one specific friend.
///
/// Both documents store exactly the fields already defined by
/// [AlertAudioMetadataModel.toMap] (alertId, displayName, audioUrl,
/// checksum, format, fileSizeBytes, durationMs, createdAt) plus
/// `cloudinaryPublicId` (needed for delete) — the existing model/shape is
/// reused as-is, not redesigned.
abstract class AlertSoundRemoteDataSource {
  Future<List<FriendAlertSoundEntity>> getGlobalSounds(String ownerUid);

  Future<List<FriendAlertSoundEntity>> getFriendSounds({
    required String ownerUid,
    required String friendUid,
  });

  Future<void> saveSound(FriendAlertSoundEntity sound);

  Future<void> deleteSound(FriendAlertSoundEntity sound);
}

class AlertSoundRemoteDataSourceImpl implements AlertSoundRemoteDataSource {
  final FirebaseFirestore firestore;

  const AlertSoundRemoteDataSourceImpl({required this.firestore});

  CollectionReference<Map<String, dynamic>> _globalCollection(String ownerUid) {
    return firestore.collection('users').doc(ownerUid).collection('alertSounds');
  }

  CollectionReference<Map<String, dynamic>> _friendCollection({
    required String ownerUid,
    required String friendUid,
  }) {
    return firestore
        .collection('users')
        .doc(ownerUid)
        .collection('friendAlertSounds')
        .doc(friendUid)
        .collection('sounds');
  }

  @override
  Future<List<FriendAlertSoundEntity>> getGlobalSounds(String ownerUid) async {
    try {
      final snapshot = await _globalCollection(ownerUid).get();
      return snapshot.docs
          .map((doc) => _fromDoc(doc.data(), ownerUid: ownerUid, scope: FriendAlertSoundScope.global))
          .toList();
    } catch (e) {
      throw ServerException(message: 'Failed to load global alert sounds: $e');
    }
  }

  @override
  Future<List<FriendAlertSoundEntity>> getFriendSounds({
    required String ownerUid,
    required String friendUid,
  }) async {
    try {
      final snapshot = await _friendCollection(ownerUid: ownerUid, friendUid: friendUid).get();
      return snapshot.docs
          .map((doc) => _fromDoc(
                doc.data(),
                ownerUid: ownerUid,
                scope: FriendAlertSoundScope.friendSpecific,
                friendUid: friendUid,
              ))
          .toList();
    } catch (e) {
      throw ServerException(message: 'Failed to load friend alert sounds: $e');
    }
  }

  @override
  Future<void> saveSound(FriendAlertSoundEntity sound) async {
    final map = AlertAudioMetadataModel.fromEntity(sound.metadata).toMap();
    map['createdAt'] = FieldValue.serverTimestamp();
    if (sound.cloudinaryPublicId != null) {
      map['cloudinaryPublicId'] = sound.cloudinaryPublicId;
    }

    try {
      final ref = sound.isGlobal
          ? _globalCollection(sound.ownerUid).doc(sound.alertId)
          : _friendCollection(ownerUid: sound.ownerUid, friendUid: sound.friendUid!).doc(sound.alertId);
      await ref.set(map, SetOptions(merge: true));
    } catch (e) {
      throw ServerException(message: 'Failed to save alert sound: $e');
    }
  }

  @override
  Future<void> deleteSound(FriendAlertSoundEntity sound) async {
    try {
      final ref = sound.isGlobal
          ? _globalCollection(sound.ownerUid).doc(sound.alertId)
          : _friendCollection(ownerUid: sound.ownerUid, friendUid: sound.friendUid!).doc(sound.alertId);
      await ref.delete();
    } catch (e) {
      throw ServerException(message: 'Failed to delete alert sound: $e');
    }
  }

  FriendAlertSoundEntity _fromDoc(
    Map<String, dynamic> data, {
    required String ownerUid,
    required FriendAlertSoundScope scope,
    String? friendUid,
  }) {
    // Firestore returns Timestamp for createdAt; AlertAudioMetadataModel.fromMap
    // expects an ISO string (its existing FCM-push-payload contract), so we
    // adapt here rather than changing that shared model.
    final normalized = Map<String, dynamic>.from(data);
    final rawCreatedAt = normalized['createdAt'];
    if (rawCreatedAt is Timestamp) {
      normalized['createdAt'] = rawCreatedAt.toDate().toIso8601String();
    }

    final metadata = AlertAudioMetadataModel.fromMap(normalized);
    return FriendAlertSoundEntity(
      metadata: metadata,
      ownerUid: ownerUid,
      scope: scope,
      friendUid: friendUid,
      cloudinaryPublicId: normalized['cloudinaryPublicId'] as String?,
    );
  }
}
