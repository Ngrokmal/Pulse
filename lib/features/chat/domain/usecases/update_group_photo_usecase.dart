import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

class UpdateGroupPhotoUseCase {
  final GroupRepository repository;
  final ModerationGuard moderationGuard;
  const UpdateGroupPhotoUseCase(this.repository, this.moderationGuard);

  Future<void> call({required String groupId, required String photoUrl, required String publicId, required String actorUid}) async {
    await moderationGuard.ensureNotBlocked(actorUid);
    return repository.updateGroupPhoto(groupId: groupId, photoUrl: photoUrl, publicId: publicId);
  }
}
