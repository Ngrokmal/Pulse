import 'alert_audio_metadata_model.dart';
import '../../domain/entities/alert_audio_metadata_entity.dart';
import '../../domain/entities/friend_alert_sound_entity.dart';

class FriendAlertSoundModel extends FriendAlertSoundEntity {
  const FriendAlertSoundModel({
    required super.metadata,
    required super.ownerUid,
    required super.scope,
    super.friendUid,
    super.cloudinaryPublicId,
  });

  factory FriendAlertSoundModel.fromEntity(FriendAlertSoundEntity e) {
    return FriendAlertSoundModel(
      metadata: e.metadata,
      ownerUid: e.ownerUid,
      scope: e.scope,
      friendUid: e.friendUid,
      cloudinaryPublicId: e.cloudinaryPublicId,
    );
  }

  factory FriendAlertSoundModel.fromSupabaseRow(
    Map<String, dynamic> row, {
    required String ownerUid,
    String? friendUid,
  }) {
    final rawCreatedAt = row['created_at'];
    final DateTime createdAt = rawCreatedAt is String ? DateTime.parse(rawCreatedAt).toLocal() : DateTime.now();

    final metadata = AlertAudioMetadata(
      alertId: row['alert_key'] as String? ?? '',
      displayName: row['display_name'] as String? ?? '',
      audioUrl: row['audio_url'] as String? ?? '',
      checksum: row['checksum'] as String? ?? '',
      format: row['format'] as String? ?? '',
      fileSizeBytes: (row['file_size_bytes'] as num?)?.toInt() ?? 0,
      durationMs: (row['duration_ms'] as num?)?.toInt(),
      createdAt: createdAt,
    );

    return FriendAlertSoundModel(
      metadata: metadata,
      ownerUid: ownerUid,
      scope: (row['scope'] as String?) == 'global' ? FriendAlertSoundScope.global : FriendAlertSoundScope.friendSpecific,
      friendUid: friendUid,
      cloudinaryPublicId: row['cloudinary_public_id'] as String?,
    );
  }

  factory FriendAlertSoundModel.fromCacheJson(Map<String, dynamic> json) {
    final metadata = AlertAudioMetadataModel.fromMap(json);
    return FriendAlertSoundModel(
      metadata: metadata,
      ownerUid: json['ownerUid'] as String? ?? '',
      scope: (json['scope'] as String?) == 'global' ? FriendAlertSoundScope.global : FriendAlertSoundScope.friendSpecific,
      friendUid: json['friendUid'] as String?,
      cloudinaryPublicId: json['cloudinaryPublicId'] as String?,
    );
  }

  Map<String, dynamic> toCacheJson() {
    final map = AlertAudioMetadataModel.fromEntity(metadata).toMap();
    map['ownerUid'] = ownerUid;
    map['scope'] = scope == FriendAlertSoundScope.global ? 'global' : 'friend';
    map['friendUid'] = friendUid;
    map['cloudinaryPublicId'] = cloudinaryPublicId;
    return map;
  }

  Map<String, dynamic> toSupabaseRow({required String ownerId, String? friendId}) {
    return {
      'owner_id': ownerId,
      'friend_id': friendId,
      'scope': isGlobal ? 'global' : 'friend',
      'alert_key': alertId,
      'display_name': displayName,
      'audio_url': metadata.audioUrl,
      'checksum': metadata.checksum,
      'format': metadata.format,
      'file_size_bytes': metadata.fileSizeBytes,
      'duration_ms': metadata.durationMs,
      'cloudinary_public_id': cloudinaryPublicId,
    };
  }
}
