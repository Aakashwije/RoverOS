import '../../models/settings.dart';
import '../../models/telemetry.dart';
import '../utils/clamp.dart';
import 'distance_filter.dart';
import 'proximity_gate.dart';
import 'radar_field.dart';

/// Everything the app has inferred from the vehicle's sensors.
///
/// Held strictly apart from [Telemetry], which is what the vehicle *reported*.
/// The same separation the app already draws between commanded and reported
/// state applies here: a filtered distance is the phone's opinion, and the UI
/// has to be able to label it as one.
class PerceptionSnapshot {
  const PerceptionSnapshot({
    required this.current,
    required this.forward,
    required this.proximity,
    required this.field,
    required this.bearings,
    required this.updatedAt,
  });

  static const PerceptionSnapshot empty = PerceptionSnapshot(
    current: null,
    forward: null,
    proximity: ProximityAssessment.unknown,
    field: FieldAnalysis.empty,
    bearings: <int, DistanceEstimate>{},
    updatedAt: null,
  );

  /// Estimate at the bearing the servo is pointed at right now.
  final DistanceEstimate? current;

  /// Estimate dead ahead — the direction that can actually be collided with.
  /// `null` once it goes stale, which it does while the servo sweeps away.
  final DistanceEstimate? forward;

  final ProximityAssessment proximity;
  final FieldAnalysis field;

  /// Latest estimate per bearing bucket.
  final Map<int, DistanceEstimate> bearings;

  final DateTime? updatedAt;

  bool get hasData => updatedAt != null;

  /// True when the app is holding an opinion it does not trust enough to act
  /// on. Worth surfacing: it means the sensor is being defeated by the
  /// surface, not that the path is clear.
  bool get isUncertain =>
      hasData && proximity.cause == ProximityCause.lowConfidence;
}

/// Assembles the perception pipeline from one telemetry stream.
///
/// Ordinary object, no Flutter and no Riverpod, so the whole chain — filter,
/// hysteresis, gap finding, segmentation — can be driven frame by frame in a
/// test with a controlled clock.
///
/// The pipeline is advisory end to end. It never builds a command, never
/// touches the transport, and nothing downstream of it may: the ESP32 owns
/// every stop and every autonomous decision, exactly as before.
class PerceptionEngine {
  PerceptionEngine({int? bearingBucketDegrees})
    : _bucketDegrees = bearingBucketDegrees ?? _defaultBucketDegrees;

  /// Bearings are bucketed because the servo reports a continuous angle and a
  /// filter per raw degree would never accumulate enough samples to converge.
  static const int _defaultBucketDegrees = 15;

  final int _bucketDegrees;

  final Map<int, DistanceFilter> _filters = <int, DistanceFilter>{};
  final ProximityGate _gate = ProximityGate();

  PerceptionSnapshot _snapshot = PerceptionSnapshot.empty;

  PerceptionSnapshot get snapshot => _snapshot;

  /// Folds one telemetry frame in and returns the updated snapshot.
  PerceptionSnapshot ingest({
    required Telemetry telemetry,
    required AppSettings settings,
    DateTime? at,
  }) {
    if (!telemetry.hasData) return _snapshot;
    final now = at ?? DateTime.now();

    final servoAngle = telemetry.servoAngle ?? settings.servoCenter;
    final bearing = _bucket(servoAngle);
    final filter = _filters.putIfAbsent(
      bearing,
      () => DistanceFilter(bearingDegrees: bearing),
    );
    filter.update(measurementCm: telemetry.distanceCm, at: now);

    final forwardBearing = _bucket(settings.servoCenter);
    final forwardCandidate = _filters[forwardBearing]?.latest;
    final forward =
        forwardCandidate != null && !forwardCandidate.isStaleAt(now)
        ? forwardCandidate
        : null;

    final proximity = _gate.assess(
      estimate: forward,
      cautionCm: settings.cautionDistanceCm,
      dangerCm: settings.dangerDistanceCm,
      now: now,
    );

    final field = RadarField.analyse(
      samples: _sweep(telemetry, servoAngle, now),
      clearanceCm: settings.cautionDistanceCm,
      referenceBearing: clampInt(settings.servoCenter, 0, 180),
      now: now,
    );

    return _snapshot = PerceptionSnapshot(
      current: filter.latest,
      forward: forward,
      proximity: proximity,
      field: field,
      bearings: Map.unmodifiable(<int, DistanceEstimate>{
        for (final entry in _filters.entries)
          if (entry.value.latest != null) entry.key: entry.value.latest!,
      }),
      updatedAt: now,
    );
  }

  /// Drops everything. Called on disconnect: a filtered estimate from the last
  /// vehicle is not a weaker claim about this one, it is a false one.
  void reset() {
    _filters.clear();
    _gate.reset();
    _snapshot = PerceptionSnapshot.empty;
  }

  /// The radar map, with the live reading laid over it.
  ///
  /// `radarSamples` accumulates across frames, so the entry for the bearing the
  /// servo is pointed at now can be a sweep or two old. The live pair is the
  /// freshest thing available at that bearing and takes precedence.
  Map<int, RadarSample> _sweep(
    Telemetry telemetry,
    int servoAngle,
    DateTime now,
  ) {
    final angle = clampInt(servoAngle, 0, 180);
    return <int, RadarSample>{
      ...telemetry.radarSamples,
      angle: RadarSample(
        angle: angle,
        distanceCm: telemetry.distanceCm,
        takenAt: telemetry.updatedAt ?? now,
      ),
    };
  }

  int _bucket(int angleDegrees) {
    final snapped = (angleDegrees / _bucketDegrees).round() * _bucketDegrees;
    return clampInt(snapped, 0, 180);
  }
}
