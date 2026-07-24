import '../repositories/media_repository.dart';

/// UploadGroupPhotoUseCase-এর প্রতিসম wrapper — পুরনো Cloudinary asset
/// ডিলিটের জন্য (replace-photo ফ্লোর দ্বিতীয় ধাপ, GroupInfoBloc-এ best-effort
/// হিসেবে কল হয়)।
class DeleteGroupPhotoUseCase {
  final MediaRepository repository;
  const DeleteGroupPhotoUseCase(this.repository);

  Future<void> call({required String publicId}) {
    return repository.deleteImage(publicId: publicId);
  }
}
