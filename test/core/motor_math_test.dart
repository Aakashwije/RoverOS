import 'package:flutter_test/flutter_test.dart';
import 'package:roveros/core/utils/motor_math.dart';
import 'package:roveros/models/settings.dart';

void main() {
  const neutralSettings = AppSettings(
    maxSpeedPercent: 100,
    deadZonePercent: 0,
    joystickSensitivity: 1.0,
  );

  group('fromJoystick — differential drive mix', () {
    test('centre stick produces a full stop', () {
      final output = MotorMath.fromJoystick(
        x: 0,
        y: 0,
        settings: neutralSettings,
      );
      expect(output, MotorOutput.stopped);
    });

    test('full forward drives both motors forward equally', () {
      final output = MotorMath.fromJoystick(
        x: 0,
        y: 1,
        settings: neutralSettings,
      );
      expect(output.left, 100);
      expect(output.right, 100);
    });

    test('full reverse drives both motors backward equally', () {
      final output = MotorMath.fromJoystick(
        x: 0,
        y: -1,
        settings: neutralSettings,
      );
      expect(output.left, -100);
      expect(output.right, -100);
    });

    test('full right at centre y pivots in place: L = +100, R = -100', () {
      final output = MotorMath.fromJoystick(
        x: 1,
        y: 0,
        settings: neutralSettings,
      );
      expect(output.left, 100);
      expect(output.right, -100);
    });

    test('full left at centre y pivots the other way', () {
      final output = MotorMath.fromJoystick(
        x: -1,
        y: 0,
        settings: neutralSettings,
      );
      expect(output.left, -100);
      expect(output.right, 100);
    });

    test(
      'diagonal forward-right biases the right motor down, not negative',
      () {
        final output = MotorMath.fromJoystick(
          x: 0.5,
          y: 0.5,
          settings: neutralSettings,
        );
        expect(output.left, greaterThan(output.right));
        expect(output.left, greaterThan(0));
        expect(output.right, greaterThanOrEqualTo(0));
      },
    );

    test('output is always clamped to -100..100 even past unit input', () {
      final output = MotorMath.fromJoystick(
        x: 2,
        y: 2,
        settings: neutralSettings,
      );
      expect(output.left, lessThanOrEqualTo(100));
      expect(output.right, lessThanOrEqualTo(100));
    });
  });

  group('dead zone handling', () {
    const deadZoneSettings = AppSettings(
      maxSpeedPercent: 100,
      deadZonePercent: 20,
      joystickSensitivity: 1.0,
    );

    test('input inside the dead zone produces a full stop', () {
      final output = MotorMath.fromJoystick(
        x: 0.1,
        y: 0.1,
        settings: deadZoneSettings,
      );
      expect(output, MotorOutput.stopped);
    });

    test('input just outside the dead zone still moves the vehicle', () {
      final output = MotorMath.fromJoystick(
        x: 0,
        y: 0.9,
        settings: deadZoneSettings,
      );
      expect(output.isStopped, isFalse);
    });

    test('full deflection still reaches full output despite the dead zone', () {
      final output = MotorMath.fromJoystick(
        x: 0,
        y: 1,
        settings: deadZoneSettings,
      );
      expect(output.left, 100);
      expect(output.right, 100);
    });
  });

  group('speed limiting', () {
    test('maxSpeedPercent scales every output as a hard ceiling', () {
      final settings = neutralSettings.copyWith(maxSpeedPercent: 50);
      final output = MotorMath.fromJoystick(x: 0, y: 1, settings: settings);
      expect(output.left, 50);
      expect(output.right, 50);
    });

    test('a 0% ceiling produces zero output regardless of stick position', () {
      final settings = neutralSettings.copyWith(maxSpeedPercent: 0);
      final output = MotorMath.fromJoystick(x: 1, y: 1, settings: settings);
      expect(output.left, 0);
      expect(output.right, 0);
    });
  });

  group('calibration', () {
    test('inverting a motor flips its sign without changing magnitude', () {
      final settings = neutralSettings.copyWith(invertLeftMotor: true);
      final output = MotorMath.applyCalibration(
        left: 60,
        right: 60,
        settings: settings,
      );
      expect(output.left, -60);
      expect(output.right, 60);
    });

    test(
      'trim scales magnitude but never flips a positive output negative',
      () {
        final settings = neutralSettings.copyWith(leftMotorTrim: -25);
        final output = MotorMath.applyCalibration(
          left: 40,
          right: 40,
          settings: settings,
        );
        expect(output.left, lessThan(40));
        expect(output.left, greaterThanOrEqualTo(0));
      },
    );

    test('calibration output is still clamped to the motor range', () {
      final settings = neutralSettings.copyWith(leftMotorTrim: 25);
      final output = MotorMath.applyCalibration(
        left: 95,
        right: 0,
        settings: settings,
      );
      expect(output.left, lessThanOrEqualTo(100));
    });
  });

  group('epsilon / throttling support', () {
    test('outputs within epsilon are treated as unchanged', () {
      expect(
        MotorMath.isWithinEpsilon(
          const MotorOutput(50, 50),
          const MotorOutput(51, 49),
          2,
        ),
        isTrue,
      );
    });

    test('outputs outside epsilon are treated as changed', () {
      expect(
        MotorMath.isWithinEpsilon(
          const MotorOutput(50, 50),
          const MotorOutput(60, 50),
          2,
        ),
        isFalse,
      );
    });

    test('a transition to or from stop is never suppressed by epsilon', () {
      expect(
        MotorMath.isWithinEpsilon(
          const MotorOutput(1, 1),
          MotorOutput.stopped,
          5,
        ),
        isFalse,
      );
    });
  });

  group('rampToward', () {
    test('does not jump straight to target in a single tick from a stop', () {
      final settings = neutralSettings.copyWith(accelerationRate: 200);
      final next = MotorMath.rampToward(
        current: 0,
        target: 100,
        elapsedSeconds: 0.1,
        settings: settings,
      );
      expect(next, closeTo(20, 0.01));
      expect(next, lessThan(100));
    });

    test(
      'reaches the target exactly once the ramp step would overshoot it',
      () {
        final settings = neutralSettings.copyWith(accelerationRate: 1000);
        final next = MotorMath.rampToward(
          current: 90,
          target: 100,
          elapsedSeconds: 0.1,
          settings: settings,
        );
        expect(next, 100);
      },
    );

    test('uses the deceleration rate when the magnitude is shrinking', () {
      final settings = neutralSettings.copyWith(
        accelerationRate: 100,
        decelerationRate: 1000,
      );
      // Slowing from 100 toward 0 should use the (faster) deceleration rate,
      // not the acceleration rate.
      final next = MotorMath.rampToward(
        current: 100,
        target: 0,
        elapsedSeconds: 0.1,
        settings: settings,
      );
      expect(next, closeTo(0, 0.01));
    });

    test('a value already at its target is returned unchanged', () {
      final next = MotorMath.rampToward(
        current: 50,
        target: 50,
        elapsedSeconds: 1,
        settings: neutralSettings,
      );
      expect(next, 50);
    });
  });

  group('directionOf', () {
    test('classifies straight forward and reverse', () {
      expect(
        MotorMath.directionOf(const MotorOutput(80, 80)),
        DriveDirection.forward,
      );
      expect(
        MotorMath.directionOf(const MotorOutput(-80, -80)),
        DriveDirection.reverse,
      );
    });

    test('classifies a stationary spin turn', () {
      expect(
        MotorMath.directionOf(const MotorOutput(60, -60)),
        DriveDirection.spinRight,
      );
      expect(
        MotorMath.directionOf(const MotorOutput(-60, 60)),
        DriveDirection.spinLeft,
      );
    });

    test('classifies idle', () {
      expect(MotorMath.directionOf(MotorOutput.stopped), DriveDirection.idle);
    });
  });
}
