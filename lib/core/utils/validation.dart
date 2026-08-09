import '../constants/app_config.dart';
import 'clamp.dart';

/// Legal bounds for every user-adjustable setting.
///
/// Settings arrive from persisted JSON that an older build (or a hand-edited
/// preferences file) may have written, so every value is re-validated on load
/// rather than trusted.
abstract final class SettingsRange {
  static const int minSpeedPercent = 10;
  static const int maxSpeedPercent = 100;

  static const double minSensitivity = 0.5;
  static const double maxSensitivity = 2.0;

  static const int minDeadZonePercent = 0;
  static const int maxDeadZonePercent = 40;

  /// Ramp rates in percent-per-second. Higher is snappier.
  static const double minRamp = 50;
  static const double maxRamp = 1000;

  static const int minMotorTrim = -25;
  static const int maxMotorTrim = 25;

  static const int minServoAngle = 0;
  static const int maxServoAngle = 180;

  static const int minDistanceCm = 5;
  static const int maxDistanceCm = 200;

  static const int minBrightness = 10;
  static const int maxBrightness = 100;

  static const int maxVehicleNameLength = 24;
}

/// Result of validating a single field, for inline form feedback.
class ValidationResult {
  const ValidationResult.valid() : error = null;
  const ValidationResult.invalid(this.error);

  final String? error;

  bool get isValid => error == null;
}

abstract final class Validators {
  /// Vehicle names are display-only, but an empty or oversized one breaks the
  /// dashboard layout, so it is rejected at the input.
  static ValidationResult vehicleName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return const ValidationResult.invalid('Vehicle name cannot be empty');
    }
    if (trimmed.length > SettingsRange.maxVehicleNameLength) {
      return ValidationResult.invalid(
        'Use ${SettingsRange.maxVehicleNameLength} characters or fewer',
      );
    }
    return const ValidationResult.valid();
  }

  static String sanitizeVehicleName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'ESP32-CAR';
    return trimmed.length > SettingsRange.maxVehicleNameLength
        ? trimmed.substring(0, SettingsRange.maxVehicleNameLength)
        : trimmed;
  }

  /// Danger must sit strictly below caution, otherwise the three proximity
  /// states collapse and the driver loses the early warning band.
  static ValidationResult distanceThresholds({
    required int cautionCm,
    required int dangerCm,
  }) {
    if (dangerCm >= cautionCm) {
      return const ValidationResult.invalid(
        'Danger distance must be less than caution distance',
      );
    }
    return const ValidationResult.valid();
  }

  /// Servo travel must be a non-empty range containing its own centre point.
  static ValidationResult servoRange({
    required int minAngle,
    required int maxAngle,
    required int center,
  }) {
    if (minAngle >= maxAngle) {
      return const ValidationResult.invalid(
        'Minimum servo angle must be less than maximum',
      );
    }
    if (center < minAngle || center > maxAngle) {
      return const ValidationResult.invalid(
        'Servo centre must sit between the minimum and maximum angle',
      );
    }
    return const ValidationResult.valid();
  }

  static int commandTimeoutMs(int value) => clampInt(
    value,
    AppConfig.minCommandTimeoutMs,
    AppConfig.maxCommandTimeoutMs,
  );

  static int speedPercent(int value) => clampInt(
    value,
    SettingsRange.minSpeedPercent,
    SettingsRange.maxSpeedPercent,
  );

  static double sensitivity(double value) => clampDouble(
    value,
    SettingsRange.minSensitivity,
    SettingsRange.maxSensitivity,
  );

  static int deadZonePercent(int value) => clampInt(
    value,
    SettingsRange.minDeadZonePercent,
    SettingsRange.maxDeadZonePercent,
  );

  static double rampRate(double value) =>
      clampDouble(value, SettingsRange.minRamp, SettingsRange.maxRamp);

  static int motorTrim(int value) =>
      clampInt(value, SettingsRange.minMotorTrim, SettingsRange.maxMotorTrim);

  static int servoAngle(int value) =>
      clampInt(value, SettingsRange.minServoAngle, SettingsRange.maxServoAngle);

  static int distanceCm(int value) =>
      clampInt(value, SettingsRange.minDistanceCm, SettingsRange.maxDistanceCm);

  static int brightness(int value) =>
      clampInt(value, SettingsRange.minBrightness, SettingsRange.maxBrightness);
}
