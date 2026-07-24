import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../../core/config/cloudinary_config.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/media_upload_result.dart';
import '../../domain/repositories/media_repository.dart';

class MediaRepositoryImpl implements MediaRepository {
  final http.Client client;

  const MediaRepositoryImpl({required this.client});

  @override
  Future<MediaUploadResult> uploadImage({
    required File file,
    required String folder,
    UploadProgressCallback? onProgress,
  }) {
    return _upload(file: file, folder: folder, resourceType: 'image', onProgress: onProgress);
  }

  @override
  Future<MediaUploadResult> uploadVideo({
    required File file,
    required String folder,
    UploadProgressCallback? onProgress,
  }) {
    return _upload(file: file, folder: folder, resourceType: 'video', onProgress: onProgress);
  }

  @override
  Future<MediaUploadResult> uploadFile({
    required File file,
    required String folder,
    UploadProgressCallback? onProgress,
  }) {
    return _upload(file: file, folder: folder, resourceType: 'raw', onProgress: onProgress);
  }

  @override
  Future<MediaUploadResult> uploadVoice({
    required File file,
    required String folder,
    UploadProgressCallback? onProgress,
  }) {
    return _upload(file: file, folder: folder, resourceType: 'video', onProgress: onProgress);
  }

  Future<MediaUploadResult> _upload({
    required File file,
    required String folder,
    required String resourceType,
    UploadProgressCallback? onProgress,
  }) async {
    onProgress?.call(0.1);

    final uri = Uri.parse(CloudinaryConfig.uploadUrlFor(resourceType));
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = CloudinaryConfig.uploadPreset
      ..fields['folder'] = folder
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    onProgress?.call(0.3);

    late final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await client.send(request).timeout(const Duration(seconds: 60));
    } on SocketException catch (e) {
      throw NetworkException(message: 'Media upload failed: ${e.message}');
    } on TimeoutException {
      throw NetworkException(message: 'Media upload timed out. Please try again.');
    }

    onProgress?.call(0.7);

    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      throw ServerException(message: 'Cloudinary upload failed (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final secureUrl = decoded['secure_url'] as String?;
    final publicId = decoded['public_id'] as String?;
    if (secureUrl == null || publicId == null) {
      throw ServerException(message: 'Cloudinary upload response missing secure_url/public_id');
    }

    onProgress?.call(1.0);
    return MediaUploadResult(secureUrl: secureUrl, publicId: publicId);
  }

  @override
  Future<void> deleteImage({required String publicId}) {
    return deleteMedia(publicId: publicId, resourceType: 'image');
  }

  @override
  Future<void> deleteMedia({required String publicId, required String resourceType}) async {
    // Cloudinary destroy is performed server-side by a Supabase Edge
    // Function (delete-image) — the Cloudinary API key/secret live only in
    // that function's environment. This Flutter app only ever sends
    // publicId/resourceType and never holds a Cloudinary credential, same
    // security boundary as before, now via Supabase instead of Firebase
    // Secret Manager.
    try {
      final response = await client
          .post(
            Uri.parse(SupabaseConfig.deleteImageFunctionUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'publicId': publicId, 'resourceType': resourceType}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw ServerException(message: 'Cloudinary delete failed (${response.statusCode}): ${response.body}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final result = decoded['result'] as String?;
      if (result != 'ok' && result != 'not found') {
        throw ServerException(message: 'Cloudinary delete failed: unexpected response ${response.body}');
      }
    } on SocketException catch (e) {
      throw NetworkException(message: 'Media cleanup failed: ${e.message}');
    } on TimeoutException {
      throw NetworkException(message: 'Media cleanup timed out.');
    }
  }
}
