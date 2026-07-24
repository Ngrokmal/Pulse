import 'dart:io';
import '../../../../core/config/cloudinary_config.dart';
import '../entities/media_upload_result.dart';
import '../repositories/media_repository.dart';

/// AddMemberUseCase-এর মতোই পাতলা wrapper। folder ইচ্ছাকৃতভাবে এখানে fix করা —
/// caller (Bloc)-কে Cloudinary folder জানার/পাস করার দরকার নেই।
class UploadGroupPhotoUseCase {
  final MediaRepository repository;
  const UploadGroupPhotoUseCase(this.repository);

  Future<MediaUploadResult> call({required File file}) {
    return repository.uploadImage(file: file, folder: CloudinaryConfig.groupPhotoFolder);
  }
}
