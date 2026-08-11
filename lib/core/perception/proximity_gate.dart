import '../../models/telemetry.dart';
import '../constants/app_config.dart';
import '../theme/app_colors.dart';
import '../utils/clamp.dart';
import 'distance_filter.dart';

/// Why a proximity call landed where it did.
///
/// The reason is displayed alongside the level because "CAUTION" for a reading
/// 55cm away and "CAUTION" for a reading 90cm away that is closing at 40cm/s
/// call for different responses from the driver.
enum ProximityCause {
  clear('Path clear'),
  distance('Obstacle inside the configured threshold'),
  closingRate('Closing fast enough to matter at this range'),
  lowConfidence('Sensor readings are not trustworthy enough to call'),
  noReading('No usable reading at this bearing');

  const ProximityCause(this.description);

  final String description;
}

/// The app's call on how close the vehicle is to trouble.
///
/// Advisory in every sense: the ESP32 makes the stop decision from its own
/// readings, on its own schedule. This exists so the *driver* sees the
/// situation coming, and so the drive HUD stops flickering between levels on a
/// sensor that never sits still.
class ProximityAssessment {
  const ProximityAssessment({
    required this.status,
    required this.cause,
    required this.distanceCm,
    required this.rawCm,
    required this.timeToContact,
    required this.closingSpeedCmPerSecond,
    required this.confidence,
  });

  static const ProximityAssessment unknown = ProximityAssessment(
    status: DistanceStatus.unknown,
    cause: ProximityCause.noReading,
    distanceCm: null,
    rawCm: null,
    timeToContact: null,
    closingSpeedCmPerSecond: 0,
    confidence: SensorConfidence.none,
  );

  final DistanceStatus status;
  final ProximityCause cause;

  /// Filtered distance. `null` when there is nothing to report.
  final double? distanceCm;

  /// The unfiltered reading behind it, for a UI that wants to show both.
  final int? rawCm;

  final Duration? timeToContact;
  final double closingSpeedCmPerSecond;
  final SensorConfidence confidence;

  StatusLevel get level => status.level;

  bool get isClosing => closingSpeedCmPerSecond > 0;

  bool get escalatedByClosingRate => cause == ProximityCause.closingRate;

  /// Seconds to contact as a single decimal, or `null`.
  String? get contactSeconds {
    final ttc = timeToContact;
    if (ttc == null) return null;
    return (ttc.inMilliseconds / 1000).toStringAsFixed(1);
  }

  /// The headline the driver reads. Time-to-contact wins when it exists: it is
  /// the only phrasing that carries both the distance and the speed.
  String get headline {
    final seconds = contactSeconds;
    if (seconds != null) return 'CONTACT IN ${seconds}S';
    return status.label;
  }

  String get detail {
    if (status == DistanceStatus.unknown) return cause.description;
    if (escalatedByClosingRate) {
      return 'Closing at ${closingSpeedCmPerSecond.round()}cm/s · '
          '${cause.description}';
    }
    if (isClosing) {
      return 'Closing at ${closingSpeedCmPerSecond.round()}cm/s';
    }
    return status.description;
  }

  @override
  String toString() =>
      'ProximityAssessment(${status.label}, ${cause.name}, '
      '${distanceCm?.toStringAsFixed(1) ?? "—"}cm)';
}

/// Turns a filtered estimate into a proximity call, with memory.
///
/// The memory is the point. A bare threshold test on a live ultrasonic feed
/// produces a badge that strobes between CAUTION and SAFE whenever a reading
/// sits on the boundary, which is exactly when the driver most needs to be able
/// to read it. Escalation is instant; only *recovery* has to earn its way past
/// [AppConfig.perceptionHysteresisCm] of extra clearance.
class ProximityGate {
  DistanceStatus _previous = DistanceStatus.unknown;

  DistanceStatus get current => _previous;

  void reset() => _previous = DistanceStatus.unknown;

  ProximityAssessment assess({
    required DistanceEstimate? estimate,
    required int cautionCm,
    required int dangerCm,
    required DateTime now,
  }) {
    if (estimate == null || estimate.isStaleAt(now)) {
      _previous = DistanceStatus.unknown;
      return ProximityAssessment.unknown;
    }

    final score = estimate.confidenceAt(now);
    final confidence = SensorConfidence.fromScore(score);

    if (score < AppConfig.perceptionMinConfidence) {
      // Refusing to call it is a result, not a failure. A confident-looking
      // SAFE built on readings that disagree with each other is worse than an
      // honest "no reading".
      _previous = DistanceStatus.unknown;
      return ProximityAssessment(
        status: DistanceStatus.unknown,
        cause: ProximityCause.lowConfidence,
        distanceCm: estimate.distanceCm,
        rawCm: estimate.rawCm,
        timeToContact: null,
        closingSpeedCmPerSecond: estimate.closingSpeedCmPerSecond,
        confidence: confidence,
      );
    }

    var status = _damped(estimate.distanceCm, cautionCm, dangerCm);
    var cause = status == DistanceStatus.safe
        ? ProximityCause.clear
        : ProximityCause.distance;

    final ttc = estimate.timeToContact;
    if (ttc != null) {
      if (ttc <= AppConfig.perceptionContactCritical &&
          _severity(status) < _severity(DistanceStatus.danger)) {
        status = DistanceStatus.danger;
        cause = ProximityCause.closingRate;
      } else if (ttc <= AppConfig.perceptionContactWarning &&
          _severity(status) < _severity(DistanceStatus.caution)) {
        status = DistanceStatus.caution;
        cause = ProximityCause.closingRate;
      }
    }

    _previous = status;

    return ProximityAssessment(
      status: status,
      cause: cause,
      distanceCm: estimate.distanceCm,
      rawCm: estimate.rawCm,
      timeToContact: ttc,
      closingSpeedCmPerSecond: estimate.closingSpeedCmPerSecond,
      confidence: confidence,
    );
  }

  /// Raw bucketing, then a one-way brake on improvement.
  DistanceStatus _damped(double distanceCm, int cautionCm, int dangerCm) {
    final raw = _bucket(distanceCm, cautionCm, dangerCm);
    if (raw == _previous) return raw;

    // Getting worse is always reported immediately. Only the way back out is
    // damped — a driver can act on a warning that arrives early and cannot act
    // on one that arrives late.
    if (_severity(raw) > _severity(_previous)) return raw;

    final relaxed = _bucket(
      distanceCm - AppConfig.perceptionHysteresisCm,
      cautionCm,
      dangerCm,
    );
    return _severity(relaxed) < _severity(_previous) ? relaxed : _previous;
  }

  DistanceStatus _bucket(double distanceCm, int cautionCm, int dangerCm) {
    // Clamped into sensor range so subtracting the hysteresis margin near the
    // bottom of the scale cannot fall out of range and read as "no reading",
    // which would look like an improvement rather than the danger it is.
    final clamped = clampInt(
      distanceCm.round(),
      AppConfig.sensorMinRangeCm,
      AppConfig.sensorMaxRangeCm,
    );
    return DistanceStatus.fromDistance(
      clamped,
      cautionCm: cautionCm,
      dangerCm: dangerCm,
    );
  }

  int _severity(DistanceStatus status) => switch (status) {
    DistanceStatus.unknown => 0,
    DistanceStatus.safe => 1,
    DistanceStatus.caution => 2,
    DistanceStatus.danger => 3,
  };
}
