/// Milestone 6: Cloudinary upload response-এর ডোমেইন-লেয়ার representation।
/// MessageEntity/GroupEntity-এর মতোই plain immutable data holder — কোনো
/// Cloudinary-specific টাইপ (যেমন raw JSON Map) domain/presentation লেয়ারে
/// leak করে না, শুধু data লেয়ারেই (MediaRepositoryImpl) থাকে।
class MediaUploadResult {
  final String secureUrl;
  final String publicId;

  const MediaUploadResult({
    required this.secureUrl,
    required this.publicId,
  });
}
