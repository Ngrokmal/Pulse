import '../entities/message_type.dart';
import '../entities/voice_message_entity.dart';
import 'send_media_message_usecase.dart';

class SendVoiceMessageUseCase {
  final SendMediaMessageUseCase sendMediaMessageUseCase;
  const SendVoiceMessageUseCase(this.sendMediaMessageUseCase);

  Future<void> call({
    required String chatId,
    required String messageId,
    required String senderId,
    required VoiceMessageEntity voice,
  }) async {
    return sendMediaMessageUseCase(
      chatId: chatId,
      messageId: messageId,
      senderId: senderId,
      type: MessageType.voice,
      mediaUrl: voice.remoteUrl,
      durationMs: voice.durationMs,
      waveform: voice.waveform,
    );
  }
}
