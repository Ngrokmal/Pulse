import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/network/offline_queue.dart';
import '../../../../core/services/presence_activity_pinger.dart';
import '../../../../core/supabase/user_id_bridge.dart';
import '../../../../core/sync/group_delta_sync_coordinator.dart';
import '../../domain/entities/group_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/group_repository.dart';
import '../datasources/chat_local_data_source.dart';
import '../datasources/chat_remote_data_source.dart';
import '../datasources/group_delta_remote_data_source.dart';
import '../datasources/group_info_local_data_source.dart';
import '../models/message_model.dart';
import '../services/group_offline_queue_service.dart';

class GroupRepositoryImpl implements GroupRepository {
  final ChatRemoteDataSource remoteDataSource;
  final ChatLocalDataSource localDataSource;
  final SupabaseClient supabase;
  final PresenceActivityPinger presenceActivityPinger;
  final Uuid _uuid = const Uuid();

  final GroupInfoLocalDataSource groupInfoLocalDataSource;
  final GroupDeltaRemoteDataSource groupDeltaRemoteDataSource;

  final Map<String, RealtimeChannel> _groupInfoChannels = {};
  final Map<String, RealtimeChannel> _messagesChannels = {};
  final Map<String, RealtimeChannel> _typingChannels = {};

  GroupRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.supabase,
    required this.presenceActivityPinger,
    GroupInfoLocalDataSource? groupInfoLocalDataSource,
    GroupDeltaRemoteDataSource? groupDeltaRemoteDataSource,
  })  : groupInfoLocalDataSource = groupInfoLocalDataSource ?? GroupInfoLocalDataSourceImpl(),
        groupDeltaRemoteDataSource =
            groupDeltaRemoteDataSource ?? GroupDeltaRemoteDataSource(supabase: supabase) {
    GroupDeltaSyncCoordinator.instance.configure(_runBatchedGroupDelta);
  }

  String? _currentSupabaseUid() => supabase.auth.currentUser?.id;

  Future<String> _resolveUid(String firebaseUid) {
    return UserIdBridge.resolve(firebaseUid, currentSupabaseUserId: _currentSupabaseUid());
  }

  Future<String> _reverseResolve(String supabaseUid) async {
    return await UserIdBridge.reverseResolve(supabaseUid) ?? supabaseUid;
  }

  @override
  String generateGroupId() {
    return _uuid.v4();
  }

  @override
  Future<void> createGroup({
    required String groupId,
    required String name,
    required String creatorId,
    required List<String> initialMembers,
  }) async {
    final creatorSupabaseId = await _resolveUid(creatorId);
    final memberSupabaseIds = <String>[];
    for (final uid in initialMembers) {
      memberSupabaseIds.add(await _resolveUid(uid));
    }

    await supabase.from('chats').insert({
      'id': groupId,
      'type': 'group',
      'name': name,
      'creator_id': creatorSupabaseId,
    });

    final memberRows = memberSupabaseIds
        .map((uid) => {
              'chat_id': groupId,
              'user_id': uid,
              'role': uid == creatorSupabaseId ? 'admin' : 'member',
            })
        .toList();
    await supabase.from('chat_members').insert(memberRows);
  }

  Future<GroupEntity> _buildGroupEntity(String groupId) async {
    final chatRow = await supabase
        .from('chats')
        .select('id, name, creator_id, group_photo_url, group_photo_public_id, created_at')
        .eq('id', groupId)
        .single();

    final memberRows = await supabase
        .from('chat_members')
        .select('user_id, role')
        .eq('chat_id', groupId)
        .isFilter('left_at', null);

    final memberUids = <String>[];
    final adminUids = <String>[];
    for (final row in memberRows) {
      final firebaseUid = await _reverseResolve(row['user_id'] as String);
      memberUids.add(firebaseUid);
      if (row['role'] == 'admin') adminUids.add(firebaseUid);
    }

    final creatorSupabaseId = chatRow['creator_id'] as String?;
    final creatorId = creatorSupabaseId != null ? await _reverseResolve(creatorSupabaseId) : '';

    final rawCreatedAt = chatRow['created_at'];
    final createdAt = rawCreatedAt is String ? DateTime.parse(rawCreatedAt).toLocal() : DateTime.now();

    return GroupEntity(
      groupId: chatRow['id'] as String? ?? groupId,
      name: chatRow['name'] as String? ?? '',
      creatorId: creatorId,
      cachedMemberUids: memberUids,
      adminIds: adminUids,
      createdAt: createdAt,
      groupPhotoUrl: chatRow['group_photo_url'] as String?,
      groupPhotoPublicId: chatRow['group_photo_public_id'] as String?,
    );
  }

  Future<Map<String, dynamic>?> _buildMemberCacheRow(Map<String, dynamic> row) async {
    final supabaseUserId = row['user_id'] as String?;
    if (supabaseUserId == null) return null;
    final firebaseUid = await _reverseResolve(supabaseUserId);
    return {
      'user_id': supabaseUserId,
      'role': row['role'] as String? ?? 'member',
      'left_at': row['left_at'],
      'firebase_uid': firebaseUid,
    };
  }

  Future<void> _cacheMemberRow(String groupId, Map<String, dynamic> row) async {
    final cacheRow = await _buildMemberCacheRow(row);
    if (cacheRow == null) return;
    await groupInfoLocalDataSource.upsertMembers(groupId, [cacheRow]);
  }

  Future<void> _runBatchedGroupDelta(List<String> groupIds) async {
    if (groupIds.isEmpty) return;

    DateTime? infoFloor;
    DateTime? membersFloor;
    for (final id in groupIds) {
      final infoCursor = await groupInfoLocalDataSource.getGroupInfoCursor(id);
      final membersCursor = await groupInfoLocalDataSource.getMembersCursor(id);
      final infoEpoch = infoCursor ?? DateTime.fromMillisecondsSinceEpoch(0);
      final membersEpoch = membersCursor ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (infoFloor == null || infoEpoch.isBefore(infoFloor)) infoFloor = infoEpoch;
      if (membersFloor == null || membersEpoch.isBefore(membersFloor)) membersFloor = membersEpoch;
    }
    infoFloor ??= DateTime.fromMillisecondsSinceEpoch(0);
    membersFloor ??= DateTime.fromMillisecondsSinceEpoch(0);

    final infoRows = await groupDeltaRemoteDataSource.fetchGroupsInfoDelta(
      groupIds: groupIds,
      since: infoFloor,
    );
    for (final row in infoRows) {
      final id = row['id'] as String?;
      if (id == null) continue;
      final rawCreatedAt = row['created_at'];
      final createdAt = rawCreatedAt is String ? DateTime.parse(rawCreatedAt).toLocal() : DateTime.now();
      final creatorSupabaseId = row['creator_id'] as String?;
      final creatorId = creatorSupabaseId != null ? await _reverseResolve(creatorSupabaseId) : '';
      await groupInfoLocalDataSource.upsertGroupBase(
        id,
        GroupEntity(
          groupId: id,
          name: row['name'] as String? ?? '',
          creatorId: creatorId,
          cachedMemberUids: const [],
          adminIds: const [],
          createdAt: createdAt,
          groupPhotoUrl: row['group_photo_url'] as String?,
          groupPhotoPublicId: row['group_photo_public_id'] as String?,
        ),
      );
      final rawUpdatedAt = row['updated_at'];
      final updatedAt = rawUpdatedAt is String ? DateTime.parse(rawUpdatedAt).toLocal() : createdAt;
      await groupInfoLocalDataSource.setGroupInfoCursor(id, updatedAt);
    }

    final memberRows = await groupDeltaRemoteDataSource.fetchGroupMembersDelta(
      groupIds: groupIds,
      since: membersFloor,
    );
    final latestMembersUpdateByGroup = <String, DateTime>{};
    final rowsByGroup = <String, List<Map<String, dynamic>>>{};
    for (final row in memberRows) {
      final chatId = row['chat_id'] as String?;
      if (chatId == null) continue;
      final cacheRow = await _buildMemberCacheRow(row);
      if (cacheRow != null) {
        rowsByGroup.putIfAbsent(chatId, () => []).add(cacheRow);
      }
      final rawUpdatedAt = row['updated_at'];
      if (rawUpdatedAt is String) {
        final updatedAt = DateTime.parse(rawUpdatedAt).toLocal();
        final current = latestMembersUpdateByGroup[chatId];
        if (current == null || updatedAt.isAfter(current)) latestMembersUpdateByGroup[chatId] = updatedAt;
      }
    }
    for (final entry in rowsByGroup.entries) {
      await groupInfoLocalDataSource.upsertMembers(entry.key, entry.value);
    }
    if (latestMembersUpdateByGroup.isNotEmpty) {
      for (final entry in latestMembersUpdateByGroup.entries) {
        await groupInfoLocalDataSource.setMembersCursor(entry.key, entry.value);
      }
    } else if (memberRows.isNotEmpty) {
      final now = DateTime.now();
      for (final id in groupIds) {
        await groupInfoLocalDataSource.setMembersCursor(id, now);
      }
    }
  }

  @override
  Stream<GroupEntity> streamGroup(String groupId) {
    final controller = StreamController<GroupEntity>();
    bool hasEmittedData = false;

    Future<void> emitFromCache() async {
      final cached = await groupInfoLocalDataSource.getCachedGroup(groupId);
      if (cached != null && !controller.isClosed) {
        hasEmittedData = true;
        controller.add(cached);
      }
    }

    Future<void> bootstrapFromNetwork() async {
      try {
        final group = await _buildGroupEntity(groupId);
        await groupInfoLocalDataSource.upsertGroupBase(groupId, group);
        final now = DateTime.now();
        final memberRows = await supabase
            .from('chat_members')
            .select('user_id, role, left_at')
            .eq('chat_id', groupId);
        final cacheRows = <Map<String, dynamic>>[];
        for (final row in memberRows) {
          final cacheRow = await _buildMemberCacheRow(Map<String, dynamic>.from(row));
          if (cacheRow != null) cacheRows.add(cacheRow);
        }
        if (cacheRows.isNotEmpty) {
          await groupInfoLocalDataSource.upsertMembers(groupId, cacheRows);
        }
        await groupInfoLocalDataSource.setGroupInfoCursor(groupId, now);
        await groupInfoLocalDataSource.setMembersCursor(groupId, now);
        await emitFromCache();
      } catch (err) {
        if (!hasEmittedData && !controller.isClosed) {
          controller.addError(StateError('Group not found: $groupId'));
        }
      }
    }

    Future<void> start() async {
      final cached = await groupInfoLocalDataSource.getCachedGroup(groupId);
      if (cached != null) {
        if (!controller.isClosed) {
          hasEmittedData = true;
          controller.add(cached);
        }
      } else {
        await bootstrapFromNetwork();
      }

      GroupDeltaSyncCoordinator.instance.registerActiveGroup(groupId, () {
        // ignore: discarded_futures
        emitFromCache();
      });

      bool hasSubscribedOnce = false;

      final channel = supabase
          .channel('group_info_$groupId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'chats',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: groupId),
            callback: (payload) async {
              final row = payload.newRecord;
              if (row.isEmpty) return;
              final rawCreatedAt = row['created_at'];
              final createdAt = rawCreatedAt is String ? DateTime.parse(rawCreatedAt).toLocal() : DateTime.now();
              final creatorSupabaseId = row['creator_id'] as String?;
              final creatorId = creatorSupabaseId != null ? await _reverseResolve(creatorSupabaseId) : '';
              await groupInfoLocalDataSource.upsertGroupBase(
                groupId,
                GroupEntity(
                  groupId: groupId,
                  name: row['name'] as String? ?? '',
                  creatorId: creatorId,
                  cachedMemberUids: const [],
                  adminIds: const [],
                  createdAt: createdAt,
                  groupPhotoUrl: row['group_photo_url'] as String?,
                  groupPhotoPublicId: row['group_photo_public_id'] as String?,
                ),
              );
              final rawUpdatedAt = row['updated_at'];
              if (rawUpdatedAt is String) {
                await groupInfoLocalDataSource.setGroupInfoCursor(groupId, DateTime.parse(rawUpdatedAt).toLocal());
              }
              await emitFromCache();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_members',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'chat_id', value: groupId),
            callback: (payload) async {
              final row = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
              if (row.isEmpty) return;
              await _cacheMemberRow(groupId, row);
              await emitFromCache();
            },
          );

      channel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (hasSubscribedOnce) GroupDeltaSyncCoordinator.instance.notifyReconnect();
          hasSubscribedOnce = true;
        }
        if (error != null && !hasEmittedData && !controller.isClosed) controller.addError(error);
      });

      final existing = _groupInfoChannels[groupId];
      if (existing != null) await supabase.removeChannel(existing);
      _groupInfoChannels[groupId] = channel;
    }

    start();

    controller.onCancel = () async {
      GroupDeltaSyncCoordinator.instance.unregisterActiveGroup(groupId);
      final channel = _groupInfoChannels[groupId];
      if (channel != null) {
        await supabase.removeChannel(channel);
        if (identical(_groupInfoChannels[groupId], channel)) {
          _groupInfoChannels.remove(groupId);
        }
      }
      if (!controller.isClosed) await controller.close();
    };

    return controller.stream;
  }

  @override
  Future<void> addMember({required String groupId, required String uid}) async {
    return OfflineQueueManager.instance.addToQueue(() async {
      final supabaseUid = await _resolveUid(uid);
      await supabase.from('chat_members').upsert({
        'chat_id': groupId,
        'user_id': supabaseUid,
        'role': 'member',
        'left_at': null,
        'joined_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'chat_id,user_id');
    });
  }

  @override
  Future<void> removeMember({required String groupId, required String uid}) async {
    return OfflineQueueManager.instance.addToQueue(() async {
      final supabaseUid = await _resolveUid(uid);
      await supabase
          .from('chat_members')
          .update({'left_at': DateTime.now().toUtc().toIso8601String()})
          .eq('chat_id', groupId)
          .eq('user_id', supabaseUid);
    });
  }

  @override
  Future<void> leaveGroup({required String groupId, required String uid}) async {
    return OfflineQueueManager.instance.addToQueue(() async {
      final supabaseUid = await _resolveUid(uid);

      final activeMembers = await supabase
          .from('chat_members')
          .select('user_id, joined_at')
          .eq('chat_id', groupId)
          .isFilter('left_at', null)
          .order('joined_at', ascending: true);

      final remaining =
          activeMembers.where((m) => m['user_id'] != supabaseUid).toList();

      if (remaining.isEmpty) {
        await supabase.from('chats').delete().eq('id', groupId);
        return;
      }

      final chatRow = await supabase.from('chats').select('creator_id').eq('id', groupId).single();
      final currentCreatorId = chatRow['creator_id'] as String?;

      if (currentCreatorId == supabaseUid) {
        final newCreatorId = remaining.first['user_id'] as String;
        await supabase.from('chats').update({'creator_id': newCreatorId}).eq('id', groupId);
        await supabase
            .from('chat_members')
            .update({'role': 'admin'})
            .eq('chat_id', groupId)
            .eq('user_id', newCreatorId);
      }

      await supabase
          .from('chat_members')
          .update({'left_at': DateTime.now().toUtc().toIso8601String()})
          .eq('chat_id', groupId)
          .eq('user_id', supabaseUid);
    });
  }

  @override
  Future<void> promoteToAdmin({required String groupId, required String uid}) async {
    return OfflineQueueManager.instance.addToQueue(() async {
      final supabaseUid = await _resolveUid(uid);
      await supabase.from('chat_members').update({'role': 'admin'}).eq('chat_id', groupId).eq('user_id', supabaseUid);
    });
  }

  @override
  Future<void> demoteAdmin({required String groupId, required String uid}) async {
    return OfflineQueueManager.instance.addToQueue(() async {
      final supabaseUid = await _resolveUid(uid);
      await supabase.from('chat_members').update({'role': 'member'}).eq('chat_id', groupId).eq('user_id', supabaseUid);
    });
  }

  @override
  Future<void> updateGroupName({required String groupId, required String name}) async {
    return OfflineQueueManager.instance.addToQueue(() async {
      await supabase.from('chats').update({'name': name}).eq('id', groupId);
    });
  }

  @override
  Future<void> updateGroupPhoto({
    required String groupId,
    required String photoUrl,
    required String publicId,
  }) async {
    return OfflineQueueManager.instance.addToQueue(() async {
      await supabase.from('chats').update({
        'group_photo_url': photoUrl,
        'group_photo_public_id': publicId,
      }).eq('id', groupId);
    });
  }

  @override
  String generateMessageId(String groupId) {
    return _uuid.v4();
  }

  @override
  Future<void> sendGroupMessage({
    required String groupId,
    required String messageId,
    required String senderId,
    required String text,
  }) async {
    final localModel = MessageModel(
      messageId: messageId,
      chatId: groupId,
      senderId: senderId,
      text: text,
      createdAt: DateTime.now(),
      status: 'sending',
      syncStatus: 'pending',
    );

    presenceActivityPinger.ping();

    await localDataSource.upsertMessages(groupId, [localModel]);

    unawaited(_sendGroupTextMessageRemote(
      groupId: groupId,
      messageId: messageId,
      senderId: senderId,
      text: text,
      localModel: localModel,
    ));
  }

  Future<void> _sendGroupTextMessageRemote({
    required String groupId,
    required String messageId,
    required String senderId,
    required String text,
    required MessageModel localModel,
  }) async {
    final row = localModel.toSupabaseRow()..['status'] = 'sent';

    try {
      await GroupOfflineQueueService.instance.enqueue(
        opType: GroupOfflineQueueOpType.sendMessage,
        groupId: groupId,
        messageId: messageId,
        priority: 0,
        payload: {
          'senderId': senderId,
          'text': text,
          'row': row,
        },
      );

      await localDataSource.upsertMessages(groupId, [
        localModel.copyWithSyncStatus(status: 'sent', syncStatus: 'synced'),
      ]);
    } catch (e) {
      await localDataSource.upsertMessages(groupId, [
        localModel.copyWithSyncStatus(status: 'failed', syncStatus: 'failed'),
      ]);
    }
  }

  @override
  Future<void> resetUnreadCount({
    required String groupId,
    required String uid,
  }) async {
    unawaited(() async {
      try {
        await OfflineQueueManager.instance.addToQueue(() async {
          final supabaseUid = await _resolveUid(uid);
          await supabase
              .from('chat_members')
              .update({'unread_count': 0})
              .eq('chat_id', groupId)
              .eq('user_id', supabaseUid);
        });
      } catch (e) {
      }
    }());
  }

  @override
  Future<void> markMessageAsRead({
    required String groupId,
    required String messageId,
    required String uid,
  }) async {
    presenceActivityPinger.ping();
    unawaited(() async {
      try {
        await GroupOfflineQueueService.instance.enqueue(
          opType: GroupOfflineQueueOpType.readReceipt,
          groupId: groupId,
          messageId: messageId,
          subKey: uid,
          priority: 1,
          payload: {'uid': uid},
        );
      } catch (e) {
      }
    }());
  }

  @override
  Future<void> markMessageAsDelivered({
    required String groupId,
    required String messageId,
  }) async {
    unawaited(() async {
      try {
        await GroupOfflineQueueService.instance.enqueue(
          opType: GroupOfflineQueueOpType.deliveryReceipt,
          groupId: groupId,
          messageId: messageId,
          priority: 1,
          payload: const {},
        );
      } catch (e) {
      }
    }());
  }


  @override
  Future<void> editGroupMessage({
    required String groupId,
    required String messageId,
    required String text,
  }) async {
    final previous = await localDataSource.getCachedMessage(groupId, messageId);
    if (previous != null) {
      final prevModel = MessageModel.fromEntity(previous);
      await localDataSource.upsertMessages(groupId, [
        MessageModel(
          messageId: prevModel.messageId,
          chatId: prevModel.chatId,
          senderId: prevModel.senderId,
          text: text,
          createdAt: prevModel.createdAt,
          status: prevModel.status,
          type: prevModel.type,
          mediaUrl: prevModel.mediaUrl,
          thumbnailUrl: prevModel.thumbnailUrl,
          fileName: prevModel.fileName,
          fileSizeBytes: prevModel.fileSizeBytes,
          mimeType: prevModel.mimeType,
          durationMs: prevModel.durationMs,
          width: prevModel.width,
          height: prevModel.height,
          waveform: prevModel.waveform,
          localFilePath: prevModel.localFilePath,
          uploadState: prevModel.uploadState,
          syncStatus: 'pending',
          alertId: prevModel.alertId,
          alertDisplayName: prevModel.alertDisplayName,
          alertAudioUrl: prevModel.alertAudioUrl,
          alertAudioChecksum: prevModel.alertAudioChecksum,
          alertAudioFormat: prevModel.alertAudioFormat,
          alertAudioSizeBytes: prevModel.alertAudioSizeBytes,
          alertAudioDurationMs: prevModel.alertAudioDurationMs,
        ),
      ]);
    }

    unawaited(() async {
      try {
        await GroupOfflineQueueService.instance.enqueue(
          opType: GroupOfflineQueueOpType.editMessage,
          groupId: groupId,
          messageId: messageId,
          priority: 1,
          payload: {'text': text},
        );
        if (previous != null) {
          final synced = await localDataSource.getCachedMessage(groupId, messageId);
          if (synced != null) {
            await localDataSource.upsertMessages(groupId, [
              MessageModel.fromEntity(synced).copyWithSyncStatus(status: synced.status, syncStatus: 'synced'),
            ]);
          }
        }
      } catch (e) {
        if (previous != null) {
          await localDataSource.upsertMessages(groupId, [
            MessageModel.fromEntity(previous).copyWithSyncStatus(status: previous.status, syncStatus: 'failed'),
          ]);
        }
      }
    }());
  }

  @override
  Future<void> deleteGroupMessage({
    required String groupId,
    required String messageId,
  }) async {
    final previous = await localDataSource.getCachedMessage(groupId, messageId);

    await localDataSource.deleteCachedMessage(groupId, messageId);

    unawaited(() async {
      try {
        await GroupOfflineQueueService.instance.enqueue(
          opType: GroupOfflineQueueOpType.deleteMessage,
          groupId: groupId,
          messageId: messageId,
          priority: 2,
          payload: const {},
        );
      } catch (e) {
        if (previous != null) {
          await localDataSource.upsertMessages(groupId, [
            MessageModel.fromEntity(previous).copyWithSyncStatus(status: previous.status, syncStatus: 'failed'),
          ]);
        }
      }
    }());
  }

  @override
  Future<void> updateAttachmentMetadata({
    required String groupId,
    required String messageId,
    required Map<String, dynamic> fields,
  }) async {
    const snakeToCacheKey = {
      'media_url': 'mediaUrl',
      'thumbnail_url': 'thumbnailUrl',
      'file_name': 'fileName',
      'file_size_bytes': 'fileSizeBytes',
      'mime_type': 'mimeType',
      'duration_ms': 'durationMs',
      'width': 'width',
      'height': 'height',
      'waveform': 'waveform',
    };
    final previous = await localDataSource.getCachedMessage(groupId, messageId);
    if (previous != null) {
      final prevModel = MessageModel.fromEntity(previous);
      final patchedRow = prevModel.toCacheJson();
      for (final entry in fields.entries) {
        final cacheKey = snakeToCacheKey[entry.key];
        if (cacheKey != null) patchedRow[cacheKey] = entry.value;
      }
      patchedRow['syncStatus'] = 'pending';
      await localDataSource.upsertMessages(groupId, [MessageModel.fromCacheJson(patchedRow)]);
    }

    unawaited(() async {
      try {
        await GroupOfflineQueueService.instance.enqueue(
          opType: GroupOfflineQueueOpType.attachmentMetadata,
          groupId: groupId,
          messageId: messageId,
          priority: 1,
          payload: {'fields': fields},
        );
        final synced = await localDataSource.getCachedMessage(groupId, messageId);
        if (synced != null) {
          await localDataSource.upsertMessages(groupId, [
            MessageModel.fromEntity(synced).copyWithSyncStatus(status: synced.status, syncStatus: 'synced'),
          ]);
        }
      } catch (e) {
        final current = await localDataSource.getCachedMessage(groupId, messageId);
        if (current != null) {
          await localDataSource.upsertMessages(groupId, [
            MessageModel.fromEntity(current).copyWithSyncStatus(status: current.status, syncStatus: 'failed'),
          ]);
        }
      }
    }());
  }

  @override
  Future<void> addReaction({
    required String groupId,
    required String messageId,
    required String uid,
    required String reaction,
  }) async {
    unawaited(() async {
      try {
        await GroupOfflineQueueService.instance.enqueue(
          opType: GroupOfflineQueueOpType.reactionAdd,
          groupId: groupId,
          messageId: messageId,
          subKey: uid,
          priority: 1,
          payload: {'uid': uid, 'reaction': reaction},
        );
      } catch (e) {
      }
    }());
  }

  @override
  Future<void> removeReaction({
    required String groupId,
    required String messageId,
    required String uid,
    required String reaction,
  }) async {
    unawaited(() async {
      try {
        await GroupOfflineQueueService.instance.enqueue(
          opType: GroupOfflineQueueOpType.reactionRemove,
          groupId: groupId,
          messageId: messageId,
          subKey: uid,
          priority: 1,
          payload: {'uid': uid, 'reaction': reaction},
        );
      } catch (e) {
      }
    }());
  }

  void registerOfflineQueueHandlers() {
    GroupOfflineQueueService.instance.registerHandlers(
      supabase: supabase,
      remoteDataSource: remoteDataSource,
      resolveUid: _resolveUid,
    );
  }

  @override
  Stream<List<MessageEntity>> streamGroupMessages(String groupId) {
    final controller = StreamController<List<MessageEntity>>();
    bool hasEmittedData = false;

    Future<void> runDelta() async {
      try {
      final cursor = await localDataSource.getLastSyncedAt(groupId) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final cursorIso = cursor.toUtc().toIso8601String();

      final rows = await supabase
          .from('messages')
          .select()
          .eq('chat_id', groupId)
          .or('created_at.gt.$cursorIso,updated_at.gt.$cursorIso')
          .order('created_at')
          .order('id');

      if (rows.isEmpty) return;

      final changed = <MessageModel>[];
      DateTime latest = cursor;
      for (final row in rows) {
        if (row['deleted_at'] != null) continue;

        final model = MessageModel.fromSupabaseRow(row, chatId: groupId);
        changed.add(model);
        final rawUpdatedAt = row['updated_at'];
        final updatedAt = rawUpdatedAt is String ? DateTime.parse(rawUpdatedAt).toLocal() : model.createdAt;
        if (updatedAt.isAfter(latest)) latest = updatedAt;
      }

      await localDataSource.upsertMessages(groupId, changed);
      await localDataSource.setLastSyncedAt(groupId, latest);

      if (!controller.isClosed) {
        hasEmittedData = true;
        controller.add(await localDataSource.getCachedMessages(groupId));
      }
      } catch (_) {
      }
    }

    Future<void> start() async {
      final cachedMessages = await localDataSource.getCachedMessages(groupId);
      if (!controller.isClosed) {
        hasEmittedData = true;
        controller.add(cachedMessages);
      }


      final channel = supabase.channel('group_messages_$groupId').onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'chat_id', value: groupId),
        callback: (payload) async {
          final row = payload.newRecord;
          if (row.isEmpty) return;
          presenceActivityPinger.ping();
          final model = MessageModel.fromSupabaseRow(row, chatId: groupId);
          await localDataSource.upsertMessages(groupId, [model]);

          final rawUpdatedAt = row['updated_at'];
          final updatedAt = rawUpdatedAt is String ? DateTime.parse(rawUpdatedAt).toLocal() : model.createdAt;
          final existingCursor = await localDataSource.getLastSyncedAt(groupId);
          if (existingCursor == null || updatedAt.isAfter(existingCursor)) {
            await localDataSource.setLastSyncedAt(groupId, updatedAt);
          }

          if (!controller.isClosed) {
            hasEmittedData = true;
            controller.add(await localDataSource.getCachedMessages(groupId));
          }
        },
      );

      channel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) runDelta();
        if (error != null && !hasEmittedData && !controller.isClosed) controller.addError(error);
      });

      final existing = _messagesChannels[groupId];
      if (existing != null) await supabase.removeChannel(existing);
      _messagesChannels[groupId] = channel;
    }

    start();

    controller.onCancel = () async {
      final channel = _messagesChannels[groupId];
      if (channel != null) {
        await supabase.removeChannel(channel);
        if (identical(_messagesChannels[groupId], channel)) {
          _messagesChannels.remove(groupId);
        }
      }
      if (!controller.isClosed) await controller.close();
    };

    return controller.stream;
  }

  @override
  Future<void> setTypingStatus({
    required String groupId,
    required String uid,
    required bool isTyping,
  }) async {
    presenceActivityPinger.ping();
    final supabaseUid = await _resolveUid(uid);
    await supabase.from('chat_members').update({
      'is_typing': isTyping,
      'typing_updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('chat_id', groupId).eq('user_id', supabaseUid);
  }

  @override
  Stream<List<String>> streamTypingUserIds(String groupId) {
    final controller = StreamController<List<String>>();
    bool hasEmittedData = false;

    Future<void> emitCurrent() async {
      try {
        final rows = await supabase
            .from('chat_members')
            .select('user_id, is_typing')
            .eq('chat_id', groupId)
            .eq('is_typing', true);

        final ids = <String>[];
        for (final row in rows) {
          ids.add(await _reverseResolve(row['user_id'] as String));
        }
        if (!controller.isClosed) {
          hasEmittedData = true;
          controller.add(ids);
        }
      } catch (e) {
        if (!hasEmittedData && !controller.isClosed) {
          controller.addError(e);
        }
      }
    }

    Future<void> start() async {
      await emitCurrent();

      bool hasSubscribedOnce = false;

      final channel = supabase.channel('group_typing_$groupId').onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'chat_members',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'chat_id', value: groupId),
        callback: (payload) => emitCurrent(),
      );

      channel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (hasSubscribedOnce) emitCurrent();
          hasSubscribedOnce = true;
        }
        if (error != null && !hasEmittedData && !controller.isClosed) controller.addError(error);
      });

      final existing = _typingChannels[groupId];
      if (existing != null) await supabase.removeChannel(existing);
      _typingChannels[groupId] = channel;
    }

    start();

    controller.onCancel = () async {
      final channel = _typingChannels[groupId];
      if (channel != null) {
        await supabase.removeChannel(channel);
        if (identical(_typingChannels[groupId], channel)) {
          _typingChannels.remove(groupId);
        }
      }
      if (!controller.isClosed) await controller.close();
    };

    return controller.stream;
  }

  @override
  Future<void> close() async {
    for (final channel in _groupInfoChannels.values) {
      await supabase.removeChannel(channel);
    }
    _groupInfoChannels.clear();
    for (final channel in _messagesChannels.values) {
      await supabase.removeChannel(channel);
    }
    _messagesChannels.clear();
    for (final channel in _typingChannels.values) {
      await supabase.removeChannel(channel);
    }
    _typingChannels.clear();
  }
}
