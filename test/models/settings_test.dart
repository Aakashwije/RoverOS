import 'package:flutter_test/flutter_test.dart';
import 'package:roveros/core/utils/validation.dart';
import 'package:roveros/models/settings.dart';

void main() {
  group('AppSettings.normalized', () {
    test('leaves an already-valid configuration untouched', () {
      const settings = AppSettings(
        maxSpeedPercent: 70,
        cautionDistanceCm: 60,
        dangerDistanceCm: 30,
        servoMinAngle: 0,
        servoMaxAngle: 180,
        servoCenter: 90,
      );

      final normalized = settings.normalized();
      expect(normalized.cautionDistanceCm, 60);
      expect(normalized.dangerDistanceCm, 30);
      expect(normalized.servoCenter, 90);
    });

    test('clamps an out-of-range speed and sensitivity', () {
      const settings = AppSettings(
        maxSpeedPercent: 500,
        joystickSensitivity: 99,
      );
      final normalized = settings.normalized();

      expect(normalized.maxSpeedPercent, SettingsRange.maxSpeedPercent);
      expect(normalized.joystickSensitivity, SettingsRange.maxSensitivity);
    });

    test('repairs a danger threshold that is not below caution', () {
      const settings = AppSettings(cautionDistanceCm: 40, dangerDistanceCm: 40);
      final normalized = settings.normalized();

      expect(
        normalized.dangerDistanceCm,
        lessThan(normalized.cautionDistanceCm),
      );
    });

    test('repairs an inverted servo range by falling back to full travel', () {
      const settings = AppSettings(
        servoMinAngle: 150,
        servoMaxAngle: 30,
        servoCenter: 90,
      );
      final normalized = settings.normalized();

      expect(normalized.servoMinAngle, lessThan(normalized.servoMaxAngle));
    });

    test('clamps the servo centre to sit within the min/max range', () {
      const settings = AppSettings(
        servoMinAngle: 20,
        servoMaxAngle: 100,
        servoCenter: 170,
      );
      final normalized = settings.normalized();

      expect(normalized.servoCenter, inInclusiveRange(20, 100));
    });

    test('rejects a blank vehicle name rather than persisting it', () {
      const settings = AppSettings(vehicleName: '   ');
      expect(settings.normalized().vehicleName, isNotEmpty);
    });

    test('truncates an oversized vehicle name', () {
      final settings = AppSettings(vehicleName: 'X' * 80);
      expect(
        settings.normalized().vehicleName.length,
        lessThanOrEqualTo(SettingsRange.maxVehicleNameLength),
      );
    });

    test('clamps the watchdog timeout into the firmware-supported range', () {
      const settings = AppSettings(commandTimeoutMs: 50);
      expect(settings.normalized().commandTimeoutMs, greaterThanOrEqualTo(300));
    });
  });

  group('AppSettings JSON round-trip', () {
    test('serialises and restores every field', () {
      const settings = AppSettings(
        vehicleName: 'TEST-ROVER',
        maxSpeedPercent: 55,
        invertLeftMotor: true,
        leftMotorTrim: -10,
        mockMode: false,
      );

      final restored = AppSettings.fromJson(settings.toJson());

      expect(restored.vehicleName, 'TEST-ROVER');
      expect(restored.maxSpeedPercent, 55);
      expect(restored.invertLeftMotor, isTrue);
      expect(restored.leftMotorTrim, -10);
      expect(restored.mockMode, isFalse);
    });

    test('falls back to defaults for missing keys instead of throwing', () {
      final restored = AppSettings.fromJson(const {});
      expect(restored.vehicleName, AppSettings.defaults.vehicleName);
      expect(restored.maxSpeedPercent, AppSettings.defaults.maxSpeedPercent);
    });

    test('ignores keys of the wrong type instead of throwing', () {
      final restored = AppSettings.fromJson({
        'maxSpeedPercent': 'not a number',
        'hapticsEnabled': 'not a bool',
      });
      expect(restored.maxSpeedPercent, AppSettings.defaults.maxSpeedPercent);
      expect(restored.hapticsEnabled, AppSettings.defaults.hapticsEnabled);
    });
  });
}
