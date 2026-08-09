import 'dart:math' as math;

import '../../models/settings.dart';
import 'clamp.dart';

/// Signed left/right motor outputs, each -100…100.
class MotorOutput {
  const MotorOutput(this.left, this.right);

  static const MotorOutput stopped = MotorOutput(0, 0);

  final int left;
  final int right;

  bool get isStopped => left == 0 && right == 0;

  /// Magnitude of the larger side, for the speed readout.
  int get magnitude => math.max(left.abs(), right.abs());

  /// How far apart the two sides are — the turn component.
  int get differential => (left - right).abs();

  @override
  bool operator ==(Object other) =>
      other is MotorOutput && other.left == left && other.right == right;

  @override
  int get hashCode => Object.hash(left, right);

  @override
  String toString() => 'MotorOutput(L: $left, R: $right)';
}

/// Which way the vehicle is being commanded, for the direction indicator.
enum DriveDirection {
  idle('IDLE'),
  forward('FORWARD'),
  reverse('REVERSE'),
  left('LEFT'),
  right('RIGHT'),
  forwardLeft('FWD LEFT'),
  forwardRight('FWD RIGHT'),
  reverseLeft('REV LEFT'),
  reverseRight('REV RIGHT'),
  spinLeft('SPIN LEFT'),
  spinRight('SPIN RIGHT');

  const DriveDirection(this.label);

  final String label;
}

/// Converts joystick position into motor commands.
///
/// Pure functions, deliberately free of Flutter types: this is the part of the
/// drive path that most needs to be testable in isolation, and it must behave
/// identically whether it is driven by a widget or by a test.
abstract final class MotorMath {
  /// Maps a normalised stick position to motor outputs.
  ///
  /// [x] and [y] are -1…1, with +y forward and +x right. The pipeline is:
  /// dead zone → sensitivity curve → differential mix → speed ceiling →
  /// calibration → clamp.
  static MotorOutput fromJoystick({
    required double x,
    required double y,
    required AppSettings settings,
  }) {
    final shaped = _applyDeadZoneAndCurve(x: x, y: y, settings: settings);
    if (shaped == null) return MotorOutput.stopped;

    // Differential drive mix, as specified: L = Y + X, R = Y - X.
    final rawLeft = (shaped.y + shaped.x) * 100;
    final rawRight = (shaped.y - shaped.x) * 100;

    final ceiling = settings.maxSpeedPercent / 100;
    return applyCalibration(
      left: (clampDouble(rawLeft, -100, 100) * ceiling).round(),
      right: (clampDouble(rawRight, -100, 100) * ceiling).round(),
      settings: settings,
    );
  }

  /// Applies the dead zone and sensitivity curve.
  ///
  /// Returns `null` when the stick sits inside the dead zone, which the caller
  /// must treat as a full stop rather than as a very small movement.
  static ({double x, double y})? _applyDeadZoneAndCurve({
    required double x,
    required double y,
    required AppSettings settings,
  }) {
    final clampedX = clampUnit(x);
    final clampedY = clampUnit(y);

    final magnitude = math.sqrt(clampedX * clampedX + clampedY * clampedY);
    if (magnitude <= 0) return null;

    final deadZone = settings.deadZoneFraction;
    if (magnitude <= deadZone) return null;

    // Rescale so output starts at zero at the dead-zone edge instead of
    // jumping to a step change the moment the stick crosses it.
    final travel = deadZone >= 1
        ? 0.0
        : ((magnitude - deadZone) / (1 - deadZone)).clamp(0.0, 1.0);

    // Sensitivity bends the response curve. >1 is more aggressive off-centre,
    // <1 gives finer control near the middle.
    final curved = math
        .pow(travel, 1 / settings.joystickSensitivity)
        .toDouble();

    // Re-project onto the original direction at the shaped magnitude.
    final scale = curved / magnitude;
    return (
      x: clampDouble(clampedX * scale, -1, 1),
      y: clampDouble(clampedY * scale, -1, 1),
    );
  }

  /// Applies per-side trim and direction inversion, then clamps.
  ///
  /// Trim straightens a rover that pulls to one side; inversion corrects motors
  /// wired backwards, so it is applied last and never re-scaled afterwards.
  static MotorOutput applyCalibration({
    required int left,
    required int right,
    required AppSettings settings,
  }) {
    var trimmedLeft = left;
    var trimmedRight = right;

    // Trim scales magnitude without changing direction, so a trimmed motor
    // cannot be pushed into reverse by calibration alone.
    if (trimmedLeft != 0) {
      trimmedLeft = (trimmedLeft * (1 + settings.leftMotorTrim / 100)).round();
    }
    if (trimmedRight != 0) {
      trimmedRight = (trimmedRight * (1 + settings.rightMotorTrim / 100))
          .round();
    }

    if (settings.invertLeftMotor) trimmedLeft = -trimmedLeft;
    if (settings.invertRightMotor) trimmedRight = -trimmedRight;

    return MotorOutput(clampMotor(trimmedLeft), clampMotor(trimmedRight));
  }

  /// Classifies an output for the direction readout.
  static DriveDirection directionOf(MotorOutput output) {
    final left = output.left;
    final right = output.right;
    if (left == 0 && right == 0) return DriveDirection.idle;

    // Opposite signs mean the rover is pivoting on the spot.
    if (left > 0 && right < 0) return DriveDirection.spinRight;
    if (left < 0 && right > 0) return DriveDirection.spinLeft;

    final forward = left + right > 0;
    final difference = left - right;
    // Below this the sides are close enough to read as travelling straight.
    const straightThreshold = 8;

    if (difference.abs() <= straightThreshold) {
      return forward ? DriveDirection.forward : DriveDirection.reverse;
    }

    if (forward) {
      return difference > 0
          ? DriveDirection.forwardRight
          : DriveDirection.forwardLeft;
    }
    return difference > 0
        ? DriveDirection.reverseRight
        : DriveDirection.reverseLeft;
  }

  /// True when two outputs are close enough that resending would be wasted
  /// radio time. [epsilon] comes from `AppConfig.driveCommandEpsilon`.
  static bool isWithinEpsilon(MotorOutput a, MotorOutput b, int epsilon) {
    // A stop is never "close enough" to a non-stop: it must always be sent.
    if (a.isStopped != b.isStopped) return false;
    return (a.left - b.left).abs() <= epsilon &&
        (a.right - b.right).abs() <= epsilon;
  }

  /// Moves [current] toward [target] at the configured ramp rate.
  ///
  /// Smoothing lives on the phone so the firmware stays a dumb, predictable
  /// executor; deceleration is normally faster than acceleration so releasing
  /// the stick feels immediate.
  static double rampToward({
    required double current,
    required double target,
    required double elapsedSeconds,
    required AppSettings settings,
  }) {
    if (current == target) return target;

    final isSlowing = target.abs() < current.abs();
    final rate = isSlowing
        ? settings.decelerationRate
        : settings.accelerationRate;
    // rate is already in output-percent-per-second, the same units as current
    // and target, so the step is a direct product — no rescaling.
    final maxStep = rate * elapsedSeconds;

    final delta = target - current;
    if (delta.abs() <= maxStep) return target;
    return current + maxStep * delta.sign;
  }
}
