import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

/// PromoteAdminUseCase-এর প্রতিসম wrapper।
class DemoteAdminUseCase {
  final GroupRepository repository;
  final ModerationGuard moderationGuard;
  const DemoteAdminUseCase(this.repository, this.moderationGuard);

  Future<void> call({required String groupId, required String uid, required String actorUid}) async {
    await moderationGuard.ensureNotBlocked(actorUid);
    return repository.demoteAdmin(groupId: groupId, uid: uid);
  }
}
