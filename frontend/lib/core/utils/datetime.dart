/// Date/time formatting: ISO strings from the API (UTC) -> readable local
/// text. Locale pinned to 'en' for deterministic output on every platform.
library;

import 'package:intl/intl.dart';

String formatDateTime(DateTime time) =>
    DateFormat('d MMM yyyy, HH:mm', 'en').format(time.toLocal());

String formatTime(DateTime time) => DateFormat('HH:mm', 'en').format(time.toLocal());

String formatDate(DateTime time) => DateFormat('d MMM yyyy', 'en').format(time.toLocal());

/// "just now" / minutes ago for notification chronology.
String formatRelative(DateTime time) {
  final diff = DateTime.now().toUtc().difference(time.toUtc());
  if (diff.isNegative || diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDate(time);
}
