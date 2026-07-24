import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

/// Day 6 Milestone 3 (Read Receipts): MarkMessageAsReadUseCase-এর
/// group-সমতুল্য পাতলা wrapper — GroupRepository.markMessageAsRead
/// (পূর্ব-বিদ্যমান, receipts sub-collection + status flip) কল করে।
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
