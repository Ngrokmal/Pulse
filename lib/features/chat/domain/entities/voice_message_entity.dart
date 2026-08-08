class VoiceMessageEntity {
  final String? remoteUrl;
  final String? localPath;
  final int durationMs;
  final List<double> waveform;
  final double playbackSpeed;
  final String? replyToMessageId;

  const VoiceMessageEntity({
    this.remoteUrl,
    this.localPath,
    required this.durationMs,
    this.waveform = const [],
    this.playbackSpeed = 1.0,
    this.replyToMessageId,
  });

  bool get isPlaybackReady => remoteUrl != null && remoteUrl!.isNotEmpty;

  VoiceMessageEntity copyWith({
    String? remoteUrl,
    String? localPath,
    int? durationMs,
    List<double>? waveform,
    double? playbackSpeed,
    String? replyToMessageId,
  }) {
    return VoiceMessageEntity(
      remoteUrl: remoteUrl ?? this.remoteUrl,
      localPath: localPath ?? this.localPath,
      durationMs: durationMs ?? this.durationMs,
      waveform: waveform ?? this.waveform,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
    );
  }
}
