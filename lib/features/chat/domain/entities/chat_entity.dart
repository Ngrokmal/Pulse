class ChatEntity {
  final String chatId;
  final List<String> memberUids;
  final Map<String, dynamic>? metadata;

  const ChatEntity({
    required this.chatId,
    required this.memberUids,
    this.metadata,
  });
}
