import '../repositories/media_repository.dart';

class DeleteGroupPhotoUseCase {
  final MediaRepository repository;
  const DeleteGroupPhotoUseCase(this.repository);

  Future<void> call({required String publicId}) {
    return repository.deleteImage(publicId: publicId);
  }
}
