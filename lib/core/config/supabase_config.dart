class SupabaseConfig {
  const SupabaseConfig._();

  static const String deleteImageFunctionUrl =
      'https://qsnauioozvkhksbxajam.supabase.co/functions/v1/delete-image';

  static const String sendPushNotificationFunctionUrl =
      'https://eqqlscbklniuttvrglmo.supabase.co/functions/v1/send-push-notification';

  // Call module (Phase 1 §9/§21, Open Decision #6): mints short-lived Agora
  // RTC tokens server-side so the Agora App Certificate never reaches the
  // client. Same project ref as sendPushNotificationFunctionUrl. NOTE: this
  // Edge Function has NOT been deployed as of this milestone (Data Layer
  // only, per instruction — no Edge Function deployment in scope) —
  // CallRemoteDataSourceImpl.fetchAgoraToken will fail until it exists.
  static const String generateAgoraTokenFunctionUrl =
      'https://eqqlscbklniuttvrglmo.supabase.co/functions/v1/generate-agora-token';
}
