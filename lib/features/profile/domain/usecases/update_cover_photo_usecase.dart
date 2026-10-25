import '../repositories/profile_repository.dart';

class UpdateCoverPhotoUseCase {
  final ProfileRepository repository;
  const UpdateCoverPhotoUseCase(this.repository);

  Future<void> call({required String uid, required String photoUrl, required String publicId}) {
    return repository.updateCoverPhoto(uid: uid, url: photoUrl, publicId: publicId);
  }
}
