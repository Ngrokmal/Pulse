import '../../../../core/utils/moderation_guard.dart';
import '../repositories/chat_repository.dart';

/// Day 6 Milestone 2 (Delivery Status): SetTypingStatusUseCase-এর মতোই
/// পাতলা wrapper — MarkGroupMessageAsDeliveredUseCase-এর 1:1-সমতুল্য।
class MarkMessageAsDeliveredUseCase {
  final ChatRepository repository;
  final ModerationGuard moderationGuard;
  const MarkMessageAsDeliveredUseCase(this.repository, this.moderationGuard);

  Future<void> call({
    required String chatId,
    required String messageId,
    required String uid,
  }) async {
    await moderationGuard.ensureNotBlocked(uid);
    return repository.markMessageAsDelivered(chatId: chatId, messageId: messageId);
  }
}
