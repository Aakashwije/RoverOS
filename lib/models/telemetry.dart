import '../core/constants/app_config.dart';
import '../core/theme/app_colors.dart';
import 'commands.dart';

/// Battery health buckets. Always rendered with a label, never colour alone.
enum BatteryStatus {
  healthy('Battery Healthy', StatusLevel.good),
  low('Battery Low', StatusLevel.caution),
  critical('Critical Battery', StatusLevel.danger),
  unknown('Battery Unknown', StatusLevel.neutral);

  const BatteryStatus(this.label, this.level);

  final String label;
  final StatusLevel level;

  static BatteryStatus fromPercent(int? percent) {
    if (percent == null) return unknown;
    if (percent <= AppConfig.batteryCriticalPercent) return critical;
    if (percent <= AppConfig.batteryLowPercent) return low;
    return healthy;
  }
}

/// Proximity buckets for the front ultrasonic sensor.
enum DistanceStatus {
  safe('SAFE', 'Path clear', StatusLevel.good),
  caution('CAUTION', 'Obstacle ahead', StatusLevel.caution),
  danger('DANGER', 'Obstacle very close', StatusLevel.danger),
  unknown('NO READING', 'Sensor has not reported', StatusLevel.neutral);

  const DistanceStatus(this.label, this.description, this.level);

  final String label;
  final String description;
  final StatusLevel level;

  /// Thresholds come from user settings, so they are passed in rather than
  /// baked into the enum.
  static DistanceStatus fromDistance(
    int? cm, {
    required int cautionCm,
    required int dangerCm,
  }) {
    if (cm == null ||
        cm < AppConfig.sensorMinRangeCm ||
        cm > AppConfig.sensorMaxRangeCm) {
      return unknown;
    }
    if (cm < dangerCm) return danger;
    if (cm <= cautionCm) return caution;
    return safe;
  }
}

/// One servo position and the distance measured there.
class RadarSample {
  const RadarSample({
    required this.angle,
    required this.distanceCm,
    required this.takenAt,
  });

  final int angle;

  /// `null` when the sensor returned no echo at this angle.
  final int? distanceCm;

  final DateTime takenAt;

  bool get hasReading => distanceCm != null;

  RadarSample copyWith({int? distanceCm, DateTime? takenAt}) => RadarSample(
    angle: angle,
    distanceCm: distanceCm ?? this.distanceCm,
    takenAt: takenAt ?? this.takenAt,
  );

  @override
  String toString() => 'RadarSample($angle° → ${distanceCm ?? "—"}cm)';
}

/// A complete snapshot of vehicle state.
///
/// Immutable: telemetry frames produce a new snapshot via [merge] so a partial
/// frame (`DATA;BAT:82`) never wipes fields it did not mention.
class Telemetry {
  const Telemetry({
    this.batteryPercent,
    this.distanceCm,
    this.servoAngle,
    this.speedPercent,
    this.leftMotor,
    this.rightMotor,
    this.driveMode,
    this.lightMode,
    this.signalMode,
    this.brakeLightOn,
    this.vehicleState,
    this.signalPercent,
    this.radarSamples = const {},
    this.decision,
    this.updatedAt,
  });

  static const Telemetry empty = Telemetry();

  final int? batteryPercent;
  final int? distanceCm;
  final int? servoAngle;

  /// Commanded speed ceiling the vehicle is applying, 0–100.
  final int? speedPercent;

  /// Signed motor outputs, -100…100.
  final int? leftMotor;
  final int? rightMotor;

  final DriveMode? driveMode;
  final LightMode? lightMode;
  final SignalMode? signalMode;
  final bool? brakeLightOn;
  final VehicleState? vehicleState;

  /// Link quality as reported by the vehicle, 0–100. The phone's own RSSI is
  /// tracked separately in [LinkState].
  final int? signalPercent;

  /// Latest distance per servo angle, keyed by angle.
  final Map<int, RadarSample> radarSamples;

  /// Firmware's current autonomous decision, e.g. `PATH CLEAR`, `TURN LEFT`.
  final String? decision;

  final DateTime? updatedAt;

  bool get hasData => updatedAt != null;

  bool isStale({DateTime? now}) {
    if (updatedAt == null) return true;
    return (now ?? DateTime.now()).difference(updatedAt!) >
        AppConfig.telemetryStaleAfter;
  }

  BatteryStatus get batteryStatus => BatteryStatus.fromPercent(batteryPercent);

  DistanceStatus distanceStatus({
    required int cautionCm,
    required int dangerCm,
  }) => DistanceStatus.fromDistance(
    distanceCm,
    cautionCm: cautionCm,
    dangerCm: dangerCm,
  );

  /// Nearest sampled angle at or left of centre (0–89°).
  int? get leftDistanceCm => _nearestSampleIn(0, 89)?.distanceCm;

  int? get centerDistanceCm => radarSamples[90]?.distanceCm ?? distanceCm;

  int? get rightDistanceCm => _nearestSampleIn(91, 180)?.distanceCm;

  RadarSample? _nearestSampleIn(int minAngle, int maxAngle) {
    RadarSample? best;
    for (final sample in radarSamples.values) {
      if (sample.angle < minAngle || sample.angle > maxAngle) continue;
      if (!sample.hasReading) continue;
      if (best == null || sample.takenAt.isAfter(best.takenAt)) best = sample;
    }
    return best;
  }

  /// Overlays non-null fields of [update] onto this snapshot.
  Telemetry merge(Telemetry update) {
    return Telemetry(
      batteryPercent: update.batteryPercent ?? batteryPercent,
      distanceCm: update.distanceCm ?? distanceCm,
      servoAngle: update.servoAngle ?? servoAngle,
      speedPercent: update.speedPercent ?? speedPercent,
      leftMotor: update.leftMotor ?? leftMotor,
      rightMotor: update.rightMotor ?? rightMotor,
      driveMode: update.driveMode ?? driveMode,
      lightMode: update.lightMode ?? lightMode,
      signalMode: update.signalMode ?? signalMode,
      brakeLightOn: update.brakeLightOn ?? brakeLightOn,
      vehicleState: update.vehicleState ?? vehicleState,
      signalPercent: update.signalPercent ?? signalPercent,
      radarSamples: update.radarSamples.isEmpty
          ? radarSamples
          : {...radarSamples, ...update.radarSamples},
      decision: update.decision ?? decision,
      updatedAt: update.updatedAt ?? updatedAt,
    );
  }

  Telemetry copyWith({
    int? batteryPercent,
    int? distanceCm,
    int? servoAngle,
    int? speedPercent,
    int? leftMotor,
    int? rightMotor,
    DriveMode? driveMode,
    LightMode? lightMode,
    SignalMode? signalMode,
    bool? brakeLightOn,
    VehicleState? vehicleState,
    int? signalPercent,
    Map<int, RadarSample>? radarSamples,
    String? decision,
    DateTime? updatedAt,
  }) {
    return Telemetry(
      batteryPercent: batteryPercent ?? this.batteryPercent,
      distanceCm: distanceCm ?? this.distanceCm,
      servoAngle: servoAngle ?? this.servoAngle,
      speedPercent: speedPercent ?? this.speedPercent,
      leftMotor: leftMotor ?? this.leftMotor,
      rightMotor: rightMotor ?? this.rightMotor,
      driveMode: driveMode ?? this.driveMode,
      lightMode: lightMode ?? this.lightMode,
      signalMode: signalMode ?? this.signalMode,
      brakeLightOn: brakeLightOn ?? this.brakeLightOn,
      vehicleState: vehicleState ?? this.vehicleState,
      signalPercent: signalPercent ?? this.signalPercent,
      radarSamples: radarSamples ?? this.radarSamples,
      decision: decision ?? this.decision,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'Telemetry(bat: $batteryPercent, dist: $distanceCm, servo: $servoAngle, '
      'spd: $speedPercent, mode: ${driveMode?.name})';
}
