/// Lightweight, dependency-free timestamp formatting for chat UI.
///
/// Deliberately does NOT use the `intl` package (not a project dependency,
/// and not required for the fixed set of formats needed here). Two entry
/// points are exposed so chat-list rows and message bubbles each get the
/// exact WhatsApp-style format they need, without duplicating the
/// same-day/yesterday/this-week/older date-math in multiple files.
library time_formatter;

const List<String> _weekdayShortNames = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> _weekdayFullNames = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _monthFullNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');

/// `7:24 AM` / `11:05 PM` — 12-hour clock, no leading zero on the hour,
/// matching WhatsApp's own time display.
String _formatClockTime(DateTime dt) {
  final local = dt.toLocal();
  final hour24 = local.hour;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  int hour12 = hour24 % 12;
  if (hour12 == 0) hour12 = 12;
  final minute = _twoDigits(local.minute);
  return '$hour12:$minute $period';
}

/// `12/7/26` — day/month/2-digit-year, matching the ticket's example
/// (`12/7/26`) exactly, i.e. no zero-padding on day/month.
String _formatShortDate(DateTime dt) {
  final local = dt.toLocal();
  final year2 = _twoDigits(local.year % 100);
  return '${local.day}/${local.month}/$year2';
}

/// For the home screen chat-list row (right-hand side, above the unread
/// badge):
/// - Today            -> `7:24 AM`
/// - Yesterday        -> `Yesterday`
/// - Within last 7d   -> weekday short name (`Mon`, `Tue`, ...)
/// - Older than 7 days -> `12/7/26`
String formatChatListTimestamp(DateTime timestamp, {DateTime? now}) {
  final DateTime nowLocal = (now ?? DateTime.now()).toLocal();
  final DateTime tsLocal = timestamp.toLocal();

  final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final tsDay = DateTime(tsLocal.year, tsLocal.month, tsLocal.day);
  final differenceInDays = today.difference(tsDay).inDays;

  if (differenceInDays == 0) {
    return _formatClockTime(tsLocal);
  }
  if (differenceInDays == 1) {
    return 'Yesterday';
  }
  if (differenceInDays > 1 && differenceInDays < 7) {
    // DateTime.weekday: Monday = 1 ... Sunday = 7
    return _weekdayShortNames[tsLocal.weekday - 1];
  }
  return _formatShortDate(tsLocal);
}

/// For the message bubble (inside the chat thread):
/// - Today   -> `7:24 AM`
/// - Yesterday -> `Yesterday 7:24 AM`
/// - Older   -> `12/7/26 7:24 AM`
String formatBubbleTimestamp(DateTime timestamp, {DateTime? now}) {
  final DateTime nowLocal = (now ?? DateTime.now()).toLocal();
  final DateTime tsLocal = timestamp.toLocal();

  if (_isSameDate(tsLocal, nowLocal)) {
    return _formatClockTime(tsLocal);
  }

  final yesterday = nowLocal.subtract(const Duration(days: 1));
  if (_isSameDate(tsLocal, yesterday)) {
    return 'Yesterday ${_formatClockTime(tsLocal)}';
  }

  return '${_formatShortDate(tsLocal)} ${_formatClockTime(tsLocal)}';
}

/// WhatsApp-style date-separator label shown between groups of messages in
/// the thread (not the same as [formatChatListTimestamp], which is for the
/// home-screen row):
/// - Same calendar day as now -> `Today`
/// - 1 day ago                -> `Yesterday`
/// - 2-6 days ago             -> full weekday name (`Monday`, `Tuesday`, ...)
/// - 7+ days ago              -> `Month Day, Year` (e.g. `July 5, 2026`)
String formatDateSeparator(DateTime timestamp, {DateTime? now}) {
  final DateTime nowLocal = (now ?? DateTime.now()).toLocal();
  final DateTime tsLocal = timestamp.toLocal();

  final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final tsDay = DateTime(tsLocal.year, tsLocal.month, tsLocal.day);
  final differenceInDays = today.difference(tsDay).inDays;

  if (differenceInDays == 0) {
    return 'Today';
  }
  if (differenceInDays == 1) {
    return 'Yesterday';
  }
  if (differenceInDays > 1 && differenceInDays < 7) {
    return _weekdayFullNames[tsLocal.weekday - 1];
  }
  return '${_monthFullNames[tsLocal.month - 1]} ${tsLocal.day}, ${tsLocal.year}';
}

/// Bubble timestamp, time-only (e.g. `8:48 AM`). Date context is now carried
/// by the separate date-separator row above each new day's messages (see
/// [formatDateSeparator]), so the bubble itself never needs to repeat
/// "Yesterday" or a date — just the clock time, every day.
String formatMessageBubbleTime(DateTime timestamp) {
  return _formatClockTime(timestamp.toLocal());
}

/// WhatsApp-style "last seen" line for the chat header:
/// - Today     -> `last seen today at 7:24 AM`
/// - Yesterday -> `last seen yesterday at 7:24 AM`
/// - Older     -> `last seen July 5, 2026`
String formatLastSeen(DateTime lastSeen, {DateTime? now}) {
  final DateTime nowLocal = (now ?? DateTime.now()).toLocal();
  final DateTime tsLocal = lastSeen.toLocal();

  final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final tsDay = DateTime(tsLocal.year, tsLocal.month, tsLocal.day);
  final differenceInDays = today.difference(tsDay).inDays;

  if (differenceInDays == 0) {
    return 'last seen today at ${_formatClockTime(tsLocal)}';
  }
  if (differenceInDays == 1) {
    return 'last seen yesterday at ${_formatClockTime(tsLocal)}';
  }
  return 'last seen ${_monthFullNames[tsLocal.month - 1]} ${tsLocal.day}, ${tsLocal.year}';
}
