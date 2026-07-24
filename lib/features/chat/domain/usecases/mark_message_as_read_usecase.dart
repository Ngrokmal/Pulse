import '../../../../core/utils/moderation_guard.dart';
import '../repositories/chat_repository.dart';

/// Day 6 Milestone 3 (Read Receipts): MarkMessageAsDeliveredUseCase-এর মতোই
/// পাতলা wrapper — MarkGroupMessageAsReadUseCase-এর 1:1-সমতুল্য।
class MarkMessageAsReadUseCase {
  final ChatRepository repository;
  final ModerationGuard moderationGuard;
  const MarkMessageAsReadUseCase(this.repository, this.moderationGuard);

  Future<void> call({
    required String chatId,
    required String messageId,
    required String uid,
  }) async {
    await moderationGuard.ensureNotBlocked(uid);
    return repository.markMessageAsRead(chatId: chatId, messageId: messageId);
  }
}
