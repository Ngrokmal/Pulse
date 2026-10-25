import '../../../../core/services/local_db_service.dart';
import '../../domain/entities/message_entity.dart';
import '../models/message_model.dart';

abstract class ChatLocalDataSource {
  Future<List<MessageEntity>> getCachedMessages(String chatId);

  Future<void> upsertMessages(String chatId, List<MessageEntity> messages);

  Future<DateTime?> getLastSyncedAt(String chatId);

  Future<void> setLastSyncedAt(String chatId, DateTime time);

  Future<String?> getRemoteChatId(String chatId);

  Future<void> setRemoteChatId(String chatId, String remoteChatId);

  Future<MessageEntity?> getCachedMessage(String chatId, String messageId);

  Future<void> deleteCachedMessage(String chatId, String messageId);
}

class ChatLocalDataSourceImpl implements ChatLocalDataSource {
  @override
  Future<List<MessageEntity>> getCachedMessages(String chatId) async {
    final box = await LocalDbService.messagesBox(chatId);
    final messages = box.values
        .map((raw) => MessageModel.fromCacheJson(Map<String, dynamic>.from(raw)))
        .toList();
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  @override
  Future<void> upsertMessages(String chatId, List<MessageEntity> messages) async {
    if (messages.isEmpty) return;
    final box = await LocalDbService.messagesBox(chatId);
    final entries = <String, Map<String, dynamic>>{};
    for (final message in messages) {
      final model = message is MessageModel ? message : MessageModel.fromEntity(message);
      entries[model.messageId] = model.toCacheJson();
    }
    await box.putAll(entries);
  }

  @override
  Future<DateTime?> getLastSyncedAt(String chatId) async {
    final box = await LocalDbService.syncMetaBox();
    final millis = box.get('lastSyncedAt_$chatId') as int?;
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  @override
  Future<void> setLastSyncedAt(String chatId, DateTime time) async {
    final box = await LocalDbService.syncMetaBox();
    final key = 'lastSyncedAt_$chatId';
    final existingMillis = box.get(key) as int?;
    final newMillis = time.millisecondsSinceEpoch;
    if (existingMillis == null || newMillis > existingMillis) {
      await box.put(key, newMillis);
    }
  }

  @override
  Future<String?> getRemoteChatId(String chatId) async {
    final box = await LocalDbService.syncMetaBox();
    return box.get('remoteChatId_$chatId') as String?;
  }

  @override
  Future<void> setRemoteChatId(String chatId, String remoteChatId) async {
    final box = await LocalDbService.syncMetaBox();
    await box.put('remoteChatId_$chatId', remoteChatId);
  }

  @override
  Future<MessageEntity?> getCachedMessage(String chatId, String messageId) async {
    final box = await LocalDbService.messagesBox(chatId);
    final raw = box.get(messageId);
    if (raw == null) return null;
    return MessageModel.fromCacheJson(Map<String, dynamic>.from(raw));
  }

  @override
  Future<void> deleteCachedMessage(String chatId, String messageId) async {
    final box = await LocalDbService.messagesBox(chatId);
    await box.delete(messageId);
  }
}
