import '../../domain/entities/voice_message_entity.dart';

class VoiceMessageModel extends VoiceMessageEntity {
  const VoiceMessageModel({
    super.remoteUrl,
    super.localPath,
    required super.durationMs,
    super.waveform,
    super.playbackSpeed,
    super.replyToMessageId,
  });

  factory VoiceMessageModel.fromMessageJson(Map<String, dynamic> json) {
    final dynamic rawWaveform = json['waveform'];
    final List<double> waveform = rawWaveform is List
        ? rawWaveform.map((e) => (e as num).toDouble()).toList()
        : const [];

    return VoiceMessageModel(
      remoteUrl: json['mediaUrl'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      waveform: waveform,
    );
  }

  Map<String, dynamic> toMessageJsonFragment() {
    return {
      'mediaUrl': remoteUrl,
      'durationMs': durationMs,
      'waveform': waveform,
    };
  }
}
