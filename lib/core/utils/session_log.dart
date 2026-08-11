import '../../features/telemetry/telemetry_history.dart';
import '../../models/vehicle.dart';
import '../constants/app_config.dart';

/// Renders a session's trend history and activity log as plain text, for the
/// share sheet on the telemetry screen.
///
/// Plain text rather than CSV on purpose: the person receiving this is usually
/// the user themselves, mid-debug, reading it on another screen. Aligned
/// columns survive that; a CSV does not. Gaps in a series render as empty
/// fields — a missing frame must never be smoothed into a value the vehicle
/// did not report.
abstract final class SessionLog {
  static String build({
    required TelemetryHistory history,
    required List<ActivityEntry> activity,
    required DateTime now,
  }) {
    final buffer = StringBuffer()
      ..writeln('${AppConfig.appName} session log')
      ..writeln('Exported ${now.toIso8601String()}')
      ..writeln();

    buffer
      ..writeln('TELEMETRY (${history.samples.length} samples, '
          'every ${TelemetryHistoryController.sampleInterval.inSeconds}s)')
      ..writeln('time  battery%  distance_cm  signal%  output%');
    for (final sample in history.samples) {
      final at = sample.at;
      final hh = at.hour.toString().padLeft(2, '0');
      final mm = at.minute.toString().padLeft(2, '0');
      final ss = at.second.toString().padLeft(2, '0');
      buffer.writeln(
        '$hh:$mm:$ss  '
        '${_cell(sample.batteryPercent)}  '
        '${_cell(sample.distanceCm)}  '
        '${_cell(sample.signalPercent)}  '
        '${_cell(sample.outputPercent)}',
      );
    }

    buffer
      ..writeln()
      ..writeln('ACTIVITY (${activity.length} entries, newest first)');
    for (final entry in activity) {
      final at = entry.timestamp;
      final hh = at.hour.toString().padLeft(2, '0');
      final mm = at.minute.toString().padLeft(2, '0');
      final ss = at.second.toString().padLeft(2, '0');
      buffer.writeln(
        '$hh:$mm:$ss  [${entry.severity.name.toUpperCase()}] '
        '${entry.message}${entry.detail == null ? '' : ' — ${entry.detail}'}',
      );
    }

    return buffer.toString();
  }

  static String _cell(double? value) =>
      value == null ? '' : value.toStringAsFixed(0);
}
