import '../repositories/profile_repository.dart';

class UpdateProfilePhotoUseCase {
  final ProfileRepository repository;
  const UpdateProfilePhotoUseCase(this.repository);

  Future<void> call({required String uid, required String photoUrl, required String publicId}) {
    return repository.updateAvatarPhoto(uid: uid, url: photoUrl, publicId: publicId);
  }
}
