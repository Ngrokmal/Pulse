import '../../domain/entities/message_entity.dart';
import '../../domain/entities/message_type.dart';

class MessageModel extends MessageEntity {
  const MessageModel({
    required super.messageId,
    required super.chatId,
    required super.senderId,
    required super.text,
    required super.createdAt,
    super.status,
    super.type,
    super.mediaUrl,
    super.thumbnailUrl,
    super.fileName,
    super.fileSizeBytes,
    super.mimeType,
    super.durationMs,
    super.width,
    super.height,
    super.waveform,
    super.localFilePath,
    super.uploadState,
    super.syncStatus,
    super.alertId,
    super.alertDisplayName,
    super.alertAudioUrl,
    super.alertAudioChecksum,
    super.alertAudioFormat,
    super.alertAudioSizeBytes,
    super.alertAudioDurationMs,
  });

  factory MessageModel.fromEntity(MessageEntity e) => MessageModel(
        messageId: e.messageId,
        chatId: e.chatId,
        senderId: e.senderId,
        text: e.text,
        createdAt: e.createdAt,
        status: e.status,
        type: e.type,
        mediaUrl: e.mediaUrl,
        thumbnailUrl: e.thumbnailUrl,
        fileName: e.fileName,
        fileSizeBytes: e.fileSizeBytes,
        mimeType: e.mimeType,
        durationMs: e.durationMs,
        width: e.width,
        height: e.height,
        waveform: e.waveform,
        localFilePath: e.localFilePath,
        uploadState: e.uploadState,
        syncStatus: e.syncStatus,
        alertId: e.alertId,
        alertDisplayName: e.alertDisplayName,
        alertAudioUrl: e.alertAudioUrl,
        alertAudioChecksum: e.alertAudioChecksum,
        alertAudioFormat: e.alertAudioFormat,
        alertAudioSizeBytes: e.alertAudioSizeBytes,
        alertAudioDurationMs: e.alertAudioDurationMs,
      );

  MessageModel copyWithSyncStatus({required String status, required String? syncStatus}) {
    return MessageModel(
      messageId: messageId,
      chatId: chatId,
      senderId: senderId,
      text: text,
      createdAt: createdAt,
      status: status,
      type: type,
      mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl,
      fileName: fileName,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      durationMs: durationMs,
      width: width,
      height: height,
      waveform: waveform,
      localFilePath: localFilePath,
      uploadState: uploadState,
      syncStatus: syncStatus,
      alertId: alertId,
      alertDisplayName: alertDisplayName,
      alertAudioUrl: alertAudioUrl,
      alertAudioChecksum: alertAudioChecksum,
      alertAudioFormat: alertAudioFormat,
      alertAudioSizeBytes: alertAudioSizeBytes,
      alertAudioDurationMs: alertAudioDurationMs,
    );
  }

  factory MessageModel.fromCacheJson(Map<String, dynamic> json) {
    final dynamic rawWaveform = json['waveform'];
    final List<double>? waveform = rawWaveform is List
        ? rawWaveform.map((e) => (e as num).toDouble()).toList()
        : null;

    return MessageModel(
      messageId: json['messageId'] as String? ?? '',
      chatId: json['chatId'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      text: json['text'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int? ?? 0),
      status: json['status'] as String? ?? 'sent',
      type: json['type'] as String? ?? MessageType.text,
      mediaUrl: json['mediaUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      fileName: json['fileName'] as String?,
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt(),
      mimeType: json['mimeType'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      waveform: waveform,
      localFilePath: json['localFilePath'] as String?,
      uploadState: json['uploadState'] as String?,
      syncStatus: json['syncStatus'] as String?,
      alertId: json['alertId'] as String?,
      alertDisplayName: json['alertDisplayName'] as String?,
      alertAudioUrl: json['alertAudioUrl'] as String?,
      alertAudioChecksum: json['alertAudioChecksum'] as String?,
      alertAudioFormat: json['alertAudioFormat'] as String?,
      alertAudioSizeBytes: (json['alertAudioSizeBytes'] as num?)?.toInt(),
      alertAudioDurationMs: (json['alertAudioDurationMs'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toCacheJson() {
    return {
      'messageId': messageId,
      'chatId': chatId,
      'senderId': senderId,
      'text': text,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'status': status,
      'type': type,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      if (fileName != null) 'fileName': fileName,
      if (fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
      if (mimeType != null) 'mimeType': mimeType,
      if (durationMs != null) 'durationMs': durationMs,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (waveform != null) 'waveform': waveform,
      if (localFilePath != null) 'localFilePath': localFilePath,
      if (uploadState != null) 'uploadState': uploadState,
      if (syncStatus != null) 'syncStatus': syncStatus,
      if (alertId != null) 'alertId': alertId,
      if (alertDisplayName != null) 'alertDisplayName': alertDisplayName,
      if (alertAudioUrl != null) 'alertAudioUrl': alertAudioUrl,
      if (alertAudioChecksum != null) 'alertAudioChecksum': alertAudioChecksum,
      if (alertAudioFormat != null) 'alertAudioFormat': alertAudioFormat,
      if (alertAudioSizeBytes != null) 'alertAudioSizeBytes': alertAudioSizeBytes,
      if (alertAudioDurationMs != null) 'alertAudioDurationMs': alertAudioDurationMs,
    };
  }

  factory MessageModel.fromSupabaseRow(
    Map<String, dynamic> row, {
    required String chatId,
  }) {
    final dynamic rawCreatedAt = row['created_at'];
    final DateTime resolvedCreatedAt = rawCreatedAt is String
        ? DateTime.parse(rawCreatedAt).toLocal()
        : DateTime.now();

    final dynamic rawWaveform = row['waveform'];
    final List<double>? waveform = rawWaveform is List
        ? rawWaveform.map((e) => (e as num).toDouble()).toList()
        : null;

    return MessageModel(
      messageId: row['id'] as String? ?? '',
      chatId: chatId,
      senderId: row['sender_id'] as String? ?? '',
      text: row['text'] as String? ?? '',
      createdAt: resolvedCreatedAt,
      status: row['status'] as String? ?? 'sent',
      type: row['type'] as String? ?? MessageType.text,
      mediaUrl: row['media_url'] as String?,
      thumbnailUrl: row['thumbnail_url'] as String?,
      fileName: row['file_name'] as String?,
      fileSizeBytes: (row['file_size_bytes'] as num?)?.toInt(),
      mimeType: row['mime_type'] as String?,
      durationMs: (row['duration_ms'] as num?)?.toInt(),
      width: (row['width'] as num?)?.toInt(),
      height: (row['height'] as num?)?.toInt(),
      waveform: waveform,
      alertId: row['alert_id'] as String?,
      alertDisplayName: row['alert_display_name'] as String?,
      alertAudioUrl: row['alert_audio_url'] as String?,
      alertAudioChecksum: row['alert_audio_checksum'] as String?,
      alertAudioFormat: row['alert_audio_format'] as String?,
      alertAudioSizeBytes: (row['alert_audio_size_bytes'] as num?)?.toInt(),
      alertAudioDurationMs: (row['alert_audio_duration_ms'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toSupabaseRow() {
    final data = <String, dynamic>{
      'id': messageId,
      'sender_id': senderId,
      'text': text,
      'status': status,
      'type': type,
    };

    if (mediaUrl != null) data['media_url'] = mediaUrl;
    if (thumbnailUrl != null) data['thumbnail_url'] = thumbnailUrl;
    if (fileName != null) data['file_name'] = fileName;
    if (fileSizeBytes != null) data['file_size_bytes'] = fileSizeBytes;
    if (mimeType != null) data['mime_type'] = mimeType;
    if (durationMs != null) data['duration_ms'] = durationMs;
    if (width != null) data['width'] = width;
    if (height != null) data['height'] = height;
    if (waveform != null) data['waveform'] = waveform;

    if (alertId != null) data['alert_id'] = alertId;
    if (alertDisplayName != null) data['alert_display_name'] = alertDisplayName;
    if (alertAudioUrl != null) data['alert_audio_url'] = alertAudioUrl;
    if (alertAudioChecksum != null) data['alert_audio_checksum'] = alertAudioChecksum;
    if (alertAudioFormat != null) data['alert_audio_format'] = alertAudioFormat;
    if (alertAudioSizeBytes != null) data['alert_audio_size_bytes'] = alertAudioSizeBytes;
    if (alertAudioDurationMs != null) data['alert_audio_duration_ms'] = alertAudioDurationMs;

    return data;
  }
}
