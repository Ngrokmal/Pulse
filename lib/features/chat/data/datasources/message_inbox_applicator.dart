import '../models/message_model.dart';
import 'chat_local_data_source.dart';

class MessageInboxApplicator {
  MessageInboxApplicator(this._local);
  final ChatLocalDataSource _local;

  Future<void> apply({
    required String chatId,
    required MessageModel message,
    DateTime? cursorHint,
  }) async {
    await _local.upsertMessages(chatId, [message]);
    final ts = cursorHint ?? message.createdAt;
    final existing = await _local.getLastSyncedAt(chatId);
    if (existing == null || ts.isAfter(existing)) {
      await _local.setLastSyncedAt(chatId, ts);
    }
  }

  Future<void> applyFromSupabaseRow({
    required String logicalChatId,
    required Map<String, dynamic> row,
  }) async {
    if (row.isEmpty) return;
    if (row['deleted_at'] != null) {
      final id = row['id'] as String?;
      if (id != null) await _local.deleteCachedMessage(logicalChatId, id);
      return;
    }
    final model = MessageModel.fromSupabaseRow(row, chatId: logicalChatId);
    final raw = row['updated_at'];
    final hint = raw is String ? DateTime.parse(raw).toLocal() : model.createdAt;
    await apply(chatId: logicalChatId, message: model, cursorHint: hint);
  }
}
