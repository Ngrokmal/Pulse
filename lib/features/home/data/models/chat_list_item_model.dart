import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/chat_list_item_entity.dart';

class ChatListItemModel extends ChatListItemEntity {
  const ChatListItemModel({
    required super.chatId,
    required super.participantIds,
    required super.lastMessage,
    required super.lastMessageAt,
    required super.lastMessageSenderId,
    required super.unreadCount,
    super.groupPhotoUrl,
    super.isGroup,
    super.name,
  });

  factory ChatListItemModel.fromJson(
    Map<String, dynamic> json, {
    String? documentId,
  }) {
    final dynamic rawLastMessageAt = json['lastMessageAt'];
    final DateTime resolvedLastMessageAt = rawLastMessageAt is Timestamp
        ? rawLastMessageAt.toDate()
        : DateTime.now();

    final dynamic rawUnreadCount = json['unreadCount'];
    final Map<String, int> resolvedUnreadCount = rawUnreadCount is Map
        ? rawUnreadCount.map(
            (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
          )
        : <String, int>{};

    return ChatListItemModel(
      chatId: json['chatId'] as String? ?? documentId ?? '',
      participantIds: (json['participantIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      lastMessage: json['lastMessage'] as String? ?? '',
      lastMessageAt: resolvedLastMessageAt,
      lastMessageSenderId: json['lastMessageSenderId'] as String? ?? '',
      unreadCount: resolvedUnreadCount,
      groupPhotoUrl: json['groupPhotoUrl'] as String?,
      isGroup: json.containsKey('memberUids'),
      name: json['name'] as String?,
    );
  }

  factory ChatListItemModel.fromSupabaseRow(
    Map<String, dynamic> row, {
    required String logicalChatId,
    required List<String> participantIds,
    required String lastMessageSenderId,
    required String currentUserId,
    required int myUnreadCount,
  }) {
    final dynamic rawLastMessageAt = row['last_message_at'];
    final DateTime resolvedLastMessageAt = rawLastMessageAt is String
        ? DateTime.parse(rawLastMessageAt).toLocal()
        : DateTime.now();

    return ChatListItemModel(
      chatId: logicalChatId,
      participantIds: participantIds,
      lastMessage: row['last_message'] as String? ?? '',
      lastMessageAt: resolvedLastMessageAt,
      lastMessageSenderId: lastMessageSenderId,
      unreadCount: {currentUserId: myUnreadCount},
      groupPhotoUrl: null,
      isGroup: false,
      name: null,
    );
  }

  factory ChatListItemModel.fromCacheJson(Map<String, dynamic> json) {
    final dynamic rawUnreadCount = json['unreadCount'];
    final Map<String, int> unreadCount = rawUnreadCount is Map
        ? rawUnreadCount.map((key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0))
        : <String, int>{};

    final dynamic rawParticipantIds = json['participantIds'];
    final List<String> participantIds = rawParticipantIds is List
        ? rawParticipantIds.map((e) => e.toString()).toList()
        : <String>[];

    return ChatListItemModel(
      chatId: json['chatId'] as String? ?? '',
      participantIds: participantIds,
      lastMessage: json['lastMessage'] as String? ?? '',
      lastMessageAt: DateTime.fromMillisecondsSinceEpoch(json['lastMessageAt'] as int? ?? 0),
      lastMessageSenderId: json['lastMessageSenderId'] as String? ?? '',
      unreadCount: unreadCount,
      groupPhotoUrl: json['groupPhotoUrl'] as String?,
      isGroup: json['isGroup'] as bool? ?? false,
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toCacheJson() {
    return {
      'chatId': chatId,
      'participantIds': participantIds,
      'lastMessage': lastMessage,
      'lastMessageAt': lastMessageAt.millisecondsSinceEpoch,
      'lastMessageSenderId': lastMessageSenderId,
      'unreadCount': unreadCount,
      if (groupPhotoUrl != null) 'groupPhotoUrl': groupPhotoUrl,
      'isGroup': isGroup,
      if (name != null) 'name': name,
    };
  }

  ChatListItemModel copyWith({
    String? lastMessage,
    DateTime? lastMessageAt,
    String? lastMessageSenderId,
    Map<String, int>? unreadCount,
  }) {
    return ChatListItemModel(
      chatId: chatId,
      participantIds: participantIds,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      unreadCount: unreadCount ?? this.unreadCount,
      groupPhotoUrl: groupPhotoUrl,
      isGroup: isGroup,
      name: name,
    );
  }
}
