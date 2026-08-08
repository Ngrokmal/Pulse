import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

class CreateGroupUseCase {
  final GroupRepository repository;
  final ModerationGuard moderationGuard;
  const CreateGroupUseCase(this.repository, this.moderationGuard);

  Future<String> call({
    required String name,
    required String creatorId,
    required List<String> initialMembers,
  }) async {
    await moderationGuard.ensureNotBlocked(creatorId);
    final groupId = repository.generateGroupId();

    await repository.createGroup(
      groupId: groupId,
      name: name,
      creatorId: creatorId,
      initialMembers: initialMembers,
    );

    return groupId;
  }
}
