class AlertAudioMetadata {
  final String alertId;
  final String displayName;
  final String audioUrl;
  final String checksum;
  final String format;
  final int fileSizeBytes;
  final int? durationMs;
  final DateTime createdAt;

  const AlertAudioMetadata({
    required this.alertId,
    required this.displayName,
    required this.audioUrl,
    required this.checksum,
    required this.format,
    required this.fileSizeBytes,
    this.durationMs,
    required this.createdAt,
  });
}
