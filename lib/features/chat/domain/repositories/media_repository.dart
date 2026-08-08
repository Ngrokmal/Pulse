import 'dart:io';
import '../entities/media_upload_result.dart';

typedef UploadProgressCallback = void Function(double progress);

abstract class MediaRepository {
  Future<MediaUploadResult> uploadImage({
    required File file,
    required String folder,
    UploadProgressCallback? onProgress,
  });

  Future<MediaUploadResult> uploadVideo({
    required File file,
    required String folder,
    UploadProgressCallback? onProgress,
  });

  Future<MediaUploadResult> uploadFile({
    required File file,
    required String folder,
    UploadProgressCallback? onProgress,
  });

  Future<MediaUploadResult> uploadVoice({
    required File file,
    required String folder,
    UploadProgressCallback? onProgress,
  });

  Future<void> deleteImage({required String publicId});

  Future<void> deleteMedia({required String publicId, required String resourceType});
}
