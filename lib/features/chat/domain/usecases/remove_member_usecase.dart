import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

/// AddMemberUseCase-এর প্রতিসম wrapper — GroupRepository.removeMember-এর ওপর।
class RemoveMemberUseCase {
  final GroupRepository repository;
  final ModerationGuard moderationGuard;
  const RemoveMemberUseCase(this.repository, this.moderationGuard);

  Future<void> call({required String groupId, required String uid, required String actorUid}) async {
    await moderationGuard.ensureNotBlocked(actorUid);
    return repository.removeMember(groupId: groupId, uid: uid);
  }
}
