import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

class LeaveGroupUseCase {
  final GroupRepository repository;
  final ModerationGuard moderationGuard;
  const LeaveGroupUseCase(this.repository, this.moderationGuard);

  Future<void> call({required String groupId, required String uid}) async {
    await moderationGuard.ensureNotBlocked(uid);
    return repository.leaveGroup(groupId: groupId, uid: uid);
  }
}
