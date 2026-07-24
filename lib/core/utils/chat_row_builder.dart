/// Shared "insert a date-separator row before the first message of each new
/// calendar day" logic (BUG-3), generic over the message type so it works
/// identically for ChatScreen's `MessageEntity` list and GroupChatScreen's
/// `MessageEntity` list (or any other future message list) without
/// duplicating the day-boundary computation in each screen.
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

/// [messages] must already be in ascending chronological order (oldest
/// first) — the same ordering ChatBloc/GroupChatBloc already produce, so no
/// re-sort happens here.
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
