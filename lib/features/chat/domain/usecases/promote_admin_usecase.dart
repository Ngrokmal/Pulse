import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

class PromoteAdminUseCase {
  final GroupRepository repository;
  final ModerationGuard moderationGuard;
  const PromoteAdminUseCase(this.repository, this.moderationGuard);

  Future<void> call({required String groupId, required String uid, required String actorUid}) async {
    await moderationGuard.ensureNotBlocked(actorUid);
    return repository.promoteToAdmin(groupId: groupId, uid: uid);
  }
}
