import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/connection_state.dart';
import '../../models/telemetry.dart';
import '../connection/connection_controller.dart';
import 'telemetry_controller.dart';

/// One point in the trend record.
///
/// Every field is nullable because a partial frame is normal: the vehicle may
/// report battery without distance, and a sparkline must show that as a gap
/// rather than inventing a value.
class TelemetrySample {
  const TelemetrySample({
    required this.at,
    this.batteryPercent,
    this.distanceCm,
    this.signalPercent,
    this.outputPercent,
  });

  final DateTime at;
  final double? batteryPercent;
  final double? distanceCm;

  /// Link quality, 0–100. Sourced from the phone's own RSSI so the series
  /// still moves when the firmware does not report `SIG`.
  final double? signalPercent;

  /// Magnitude of the commanded motor output, 0–100.
  final double? outputPercent;
}

/// Rolling trend record for the telemetry sparklines.
class TelemetryHistory {
  const TelemetryHistory({this.samples = const []});

  /// Oldest first.
  final List<TelemetrySample> samples;

  bool get isEmpty => samples.isEmpty;

  List<double?> get battery =>
      samples.map((s) => s.batteryPercent).toList(growable: false);

  List<double?> get distance =>
      samples.map((s) => s.distanceCm).toList(growable: false);

  List<double?> get signal =>
      samples.map((s) => s.signalPercent).toList(growable: false);

  List<double?> get output =>
      samples.map((s) => s.outputPercent).toList(growable: false);

  /// Change in battery across the record, negative while draining.
  ///
  /// Reads the first and last *reported* values, so a gap at either end does
  /// not silently turn a drain into "no change".
  double? get batteryDelta {
    final reported = samples
        .map((s) => s.batteryPercent)
        .whereType<double>()
        .toList(growable: false);
    if (reported.length < 2) return null;
    return reported.last - reported.first;
  }

  Duration? get span {
    if (samples.length < 2) return null;
    return samples.last.at.difference(samples.first.at);
  }
}

/// Records telemetry over time so the dashboard can show trends, not just
/// instantaneous values.
///
/// Sampling is decoupled from the telemetry stream on purpose. Frames arrive
/// at 5Hz, which would fill the window with 24 seconds of history and burn
/// rebuilds on data no sparkline can resolve; one sample per
/// [sampleInterval] gives a window measured in minutes at a fraction of the
/// cost.
class TelemetryHistoryController extends Notifier<TelemetryHistory> {
  /// Roughly ten minutes of record at the sample interval below.
  static const int maxSamples = 120;

  /// Published for the session-log exporter, which names the sampling rate in
  /// its header rather than guessing at it.
  static const Duration sampleInterval = Duration(seconds: 5);

  DateTime _lastSampleAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  TelemetryHistory build() {
    ref.listen(telemetryProvider, (previous, next) => _record(next));

    // A new link is a new run. Carrying the previous vehicle's battery curve
    // into this one would draw a cliff that never happened.
    ref.listen(connectionProvider, (previous, next) {
      final wasConnected = previous?.isConnected ?? false;
      if (wasConnected == next.isConnected) return;
      if (next.isConnected) clear();
    });

    return const TelemetryHistory();
  }

  void _record(Telemetry telemetry) {
    if (!telemetry.hasData) return;

    final now = DateTime.now();
    if (now.difference(_lastSampleAt) < sampleInterval) return;
    _lastSampleAt = now;

    final link = ref.read(connectionProvider);
    final output = telemetry.leftMotor == null && telemetry.rightMotor == null
        ? null
        : ((telemetry.leftMotor ?? 0).abs() +
                  (telemetry.rightMotor ?? 0).abs()) /
              2;

    final sample = TelemetrySample(
      at: now,
      batteryPercent: telemetry.batteryPercent?.toDouble(),
      distanceCm: telemetry.distanceCm?.toDouble(),
      signalPercent: _signalPercent(telemetry, link),
      outputPercent: output?.toDouble(),
    );

    final next = [...state.samples, sample];
    state = TelemetryHistory(
      samples: next.length <= maxSamples
          ? List.unmodifiable(next)
          : List.unmodifiable(next.sublist(next.length - maxSamples)),
    );
  }

  /// Prefers the vehicle's own `SIG` field, falling back to the phone's RSSI
  /// bucket. Firmware that never sends `SIG` still gets a signal trend.
  double? _signalPercent(Telemetry telemetry, LinkState link) {
    final reported = telemetry.signalPercent;
    if (reported != null) return reported.toDouble();
    if (!link.isConnected || link.rssi == null) return null;
    return link.signal.percent.toDouble();
  }

  void clear() {
    _lastSampleAt = DateTime.fromMillisecondsSinceEpoch(0);
    state = const TelemetryHistory();
  }
}

final telemetryHistoryProvider =
    NotifierProvider<TelemetryHistoryController, TelemetryHistory>(
      TelemetryHistoryController.new,
    );
