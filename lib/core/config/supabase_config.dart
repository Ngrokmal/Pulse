/// Supabase Edge Function endpoint(s) used by this app.
///
/// Currently only the Cloudinary delete flow: MediaRepositoryImpl.deleteMedia
/// posts `{publicId, resourceType}` to this URL and the Edge Function (which
/// holds the Cloudinary API key/secret server-side) performs the actual
/// Cloudinary destroy call. The Flutter app never sees or stores a
/// Cloudinary API key or API secret — same security boundary the previous
/// Firebase Cloud Function (`deleteCloudinaryMedia`) provided, just fronted
/// by Supabase instead of Firebase Secret Manager.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String deleteImageFunctionUrl =
      'https://qsnauioozvkhksbxajam.supabase.co/functions/v1/delete-image';
}
