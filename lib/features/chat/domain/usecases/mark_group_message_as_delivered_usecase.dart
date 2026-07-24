import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

/// Day 6 Milestone 2 (Delivery Status): MarkMessageAsDeliveredUseCase-এর
/// group-সমতুল্য পাতলা wrapper।
class MarkGroupMessageAsDeliveredUseCase {
  final GroupRepository repository;
  final ModerationGuard moderationGuard;
  const MarkGroupMessageAsDeliveredUseCase(this.repository, this.moderationGuard);

  Future<void> call({
    required String groupId,
    required String messageId,
    required String uid,
  }) async {
    await moderationGuard.ensureNotBlocked(uid);
    return repository.markMessageAsDelivered(groupId: groupId, messageId: messageId);
  }
}
