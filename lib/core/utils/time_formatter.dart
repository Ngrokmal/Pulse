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

String _formatClockTime(DateTime dt) {
  final local = dt.toLocal();
  final hour24 = local.hour;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  int hour12 = hour24 % 12;
  if (hour12 == 0) hour12 = 12;
  final minute = _twoDigits(local.minute);
  return '$hour12:$minute $period';
}

String _formatShortDate(DateTime dt) {
  final local = dt.toLocal();
  final year2 = _twoDigits(local.year % 100);
  return '${local.day}/${local.month}/$year2';
}

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
    return _weekdayShortNames[tsLocal.weekday - 1];
  }
  return _formatShortDate(tsLocal);
}

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

String formatMessageBubbleTime(DateTime timestamp) {
  return _formatClockTime(timestamp.toLocal());
}

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
