import 'dart:math' as math;

import '../constants/app_config.dart';
import '../utils/clamp.dart';

/// How much the app trusts a filtered reading.
///
/// Rendered as a word, never as a bar alone: "34cm" and "34cm, probably" are
/// different claims and the driver has to be able to tell them apart.
enum SensorConfidence {
  high('HIGH', 'Readings agree with each other'),
  fair('FAIR', 'Some scatter between readings'),
  low('LOW', 'Readings disagree — treat with suspicion'),
  none('NO DATA', 'Nothing measured yet');

  const SensorConfidence(this.label, this.description);

  final String label;
  final String description;

  bool get isTrustworthy => this == high || this == fair;

  static SensorConfidence fromScore(double score) {
    if (score >= 0.7) return high;
    if (score >= 0.45) return fair;
    if (score > 0) return low;
    return none;
  }
}

/// A filtered distance at one bearing, with the derivative that comes free
/// with it.
///
/// [distanceCm] is the estimate, not a measurement: it is what the filter
/// believes after weighing this frame against everything before it. The raw
/// frame is kept in [rawCm] so the UI can show both and never imply the
/// vehicle reported a number it did not.
class DistanceEstimate {
  const DistanceEstimate({
    required this.bearingDegrees,
    required this.distanceCm,
    required this.velocityCmPerSecond,
    required this.standardDeviationCm,
    required this.confidenceScore,
    required this.sampleCount,
    required this.rawCm,
    required this.wasRejected,
    required this.echoRate,
    required this.updatedAt,
  });

  /// Servo angle this estimate describes, 0 (left) to 180 (right).
  final int bearingDegrees;

  final double distanceCm;

  /// Negative while closing on whatever is out there.
  final double velocityCmPerSecond;

  /// One sigma on [distanceCm], from the filter's own covariance.
  final double standardDeviationCm;

  /// 0–1. Combines maturity, agreement between readings, and echo rate.
  /// Freshness is deliberately *not* baked in — see [confidenceAt].
  final double confidenceScore;

  final int sampleCount;

  /// The unfiltered reading behind this estimate. `null` on a no-echo frame,
  /// where the estimate is a prediction with nothing corroborating it.
  final int? rawCm;

  /// True when the raw reading was withheld as an outlier.
  final bool wasRejected;

  /// Fraction of recent frames that came back with an echo at all.
  final double echoRate;

  final DateTime updatedAt;

  SensorConfidence get confidence =>
      SensorConfidence.fromScore(confidenceScore);

  bool get isClosing =>
      velocityCmPerSecond <= -AppConfig.perceptionMinClosingCmPerSecond;

  double get closingSpeedCmPerSecond =>
      isClosing ? -velocityCmPerSecond : 0;

  /// Time until this bearing's obstacle is reached at the current closing
  /// speed, or `null` when nothing is closing fast enough to matter.
  ///
  /// This is time to *contact*, not time to the danger threshold — the number
  /// the driver actually wants when deciding whether to let go of the stick.
  Duration? get timeToContact {
    if (!isClosing) return null;
    final seconds = distanceCm / closingSpeedCmPerSecond;
    if (!seconds.isFinite || seconds < 0) return null;
    if (seconds * 1000 > AppConfig.perceptionMaxTimeToContact.inMilliseconds) {
      return null;
    }
    return Duration(microseconds: (seconds * 1000000).round());
  }

  Duration ageAt(DateTime now) => now.difference(updatedAt);

  bool isStaleAt(DateTime now) =>
      ageAt(now) >= AppConfig.perceptionBearingStaleAfter;

  /// [confidenceScore] with age folded in.
  ///
  /// Freshness is applied here rather than at construction because the same
  /// estimate is worth less the longer it sits on screen, and the object
  /// cannot know how long that will be.
  double confidenceAt(DateTime now) {
    final age = ageAt(now).inMilliseconds;
    if (age <= 0) return confidenceScore;
    final window = AppConfig.perceptionBearingStaleAfter.inMilliseconds;
    if (age >= window) return 0;
    return confidenceScore * (1 - age / window);
  }

  @override
  String toString() =>
      'DistanceEstimate($bearingDegrees° → ${distanceCm.toStringAsFixed(1)}cm '
      '± ${standardDeviationCm.toStringAsFixed(1)}, '
      'v ${velocityCmPerSecond.toStringAsFixed(1)}cm/s, '
      '${confidence.label})';
}

/// A one-dimensional constant-velocity Kalman filter over a single bearing.
///
/// The HC-SR04 is a noisy sensor with two distinct failure modes, and they
/// need different treatment:
///
/// * **Echo artefacts** — a single wildly wrong reading from a reflection off
///   the floor or a nearby surface. Gated out by [AppConfig.perceptionOutlierSigma]
///   so one bad frame cannot flip the status badge.
/// * **No echo at all** — an angled or soft surface returning nothing. The
///   filter coasts on its prediction and drops its confidence rather than
///   inventing a reading.
///
/// One filter per bearing. Filtering across a moving servo would average
/// together distances to entirely different objects, which is worse than not
/// filtering at all — the engine keeps a filter per angle bucket and this
/// class never sees more than one of them.
class DistanceFilter {
  DistanceFilter({
    required this.bearingDegrees,
    double? measurementNoiseCm,
    double? measurementNoiseFraction,
    double? manoeuvreNoiseCmPerSecondSquared,
  }) : _noiseCm = measurementNoiseCm ?? AppConfig.sensorNoiseCm,
       _noiseFraction = measurementNoiseFraction ?? AppConfig.sensorNoiseFraction,
       _manoeuvreNoise =
           manoeuvreNoiseCmPerSecondSquared ??
           AppConfig.perceptionManoeuvreNoiseCmPerSecondSquared;

  final int bearingDegrees;

  final double _noiseCm;
  final double _noiseFraction;
  final double _manoeuvreNoise;

  // State: [distance, velocity].
  double _distance = 0;
  double _velocity = 0;

  // Covariance, row-major. Small enough that naming the cells beats a matrix
  // library and a dependency.
  double _p00 = 0;
  double _p01 = 0;
  double _p10 = 0;
  double _p11 = 0;

  bool _seeded = false;
  int _sampleCount = 0;
  int _consecutiveRejects = 0;
  DateTime? _lastUpdateAt;

  /// Normalised residuals, for the agreement term of the confidence score.
  final List<double> _residuals = <double>[];

  /// Whether recent frames carried an echo, for the echo-rate term.
  final List<bool> _echoes = <bool>[];

  DistanceEstimate? _latest;

  /// The most recent estimate, or `null` before the first usable reading.
  DistanceEstimate? get latest => _latest;

  bool get isSeeded => _seeded;

  /// Folds one telemetry frame in. [measurementCm] is `null` on a no-echo
  /// frame; out-of-range values are treated the same way.
  DistanceEstimate? update({int? measurementCm, required DateTime at}) {
    final reading = _usable(measurementCm);
    _remember(_echoes, reading != null);

    final last = _lastUpdateAt;
    final elapsed = last == null
        ? 0.0
        : at.difference(last).inMicroseconds / 1000000;
    _lastUpdateAt = at;

    // A long silence at this bearing means the servo was pointed elsewhere and
    // has come back. Coasting a two-second-old velocity across that gap would
    // put the estimate somewhere the rover never was.
    if (_seeded &&
        elapsed * 1000 >= AppConfig.perceptionBearingStaleAfter.inMilliseconds) {
      reset(keepEchoRecord: true);
    }

    if (!_seeded) {
      if (reading == null) return _latest;
      _seed(reading.toDouble());
      return _latest = _snapshot(at: at, rawCm: reading, wasRejected: false);
    }

    _predict(elapsed);

    if (reading == null) {
      // Nothing corroborates the prediction. It still stands — an obstacle
      // does not stop existing because one ping missed it — but the echo rate
      // is already dragging confidence down.
      return _latest = _snapshot(at: at, rawCm: null, wasRejected: false);
    }

    final z = reading.toDouble();
    final variance = _measurementVariance(z);
    final innovation = z - _distance;
    final innovationVariance = _p00 + variance;
    final normalised = innovationVariance <= 0
        ? 0.0
        : (innovation * innovation) / innovationVariance;

    _remember(_residuals, innovation.abs() / math.sqrt(variance));

    const gate =
        AppConfig.perceptionOutlierSigma * AppConfig.perceptionOutlierSigma;
    if (normalised > gate) {
      _consecutiveRejects++;
      if (_consecutiveRejects >= AppConfig.perceptionMaxConsecutiveRejects) {
        // Three disagreements in a row is not a run of bad luck. The world
        // changed — re-seed on what the sensor is actually saying.
        _seed(z);
        return _latest = _snapshot(at: at, rawCm: reading, wasRejected: false);
      }
      return _latest = _snapshot(at: at, rawCm: reading, wasRejected: true);
    }

    _consecutiveRejects = 0;

    // Gain, then the standard covariance update for H = [1 0].
    final k0 = _p00 / innovationVariance;
    final k1 = _p10 / innovationVariance;

    _distance += k0 * innovation;
    _velocity += k1 * innovation;
    _velocity = clampDouble(
      _velocity,
      -AppConfig.perceptionMaxSpeedCmPerSecond,
      AppConfig.perceptionMaxSpeedCmPerSecond,
    );

    final p00 = _p00 - k0 * _p00;
    final p01 = _p01 - k0 * _p01;
    final p10 = _p10 - k1 * _p00;
    final p11 = _p11 - k1 * _p01;
    _p00 = p00;
    _p01 = p01;
    _p10 = p10;
    _p11 = p11;

    _sampleCount++;
    return _latest = _snapshot(at: at, rawCm: reading, wasRejected: false);
  }

  /// Drops all state. [keepEchoRecord] preserves the dropout history, which
  /// describes the *sensor* rather than the estimate and stays true across a
  /// re-seed.
  void reset({bool keepEchoRecord = false}) {
    _seeded = false;
    _distance = 0;
    _velocity = 0;
    _p00 = _p01 = _p10 = _p11 = 0;
    _sampleCount = 0;
    _consecutiveRejects = 0;
    _residuals.clear();
    if (!keepEchoRecord) _echoes.clear();
    _latest = null;
  }

  void _seed(double distanceCm) {
    _distance = distanceCm;
    _velocity = 0;
    _p00 = _measurementVariance(distanceCm);
    _p01 = 0;
    _p10 = 0;
    _p11 =
        AppConfig.perceptionInitialVelocitySigma *
        AppConfig.perceptionInitialVelocitySigma;
    _seeded = true;
    _sampleCount = 1;
    _consecutiveRejects = 0;
    _residuals.clear();
  }

  /// Advances the state and inflates the covariance by the manoeuvre noise a
  /// rover can produce in [dt] seconds.
  void _predict(double dt) {
    if (dt <= 0) return;

    _distance += _velocity * dt;

    final p00 = _p00 + dt * (_p01 + _p10) + dt * dt * _p11;
    final p01 = _p01 + dt * _p11;
    final p10 = _p10 + dt * _p11;
    final p11 = _p11;

    final q = _manoeuvreNoise * _manoeuvreNoise;
    final dt2 = dt * dt;
    final dt3 = dt2 * dt;
    final dt4 = dt2 * dt2;

    _p00 = p00 + q * dt4 / 4;
    _p01 = p01 + q * dt3 / 2;
    _p10 = p10 + q * dt3 / 2;
    _p11 = p11 + q * dt2;
  }

  /// Sensor error grows with range, so the filter's trust in a reading has to
  /// shrink with it — otherwise a 300cm reading is weighted as heavily as a
  /// 10cm one, which it has no right to be.
  double _measurementVariance(double distanceCm) {
    final sigma = _noiseCm + _noiseFraction * distanceCm.abs();
    return sigma * sigma;
  }

  int? _usable(int? cm) {
    if (cm == null) return null;
    if (cm < AppConfig.sensorMinRangeCm) return null;
    if (cm > AppConfig.sensorMaxRangeCm) return null;
    return cm;
  }

  void _remember<T>(List<T> record, T value) {
    record.add(value);
    if (record.length > AppConfig.perceptionWindowSamples) record.removeAt(0);
  }

  double _echoRate() {
    if (_echoes.isEmpty) return 0;
    var seen = 0;
    for (final echo in _echoes) {
      if (echo) seen++;
    }
    return seen / _echoes.length;
  }

  /// Three independent reasons to doubt an estimate, multiplied so any one of
  /// them alone is enough to sink it.
  double _confidenceScore() {
    if (!_seeded) return 0;

    final maturity = clampDouble(
      _sampleCount / AppConfig.perceptionMaturitySamples,
      0,
      1,
    );

    // Residuals are already in units of sigma, so an RMS of 1 means the sensor
    // is behaving exactly as modelled and anything above that is scatter the
    // noise model did not account for.
    var agreement = 1.0;
    if (_residuals.isNotEmpty) {
      var sum = 0.0;
      for (final residual in _residuals) {
        sum += residual * residual;
      }
      final rms = math.sqrt(sum / _residuals.length);
      agreement = 1 / (1 + math.max(0.0, rms - 1));
    }

    return clampDouble(maturity * agreement * _echoRate(), 0, 1);
  }

  DistanceEstimate _snapshot({
    required DateTime at,
    required int? rawCm,
    required bool wasRejected,
  }) {
    return DistanceEstimate(
      bearingDegrees: bearingDegrees,
      distanceCm: _distance,
      velocityCmPerSecond: _velocity,
      standardDeviationCm: math.sqrt(math.max(_p00, 0)),
      confidenceScore: _confidenceScore(),
      sampleCount: _sampleCount,
      rawCm: rawCm,
      wasRejected: wasRejected,
      echoRate: _echoRate(),
      updatedAt: at,
    );
  }
}
