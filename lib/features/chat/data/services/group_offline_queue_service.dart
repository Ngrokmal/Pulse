import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/offline_queue.dart';
import '../datasources/chat_remote_data_source.dart';

class GroupOfflineQueueOpType {
  static const sendMessage = 'group.message.send';
  static const editMessage = 'group.message.edit';
  static const deleteMessage = 'group.message.delete';
  static const reactionAdd = 'group.reaction.add';
  static const reactionRemove = 'group.reaction.remove';
  static const readReceipt = 'group.receipt.read';
  static const deliveryReceipt = 'group.receipt.delivered';
  static const attachmentMetadata = 'group.attachment.metadata';

  static const Map<String, int> _statusRank = {'sent': 0, 'delivered': 1, 'read': 2};
  static int statusRank(String? status) => _statusRank[status] ?? 0;
}

class GroupOfflineQueueService {
  GroupOfflineQueueService._privateConstructor();
  static final GroupOfflineQueueService instance = GroupOfflineQueueService._privateConstructor();

  static const String _boxName = 'offline_queue_v1';
  bool _handlersRegistered = false;

  Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return Hive.openBox(_boxName);
  }

  String _taskId({
    required String opType,
    required String groupId,
    required String messageId,
    String? subKey,
  }) {
    final suffix = subKey == null ? '' : ':$subKey';
    return 'group:$opType:$groupId:$messageId$suffix';
  }

  Future<void> enqueue({
    required String opType,
    required String groupId,
    required String messageId,
    required Map<String, dynamic> payload,
    int priority = 0,
    String? subKey,
  }) async {
    final id = _taskId(opType: opType, groupId: groupId, messageId: messageId, subKey: subKey);

    final box = await _box();
    await box.put(id, {
      'opType': opType,
      'payload': {
        ...payload,
        'groupId': groupId,
        'messageId': messageId,
        'priority': priority,
        'queuedAt': DateTime.now().toUtc().toIso8601String(),
      },
      'enqueuedAt': DateTime.now().millisecondsSinceEpoch,
    });

    final entry = box.get(id);
    final mergedPayload = Map<String, dynamic>.from((entry as Map)['payload'] as Map);

    await OfflineQueueManager.instance.addPersistentTask(
      opType: opType,
      taskId: id,
      payload: mergedPayload,
    );
  }

  void registerHandlers({
    required SupabaseClient supabase,
    required ChatRemoteDataSource remoteDataSource,
    required Future<String> Function(String) resolveUid,
  }) {
    if (_handlersRegistered) return;
    _handlersRegistered = true;

    OfflineQueueManager.instance.registerHandler(GroupOfflineQueueOpType.sendMessage, (payload) async {
      final groupId = payload['groupId'] as String;
      final senderSupabaseId = await resolveUid(payload['senderId'] as String);
      final row = Map<String, dynamic>.from(payload['row'] as Map)..['sender_id'] = senderSupabaseId;
      await remoteDataSource.sendMessage(chatId: groupId, messageData: row);

      final nowIso = DateTime.now().toUtc().toIso8601String();
      await supabase.from('chats').update({
        'last_message': payload['text'] ?? '',
        'last_message_at': nowIso,
        'last_message_sender_id': senderSupabaseId,
      }).eq('id', groupId);

      await supabase.rpc('increment_unread_counts', params: {
        'p_chat_id': groupId,
        'p_sender_id': senderSupabaseId,
      });
    });

    OfflineQueueManager.instance.registerHandler(GroupOfflineQueueOpType.editMessage, (payload) async {
      final messageId = payload['messageId'] as String;
      final existing = await supabase.from('messages').select('id').eq('id', messageId).maybeSingle();
      if (existing == null) return;
      await remoteDataSource.updateMessageText(messageId: messageId, text: payload['text'] as String);
    });

    OfflineQueueManager.instance.registerHandler(GroupOfflineQueueOpType.deleteMessage, (payload) async {
      await remoteDataSource.deleteMessage(messageId: payload['messageId'] as String);
    });

    Future<void> applyReceipt(Map<String, dynamic> payload, String targetStatus) async {
      final messageId = payload['messageId'] as String;
      final row = await supabase.from('messages').select('status').eq('id', messageId).maybeSingle();
      if (row == null) return;
      final currentStatus = row['status'] as String?;
      if (GroupOfflineQueueOpType.statusRank(currentStatus) >= GroupOfflineQueueOpType.statusRank(targetStatus)) {
        return;
      }
      await supabase.from('messages').update({'status': targetStatus}).eq('id', messageId);
    }

    OfflineQueueManager.instance.registerHandler(
      GroupOfflineQueueOpType.deliveryReceipt,
      (payload) => applyReceipt(payload, 'delivered'),
    );
    OfflineQueueManager.instance.registerHandler(
      GroupOfflineQueueOpType.readReceipt,
      (payload) => applyReceipt(payload, 'read'),
    );

    OfflineQueueManager.instance.registerHandler(GroupOfflineQueueOpType.attachmentMetadata, (payload) async {
      final messageId = payload['messageId'] as String;
      final existing = await supabase.from('messages').select('id').eq('id', messageId).maybeSingle();
      if (existing == null) return;
      final fields = Map<String, dynamic>.from(payload['fields'] as Map);
      if (fields.isEmpty) return;
      await supabase.from('messages').update(fields).eq('id', messageId);
    });

    Future<void> reactionUnsupported(Map<String, dynamic> payload) async {
      throw UnimplementedError(
        'Group reactions have no backing storage yet (no schema change made '
        'per Phase 3.5 scope) — queue plumbing is ready, handler is not.',
      );
    }

    OfflineQueueManager.instance.registerHandler(GroupOfflineQueueOpType.reactionAdd, reactionUnsupported);
    OfflineQueueManager.instance.registerHandler(GroupOfflineQueueOpType.reactionRemove, reactionUnsupported);
  }
}
