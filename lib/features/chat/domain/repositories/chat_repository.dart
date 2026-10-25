import '../entities/message_entity.dart';

abstract class ChatRepository {
  String generateMessageId(String chatId);

  Future<void> sendMessage({
    required String chatId,
    required String messageId,
    required String senderId,
    required String text,
  });

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
  });

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
  });

  Future<void> resetUnreadCount({required String chatId, required String uid});

  Future<void> setTypingStatus({
    required String chatId,
    required String uid,
    required bool isTyping,
  });

  Stream<List<String>> streamTypingUserIds(String chatId);

  Future<void> markMessagesAsDelivered({
    required String chatId,
    required List<String> messageIds,
  });

  Future<void> markMessagesAsRead({
    required String chatId,
    required List<String> messageIds,
  });

  Stream<List<MessageEntity>> streamMessages(String chatId);

  Future<List<MessageEntity>> getCachedMessages(String chatId);

  Future<void> updateMessage({
    required String chatId,
    required String messageId,
    required String text,
  });

  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  });

  Future<List<MessageEntity>> fetchMessages({
    required String chatId,
    int limit,
  });

  Future<List<MessageEntity>> loadOlderMessages({
    required String chatId,
    required DateTime beforeCreatedAt,
    int limit = 30,
  });

  String generateDirectChatId({required String uidA, required String uidB});

  Future<void> ensureDirectChatExists({
    required String chatId,
    required String uidA,
    required String uidB,
  });

  Future<void> touchDirectChat({required String chatId});

  Future<void> close();
}
