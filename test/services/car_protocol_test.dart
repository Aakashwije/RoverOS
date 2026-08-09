import 'package:flutter_test/flutter_test.dart';
import 'package:roveros/core/constants/command_constants.dart';
import 'package:roveros/models/commands.dart';
import 'package:roveros/services/car_protocol.dart';

void main() {
  group('command serialisation', () {
    test('drive command carries both motor outputs', () {
      final command = CarProtocol.buildDriveCommand(left: 70, right: 80);
      expect(command.readable, 'CMD:DRIVE;L:70;R:80');
      expect(command.verb, Wire.verbDrive);
      expect(command.frame.endsWith('\n'), isTrue);
    });

    test('drive command clamps outputs to the motor range', () {
      expect(
        CarProtocol.buildDriveCommand(left: 250, right: -400).readable,
        'CMD:DRIVE;L:100;R:-100',
      );
    });

    test('drive command preserves reverse as a negative value', () {
      expect(
        CarProtocol.buildDriveCommand(left: -60, right: -60).readable,
        'CMD:DRIVE;L:-60;R:-60',
      );
    });

    test('stop command is critical so it is never throttled or dropped', () {
      final stop = CarProtocol.buildStopCommand();
      expect(stop.readable, 'CMD:STOP');
      expect(stop.isCritical, isTrue);
    });

    test('mode command is critical', () {
      expect(CarProtocol.buildModeCommand(DriveMode.manual).isCritical, isTrue);
    });

    test('speed command clamps to 0-100', () {
      expect(CarProtocol.buildSpeedCommand(75).readable, 'CMD:SPEED;V:75');
      expect(CarProtocol.buildSpeedCommand(140).readable, 'CMD:SPEED;V:100');
      expect(CarProtocol.buildSpeedCommand(-5).readable, 'CMD:SPEED;V:0');
    });

    test('light command names a mode and never toggles the LED itself', () {
      expect(
        CarProtocol.buildLightCommand(LightMode.flashFast).readable,
        'CMD:LIGHT;MODE:FLASH_FAST',
      );
      expect(
        CarProtocol.buildLightCommand(LightMode.on, brightness: 60).readable,
        'CMD:LIGHT;MODE:ON;BRIGHT:60',
      );
    });

    test('servo command clamps to the physical 0-180 range', () {
      expect(
        CarProtocol.buildServoCommand(120).readable,
        'CMD:SERVO;ANGLE:120',
      );
      expect(
        CarProtocol.buildServoCommand(400).readable,
        'CMD:SERVO;ANGLE:180',
      );
      expect(CarProtocol.buildServoCommand(-30).readable, 'CMD:SERVO;ANGLE:0');
    });

    test('mode and scan commands use firmware tokens', () {
      expect(
        CarProtocol.buildModeCommand(DriveMode.obstacleAvoidance).readable,
        'CMD:MODE;VALUE:AVOID',
      );
      expect(
        CarProtocol.buildScanCommand(ScanMode.auto).readable,
        'CMD:SCAN;MODE:AUTO',
      );
    });

    test('config command clamps the watchdog window to a safe range', () {
      expect(
        CarProtocol.buildConfigCommand(timeoutMs: 750).readable,
        'CMD:CONFIG;TIMEOUT:750',
      );
      expect(
        CarProtocol.buildConfigCommand(timeoutMs: 50).readable,
        'CMD:CONFIG;TIMEOUT:300',
      );
      expect(
        CarProtocol.buildConfigCommand(timeoutMs: 99999).readable,
        'CMD:CONFIG;TIMEOUT:2000',
      );
    });
  });

  group('validateCommand', () {
    test('accepts every command the builders produce', () {
      final commands = [
        CarProtocol.buildDriveCommand(left: 10, right: -10),
        CarProtocol.buildStopCommand(),
        CarProtocol.buildSpeedCommand(50),
        CarProtocol.buildLightCommand(LightMode.hazard),
        CarProtocol.buildServoCommand(90),
        CarProtocol.buildModeCommand(DriveMode.autoScan),
        CarProtocol.buildScanCommand(ScanMode.once),
        CarProtocol.buildConfigCommand(timeoutMs: 500),
        CarProtocol.buildMotorTestCommand(MotorTarget.both),
        CarProtocol.buildPingCommand(),
      ];
      for (final command in commands) {
        expect(
          CarProtocol.validateCommand(command.frame),
          isTrue,
          reason: 'rejected ${command.readable}',
        );
      }
    });

    test('rejects unsupported verbs', () {
      expect(CarProtocol.validateCommand('CMD:LAUNCH;V:1'), isFalse);
    });

    test('rejects a wrong prefix', () {
      expect(CarProtocol.validateCommand('DRIVE;L:10;R:10'), isFalse);
      expect(CarProtocol.validateCommand('DATA;BAT:80'), isFalse);
    });

    test('rejects malformed field pairs', () {
      expect(CarProtocol.validateCommand('CMD:DRIVE;L;R:10'), isFalse);
      expect(CarProtocol.validateCommand('CMD:DRIVE;:70;R:10'), isFalse);
    });

    test('rejects empty and oversized frames', () {
      expect(CarProtocol.validateCommand(''), isFalse);
      expect(CarProtocol.validateCommand('   '), isFalse);
      expect(CarProtocol.validateCommand('CMD:DRIVE;L:${'9' * 300}'), isFalse);
    });
  });

  group('parseTelemetry', () {
    test('reads a full frame', () {
      final telemetry = CarProtocol.parseTelemetry(
        'DATA;BAT:82;DIST:64;SERVO:90;SPD:72;MODE:MANUAL',
      )!;

      expect(telemetry.batteryPercent, 82);
      expect(telemetry.distanceCm, 64);
      expect(telemetry.servoAngle, 90);
      expect(telemetry.speedPercent, 72);
      expect(telemetry.driveMode, DriveMode.manual);
      expect(telemetry.updatedAt, isNotNull);
    });

    test('reads motor, light and signal fields', () {
      final telemetry = CarProtocol.parseTelemetry(
        'DATA;L:70;R:80;LIGHT:ON;SIG:90',
      )!;

      expect(telemetry.leftMotor, 70);
      expect(telemetry.rightMotor, 80);
      expect(telemetry.lightMode, LightMode.on);
      expect(telemetry.signalPercent, 90);
    });

    test('treats legacy AUTO mode as obstacle avoidance', () {
      expect(
        CarProtocol.parseTelemetry('DATA;MODE:AUTO')!.driveMode,
        DriveMode.obstacleAvoidance,
      );
    });

    test('drops a single unreadable field but keeps the rest', () {
      final telemetry = CarProtocol.parseTelemetry('DATA;BAT:oops;DIST:64')!;

      expect(telemetry.batteryPercent, isNull);
      expect(telemetry.distanceCm, 64);
    });

    test('clamps out-of-range battery instead of trusting it', () {
      expect(CarProtocol.parseTelemetry('DATA;BAT:140')!.batteryPercent, 100);
      expect(CarProtocol.parseTelemetry('DATA;BAT:-20')!.batteryPercent, 0);
    });

    test(
      'treats an out-of-range distance as no echo, not a clamped reading',
      () {
        // A real HC-SR04 reports 0 when it never hears an echo back.
        expect(CarProtocol.parseTelemetry('DATA;DIST:0')!.distanceCm, isNull);
        expect(
          CarProtocol.parseTelemetry('DATA;DIST:9999')!.distanceCm,
          isNull,
        );
      },
    );

    test(
      'records a radar sample when a distance arrives with a servo angle',
      () {
        final telemetry = CarProtocol.parseTelemetry('DATA;SERVO:45;DIST:120')!;

        expect(telemetry.radarSamples[45]?.distanceCm, 120);
      },
    );

    test('maps left/centre/right shorthand onto radar angles', () {
      final telemetry = CarProtocol.parseTelemetry('DATA;DL:120;DC:85;DR:64')!;

      expect(telemetry.radarSamples[0]?.distanceCm, 120);
      expect(telemetry.radarSamples[90]?.distanceCm, 85);
      expect(telemetry.radarSamples[180]?.distanceCm, 64);
      expect(telemetry.leftDistanceCm, 120);
      expect(telemetry.rightDistanceCm, 64);
    });

    test('returns null for frames with nothing readable', () {
      expect(CarProtocol.parseTelemetry('DATA'), isNull);
      expect(CarProtocol.parseTelemetry('DATA;;;'), isNull);
      expect(CarProtocol.parseTelemetry('DATA;GARBAGE'), isNull);
      expect(CarProtocol.parseTelemetry('ACK:DRIVE'), isNull);
      expect(CarProtocol.parseTelemetry(''), isNull);
    });
  });

  group('parseAck', () {
    test('reads a known verb', () {
      expect(CarProtocol.parseAck('ACK:DRIVE')!.verb, 'DRIVE');
      expect(CarProtocol.parseAck('ACK:STOP')!.verb, 'STOP');
      expect(CarProtocol.parseAck('ACK:LIGHT')!.verb, 'LIGHT');
      expect(CarProtocol.parseAck('ACK:MODE')!.verb, 'MODE');
    });

    test('rejects unknown verbs and malformed frames', () {
      expect(CarProtocol.parseAck('ACK:TELEPORT'), isNull);
      expect(CarProtocol.parseAck('ACK'), isNull);
      expect(CarProtocol.parseAck('ACK:'), isNull);
      expect(CarProtocol.parseAck('DATA;BAT:80'), isNull);
    });
  });

  group('parseError', () {
    test('reads code and humanises the firmware message', () {
      final error = CarProtocol.parseError('ERROR;CODE:03;MSG:SENSOR_FAIL')!;

      expect(error.code, RoverErrorCode.sensorFail);
      expect(error.message, 'Sensor fail');
      expect(error.isFailSafe, isTrue);
    });

    test('falls back to the built-in message when none is supplied', () {
      final error = CarProtocol.parseError('ERROR;CODE:05')!;

      expect(error.code, RoverErrorCode.lowBattery);
      expect(error.message, RoverErrorCode.lowBattery.message);
      expect(error.isFailSafe, isFalse);
    });

    test('surfaces an unclassifiable error rather than dropping it', () {
      final error = CarProtocol.parseError('ERROR;CODE:99')!;

      expect(error.code, RoverErrorCode.unknown);
      expect(error.message, isNotEmpty);
    });

    test('rejects non-error frames', () {
      expect(CarProtocol.parseError('ACK:STOP'), isNull);
    });
  });

  group('parseFrame classification', () {
    test('routes each frame type to its own branch', () {
      expect(CarProtocol.parseFrame('DATA;BAT:80'), isA<TelemetryFrame>());
      expect(CarProtocol.parseFrame('ACK:STOP'), isA<AckFrame>());
      expect(CarProtocol.parseFrame('ERROR;CODE:03'), isA<ErrorFrame>());
    });

    test('reports unrecognised frames instead of silently dropping them', () {
      final frame = CarProtocol.parseFrame('HELLO WORLD');

      expect(frame, isA<UnknownFrame>());
      expect((frame as UnknownFrame).reason, isNotEmpty);
    });

    test('an empty frame is unknown, not a crash', () {
      expect(CarProtocol.parseFrame('   '), isA<UnknownFrame>());
    });
  });
}
