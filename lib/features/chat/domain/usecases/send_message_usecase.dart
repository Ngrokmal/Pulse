import '../../../../core/utils/moderation_guard.dart';
import '../repositories/chat_repository.dart';

/// Day 6 M1 composer-fix: SendGroupMessageUseCase-এর প্যাটার্নের 1:1-সমতুল্য —
/// messageId generation এখন internal, UI/Bloc-কে ID generation নিয়ে ভাবতে
/// হয় না (আগে messageId caller-কে সরবরাহ করতে হতো কিন্তু কোনো call-site
/// কখনো ছিল না, handoff.md ধারা ৬)।
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
