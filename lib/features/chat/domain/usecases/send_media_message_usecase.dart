import '../../../../core/utils/moderation_guard.dart';
import '../repositories/chat_repository.dart';

class SendMediaMessageUseCase {
  final ChatRepository repository;
  final ModerationGuard moderationGuard;
  const SendMediaMessageUseCase(this.repository, this.moderationGuard);

  String generateMessageId(String chatId) => repository.generateMessageId(chatId);

  Future<void> call({
    required String chatId,
    required String messageId,
    required String senderId,
    required String type,
    String text = '',
    String? mediaUrl,
    String? thumbnailUrl,
    String? fileName,
    int? fileSizeBytes,
    String? mimeType,
    int? durationMs,
    int? width,
    int? height,
    List<double>? waveform,
  }) async {
    await moderationGuard.ensureNotBlocked(senderId);
    return repository.sendMediaMessage(
      chatId: chatId,
      messageId: messageId,
      senderId: senderId,
      type: type,
      text: text,
      mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl,
      fileName: fileName,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      durationMs: durationMs,
      width: width,
      height: height,
      waveform: waveform,
    );
  }
}
