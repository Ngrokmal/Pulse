import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/offline_queue.dart';
import '../../../../core/services/shared_presence_manager.dart';
import '../../../../core/supabase/user_id_bridge.dart';
import '../../domain/entities/profile_entity.dart';
import '../../domain/entities/profile_visibility.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/profile_local_data_source.dart';
import '../datasources/profile_remote_data_source.dart';
import '../models/profile_model.dart';

class _ColumnMapping {
  final String column;
  final bool isDateOnly;
  const _ColumnMapping(this.column, {this.isDateOnly = false});
}

const Map<String, _ColumnMapping> _kUserFieldColumns = {
  'displayName': _ColumnMapping('display_name'),
  'username': _ColumnMapping('username'),
  'bio': _ColumnMapping('bio'),
  'location': _ColumnMapping('location'),
  'gender': _ColumnMapping('gender'),
  'birthday': _ColumnMapping('birthday', isDateOnly: true),
  'phone': _ColumnMapping('phone'),
  'email': _ColumnMapping('email'),
  'website': _ColumnMapping('website'),
  'avatarUrl': _ColumnMapping('avatar_url'),
  'avatarPublicId': _ColumnMapping('avatar_public_id'),
  'coverUrl': _ColumnMapping('cover_url'),
  'coverPublicId': _ColumnMapping('cover_public_id'),
  'isBanned': _ColumnMapping('is_banned'),
  'bannedAt': _ColumnMapping('banned_at'),
  'banType': _ColumnMapping('ban_type'),
  'banExpiresAt': _ColumnMapping('ban_expires_at'),
  'isDisabled': _ColumnMapping('is_disabled'),
  'disabledAt': _ColumnMapping('disabled_at'),
};

const Map<String, _ColumnMapping> _kSettingsFieldColumns = {
  'notificationsEnabled': _ColumnMapping('notifications_enabled'),
  'profilePrivacy': _ColumnMapping('profile_privacy'),
  'lastSeenVisibility': _ColumnMapping('last_seen_visibility'),
  'onlineStatusVisibility': _ColumnMapping('online_status_visibility'),
  'friendRequestPrivacy': _ColumnMapping('friend_request_privacy'),
  'themeMode': _ColumnMapping('theme_mode'),
  'enterToSend': _ColumnMapping('enter_to_send'),
  'readReceiptsEnabled': _ColumnMapping('read_receipts_enabled'),
  'typingIndicatorEnabled': _ColumnMapping('typing_indicator_enabled'),
  'autoDownloadImages': _ColumnMapping('auto_download_images'),
  'autoDownloadVideos': _ColumnMapping('auto_download_videos'),
  'autoDownloadFiles': _ColumnMapping('auto_download_files'),
  'mediaWifiOnly': _ColumnMapping('media_wifi_only'),
};

String _formatDateOnly(DateTime d) {
  final utc = d.toUtc();
  String pad2(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${pad2(utc.month)}-${pad2(utc.day)}';
}

dynamic _coerceValue(String key, _ColumnMapping mapping, dynamic value) {
  if (value == null) return null;
  if (value is DateTime) {
    return mapping.isDateOnly ? _formatDateOnly(value) : value.toUtc().toIso8601String();
  }
  if (value is String || value is num || value is bool) return value;
  throw ArgumentError(
    'ProfileRepository (Supabase): unsupported value type for field "$key" '
    '(${value.runtimeType}). Only String/num/bool/DateTime/null are '
    'accepted — Firestore FieldValue sentinels are not supported here.',
  );
}

class ProfileRepositoryImpl implements ProfileRepository {
  final ProfileRemoteDataSource remoteDataSource;
  final ProfileLocalDataSource localDataSource;
  final SupabaseClient supabase;
  final SharedPresenceManager presenceManager;

  ProfileRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.supabase,
    required this.presenceManager,
  });

  String? _currentSupabaseUid() => supabase.auth.currentUser?.id;

  Future<String> _resolveSupabaseUid(String uid) {
    return UserIdBridge.resolve(uid, currentSupabaseUserId: _currentSupabaseUid());
  }

  final Map<String, RealtimeChannel> _channelSets = {};
  final Map<String, _MultiplexedProfileStream> _multiplexed = {};

  @override
  Stream<ProfileEntity> streamProfile(String uid) {
    return Stream.multi((controller) {
      late final _MultiplexedProfileStream entry;
      entry = _multiplexed.putIfAbsent(
        uid,
        () => _MultiplexedProfileStream(
          () => _streamProfileRaw(uid),
          onIdle: () {
            if (identical(_multiplexed[uid], entry)) _multiplexed.remove(uid);
          },
        ),
      );
      entry.attach(controller);
    }, isBroadcast: true);
  }

  Stream<ProfileEntity> _streamProfileRaw(String uid) {
    final controller = StreamController<ProfileEntity>();
    bool cancelled = false;
    String? resolvedSupabaseUid;
    ProfileModel? current;
    StreamSubscription<Map<String, dynamic>>? presenceSub;
    Map<String, dynamic>? pendingPresenceRow;

    Future<void> emit(ProfileModel model) async {
      current = model;
      await localDataSource.cacheProfile(model);
      if (!cancelled && !controller.isClosed) controller.add(model);
    }

    Future<void> start() async {
      final cached = await localDataSource.getCachedProfile(uid);
      if (cached != null) {
        current = cached.isOnline ? cached.copyWithModel(isOnline: false) : cached;
        if (!controller.isClosed) controller.add(current!);
      }

      final String supabaseUid;
      try {
        supabaseUid = await _resolveSupabaseUid(uid);
      } catch (e) {
        if (current == null && !controller.isClosed) {
          controller.addError(e);
        }
        return;
      }
      if (cancelled) return;
      resolvedSupabaseUid = supabaseUid;
      final bool isOwnProfile = supabaseUid == _currentSupabaseUid();

      presenceSub = presenceManager.watch(supabaseUid).listen((row) async {
        if (cancelled) return;
        if (current == null) {
          pendingPresenceRow = row;
          return;
        }
        await emit(current!.mergePresenceRow(row));
      });

      final DateTime? cachedSyncedAt = cached != null ? await localDataSource.getLastSyncedAt(uid) : null;
      final bool isDeltaLoad = cached != null && cachedSyncedAt != null;

      Map<String, dynamic>? userRow;
      Map<String, dynamic>? settingsRow;
      try {
        userRow = isDeltaLoad
            ? await remoteDataSource.fetchUserRowUpdatedSince(
                supabaseUid: supabaseUid,
                since: cachedSyncedAt!,
              )
            : await remoteDataSource.fetchUserRow(supabaseUid);
        if (cancelled) return;
        settingsRow = isOwnProfile
            ? await remoteDataSource.fetchSettingsRow(supabaseUid)
            : null;
      } catch (e) {
        if (current == null && !controller.isClosed) {
          controller.addError(
            e is Exception ? e : NetworkException(message: e.toString()),
          );
        }
        return;
      }
      if (cancelled) return;

      if (userRow == null && !isDeltaLoad) {
        if (current == null && !controller.isClosed) {
          controller.addError(StateError('Profile not found: $uid'));
        }
        return;
      }

      if (userRow != null) {
        final fresh = ProfileModel.fromSupabaseRows(
          uid: uid,
          userRow: userRow,
          settingsRow: settingsRow,
        );
        var preserved = current != null
            ? fresh.copyWithModel(isOnline: current!.isOnline, lastSeen: current!.lastSeen, clearLastSeen: current!.lastSeen == null)
            : fresh;
        final pending = pendingPresenceRow;
        if (pending != null) {
          preserved = preserved.mergePresenceRow(pending);
          pendingPresenceRow = null;
        }
        await localDataSource.setLastSyncedAt(uid, DateTime.now());
        await emit(preserved);
      } else if (current != null) {
        var merged = current!;
        if (settingsRow != null) merged = merged.mergeSettingsRow(settingsRow);
        await emit(merged);
      }
      if (cancelled) return;

      final profileChannel = supabase.channel('profile_$supabaseUid');

      profileChannel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'users',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: supabaseUid),
        callback: (payload) async {
          final row = payload.newRecord;
          if (row.isEmpty || current == null) return;
          await localDataSource.setLastSyncedAt(uid, DateTime.now());
          await emit(current!.mergeUsersRow(row));
        },
      );

      if (isOwnProfile) {
        profileChannel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_settings',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'owner_id', value: supabaseUid),
          callback: (payload) async {
            final row = payload.newRecord;
            if (row.isEmpty || current == null) return;
            await emit(current!.mergeSettingsRow(row));
          },
        );
      }

      bool firstSubscribe = true;
      profileChannel.subscribe((status, error) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (firstSubscribe) {
            firstSubscribe = false;
          } else {
            final since = await localDataSource.getLastSyncedAt(uid);
            if (since != null && !cancelled) {
              final delta = await remoteDataSource.fetchUserRowUpdatedSince(supabaseUid: supabaseUid, since: since);
              if (delta != null && current != null && !cancelled) {
                await localDataSource.setLastSyncedAt(uid, DateTime.now());
                await emit(current!.mergeUsersRow(delta));
              }
            }
            if (isOwnProfile && !cancelled) {
              final freshSettings = await remoteDataSource.fetchSettingsRow(supabaseUid);
              if (freshSettings != null && current != null && !cancelled) {
                await emit(current!.mergeSettingsRow(freshSettings));
              }
            }
          }
        }
        if (error != null && current == null && !controller.isClosed) {
          controller.addError(error);
        }
      });

      if (cancelled) {
        await supabase.removeChannel(profileChannel);
        await presenceSub?.cancel();
        return;
      }

      final previous = _channelSets[supabaseUid];
      _channelSets[supabaseUid] = profileChannel;
      if (previous != null) {
        await supabase.removeChannel(previous);
      }
    }

    start();

    controller.onCancel = () async {
      cancelled = true;
      await presenceSub?.cancel();
      final supabaseUid = resolvedSupabaseUid;
      if (supabaseUid != null) {
        final channel = _channelSets[supabaseUid];
        if (channel != null) {
          await supabase.removeChannel(channel);
          if (identical(_channelSets[supabaseUid], channel)) {
            _channelSets.remove(supabaseUid);
          }
        }
      }
      if (!controller.isClosed) await controller.close();
    };

    return controller.stream;
  }

  @override
  Future<void> ensureProfileExists({
    required String uid,
    required String username,
    required String displayName,
    String? email,
  }) async {
    final cached = await localDataSource.getCachedProfile(uid);
    if (cached != null) return;

    final supabaseUid = await _resolveSupabaseUid(uid);
    await remoteDataSource.ensureUserRowExists(
      supabaseUid: supabaseUid,
      username: username,
      displayName: displayName,
      email: email,
    );
  }

  @override
  Future<void> updateProfile({required String uid, required Map<String, dynamic> updates}) async {
    if (updates.isEmpty) return;
    final sanitized = Map<String, dynamic>.from(updates)
      ..remove('verificationStatus')
      ..remove('uid')
      ..remove('friendsCount')
      ..remove('groupsCount');
    if (sanitized.isEmpty) return;

    final userColumns = <String, dynamic>{};
    final settingsColumns = <String, dynamic>{};
    for (final entry in sanitized.entries) {
      final userMapping = _kUserFieldColumns[entry.key];
      final settingsMapping = _kSettingsFieldColumns[entry.key];
      if (userMapping != null) {
        userColumns[userMapping.column] = _coerceValue(entry.key, userMapping, entry.value);
      } else if (settingsMapping != null) {
        settingsColumns[settingsMapping.column] = _coerceValue(entry.key, settingsMapping, entry.value);
      } else {
        throw ArgumentError('ProfileRepository (Supabase): unknown updateProfile field "${entry.key}".');
      }
    }
    if (userColumns.isEmpty && settingsColumns.isEmpty) return;

    final supabaseUid = await _resolveSupabaseUid(uid);

    return OfflineQueueManager.instance.addToQueue(() async {
      if (userColumns.isNotEmpty) {
        await remoteDataSource.updateUserFields(supabaseUid: supabaseUid, columns: userColumns);
      }
      if (settingsColumns.isNotEmpty) {
        await remoteDataSource.updateSettingsFields(supabaseUid: supabaseUid, columns: settingsColumns);
      }
    });
  }

  @override
  Future<void> updateAvatarPhoto({required String uid, required String url, required String publicId}) async {
    final supabaseUid = await _resolveSupabaseUid(uid);
    return OfflineQueueManager.instance.addToQueue(() async {
      await remoteDataSource.updateUserFields(
        supabaseUid: supabaseUid,
        columns: {'avatar_url': url, 'avatar_public_id': publicId},
      );
    });
  }

  @override
  Future<void> removeAvatarPhoto(String uid) async {
    final supabaseUid = await _resolveSupabaseUid(uid);
    return OfflineQueueManager.instance.addToQueue(() async {
      await remoteDataSource.updateUserFields(
        supabaseUid: supabaseUid,
        columns: {'avatar_url': null, 'avatar_public_id': null},
      );
    });
  }

  @override
  Future<void> updateCoverPhoto({required String uid, required String url, required String publicId}) async {
    final supabaseUid = await _resolveSupabaseUid(uid);
    return OfflineQueueManager.instance.addToQueue(() async {
      await remoteDataSource.updateUserFields(
        supabaseUid: supabaseUid,
        columns: {'cover_url': url, 'cover_public_id': publicId},
      );
    });
  }

  @override
  Future<void> removeCoverPhoto(String uid) async {
    final supabaseUid = await _resolveSupabaseUid(uid);
    return OfflineQueueManager.instance.addToQueue(() async {
      await remoteDataSource.updateUserFields(
        supabaseUid: supabaseUid,
        columns: {'cover_url': null, 'cover_public_id': null},
      );
    });
  }

  @override
  Future<void> setOnlineStatus({required String uid, required bool isOnline, required String deviceId}) async {
    final supabaseUid = await _resolveSupabaseUid(uid);
    await remoteDataSource.upsertPresence(
      supabaseUid: supabaseUid,
      isOnline: isOnline,
      lastSeen: DateTime.now(),
      deviceId: deviceId,
    );
  }

  @override
  Future<void> heartbeatPresence({required String uid, required String deviceId}) async {
    await _resolveSupabaseUid(uid);
    await remoteDataSource.heartbeatPresence(deviceId: deviceId);
  }

  @override
  Future<Either<Failure, int>> getFriendsCount(String uid) async {
    try {
      final supabaseUid = await _resolveSupabaseUid(uid);
      final count = await remoteDataSource.fetchFriendsCount(supabaseUid);
      return Right(count);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, int>> getMutualGroupsCount({required String uid, required String otherUid}) async {
    try {
      await _resolveSupabaseUid(uid);
      final otherSupabaseUid = await _resolveSupabaseUid(otherUid);
      final count = await remoteDataSource.fetchMutualGroupsCount(otherSupabaseUid);
      return Right(count);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ProfileVisibility>> getRelationshipStatus({
    required String viewerUid,
    required String profileUid,
  }) async {
    try {
      await _resolveSupabaseUid(viewerUid);
      final profileSupabaseUid = await _resolveSupabaseUid(profileUid);
      final visibility = await remoteDataSource.fetchRelationshipStatus(profileSupabaseUid);
      return Right(visibility);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }
}

class _MultiplexedProfileStream {
  _MultiplexedProfileStream(this._open, {required this.onIdle});

  final Stream<ProfileEntity> Function() _open;
  final void Function() onIdle;

  final Set<MultiStreamController<ProfileEntity>> _controllers = {};
  StreamSubscription<ProfileEntity>? _sourceSub;
  ProfileEntity? _latest;

  void attach(MultiStreamController<ProfileEntity> controller) {
    _controllers.add(controller);

    final latest = _latest;
    if (latest != null) controller.addSync(latest);

    _sourceSub ??= _open().listen(
      (profile) {
        _latest = profile;
        for (final c in List<MultiStreamController<ProfileEntity>>.of(_controllers)) {
          c.addSync(profile);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        for (final c in List<MultiStreamController<ProfileEntity>>.of(_controllers)) {
          c.addErrorSync(error, stackTrace);
        }
      },
    );

    controller.onCancel = () {
      _controllers.remove(controller);
      if (_controllers.isEmpty) {
        _sourceSub?.cancel();
        _sourceSub = null;
        onIdle();
      }
    };
  }
}