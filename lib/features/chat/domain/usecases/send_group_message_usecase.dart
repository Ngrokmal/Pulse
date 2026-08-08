import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

class SendGroupMessageUseCase {
  final GroupRepository repository;
  final ModerationGuard moderationGuard;
  const SendGroupMessageUseCase(this.repository, this.moderationGuard);

  Future<void> call({
    required String groupId,
    required String senderId,
    required String text,
  }) async {
    await moderationGuard.ensureNotBlocked(senderId);
    final messageId = repository.generateMessageId(groupId);

    await repository.sendGroupMessage(
      groupId: groupId,
      messageId: messageId,
      senderId: senderId,
      text: text,
    );
  }
}
