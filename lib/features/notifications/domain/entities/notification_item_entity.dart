class NotificationItemEntity {
  final String id;
  final String type;
  final String? title;
  final String? body;
  final Map<String, dynamic> data;
  final String? chatId;
  final String? messageId;
  final bool isRead;
  final DateTime createdAt;

  const NotificationItemEntity({
    required this.id,
    required this.type,
    this.title,
    this.body,
    this.data = const {},
    this.chatId,
    this.messageId,
    required this.isRead,
    required this.createdAt,
  });

  NotificationItemEntity copyWith({
    bool? isRead,
  }) {
    return NotificationItemEntity(
      id: id,
      type: type,
      title: title,
      body: body,
      data: data,
      chatId: chatId,
      messageId: messageId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}
