import '../../../../core/utils/moderation_guard.dart';
import '../../../custom_alert/domain/entities/alert_audio_metadata_entity.dart';
import '../repositories/chat_repository.dart';

class SendMessageWithAlertUseCase {
  final ChatRepository repository;
  final ModerationGuard moderationGuard;
  const SendMessageWithAlertUseCase(this.repository, this.moderationGuard);

  Future<void> call({
    required String chatId,
    required String senderId,
    String text = '',
    required AlertAudioMetadata alert,
  }) async {
    await moderationGuard.ensureNotBlocked(senderId);
    final messageId = repository.generateMessageId(chatId);
    return repository.sendMessageWithAlert(
      chatId: chatId,
      messageId: messageId,
      senderId: senderId,
      text: text,
      alertId: alert.alertId,
      alertDisplayName: alert.displayName,
      alertAudioUrl: alert.audioUrl,
      alertAudioChecksum: alert.checksum,
      alertAudioFormat: alert.format,
      alertAudioSizeBytes: alert.fileSizeBytes,
      alertAudioDurationMs: alert.durationMs,
    );
  }
}
