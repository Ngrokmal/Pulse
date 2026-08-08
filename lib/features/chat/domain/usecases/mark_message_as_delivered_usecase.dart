import '../../../../core/utils/moderation_guard.dart';
import '../repositories/chat_repository.dart';

class MarkMessageAsDeliveredUseCase {
  final ChatRepository repository;
  final ModerationGuard moderationGuard;
  const MarkMessageAsDeliveredUseCase(this.repository, this.moderationGuard);

  Future<void> call({
    required String chatId,
    required List<String> messageIds,
    required String uid,
  }) async {
    if (messageIds.isEmpty) return;
    await moderationGuard.ensureNotBlocked(uid);
    return repository.markMessagesAsDelivered(chatId: chatId, messageIds: messageIds);
  }
}
