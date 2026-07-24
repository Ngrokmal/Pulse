import '../../../../core/services/local_db_service.dart';
import '../../domain/entities/message_entity.dart';
import '../models/message_model.dart';

/// TASK 2: replaced the in-memory placeholder with real Hive-backed
/// persistence. Interface grows (upsertMessages for incremental merge,
/// get/setLastSyncedAt for the delta cursor) but the class name / DI
/// registration / consumers stay the same — this is the seam the original
/// code's own comment ('রিয়েল অ্যাপে হাইভ ইনজেক্ট হবে') anticipated, not a
/// new architecture.
abstract class ChatLocalDataSource {
  /// All locally-cached messages for a chat, sorted oldest→newest. This is
  /// the ONLY source Chat Screen reads from to render history — no
  /// Firestore read happens just to open a chat (see TASK 2 in
  /// chat_repository_impl.dart / group_repository_impl.dart).
  Future<List<MessageEntity>> getCachedMessages(String chatId);

  /// Merge-writes only the given messages (new or changed) into the local
  /// cache — existing entries for other messageIds are left untouched.
  /// Never a full-list overwrite, so no duplicate downloads/writes happen
  /// for messages that haven't changed.
  Future<void> upsertMessages(String chatId, List<MessageEntity> messages);

  /// The high-water mark (max `updatedAt` seen so far) used to scope the
  /// Firestore delta query to "only what's new since last sync".
  Future<DateTime?> getLastSyncedAt(String chatId);

  Future<void> setLastSyncedAt(String chatId, DateTime time);
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
    for (final message in messages) {
      final model = message is MessageModel ? message : MessageModel.fromEntity(message);
      await box.put(model.messageId, model.toCacheJson());
    }
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
    // Only move the cursor forward — a stray out-of-order snapshot event
    // must never rewind it and cause history to be re-fetched.
    if (existingMillis == null || newMillis > existingMillis) {
      await box.put(key, newMillis);
    }
  }
}
