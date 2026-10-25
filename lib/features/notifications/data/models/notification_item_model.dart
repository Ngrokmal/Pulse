import 'dart:convert';

import '../../domain/entities/notification_item_entity.dart';

class NotificationItemModel extends NotificationItemEntity {
  const NotificationItemModel({
    required super.id,
    required super.type,
    super.title,
    super.body,
    super.data,
    super.chatId,
    super.messageId,
    required super.isRead,
    required super.createdAt,
  });

  factory NotificationItemModel.fromEntity(NotificationItemEntity e) {
    return NotificationItemModel(
      id: e.id,
      type: e.type,
      title: e.title,
      body: e.body,
      data: e.data,
      chatId: e.chatId,
      messageId: e.messageId,
      isRead: e.isRead,
      createdAt: e.createdAt,
    );
  }

  factory NotificationItemModel.fromSupabaseRow(Map<String, dynamic> row) {
    final rawData = row['data'];
    final Map<String, dynamic> data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};

    final rawCreatedAt = row['created_at'];
    final DateTime createdAt = rawCreatedAt is String ? DateTime.parse(rawCreatedAt).toLocal() : DateTime.now();

    return NotificationItemModel(
      id: row['id'] as String,
      type: row['type'] as String? ?? 'unknown',
      title: row['title'] as String?,
      body: row['body'] as String?,
      data: data,
      chatId: row['chat_id'] as String?,
      messageId: row['message_id'] as String?,
      isRead: row['is_read'] as bool? ?? false,
      createdAt: createdAt,
    );
  }

  factory NotificationItemModel.fromCacheJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final Map<String, dynamic> data =
        rawData is String && rawData.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(rawData) as Map) : {};

    return NotificationItemModel(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'unknown',
      title: json['title'] as String?,
      body: json['body'] as String?,
      data: data,
      chatId: json['chatId'] as String?,
      messageId: json['messageId'] as String?,
      isRead: json['isRead'] as bool? ?? false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    );
  }

  Map<String, dynamic> toCacheJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'body': body,
      'data': jsonEncode(data),
      'chatId': chatId,
      'messageId': messageId,
      'isRead': isRead,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }
}
