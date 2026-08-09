import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roveros/core/constants/command_constants.dart';
import 'package:roveros/core/providers/app_providers.dart';
import 'package:roveros/core/utils/motor_math.dart';
import 'package:roveros/features/connection/connection_controller.dart';
import 'package:roveros/features/drive/drive_controller.dart';
import 'package:roveros/models/commands.dart';
import 'package:roveros/models/vehicle.dart';
import 'package:roveros/services/transport/mock_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_storage.dart';

/// These exercise the safety paths called out in the brief end to end, through
/// [MockTransport], rather than only the pure motor-math functions.
void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = await createTestStorage();
    container = ProviderContainer(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
  });

  Future<void> connect() async {
    await container
        .read(connectionProvider.notifier)
        .connectTo(
          const DiscoveredVehicle(id: 'mock-rover-01', name: 'MOCK-ESP32-CAR'),
        );
    // Let the mock transport's connect delay elapse.
    await Future<void>.delayed(const Duration(milliseconds: 950));
  }

  test('joystick engagement drives the reported motor output', () async {
    await connect();

    container.read(driveProvider.notifier).updateJoystick(x: 0, y: 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final state = container.read(driveProvider);
    expect(state.output.isStopped, isFalse);
    expect(state.output.left, greaterThan(0));
    expect(state.output.right, greaterThan(0));
  });

  test(
    'releasing the joystick immediately zeroes the commanded output',
    () async {
      await connect();

      container.read(driveProvider.notifier).updateJoystick(x: 0, y: 1);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      container.read(driveProvider.notifier).releaseJoystick();

      final state = container.read(driveProvider);
      expect(state.output, MotorOutput.stopped);
      expect(state.isEngaged, isFalse);
    },
  );

  test('emergency stop zeroes output and latches the stopped state', () async {
    await connect();

    container.read(driveProvider.notifier).updateJoystick(x: 0, y: 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await container.read(driveProvider.notifier).emergencyStop();

    final state = container.read(driveProvider);
    expect(state.output, MotorOutput.stopped);
    expect(state.isEmergencyStopped, isTrue);
    expect(state.acceptsInput, isFalse);
  });

  test('joystick input is ignored while emergency-stopped', () async {
    await connect();
    await container.read(driveProvider.notifier).emergencyStop();

    container.read(driveProvider.notifier).updateJoystick(x: 1, y: 1);

    expect(container.read(driveProvider).output, MotorOutput.stopped);
  });

  test('clearing the emergency stop allows driving again', () async {
    await connect();
    await container.read(driveProvider.notifier).emergencyStop();

    container.read(driveProvider.notifier).clearEmergencyStop();
    expect(container.read(driveProvider).acceptsInput, isTrue);

    container.read(driveProvider.notifier).updateJoystick(x: 0, y: 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(container.read(driveProvider).output.isStopped, isFalse);
  });

  test('a lost connection clears the commanded output', () async {
    await connect();
    container.read(driveProvider.notifier).updateJoystick(x: 0, y: 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(container.read(driveProvider).output.isStopped, isFalse);

    await container.read(connectionProvider.notifier).disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(driveProvider).output, MotorOutput.stopped);
  });

  test('entering an autonomous mode stops any manual output first', () async {
    await connect();
    container.read(driveProvider.notifier).updateJoystick(x: 0, y: 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await container
        .read(driveProvider.notifier)
        .setDriveMode(DriveMode.obstacleAvoidance);

    expect(container.read(driveProvider).output, MotorOutput.stopped);
    expect(
      container.read(driveProvider).driveMode,
      DriveMode.obstacleAvoidance,
    );
  });

  test('setSpeed clamps to 0-100', () {
    container.read(driveProvider.notifier).setSpeed(500);
    expect(container.read(driveProvider).speedPercent, 100);

    container.read(driveProvider.notifier).setSpeed(-50);
    expect(container.read(driveProvider).speedPercent, 0);
  });

  test(
    'the mock transport enforces its own watchdog independent of the app',
    () async {
      await connect();

      final transport = container.read(transportProvider) as MockTransport;

      // Subscribe before sending: the inbound stream is a broadcast stream with
      // no replay, so listening late would miss the watchdog frame.
      final frames = <String>[];
      final subscription = transport.subscribe().listen(frames.add);

      await transport.send('CMD:CONFIG;TIMEOUT:300\n');
      await transport.send('CMD:DRIVE;L:80;R:80\n');

      // Simulate the app going silent, as it would if the process were killed
      // mid-drive: no more commands are sent, but the firmware must still stop.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await subscription.cancel();

      expect(
        frames.any(
          (f) => f.contains('CODE:${RoverErrorCode.watchdogStop.code}'),
        ),
        isTrue,
        reason:
            'expected a watchdog-stop error frame once commands stopped arriving',
      );
    },
  );
}
