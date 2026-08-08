library chat_row_builder;

enum ChatRowType { dateSeparator, message }

class ChatRow<T> {
  final ChatRowType type;
  final DateTime? separatorDate;
  final T? message;

  const ChatRow.separator(DateTime date)
      : type = ChatRowType.dateSeparator,
        separatorDate = date,
        message = null;

  const ChatRow.message(T value)
      : type = ChatRowType.message,
        separatorDate = null,
        message = value;

  bool get isSeparator => type == ChatRowType.dateSeparator;
}

List<ChatRow<T>> buildChatRowsWithDateSeparators<T>(
  List<T> messages,
  DateTime Function(T message) createdAtOf,
) {
  final rows = <ChatRow<T>>[];
  DateTime? previousDay;

  for (final message in messages) {
    final createdAt = createdAtOf(message).toLocal();
    final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
    if (previousDay == null || day != previousDay) {
      rows.add(ChatRow<T>.separator(day));
      previousDay = day;
    }
    rows.add(ChatRow<T>.message(message));
  }

  return rows;
}
