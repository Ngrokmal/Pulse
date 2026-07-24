import '../../domain/entities/alert_audio_metadata_entity.dart';

class AlertAudioMetadataModel extends AlertAudioMetadata {
  const AlertAudioMetadataModel({
    required super.alertId,
    required super.displayName,
    required super.audioUrl,
    required super.checksum,
    required super.format,
    required super.fileSizeBytes,
    super.durationMs,
    required super.createdAt,
  });

  factory AlertAudioMetadataModel.fromMap(Map<String, dynamic> map) {
    final dynamic rawCreatedAt = map['createdAt'];
    final DateTime resolvedCreatedAt = rawCreatedAt is String
        ? DateTime.tryParse(rawCreatedAt) ?? DateTime.now()
        : DateTime.now();

    return AlertAudioMetadataModel(
      alertId: map['alertId'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      audioUrl: map['audioUrl'] as String? ?? '',
      checksum: map['checksum'] as String? ?? '',
      format: map['format'] as String? ?? '',
      fileSizeBytes: (map['fileSizeBytes'] as num?)?.toInt() ?? 0,
      durationMs: (map['durationMs'] as num?)?.toInt(),
      createdAt: resolvedCreatedAt,
    );
  }

  factory AlertAudioMetadataModel.fromEntity(AlertAudioMetadata entity) {
    return AlertAudioMetadataModel(
      alertId: entity.alertId,
      displayName: entity.displayName,
      audioUrl: entity.audioUrl,
      checksum: entity.checksum,
      format: entity.format,
      fileSizeBytes: entity.fileSizeBytes,
      durationMs: entity.durationMs,
      createdAt: entity.createdAt,
    );
  }

  static AlertAudioMetadataModel? fromPushData(Map<String, dynamic> data) {
    final String? alertId = data['alertId'] as String?;
    final String? audioUrl = data['alertAudioUrl'] as String?;
    final String? checksum = data['alertAudioChecksum'] as String?;
    final String? format = data['alertAudioFormat'] as String?;
    final String? sizeRaw = data['alertAudioSizeBytes'] as String?;

    if (alertId == null ||
        alertId.isEmpty ||
        audioUrl == null ||
        checksum == null ||
        format == null ||
        sizeRaw == null) {
      return null;
    }

    final int? fileSizeBytes = int.tryParse(sizeRaw);
    if (fileSizeBytes == null) return null;

    final String? durationRaw = data['alertAudioDurationMs'] as String?;

    return AlertAudioMetadataModel(
      alertId: alertId,
      displayName: (data['alertDisplayName'] as String?) ?? alertId,
      audioUrl: audioUrl,
      checksum: checksum,
      format: format,
      fileSizeBytes: fileSizeBytes,
      durationMs: durationRaw != null ? int.tryParse(durationRaw) : null,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'alertId': alertId,
      'displayName': displayName,
      'audioUrl': audioUrl,
      'checksum': checksum,
      'format': format,
      'fileSizeBytes': fileSizeBytes,
      'durationMs': durationMs,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
