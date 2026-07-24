import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

/// GROUP_CHAT_ALGORITHM.md ধারা ২ — V1 বেসিক স্কোপ (permission/receipt বাদে)।
/// CreateGroupUseCase-এর মতোই প্যাটার্ন: ID generation + repository call একসাথে
/// encapsulate করা হয়েছে, যাতে Bloc/UI-কে ID generation নিয়ে ভাবতে না হয়।
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
