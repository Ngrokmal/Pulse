class MessageType {
  MessageType._();

  static const String text = 'text';
  static const String image = 'image';
  static const String video = 'video';
  static const String file = 'file';
  static const String voice = 'voice';

  static bool isMedia(String type) => type != text;
}
