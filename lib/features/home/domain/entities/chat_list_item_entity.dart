class ChatListItemEntity {
  final String chatId;
  final List<String> participantIds;
  final String lastMessage;
  final DateTime lastMessageAt;
  final String lastMessageSenderId;
  final Map<String, int> unreadCount;
  final String? groupPhotoUrl;
  final bool isGroup;
  final String? name;

  const ChatListItemEntity({
    required this.chatId,
    required this.participantIds,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastMessageSenderId,
    required this.unreadCount,
    this.groupPhotoUrl,
    this.isGroup = false,
    this.name,
  });
}
