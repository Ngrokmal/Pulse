import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/network/offline_queue.dart';
import '../../../../core/services/push_notification_sender_service.dart';
import '../../../../core/services/local_chat_created_bus.dart';
import '../../../../core/services/presence_activity_pinger.dart';
import '../../../../core/supabase/user_id_bridge.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_remote_data_source.dart';
import '../datasources/chat_local_data_source.dart';
import '../datasources/message_inbox_applicator.dart';
import '../models/message_model.dart';
import '../../../home/data/models/chat_list_item_model.dart';

class ChatRepositoryImpl implements ChatRepository {
  final ChatRemoteDataSource remoteDataSource;
  final ChatLocalDataSource localDataSource;
  final SupabaseClient supabase;
  final PushNotificationSenderService pushNotificationSender;
  final MessageInboxApplicator inboxApplicator;
  final PresenceActivityPinger presenceActivityPinger;
  final Uuid _uuid = const Uuid();

  final Map<String, RealtimeChannel> _messagesChannels = {};
  final Map<String, RealtimeChannel> _typingChannels = {};

  ChatRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.supabase,
    required this.pushNotificationSender,
    required this.inboxApplicator,
    required this.presenceActivityPinger,
  });

  @override
  String generateDirectChatId({required String uidA, required String uidB}) {
    final sorted = [uidA, uidB]..sort();
    return 'direct_${sorted[0]}_${sorted[1]}';
  }

  String? _currentSupabaseUid() => supabase.auth.currentUser?.id;

  Future<String> _resolveUid(String firebaseUid) {
    return UserIdBridge.resolve(firebaseUid, currentSupabaseUserId: _currentSupabaseUid());
  }

  Future<String?> _resolveOrHealRemoteChatId(String chatId) async {
    final cached = await localDataSource.getRemoteChatId(chatId);
    if (cached != null) return cached;

    final parts = chatId.split('_');
    if (parts.length != 3 || parts[0] != 'direct') return null;

    await ensureDirectChatExists(chatId: chatId, uidA: parts[1], uidB: parts[2]);

    for (var attempt = 0; attempt < 10; attempt++) {
      final id = await localDataSource.getRemoteChatId(chatId);
      if (id != null) return id;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return null;
  }

  Future<String?> _findExistingDirectChatId(String uidAId, String uidBId) async {
    final aRows = await supabase.from('chat_members').select('chat_id').eq('user_id', uidAId);
    final aChatIds = aRows.map((r) => r['chat_id'] as String).toSet();
    if (aChatIds.isEmpty) return null;

    final bRows = await supabase
        .from('chat_members')
        .select('chat_id')
        .eq('user_id', uidBId)
        .inFilter('chat_id', aChatIds.toList());
    final sharedChatIds = bRows.map((r) => r['chat_id'] as String).toSet();
    if (sharedChatIds.isEmpty) return null;

    final directRows = await supabase
        .from('chats')
        .select('id')
        .eq('type', 'direct')
        .inFilter('id', sharedChatIds.toList())
        .limit(1);
    if (directRows.isEmpty) return null;
    return directRows.first['id'] as String;
  }

  @override
  Future<void> ensureDirectChatExists({
    required String chatId,
    required String uidA,
    required String uidB,
  }) async {
    final alreadyMapped = await localDataSource.getRemoteChatId(chatId);
    if (alreadyMapped != null) return;

    final uidAId = await _resolveUid(uidA);
    final uidBId = await _resolveUid(uidB);

    var remoteChatId = await _findExistingDirectChatId(uidAId, uidBId);

    if (remoteChatId == null) {
      final low = uidAId.compareTo(uidBId) <= 0 ? uidAId : uidBId;
      final high = uidAId.compareTo(uidBId) <= 0 ? uidBId : uidAId;

      String remoteId;
      try {
        final inserted = await supabase.from('chats').insert({
          'type': 'direct',
          'direct_member_low': low,
          'direct_member_high': high,
        }).select('id').single();
        remoteId = inserted['id'] as String;

        await supabase.from('chat_members').insert([
          {'chat_id': remoteId, 'user_id': uidAId},
          {'chat_id': remoteId, 'user_id': uidBId},
        ]);

        final stub = ChatListItemModel(
          chatId: chatId,
          participantIds: [uidA, uidB],
          lastMessage: '',
          lastMessageAt: DateTime.now(),
          lastMessageSenderId: '',
          unreadCount: {uidA: 0, uidB: 0},
          isGroup: false,
        );
        final stubJson = stub.toCacheJson();

        LocalChatCreatedBus.instance.emit(uid: uidA, chatStub: stubJson);
        LocalChatCreatedBus.instance.emit(uid: uidB, chatStub: stubJson);
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow;
        final existing = await _findExistingDirectChatId(uidAId, uidBId);
        if (existing == null) rethrow;
        remoteId = existing;
      }

      remoteChatId = remoteId;
    }

    await localDataSource.setRemoteChatId(chatId, remoteChatId);
  }

  @override
  Future<void> touchDirectChat({required String chatId}) async {
    final remoteChatId = await _resolveOrHealRemoteChatId(chatId);
    if (remoteChatId == null) return;
    await supabase
        .from('chats')
        .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', remoteChatId);
  }

  @override
  String generateMessageId(String chatId) {
    return _uuid.v4();
  }

  @override
  Future<void> sendMessage({
    required String chatId,
    required String messageId,
    required String senderId,
    required String text,
  }) async {
    final localModel = MessageModel(
      messageId: messageId,
      chatId: chatId,
      senderId: senderId,
      text: text,
      createdAt: DateTime.now(),
      status: 'sending',
      syncStatus: 'pending',
    );

    presenceActivityPinger.ping();

    await localDataSource.upsertMessages(chatId, [localModel]);

    unawaited(_sendTextMessageRemote(
      chatId: chatId,
      senderId: senderId,
      lastMessagePreview: text,
      localModel: localModel,
    ));
  }

  Future<void> _sendTextMessageRemote({
    required String chatId,
    required String senderId,
    required String lastMessagePreview,
    required MessageModel localModel,
  }) async {
    try {
      await OfflineQueueManager.instance.addToQueue(() async {
        final remoteChatId = await _resolveOrHealRemoteChatId(chatId);
        if (remoteChatId == null) {
          throw StateError(
            'No Supabase chat resolved for "$chatId" - ensureDirectChatExists '
            'must run (and succeed) before sendMessage.',
          );
        }
        final senderSupabaseId = await _resolveUid(senderId);

        final row = localModel.toSupabaseRow()
          ..['sender_id'] = senderSupabaseId
          ..['status'] = 'sent';
        await remoteDataSource.sendMessage(chatId: remoteChatId, messageData: row);

        final nowIso = DateTime.now().toUtc().toIso8601String();
        await supabase.from('chats').update({
          'last_message': lastMessagePreview,
          'last_message_at': nowIso,
          'last_message_sender_id': senderSupabaseId,
        }).eq('id', remoteChatId);

        final affectedUserIds = await supabase.rpc('increment_unread_counts', params: {
          'p_chat_id': remoteChatId,
          'p_sender_id': senderSupabaseId,
        });
        for (final memberUid in List<String>.from(affectedUserIds as List)) {
          unawaited(
            pushNotificationSender.sendChatMessageNotification(
              targetUserId: memberUid,
              title: 'New message',
              body: lastMessagePreview,
              data: {'chatId': chatId},
            ),
          );
        }
      });

      await localDataSource.upsertMessages(chatId, [
        localModel.copyWithSyncStatus(status: 'sent', syncStatus: 'synced'),
      ]);
    } catch (e) {
      await localDataSource.upsertMessages(chatId, [
        localModel.copyWithSyncStatus(status: 'failed', syncStatus: 'failed'),
      ]);
    }
  }

  @override
  Future<void> sendMediaMessage({
    required String chatId,
    required String messageId,
    required String senderId,
    required String type,
    String text = '',
    String? mediaUrl,
    String? thumbnailUrl,
    String? fileName,
    int? fileSizeBytes,
    String? mimeType,
    int? durationMs,
    int? width,
    int? height,
    List<double>? waveform,
  }) async {
    final lastMessagePreview = text.isNotEmpty ? text : _lastMessagePreviewFor(type, fileName);
    final localModel = MessageModel(
      messageId: messageId,
      chatId: chatId,
      senderId: senderId,
      text: text,
      createdAt: DateTime.now(),
      status: 'sending',
      syncStatus: 'pending',
      type: type,
      mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl,
      fileName: fileName,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      durationMs: durationMs,
      width: width,
      height: height,
      waveform: waveform,
    );

    presenceActivityPinger.ping();

    await localDataSource.upsertMessages(chatId, [localModel]);

    unawaited(_persistMessageLocalFirst(
      chatId: chatId,
      senderId: senderId,
      lastMessagePreview: lastMessagePreview,
      localModel: localModel,
    ));
  }

  @override
  Future<void> sendMessageWithAlert({
    required String chatId,
    required String messageId,
    required String senderId,
    String text = '',
    required String alertId,
    required String alertDisplayName,
    required String alertAudioUrl,
    required String alertAudioChecksum,
    required String alertAudioFormat,
    required int alertAudioSizeBytes,
    int? alertAudioDurationMs,
  }) async {
    final preview = text.isNotEmpty ? text : '🔔 $alertDisplayName';
    final localModel = MessageModel(
      messageId: messageId,
      chatId: chatId,
      senderId: senderId,
      text: text,
      createdAt: DateTime.now(),
      status: 'sending',
      syncStatus: 'pending',
      alertId: alertId,
      alertDisplayName: alertDisplayName,
      alertAudioUrl: alertAudioUrl,
      alertAudioChecksum: alertAudioChecksum,
      alertAudioFormat: alertAudioFormat,
      alertAudioSizeBytes: alertAudioSizeBytes,
      alertAudioDurationMs: alertAudioDurationMs,
    );

    await localDataSource.upsertMessages(chatId, [localModel]);

    unawaited(_persistMessageLocalFirst(
      chatId: chatId,
      senderId: senderId,
      lastMessagePreview: preview,
      localModel: localModel,
    ));
  }

  String _lastMessagePreviewFor(String type, String? fileName) {
    switch (type) {
      case 'image':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'voice':
        return 'Voice message';
      case 'file':
        return fileName ?? 'File';
      default:
        return '';
    }
  }

  Future<void> _persistMessageLocalFirst({
    required String chatId,
    required String senderId,
    required String lastMessagePreview,
    required MessageModel localModel,
  }) async {
    try {
      await OfflineQueueManager.instance.addToQueue(() async {
        final remoteChatId = await _resolveOrHealRemoteChatId(chatId);
        if (remoteChatId == null) {
          throw StateError(
            'No Supabase chat resolved for "$chatId" - ensureDirectChatExists '
            'must run (and succeed) before sendMessage.',
          );
        }
        final senderSupabaseId = await _resolveUid(senderId);

        final row = localModel.toSupabaseRow()
          ..['sender_id'] = senderSupabaseId
          ..['status'] = 'sent';
        await remoteDataSource.sendMessage(chatId: remoteChatId, messageData: row);

        final nowIso = DateTime.now().toUtc().toIso8601String();
        await supabase.from('chats').update({
          'last_message': lastMessagePreview,
          'last_message_at': nowIso,
          'last_message_sender_id': senderSupabaseId,
        }).eq('id', remoteChatId);

        final affectedUserIds = await supabase.rpc('increment_unread_counts', params: {
          'p_chat_id': remoteChatId,
          'p_sender_id': senderSupabaseId,
        });
        final pushData = {'chatId': chatId, ..._alertPushData(localModel)};
        for (final memberUid in List<String>.from(affectedUserIds as List)) {
          unawaited(
            pushNotificationSender.sendChatMessageNotification(
              targetUserId: memberUid,
              title: 'New message',
              body: lastMessagePreview,
              data: pushData,
            ),
          );
        }
      });

      await localDataSource.upsertMessages(chatId, [
        localModel.copyWithSyncStatus(status: 'sent', syncStatus: 'synced'),
      ]);
    } catch (e) {
      await localDataSource.upsertMessages(chatId, [
        localModel.copyWithSyncStatus(status: 'failed', syncStatus: 'failed'),
      ]);
    }
  }

  Map<String, String> _alertPushData(MessageModel localModel) {
    final String? alertId = localModel.alertId;
    if (alertId == null || alertId.isEmpty) return const {};

    return {
      'alertId': alertId,
      if (localModel.alertDisplayName != null) 'alertDisplayName': localModel.alertDisplayName!,
      if (localModel.alertAudioUrl != null) 'alertAudioUrl': localModel.alertAudioUrl!,
      if (localModel.alertAudioChecksum != null) 'alertAudioChecksum': localModel.alertAudioChecksum!,
      if (localModel.alertAudioFormat != null) 'alertAudioFormat': localModel.alertAudioFormat!,
      if (localModel.alertAudioSizeBytes != null)
        'alertAudioSizeBytes': localModel.alertAudioSizeBytes!.toString(),
      if (localModel.alertAudioDurationMs != null)
        'alertAudioDurationMs': localModel.alertAudioDurationMs!.toString(),
    };
  }

  @override
  Future<void> resetUnreadCount({required String chatId, required String uid}) async {
    unawaited(() async {
      try {
        await OfflineQueueManager.instance.addToQueue(() async {
          final remoteChatId = await _resolveOrHealRemoteChatId(chatId);
          if (remoteChatId == null) return;
          final supabaseUid = await _resolveUid(uid);
          await supabase
              .from('chat_members')
              .update({'unread_count': 0})
              .eq('chat_id', remoteChatId)
              .eq('user_id', supabaseUid);
        });
      } catch (e) {
      }
    }());
  }

  @override
  Future<void> markMessagesAsDelivered({
    required String chatId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    unawaited(() async {
      try {
        await OfflineQueueManager.instance.addToQueue(() async {
          await supabase.from('messages').update({'status': 'delivered'}).inFilter('id', messageIds);
        });
      } catch (e) {
      }
    }());
  }

  @override
  Future<void> markMessagesAsRead({
    required String chatId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    presenceActivityPinger.ping();
    unawaited(() async {
      try {
        await OfflineQueueManager.instance.addToQueue(() async {
          await supabase.from('messages').update({'status': 'read'}).inFilter('id', messageIds);
        });
      } catch (e) {
      }
    }());
  }

  static const int _kForwardDeltaPageSize = 200;

  @override
  Stream<List<MessageEntity>> streamMessages(String chatId) {
    final controller = StreamController<List<MessageEntity>>();

    final Map<String, MessageEntity> live = {};
    List<MessageEntity> sortedLive() =>
        live.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    void mergeIntoLive(List<MessageModel> changed) {
      for (final m in changed) {
        live[m.messageId] = m;
      }
    }

    bool deltaInFlight = false;
    bool hasEmittedData = false;
    DateTime? _lastDeltaAt;

    Future<void> runDelta(String remoteChatId) async {
      if (_lastDeltaAt != null && DateTime.now().difference(_lastDeltaAt!) < const Duration(seconds: 30)) {
        return;
      }
      _lastDeltaAt = DateTime.now();
      if (deltaInFlight) return;
      deltaInFlight = true;
      try {
        var cursor = await localDataSource.getLastSyncedAt(chatId) ?? DateTime.fromMillisecondsSinceEpoch(0);

        while (true) {
          final cursorIso = cursor.toUtc().toIso8601String();

          final rows = await supabase
              .from('messages')
              .select()
              .eq('chat_id', remoteChatId)
              .or('created_at.gt.$cursorIso,updated_at.gt.$cursorIso')
              .order('created_at')
              .order('id')
              .limit(_kForwardDeltaPageSize);

          if (rows.isEmpty) return;

          final changed = <MessageModel>[];
          DateTime latest = cursor;
          for (final row in rows) {
            final model = MessageModel.fromSupabaseRow(row, chatId: chatId);
            changed.add(model);
            final rawUpdatedAt = row['updated_at'];
            final updatedAt = rawUpdatedAt is String ? DateTime.parse(rawUpdatedAt).toLocal() : null;
            final effective =
                (updatedAt != null && updatedAt.isAfter(model.createdAt)) ? updatedAt : model.createdAt;
            if (effective.isAfter(latest)) latest = effective;
          }

          await localDataSource.upsertMessages(chatId, changed);
          await localDataSource.setLastSyncedAt(chatId, latest);
          mergeIntoLive(changed);
          if (!controller.isClosed) {
            hasEmittedData = true;
            controller.add(sortedLive());
          }

          if (rows.length < _kForwardDeltaPageSize || !latest.isAfter(cursor)) return;
          cursor = latest;
        }
      } catch (_) {
      } finally {
        deltaInFlight = false;
      }
    }

    Future<void> start() async {
      final cachedMessages = await localDataSource.getCachedMessages(chatId);
      for (final m in cachedMessages) {
        live[m.messageId] = m;
      }
      if (!controller.isClosed) {
        hasEmittedData = true;
        controller.add(sortedLive());
      }

      final remoteChatId = await _resolveOrHealRemoteChatId(chatId);
      if (remoteChatId == null) {
        if (!controller.isClosed && !hasEmittedData && live.isEmpty) {
          controller.addError(StateError(
            'No Supabase chat resolved for "$chatId" - ensureDirectChatExists '
            'must be called before streamMessages.',
          ));
        }
        return;
      }

      runDelta(remoteChatId);

      final channel = supabase.channel('messages_$remoteChatId').onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'chat_id',
          value: remoteChatId,
        ),
        callback: (payload) async {
          final row = payload.newRecord;
          if (row.isEmpty) return;
          presenceActivityPinger.ping();
          await inboxApplicator.applyFromSupabaseRow(logicalChatId: chatId, row: row);
          final model = MessageModel.fromSupabaseRow(row, chatId: chatId);
          mergeIntoLive([model]);
          if (!controller.isClosed) {
            hasEmittedData = true;
            controller.add(sortedLive());
          }
        },
      );

      channel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          runDelta(remoteChatId);
        }
        if (error != null && !hasEmittedData && !controller.isClosed) {
          controller.addError(error);
        }
      });

      final existing = _messagesChannels[chatId];
      if (existing != null) await supabase.removeChannel(existing);
      _messagesChannels[chatId] = channel;
    }

    start();

    controller.onCancel = () async {
      final channel = _messagesChannels[chatId];
      if (channel != null) {
        await supabase.removeChannel(channel);
        if (identical(_messagesChannels[chatId], channel)) {
          _messagesChannels.remove(chatId);
        }
      }
      if (!controller.isClosed) await controller.close();
    };

    return controller.stream;
  }

  @override
  Future<void> updateMessage({
    required String chatId,
    required String messageId,
    required String text,
  }) async {
    final previous = await localDataSource.getCachedMessage(chatId, messageId);
    if (previous != null) {
      final prevModel = MessageModel.fromEntity(previous);
      await localDataSource.upsertMessages(chatId, [
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
        await OfflineQueueManager.instance.addToQueue(() async {
          final remoteChatId = await _resolveOrHealRemoteChatId(chatId);
          if (remoteChatId == null) {
            throw StateError(
              'No Supabase chat resolved for "$chatId" - ensureDirectChatExists '
              'must run (and succeed) before updateMessage.',
            );
          }
          await remoteDataSource.updateMessageText(messageId: messageId, text: text);
        });
        if (previous != null) {
          final synced = await localDataSource.getCachedMessage(chatId, messageId);
          if (synced != null) {
            await localDataSource.upsertMessages(chatId, [
              MessageModel.fromEntity(synced).copyWithSyncStatus(status: synced.status, syncStatus: 'synced'),
            ]);
          }
        }
      } catch (e) {
        if (previous != null) {
          await localDataSource.upsertMessages(chatId, [
            MessageModel.fromEntity(previous).copyWithSyncStatus(
              status: previous.status,
              syncStatus: 'failed',
            ),
          ]);
        }
      }
    }());
  }

  @override
  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    final previous = await localDataSource.getCachedMessage(chatId, messageId);

    await localDataSource.deleteCachedMessage(chatId, messageId);

    unawaited(() async {
      try {
        await OfflineQueueManager.instance.addToQueue(() async {
          final remoteChatId = await _resolveOrHealRemoteChatId(chatId);
          if (remoteChatId == null) {
            throw StateError(
              'No Supabase chat resolved for "$chatId" - ensureDirectChatExists '
              'must run (and succeed) before deleteMessage.',
            );
          }
          await remoteDataSource.deleteMessage(messageId: messageId);
        });
      } catch (e) {
        if (previous != null) {
          await localDataSource.upsertMessages(chatId, [
            MessageModel.fromEntity(previous).copyWithSyncStatus(status: previous.status, syncStatus: 'failed'),
          ]);
        }
      }
    }());
  }

  @override
  Future<List<MessageEntity>> fetchMessages({
    required String chatId,
    int limit = 50,
  }) async {
    final remoteChatId = await _resolveOrHealRemoteChatId(chatId);
    if (remoteChatId == null) return const [];

    final rows = await remoteDataSource.fetchMessages(chatId: remoteChatId, limit: limit);
    return rows.map((row) => MessageModel.fromSupabaseRow(row, chatId: chatId)).toList();
  }

  @override
  Future<List<MessageEntity>> loadOlderMessages({
    required String chatId,
    required DateTime beforeCreatedAt,
    int limit = 30,
  }) async {
    final cachedMessages = await localDataSource.getCachedMessages(chatId);
    final cachedOlder = cachedMessages.where((m) => m.createdAt.isBefore(beforeCreatedAt)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (cachedOlder.length >= limit) {
      return cachedOlder.take(limit).toList().reversed.toList();
    }

    final remoteChatId = await _resolveOrHealRemoteChatId(chatId);
    if (remoteChatId == null) return const [];

    final boundaryCached = cachedMessages.where((m) => m.createdAt.isAtSameMomentAs(beforeCreatedAt));
    final beforeId = boundaryCached.isEmpty ? null : boundaryCached.first.messageId;

    final rows = await remoteDataSource.fetchMessagesBefore(
      chatId: remoteChatId,
      beforeCreatedAt: beforeCreatedAt,
      beforeId: beforeId,
      limit: limit,
    );

    final olderMessages = <MessageEntity>[];
    for (final row in rows) {
      final model = MessageModel.fromSupabaseRow(row, chatId: chatId);
      await inboxApplicator.apply(chatId: chatId, message: model);
      olderMessages.add(model);
    }

    return olderMessages.reversed.toList();
  }

  @override
  Future<void> setTypingStatus({
    required String chatId,
    required String uid,
    required bool isTyping,
  }) async {
    presenceActivityPinger.ping();
    final remoteChatId = await _resolveOrHealRemoteChatId(chatId);
    if (remoteChatId == null) return;
    final supabaseUid = await _resolveUid(uid);
    await supabase.from('chat_members').update({
      'is_typing': isTyping,
      'typing_updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('chat_id', remoteChatId).eq('user_id', supabaseUid);
  }

  @override
  Stream<List<String>> streamTypingUserIds(String chatId) {
    final controller = StreamController<List<String>>();
    bool hasEmittedData = false;

    Future<void> emitCurrent(String remoteChatId) async {
      try {
        final rows = await supabase
            .from('chat_members')
            .select('user_id, is_typing')
            .eq('chat_id', remoteChatId)
            .eq('is_typing', true);

        final ids = <String>[];
        for (final row in rows) {
          final supabaseUid = row['user_id'] as String;
          final firebaseUid = await UserIdBridge.reverseResolve(supabaseUid) ?? supabaseUid;
          ids.add(firebaseUid);
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
      final remoteChatId = await _resolveOrHealRemoteChatId(chatId);
      if (remoteChatId == null) {
        if (!controller.isClosed) {
          hasEmittedData = true;
          controller.add(const []);
        }
        return;
      }

      await emitCurrent(remoteChatId);

      bool hasSubscribedOnce = false;

      final channel = supabase.channel('typing_$remoteChatId').onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'chat_members',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'chat_id',
          value: remoteChatId,
        ),
        callback: (payload) => emitCurrent(remoteChatId),
      );
      channel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (hasSubscribedOnce) emitCurrent(remoteChatId);
          hasSubscribedOnce = true;
        }
        if (error != null && !hasEmittedData && !controller.isClosed) {
          controller.addError(error);
        }
      });

      final existing = _typingChannels[chatId];
      if (existing != null) await supabase.removeChannel(existing);
      _typingChannels[chatId] = channel;
    }

    start();

    controller.onCancel = () async {
      final channel = _typingChannels[chatId];
      if (channel != null) {
        await supabase.removeChannel(channel);
        if (identical(_typingChannels[chatId], channel)) {
          _typingChannels.remove(chatId);
        }
      }
      if (!controller.isClosed) await controller.close();
    };

    return controller.stream;
  }

  @override
  Future<List<MessageEntity>> getCachedMessages(String chatId) {
    return localDataSource.getCachedMessages(chatId);
  }

  @override
  Future<void> close() async {
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