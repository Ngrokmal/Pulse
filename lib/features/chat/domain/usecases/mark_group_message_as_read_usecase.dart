import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

class MarkGroupMessageAsReadUseCase {
  final GroupRepository repository;
  final ModerationGuard moderationGuard;
  const MarkGroupMessageAsReadUseCase(this.repository, this.moderationGuard);

  Future<void> call({
    required String groupId,
    required String messageId,
    required String uid,
  }) async {
    await moderationGuard.ensureNotBlocked(uid);
    return repository.markMessageAsRead(groupId: groupId, messageId: messageId, uid: uid);
  }
}
