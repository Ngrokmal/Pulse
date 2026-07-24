import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

/// PromoteAdminUseCase-এর মতোই পাতলা wrapper — permission গার্ড GroupInfoBloc-এ।
class UpdateGroupNameUseCase {
  final GroupRepository repository;
  final ModerationGuard moderationGuard;
  const UpdateGroupNameUseCase(this.repository, this.moderationGuard);

  Future<void> call({required String groupId, required String name, required String actorUid}) async {
    await moderationGuard.ensureNotBlocked(actorUid);
    return repository.updateGroupName(groupId: groupId, name: name);
  }
}
