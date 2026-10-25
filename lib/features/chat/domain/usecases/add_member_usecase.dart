import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

class AddMemberUseCase {
  final GroupRepository repository;
  final ModerationGuard moderationGuard;
  const AddMemberUseCase(this.repository, this.moderationGuard);

  Future<void> call({required String groupId, required String uid, required String actorUid}) async {
    await moderationGuard.ensureNotBlocked(actorUid);
    return repository.addMember(groupId: groupId, uid: uid);
  }
}
