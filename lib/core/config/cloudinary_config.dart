class CloudinaryConfig {
  const CloudinaryConfig._();

  static const String cloudName = 'uu4brxv0';
  static const String uploadPreset = 'ml_default';

  static const String groupPhotoFolder = 'pulse_group_photos';
  static const String profilePhotoFolder = 'pulse_profile_photos';
  static const String coverPhotoFolder = 'pulse_cover_photos';

  static const String chatImageFolder = 'pulse_chat_images';
  static const String chatVideoFolder = 'pulse_chat_videos';
  static const String chatFileFolder = 'pulse_chat_files';
  static const String chatVoiceFolder = 'pulse_chat_voice';

  static String uploadUrlFor(String resourceType) =>
      'https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload';
}
