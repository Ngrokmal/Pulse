import '../../../../core/utils/moderation_guard.dart';
import '../repositories/chat_repository.dart';

class SendMessageUseCase {
  final ChatRepository repository;
  final ModerationGuard moderationGuard;
  const SendMessageUseCase(this.repository, this.moderationGuard);

  Future<void> call({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    await moderationGuard.ensureNotBlocked(senderId);
    final messageId = repository.generateMessageId(chatId);
    return await repository.sendMessage(
      chatId: chatId,
      messageId: messageId,
      senderId: senderId,
      text: text,
    );
  }
}
