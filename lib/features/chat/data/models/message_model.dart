import 'package:cloud_firestore/cloud_firestore.dart';
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
    super.alertId,
    super.alertDisplayName,
    super.alertAudioUrl,
    super.alertAudioChecksum,
    super.alertAudioFormat,
    super.alertAudioSizeBytes,
    super.alertAudioDurationMs,
  });

  factory MessageModel.fromJson(
    Map<String, dynamic> json, {
    String? documentId,
    String? fallbackChatId,
  }) {
    final dynamic rawCreatedAt = json['createdAt'];
    final DateTime resolvedCreatedAt = rawCreatedAt is Timestamp
        ? rawCreatedAt.toDate()
        : DateTime.now();

    final dynamic rawWaveform = json['waveform'];
    final List<double>? waveform = rawWaveform is List
        ? rawWaveform.map((e) => (e as num).toDouble()).toList()
        : null;

    return MessageModel(
      messageId: json['messageId'] as String? ?? documentId ?? '',
      chatId: json['chatId'] as String? ?? fallbackChatId ?? '',
      senderId: json['senderId'] as String? ?? '',
      text: json['text'] as String? ?? '',
      createdAt: resolvedCreatedAt,
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
      alertId: json['alertId'] as String?,
      alertDisplayName: json['alertDisplayName'] as String?,
      alertAudioUrl: json['alertAudioUrl'] as String?,
      alertAudioChecksum: json['alertAudioChecksum'] as String?,
      alertAudioFormat: json['alertAudioFormat'] as String?,
      alertAudioSizeBytes: (json['alertAudioSizeBytes'] as num?)?.toInt(),
      alertAudioDurationMs: (json['alertAudioDurationMs'] as num?)?.toInt(),
    );
  }

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
        alertId: e.alertId,
        alertDisplayName: e.alertDisplayName,
        alertAudioUrl: e.alertAudioUrl,
        alertAudioChecksum: e.alertAudioChecksum,
        alertAudioFormat: e.alertAudioFormat,
        alertAudioSizeBytes: e.alertAudioSizeBytes,
        alertAudioDurationMs: e.alertAudioDurationMs,
      );

  /// TASK 2 — local Hive cache round-trip. Kept separate from
  /// toJson()/fromJson() (Firestore-specific: toJson writes
  /// FieldValue.serverTimestamp(), which Hive can't store) so neither the
  /// Firestore wire format nor its parsing is touched by this change.
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
      if (alertId != null) 'alertId': alertId,
      if (alertDisplayName != null) 'alertDisplayName': alertDisplayName,
      if (alertAudioUrl != null) 'alertAudioUrl': alertAudioUrl,
      if (alertAudioChecksum != null) 'alertAudioChecksum': alertAudioChecksum,
      if (alertAudioFormat != null) 'alertAudioFormat': alertAudioFormat,
      if (alertAudioSizeBytes != null) 'alertAudioSizeBytes': alertAudioSizeBytes,
      if (alertAudioDurationMs != null) 'alertAudioDurationMs': alertAudioDurationMs,
    };
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'messageId': messageId,
      'chatId': chatId,
      'senderId': senderId,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'status': status,
      'type': type,
    };

    if (mediaUrl != null) data['mediaUrl'] = mediaUrl;
    if (thumbnailUrl != null) data['thumbnailUrl'] = thumbnailUrl;
    if (fileName != null) data['fileName'] = fileName;
    if (fileSizeBytes != null) data['fileSizeBytes'] = fileSizeBytes;
    if (mimeType != null) data['mimeType'] = mimeType;
    if (durationMs != null) data['durationMs'] = durationMs;
    if (width != null) data['width'] = width;
    if (height != null) data['height'] = height;
    if (waveform != null) data['waveform'] = waveform;

    // Friend Alert Sounds — only written when the sender actually attached
    // one (Alert-only or Message+Alert send mode); a plain text/media/voice
    // message writes none of these keys, identical to today's shape.
    if (alertId != null) data['alertId'] = alertId;
    if (alertDisplayName != null) data['alertDisplayName'] = alertDisplayName;
    if (alertAudioUrl != null) data['alertAudioUrl'] = alertAudioUrl;
    if (alertAudioChecksum != null) data['alertAudioChecksum'] = alertAudioChecksum;
    if (alertAudioFormat != null) data['alertAudioFormat'] = alertAudioFormat;
    if (alertAudioSizeBytes != null) data['alertAudioSizeBytes'] = alertAudioSizeBytes;
    if (alertAudioDurationMs != null) data['alertAudioDurationMs'] = alertAudioDurationMs;

    return data;
  }
}
