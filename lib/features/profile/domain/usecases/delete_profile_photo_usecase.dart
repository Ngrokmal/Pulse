import '../../../chat/domain/repositories/media_repository.dart';
import '../repositories/profile_repository.dart';

class DeleteProfilePhotoUseCase {
  final MediaRepository mediaRepository;
  final ProfileRepository profileRepository;
  const DeleteProfilePhotoUseCase({required this.mediaRepository, required this.profileRepository});

  Future<void> call({required String uid, String? publicId}) async {
    await profileRepository.removeAvatarPhoto(uid);
    if (publicId != null && publicId.isNotEmpty) {
      try {
        await mediaRepository.deleteImage(publicId: publicId);
      } catch (_) {}
    }
  }
}
