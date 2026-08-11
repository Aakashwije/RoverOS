import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/perception/perception_engine.dart';
import '../../models/telemetry.dart';
import '../connection/connection_controller.dart';
import '../settings/settings_controller.dart';
import '../telemetry/telemetry_controller.dart';

/// Runs the perception pipeline over the live telemetry stream.
///
/// Fed from [telemetryProvider] directly rather than from the trend record in
/// `telemetry_history.dart`, which samples once every five seconds — right for
/// a sparkline, useless for a filter that needs every frame to separate a
/// moving obstacle from a noisy one.
class PerceptionController extends Notifier<PerceptionSnapshot> {
  final PerceptionEngine _engine = PerceptionEngine();

  @override
  PerceptionSnapshot build() {
    ref.listen(telemetryProvider, (previous, next) => _ingest(next));

    // A dropped link ends the run. Estimates built from the last vehicle's
    // sensors say nothing about the next one, and a stale filtered distance is
    // more dangerous than none: it looks exactly like a live one.
    ref.listen(connectionProvider, (previous, next) {
      if (previous?.isConnected == next.isConnected) return;
      if (!next.isConnected) clear();
    });

    return PerceptionSnapshot.empty;
  }

  void _ingest(Telemetry telemetry) {
    state = _engine.ingest(
      telemetry: telemetry,
      settings: ref.read(settingsProvider),
    );
  }

  void clear() {
    _engine.reset();
    state = PerceptionSnapshot.empty;
  }
}

final perceptionProvider =
    NotifierProvider<PerceptionController, PerceptionSnapshot>(
      PerceptionController.new,
    );
