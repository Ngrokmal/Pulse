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

  /// Parses a Firestore `chats/{chatId}` document into a [ChatListItemModel].
  ///
  /// [documentId] is used as a fallback for `chatId` when the field is
  /// missing from the document data itself (mirrors the fallback behavior
  /// used by [MessageModel.fromJson]).
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
      groupPhotoUrl: json['groupPhotoUrl'] as String?, // Day 5 Milestone 1, group doc-এ থাকলে, 1:1-এ null
      // Day 5 Milestone 2: 'memberUids' key-এর উপস্থিতি দিয়ে group doc শনাক্ত
      // করা হয় (createGroup সবসময় এই ফিল্ড লেখে, 1:1 doc-এ কখনো থাকে না) —
      // Firestore schema-তে নতুন কিছু যোগ করা হয়নি, শুধু বিদ্যমান ফিল্ড parse করা হচ্ছে।
      isGroup: json.containsKey('memberUids'),
      name: json['name'] as String?,
    );
  }
}
