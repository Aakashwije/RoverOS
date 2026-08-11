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

/// Freshness of a scan result.
///
/// Separate from [formatRelativeTime], which rounds everything under 45
/// seconds to "now". During a scan that whole window is the interesting part:
/// a device last heard 20 seconds ago is probably walking out of range, and
/// the user needs to see that before they tap connect.
String formatLastSeen(DateTime? seenAt, {DateTime? now}) {
  if (seenAt == null) return 'Seen just now';
  final delta = (now ?? DateTime.now()).difference(seenAt);
  if (delta.isNegative || delta.inSeconds < 2) return 'Seen just now';
  if (delta.inSeconds < 60) return 'Seen ${delta.inSeconds}s ago';
  if (delta.inMinutes < 60) return 'Seen ${delta.inMinutes}m ago';
  return 'Seen ${delta.inHours}h ago';
}

/// Whole seconds remaining, floored at zero. For scan and reconnect countdowns.
///
/// Rounds up, so a 12-second scan reads "12s" the instant it starts rather
/// than flashing "11s" before the first tick lands.
int secondsRemaining(DateTime? until, {DateTime? now}) {
  if (until == null) return 0;
  final delta = until.difference(now ?? DateTime.now());
  if (delta.isNegative) return 0;
  return (delta.inMilliseconds / 1000).ceil();
}
