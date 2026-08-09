// Display formatting helpers. Kept out of widgets so the same value renders
// identically everywhere it appears.

/// Compact relative time for the activity feed: `now`, `4m ago`, `2h ago`.
String formatRelativeTime(DateTime timestamp, {DateTime? now}) {
  final delta = (now ?? DateTime.now()).difference(timestamp);

  if (delta.isNegative) return 'now';
  if (delta.inSeconds < 45) return 'now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  if (delta.inDays < 7) return '${delta.inDays}d ago';
  return '${(delta.inDays / 7).floor()}w ago';
}

/// `MM:SS`, or `H:MM:SS` past an hour. Used for link uptime.
String formatDuration(Duration duration) {
  final seconds = duration.inSeconds.abs();
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// Signed percentage with an explicit `+`, for motor outputs where direction
/// matters as much as magnitude.
String formatSignedPercent(int? value) {
  if (value == null) return '—';
  if (value == 0) return '0%';
  return '${value > 0 ? '+' : ''}$value%';
}

/// Direction word for a signed motor output.
String formatMotorDirection(int? value) {
  if (value == null || value == 0) return 'IDLE';
  return value > 0 ? 'FORWARD' : 'REVERSE';
}
