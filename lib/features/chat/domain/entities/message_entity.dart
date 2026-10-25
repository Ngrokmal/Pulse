import 'message_type.dart';
import 'voice_message_entity.dart';

class MessageEntity {
  final String messageId;
  final String chatId;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final String status;

  final String type;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final String? fileName;
  final int? fileSizeBytes;
  final String? mimeType;
  final int? durationMs;
  final int? width;
  final int? height;
  final List<double>? waveform;
  final String? localFilePath;
  final String? uploadState;

  final String? syncStatus;

  final String? alertId;
  final String? alertDisplayName;
  final String? alertAudioUrl;
  final String? alertAudioChecksum;
  final String? alertAudioFormat;
  final int? alertAudioSizeBytes;
  final int? alertAudioDurationMs;

  const MessageEntity({
    required this.messageId,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.status = 'sent',
    this.type = MessageType.text,
    this.mediaUrl,
    this.thumbnailUrl,
    this.fileName,
    this.fileSizeBytes,
    this.mimeType,
    this.durationMs,
    this.width,
    this.height,
    this.waveform,
    this.localFilePath,
    this.uploadState,
    this.syncStatus,
    this.alertId,
    this.alertDisplayName,
    this.alertAudioUrl,
    this.alertAudioChecksum,
    this.alertAudioFormat,
    this.alertAudioSizeBytes,
    this.alertAudioDurationMs,
  });

  bool get hasAlert => alertId != null && alertAudioUrl != null;

  bool get isMediaMessage => MessageType.isMedia(type);

  VoiceMessageEntity? get voiceAttachment {
    if (type != MessageType.voice) return null;
    return VoiceMessageEntity(
      remoteUrl: mediaUrl,
      localPath: localFilePath,
      durationMs: durationMs ?? 0,
      waveform: waveform ?? const [],
    );
  }
}
