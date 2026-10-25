import 'dart:io';
import '../../../../core/config/cloudinary_config.dart';
import '../../../chat/domain/entities/media_upload_result.dart';
import '../../../chat/domain/repositories/media_repository.dart';

class UploadCoverPhotoUseCase {
  final MediaRepository repository;
  const UploadCoverPhotoUseCase(this.repository);

  Future<MediaUploadResult> call({required File file}) {
    return repository.uploadImage(file: file, folder: CloudinaryConfig.coverPhotoFolder);
  }
}
