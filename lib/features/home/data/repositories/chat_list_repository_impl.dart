import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/supabase/user_id_bridge.dart';
import '../../../../core/services/local_unread_reset_bus.dart';
import '../../../../core/services/local_chat_created_bus.dart';
import '../../../profile/data/datasources/friend_local_data_source.dart';
import '../../domain/entities/chat_list_item_entity.dart';
import '../../domain/repositories/chat_list_repository.dart';
import '../datasources/chat_list_local_data_source.dart';
import '../datasources/chat_list_remote_data_source.dart';
import '../models/chat_list_item_model.dart';

class ChatListRepositoryImpl implements ChatListRepository {
  final ChatListLocalDataSource localDataSource;
  final ChatListRemoteDataSource remoteDataSource;
  final FirebaseFirestore firestore;
  final SupabaseClient supabase;
  final FriendLocalDataSource friendLocalDataSource;

  StreamSubscription? _memberGroupsSubscription;
  final Map<String, RealtimeChannel> _homeListChannels = {};

  final Map<String, Set<String>> _friendSupabaseIdsCache = {};

  StreamSubscription<LocalUnreadResetEvent>? _unreadResetSubscription;
  final Map<String, void Function(String chatId)> _activeUnreadPatchers = {};

  StreamSubscription<LocalChatCreatedEvent>? _chatCreatedSubscription;
  final Map<String, void Function()> _activeDeltaTriggers = {};

  final Map<String, void Function(ChatListItemModel stub)> _activeChatStubMergers = {};

  ChatListRepositoryImpl({
    required this.localDataSource,
    required this.remoteDataSource,
    required this.firestore,
    required this.supabase,
    required this.friendLocalDataSource,
  }) {
    _unreadResetSubscription = LocalUnreadResetBus.instance.stream.listen((event) {
      localDataSource.setUnreadCount(event.uid, event.chatId, 0);
      _activeUnreadPatchers[event.uid]?.call(event.chatId);
    });
    _chatCreatedSubscription = LocalChatCreatedBus.instance.stream.listen((event) {
      final stubJson = event.chatStub;
      if (stubJson != null) {
        final stub = ChatListItemModel.fromCacheJson(stubJson);
        final merger = _activeChatStubMergers[event.uid];
        if (merger != null) {
          merger(stub);
        } else {
          unawaited(_upsertStubIntoCache(event.uid, stub));
        }
      }
      _activeDeltaTriggers[event.uid]?.call();
    });
  }

  Future<void> _upsertStubIntoCache(String uid, ChatListItemModel stub) async {
    try {
      final cached = await localDataSource.getCachedChatList(uid);
      final list = cached.whereType<ChatListItemModel>().toList();
      if (list.any((c) => c.chatId == stub.chatId)) return;
      list.add(stub);
      await localDataSource.cacheChatList(uid, list);
    } catch (_) {
    }
  }

  String _logicalDirectChatId(List<String> firebaseUids) {
    final sorted = List<String>.from(firebaseUids)..sort();
    return 'direct_${sorted.join('_')}';
  }

  String? _otherMemberSupabaseId(Map<String, dynamic> row, String? myUuid) {
    if (myUuid == null) return null;
    final members = List<Map<String, dynamic>>.from(row['chat_members'] as List<dynamic>? ?? []);
    for (final member in members) {
      final id = member['user_id'] as String?;
      if (id != null && id != myUuid) return id;
    }
    return null;
  }

  Future<Set<String>?> _acceptedFriendSupabaseIds(String myUuid) async {
    final inMemory = _friendSupabaseIdsCache[myUuid];
    if (inMemory != null) return inMemory;

    try {
      final hiveCached = await localDataSource.getCachedFriendSupabaseIds(myUuid);
      if (hiveCached != null) {
        _friendSupabaseIdsCache[myUuid] = hiveCached;
        return hiveCached;
      }
    } catch (_) {}

    try {
      final fetched = await remoteDataSource.fetchAcceptedFriendIds(userId: myUuid);
      _friendSupabaseIdsCache[myUuid] = fetched;
      unawaited(localDataSource.setCachedFriendSupabaseIds(myUuid, fetched));
      return fetched;
    } catch (_) {
      return null;
    }
  }

  @override
  void invalidateFriendIdsCache([String? myUuid]) {
    if (myUuid != null) {
      _friendSupabaseIdsCache.remove(myUuid);
      unawaited(localDataSource.deleteCachedFriendSupabaseIds(myUuid));
    } else {
      final uids = _friendSupabaseIdsCache.keys.toList();
      _friendSupabaseIdsCache.clear();
      for (final uid in uids) {
        unawaited(localDataSource.deleteCachedFriendSupabaseIds(uid));
      }
    }
  }

  Future<List<ChatListItemEntity>> _loadPrunedCache(String currentUserId) async {
    Set<String> cacheFriendFirebaseIds = {};
    try {
      final cachedFriendIds = await friendLocalDataSource.getCachedFriendIds(currentUserId);
      cacheFriendFirebaseIds = cachedFriendIds.toSet();
    } catch (_) {}

    final cachedData = await localDataSource.getCachedChatList(currentUserId);
    if (cacheFriendFirebaseIds.isEmpty) return cachedData;
    return cachedData.where((c) {
      if (c is! ChatListItemModel || c.isGroup) return true;
      final otherId = c.participantIds.firstWhere((id) => id != currentUserId, orElse: () => '');
      if (otherId.isEmpty) return true;
      return cacheFriendFirebaseIds.contains(otherId);
    }).toList();
  }

  @override
  Future<List<ChatListItemEntity>> getCachedChatList(String currentUserId) {
    return _loadPrunedCache(currentUserId);
  }

  @override
  Stream<List<ChatListItemEntity>> streamChatList(String currentUserId) {
    final controller = StreamController<List<ChatListItemEntity>>();

    List<ChatListItemModel> latestParticipantChats = [];
    List<ChatListItemModel> latestMemberGroups = [];
    bool participantChatsReady = false;
    bool memberGroupsReady = false;

    final Map<String, String> remoteToLogicalId = {};

    String? myUuid;
    bool cancelled = false;

    bool hasEmittedData = false;

    DateTime? lastDeltaSuccessAt;

    void emitMerged() {
      if (!participantChatsReady || !memberGroupsReady) return;

      final combinedById = <String, ChatListItemModel>{};
      for (final chat in latestParticipantChats) {
        combinedById[chat.chatId] = chat;
      }
      for (final group in latestMemberGroups) {
        combinedById[group.chatId] = group;
      }
      final merged = combinedById.values.toList()
        ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

      localDataSource.cacheChatList(currentUserId, merged);
      if (!controller.isClosed) {
        hasEmittedData = true;
        controller.add(merged);
      }
    }

    Future<ChatListItemModel> buildDirectChatModel(Map<String, dynamic> row) async {
      final remoteChatId = row['id'] as String;
      final members = List<Map<String, dynamic>>.from(row['chat_members'] as List<dynamic>? ?? []);

      final participantIds = <String>[];
      int myUnreadCount = 0;
      for (final member in members) {
        final memberSupabaseId = member['user_id'] as String;
        final memberFirebaseId = await UserIdBridge.reverseResolve(memberSupabaseId) ?? memberSupabaseId;
        participantIds.add(memberFirebaseId);
        if (memberSupabaseId == myUuid) {
          myUnreadCount = (member['unread_count'] as num?)?.toInt() ?? 0;
        }
      }

      final senderSupabaseId = row['last_message_sender_id'] as String?;
      final lastMessageSenderId = senderSupabaseId != null
          ? (await UserIdBridge.reverseResolve(senderSupabaseId) ?? senderSupabaseId)
          : '';

      final logicalChatId = participantIds.length == 2
          ? _logicalDirectChatId(participantIds)
          : remoteChatId;

      remoteToLogicalId[remoteChatId] = logicalChatId;

      return ChatListItemModel.fromSupabaseRow(
        row,
        logicalChatId: logicalChatId,
        participantIds: participantIds,
        lastMessageSenderId: lastMessageSenderId,
        currentUserId: currentUserId,
        myUnreadCount: myUnreadCount,
      );
    }

    Future<void> runDelta() async {
      try {
        final cursor = await localDataSource.getDirectChatListSyncedAt(currentUserId) ??
            DateTime.fromMillisecondsSinceEpoch(0);

        final rows = await remoteDataSource.fetchUserInbox(userId: myUuid!, since: cursor);

        if (rows.isEmpty) {
          lastDeltaSuccessAt = DateTime.now();
          if (!participantChatsReady) {
            participantChatsReady = true;
            emitMerged();
          }
          return;
        }

        Set<String>? friendSupabaseIds = await _acceptedFriendSupabaseIds(myUuid!);

        DateTime latest = cursor;
        for (final row in rows) {
          final rawUpdatedAt = row['updated_at'];
          final updatedAt = rawUpdatedAt is String ? DateTime.parse(rawUpdatedAt).toLocal() : DateTime.now();
          if (updatedAt.isAfter(latest)) latest = updatedAt;

          final otherSupabaseId = _otherMemberSupabaseId(row, myUuid);
          final isConfirmedNonFriend = otherSupabaseId == null ||
              (friendSupabaseIds != null && !friendSupabaseIds.contains(otherSupabaseId));
          if (isConfirmedNonFriend) {
            final remoteChatId = row['id'] as String?;
            final staleLogicalId = remoteChatId != null ? remoteToLogicalId[remoteChatId] : null;
            if (staleLogicalId != null) {
              latestParticipantChats.removeWhere((c) => c.chatId == staleLogicalId);
            }
            continue;
          }

          final model = await buildDirectChatModel(row);
          final idx = latestParticipantChats.indexWhere((c) => c.chatId == model.chatId);
          if (idx >= 0) {
            latestParticipantChats[idx] = model;
          } else {
            latestParticipantChats.add(model);
          }
        }

        await localDataSource.setDirectChatListSyncedAt(currentUserId, latest);
        await localDataSource.cacheChatList(currentUserId, latestParticipantChats);
        lastDeltaSuccessAt = DateTime.now();
        participantChatsReady = true;
        emitMerged();
      } catch (e) {
        if (!hasEmittedData && !controller.isClosed) {
          hasEmittedData = true;
          controller.add(const []);
        }
      }
    }

    void patchUnreadCount(Map<String, dynamic> row) {
      final chatUuid = row['chat_id'] as String?;
      final newUnread = (row['unread_count'] as num?)?.toInt();
      if (chatUuid == null || newUnread == null) return;

      final logicalId = remoteToLogicalId[chatUuid];
      if (logicalId == null) return;

      final idx = latestParticipantChats.indexWhere((c) => c.chatId == logicalId);
      if (idx < 0) return;

      latestParticipantChats[idx] = latestParticipantChats[idx].copyWith(
        unreadCount: {currentUserId: newUnread},
      );
      emitMerged();
    }

    Future<void> reconcileMessageChange(PostgresChangePayload payload) async {
      final isDelete = payload.eventType == PostgresChangeEvent.delete;
      final row = isDelete ? payload.oldRecord : payload.newRecord;
      if (row.isEmpty) return;

      final chatUuid = row['chat_id'] as String?;
      if (chatUuid == null) return;
      final logicalId = remoteToLogicalId[chatUuid];
      if (logicalId == null) return;

      final idx = latestParticipantChats.indexWhere((c) => c.chatId == logicalId);
      if (idx < 0) return;
      final current = latestParticipantChats[idx];

      final rawCreatedAt = row['created_at'];
      final messageCreatedAt = rawCreatedAt is String ? DateTime.parse(rawCreatedAt).toLocal() : null;
      if (messageCreatedAt == null || messageCreatedAt != current.lastMessageAt) return;

      if (payload.eventType == PostgresChangeEvent.update) {
        latestParticipantChats[idx] = current.copyWith(lastMessage: row['text'] as String? ?? current.lastMessage);
        emitMerged();
        return;
      }

      if (isDelete) {
        final latestRemaining = await remoteDataSource.fetchLatestMessage(chatUuid);
        if (latestRemaining == null) {
          latestParticipantChats[idx] = current.copyWith(lastMessage: '');
        } else {
          final senderSupabaseId = latestRemaining['sender_id'] as String?;
          final senderFirebaseId = senderSupabaseId != null
              ? (await UserIdBridge.reverseResolve(senderSupabaseId) ?? senderSupabaseId)
              : '';
          final rawAt = latestRemaining['created_at'];
          final at = rawAt is String ? DateTime.parse(rawAt).toLocal() : current.lastMessageAt;
          latestParticipantChats[idx] = current.copyWith(
            lastMessage: latestRemaining['text'] as String? ?? '',
            lastMessageAt: at,
            lastMessageSenderId: senderFirebaseId,
          );
        }
        emitMerged();
      }
    }

    Future<void> startDirectChats() async {
      final String resolvedUuid;
      try {
        resolvedUuid = await UserIdBridge.resolve(currentUserId, currentSupabaseUserId: supabase.auth.currentUser?.id);
      } catch (_) {
        participantChatsReady = true;
        emitMerged();
        return;
      }

      if (cancelled) return;
      myUuid = resolvedUuid;

      _activeDeltaTriggers[currentUserId] = () => runDelta();

      runDelta();

      final channel = supabase
          .channel('home_chat_list_$resolvedUuid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chats',
            callback: (payload) {
              final row = payload.newRecord;
              if (row.isEmpty) return;
              if (row['type'] != 'direct') return;
              runDelta();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'chat_members',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: resolvedUuid,
            ),
            callback: (payload) => patchUnreadCount(payload.newRecord),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'messages',
            callback: (payload) {
              if (payload.eventType == PostgresChangeEvent.insert) return;
              reconcileMessageChange(payload);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'friendships',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'requester_id',
              value: resolvedUuid,
            ),
            callback: (payload) {
              invalidateFriendIdsCache(resolvedUuid);
              runDelta();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'friendships',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'addressee_id',
              value: resolvedUuid,
            ),
            callback: (payload) {
              invalidateFriendIdsCache(resolvedUuid);
              runDelta();
            },
          );

      bool firstSubscribe = true;
      channel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (firstSubscribe) {
            firstSubscribe = false;
          } else {
            final sinceLastDelta = lastDeltaSuccessAt == null
                ? null
                : DateTime.now().difference(lastDeltaSuccessAt!);
            if (sinceLastDelta == null || sinceLastDelta > const Duration(seconds: 30)) {
              runDelta();
            }
          }
        }
        if (error != null) {
          if (!participantChatsReady) {
            participantChatsReady = true;
          }
          emitMerged();
        }
      });

      if (cancelled) {
        await supabase.removeChannel(channel);
        return;
      }

      final existing = _homeListChannels[resolvedUuid];
      if (existing != null) await supabase.removeChannel(existing);
      _homeListChannels[resolvedUuid] = channel;
    }

    void patchLocalUnread(String chatId) {
      final idx = latestParticipantChats.indexWhere((c) => c.chatId == chatId);
      if (idx < 0) return;
      final current = latestParticipantChats[idx];
      final patchedUnread = Map<String, int>.from(current.unreadCount)..[currentUserId] = 0;
      latestParticipantChats[idx] = current.copyWith(unreadCount: patchedUnread);
      emitMerged();
    }

    void mergeChatStub(ChatListItemModel stub) {
      final idx = latestParticipantChats.indexWhere((c) => c.chatId == stub.chatId);
      if (idx >= 0) return;
      latestParticipantChats.add(stub);
      emitMerged();
    }

    Future<void> start() async {
      final prunedCachedData = await _loadPrunedCache(currentUserId);
      hasEmittedData = true;
      if (prunedCachedData.isNotEmpty && !controller.isClosed) {
        controller.add(prunedCachedData);
      }

      latestParticipantChats = prunedCachedData.whereType<ChatListItemModel>().where((c) => !c.isGroup).toList();
      _activeUnreadPatchers[currentUserId] = patchLocalUnread;
      _activeChatStubMergers[currentUserId] = mergeChatStub;

      if (cancelled) return;

      final memberSubscription = firestore
          .collection('chats')
          .where('memberUids', arrayContains: currentUserId)
          .snapshots()
          .listen((snapshot) {
        latestMemberGroups = snapshot.docs
            .map((doc) => ChatListItemModel.fromJson(doc.data(), documentId: doc.id))
            .toList();
        memberGroupsReady = true;
        emitMerged();
      }, onError: (error) {
        latestMemberGroups = [];
        memberGroupsReady = true;
        emitMerged();
      });

      if (cancelled) {
        await memberSubscription.cancel();
        return;
      }
      _memberGroupsSubscription = memberSubscription;

      await startDirectChats();
    }

    start();

    controller.onCancel = () async {
      cancelled = true;
      if (identical(_activeUnreadPatchers[currentUserId], patchLocalUnread)) {
        _activeUnreadPatchers.remove(currentUserId);
      }
      if (identical(_activeChatStubMergers[currentUserId], mergeChatStub)) {
        _activeChatStubMergers.remove(currentUserId);
      }
      if (_activeDeltaTriggers.containsKey(currentUserId)) {
        _activeDeltaTriggers.remove(currentUserId);
      }
      await _memberGroupsSubscription?.cancel();
      final uuid = myUuid;
      if (uuid != null) {
        final channel = _homeListChannels[uuid];
        if (channel != null) {
          await supabase.removeChannel(channel);
          if (identical(_homeListChannels[uuid], channel)) {
            _homeListChannels.remove(uuid);
          }
        }
      }
      if (!controller.isClosed) {
        await controller.close();
      }
    };

    return controller.stream;
  }

  @override
  Future<void> close() async {
    await _unreadResetSubscription?.cancel();
    await _chatCreatedSubscription?.cancel();
    await _memberGroupsSubscription?.cancel();
    for (final channel in _homeListChannels.values) {
      await supabase.removeChannel(channel);
    }
    _homeListChannels.clear();
  }
}