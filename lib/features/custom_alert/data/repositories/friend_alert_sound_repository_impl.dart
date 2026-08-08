import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/offline_queue.dart';
import '../../../../core/supabase/user_id_bridge.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../chat/domain/repositories/media_repository.dart';
import '../../domain/entities/alert_audio_metadata_entity.dart';
import '../../domain/entities/friend_alert_sound_entity.dart';
import '../../domain/repositories/custom_alert_repository.dart';
import '../../domain/repositories/friend_alert_sound_repository.dart';
import '../datasources/alert_sound_local_data_source.dart';
import '../datasources/alert_sound_remote_data_source.dart';
import '../models/friend_alert_sound_model.dart';

class FriendAlertSoundRepositoryImpl implements FriendAlertSoundRepository {
  static const String _cloudinaryFolder = 'alert_sounds';
  static const String _cloudinaryResourceType = 'video';

  final AlertSoundRemoteDataSource remoteDataSource;
  final AlertSoundLocalDataSource localDataSource;
  final MediaRepository mediaRepository;
  final CustomAlertRepository customAlertRepository;
  final SupabaseClient supabase;

  FriendAlertSoundRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.mediaRepository,
    required this.customAlertRepository,
    required this.supabase,
  });

  final Map<String, RealtimeChannel> _channels = {};

  @override
  Stream<List<FriendAlertSoundEntity>> watchSoundsForFriend({
    required String ownerUid,
    required String friendUid,
  }) {
    final controller = StreamController<List<FriendAlertSoundEntity>>();
    bool cancelled = false;
    String? ownerUuid;

    List<FriendAlertSoundEntity> filterFor(List<FriendAlertSoundEntity> all) {
      return all.where((s) => s.usableFor(friendUid)).toList();
    }

    Future<void> emitFromCache() async {
      final cached = await localDataSource.getCachedSounds(ownerUid);
      if (!controller.isClosed) controller.add(filterFor(cached));
    }

    Future<void> runDelta() async {
      await SyncEngine.instance.runDelta<Map<String, dynamic>>(
        getCursor: () => localDataSource.getSyncedAt(ownerUid),
        setCursor: (time) => localDataSource.setSyncedAt(ownerUid, time),
        fetchChanges: (since) => remoteDataSource.fetchChangedSounds(ownerUid: ownerUid, since: since),
        updatedAtOf: (row) {
          final raw = row['updated_at'];
          return raw is String ? DateTime.parse(raw).toLocal() : DateTime.now();
        },
        isTombstone: (row) => row['deleted_at'] != null,
        onTombstone: (row) async {
          final alertKey = row['alert_key'] as String?;
          if (alertKey == null) return;
          await localDataSource.deleteCachedSound(ownerUid, alertKey);
        },
        onUpsert: (row) async {
          final friendId = row['friend_id'] as String?;
          final rowFriendUid = friendId == null ? null : (await UserIdBridge.reverseResolve(friendId) ?? friendId);
          final sound = FriendAlertSoundModel.fromSupabaseRow(row, ownerUid: ownerUid, friendUid: rowFriendUid);
          await localDataSource.upsertSounds(ownerUid, [sound]);
        },
      );
      await emitFromCache();
    }

    Future<void> start() async {
      await emitFromCache();
      if (cancelled) return;

      final String resolvedUuid;
      try {
        resolvedUuid = await UserIdBridge.resolve(ownerUid, currentSupabaseUserId: supabase.auth.currentUser?.id);
      } catch (_) {
        return;
      }
      if (cancelled) return;
      ownerUuid = resolvedUuid;

      final channel = supabase.channel('alert_sounds_$resolvedUuid').onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'alert_sounds',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'owner_id', value: resolvedUuid),
            callback: (payload) {
              if (payload.eventType == PostgresChangeEvent.delete) {
                final alertKey = payload.oldRecord['alert_key'] as String?;
                if (alertKey == null) return;
                localDataSource.deleteCachedSound(ownerUid, alertKey).then((_) => emitFromCache());
                return;
              }
              runDelta();
            },
          );

      channel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) runDelta();
        if (error != null && !controller.isClosed) controller.addError(error);
      });

      if (cancelled) {
        await supabase.removeChannel(channel);
        return;
      }
      final existing = _channels[resolvedUuid];
      if (existing != null) await supabase.removeChannel(existing);
      _channels[resolvedUuid] = channel;
    }

    start();

    controller.onCancel = () async {
      cancelled = true;
      final uuid = ownerUuid;
      if (uuid != null) {
        final channel = _channels[uuid];
        if (channel != null) {
          await supabase.removeChannel(channel);
          if (identical(_channels[uuid], channel)) _channels.remove(uuid);
        }
      }
      if (!controller.isClosed) await controller.close();
    };

    return controller.stream;
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
    if (durationMs <= 0 || durationMs > 20000) {
      throw ServerException(message: 'Alert sounds must be between 1 and 20 seconds.');
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

    await OfflineQueueManager.instance.addToQueue(() => remoteDataSource.saveSound(sound));
    await localDataSource.upsertSounds(ownerUid, [sound]);

    try {
      await customAlertRepository.ensureAudioCached(metadata);
    } catch (_) {
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

    await OfflineQueueManager.instance.addToQueue(() => remoteDataSource.saveSound(renamed));
    await localDataSource.upsertSounds(renamed.ownerUid, [renamed]);

    try {
      await customAlertRepository.evictAudioCache(renamed.alertId);
      await customAlertRepository.ensureAudioCached(renamed.metadata);
    } catch (_) {
    }

    return renamed;
  }

  @override
  Future<FriendAlertSoundEntity> replaceSoundAudio({
    required FriendAlertSoundEntity sound,
    required File audioFile,
    required int durationMs,
  }) async {
    if (durationMs <= 0 || durationMs > 20000) {
      throw ServerException(message: 'Alert sounds must be between 1 and 20 seconds.');
    }

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

    await OfflineQueueManager.instance.addToQueue(() => remoteDataSource.saveSound(replaced));
    await localDataSource.upsertSounds(replaced.ownerUid, [replaced]);

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
      }
    }

    return replaced;
  }

  static const String deleteSoundOpType = 'customAlert.deleteSound';

  @override
  Future<void> deleteSound(FriendAlertSoundEntity sound) async {
    await localDataSource.deleteCachedSound(sound.ownerUid, sound.alertId);
    await OfflineQueueManager.instance.addPersistentTask(
      opType: deleteSoundOpType,
      taskId: '$deleteSoundOpType:${sound.ownerUid}:${sound.alertId}',
      payload: {'ownerUid': sound.ownerUid, 'alertId': sound.alertId},
    );

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
      }
    }
  }

  void registerOfflineQueueHandlers() {
    OfflineQueueManager.instance.registerHandler(deleteSoundOpType, (payload) {
      final ownerUid = payload['ownerUid'] as String;
      final alertId = payload['alertId'] as String;
      return remoteDataSource.deleteSound(
        FriendAlertSoundModel(
          metadata: AlertAudioMetadata(
            alertId: alertId,
            displayName: '',
            audioUrl: '',
            checksum: '',
            format: '',
            fileSizeBytes: 0,
            createdAt: DateTime.now(),
          ),
          ownerUid: ownerUid,
          scope: FriendAlertSoundScope.global,
        ),
      );
    });
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
