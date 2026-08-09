import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/telemetry.dart';

/// Holds the latest vehicle snapshot.
///
/// Phase 1 scope: an empty snapshot plus [apply]/[reset]. The telemetry parser
/// feeds this controller once the transport exists, so every screen can already
/// be written against the real shape of the data.
class TelemetryController extends Notifier<Telemetry> {
  @override
  Telemetry build() => Telemetry.empty;

  /// Overlays a parsed frame onto the current snapshot. Partial frames leave
  /// unmentioned fields untouched.
  void apply(Telemetry update) {
    state = state.merge(update);
  }

  /// Clears everything on disconnect — stale readings must never be presented
  /// as the vehicle's current state.
  void reset() {
    state = Telemetry.empty;
  }
}

final telemetryProvider = NotifierProvider<TelemetryController, Telemetry>(
  TelemetryController.new,
);
