String formatMessageTime(DateTime value, DateTime now) {
  final DateTime localValue = value.toLocal();
  final DateTime localNow = now.toLocal();
  if (_isSameCalendarDate(localValue, localNow)) {
    return _formatClock(localValue);
  }

  return '${localValue.month}月${localValue.day}日';
}

String formatMessageTimeText(String value, DateTime now) {
  final DateTime? parsed = DateTime.tryParse(value.trim());
  return parsed == null ? value : formatMessageTime(parsed, now);
}

bool _isSameCalendarDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _formatClock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
