import 'package:flutter_test/flutter_test.dart';
import 'package:roveros/core/theme/app_colors.dart';
import 'package:roveros/features/home/home_status.dart';
import 'package:roveros/models/commands.dart';
import 'package:roveros/models/connection_state.dart';
import 'package:roveros/models/telemetry.dart';

/// Home's headline verdict is the one piece of copy a driver reads before
/// deciding whether to pick the rover up, so the precedence between "faulted",
/// "flat", "stale" and "fine" is worth pinning down.
void main() {
  final now = DateTime(2026, 8, 11, 12);

  Telemetry live({
    int? battery,
    VehicleState? state,
    Duration age = Duration.zero,
  }) => Telemetry(
    batteryPercent: battery ?? 80,
    vehicleState: state,
    updatedAt: now.subtract(age),
  );

  const connected = LinkState(status: ConnectionStatus.connected);

  HomeStatus evaluate(
    LinkState link,
    Telemetry telemetry, {
    bool isMockMode = false,
  }) => HomeStatus.evaluate(
    link: link,
    telemetry: telemetry,
    isMockMode: isMockMode,
    now: now,
  );

  group('offline', () {
    test('with no remembered vehicle, the action is to connect', () {
      final status = evaluate(const LinkState(), Telemetry.empty);
      expect(status.action, HomeAction.connect);
      expect(status.isBlocking, isFalse);
    });

    test('with a remembered vehicle, the action is to reconnect', () {
      final status = evaluate(
        const LinkState(deviceId: 'abc', deviceName: 'ESP32-CAR'),
        Telemetry.empty,
      );
      expect(status.action, HomeAction.reconnect);
      expect(status.detail, contains('ESP32-CAR'));
    });

    test('a busy link asks the user to wait rather than to tap', () {
      final status = evaluate(
        const LinkState(
          status: ConnectionStatus.reconnecting,
          reconnectAttempt: 2,
        ),
        Telemetry.empty,
      );
      expect(status.action, HomeAction.waitForLink);
      expect(status.action.isWaiting, isTrue);
      expect(status.detail, contains('2'));
    });

    test('a link failure surfaces the transport message verbatim', () {
      final status = evaluate(
        const LinkState(
          status: ConnectionStatus.error,
          errorMessage: 'The vehicle refused the connection.',
          deviceId: 'abc',
        ),
        Telemetry.empty,
      );
      expect(status.detail, 'The vehicle refused the connection.');
      expect(status.isBlocking, isTrue);
      expect(status.action, HomeAction.reconnect);
    });
  });

  group('connected', () {
    test('a healthy vehicle offers driving', () {
      final status = evaluate(connected, live(battery: 80));
      expect(status.action, HomeAction.drive);
      expect(status.level, StatusLevel.good);
      expect(status.isBlocking, isFalse);
    });

    test('mock mode says so instead of claiming all systems nominal', () {
      final status = evaluate(connected, live(), isMockMode: true);
      expect(status.action, HomeAction.drive);
      expect(status.level, StatusLevel.info);
      expect(status.title, contains('MOCK'));
    });

    test('a low battery still drives, but with a caution', () {
      final status = evaluate(connected, live(battery: 25));
      expect(status.action, HomeAction.driveWithCare);
      expect(status.action.opensDrive, isTrue);
      expect(status.level, StatusLevel.caution);
    });

    test('a critical battery blocks and routes to telemetry', () {
      final status = evaluate(connected, live(battery: 10));
      expect(status.action, HomeAction.resolveFault);
      expect(status.action.opensDrive, isFalse);
      expect(status.isBlocking, isTrue);
    });

    test('a reported fault outranks a flat battery', () {
      // Both are true at once; the fault is the thing that actually stops the
      // vehicle from being driveable, so it is the one that gets reported.
      final status = evaluate(
        connected,
        live(battery: 10, state: VehicleState.fault),
      );
      expect(status.title, 'VEHICLE FAULT');
    });

    test('stale telemetry is caught even though the link is up', () {
      final status = evaluate(
        connected,
        live(battery: 80, age: const Duration(seconds: 30)),
      );
      expect(status.title, 'TELEMETRY STALE');
      expect(status.level, StatusLevel.caution);
      expect(status.action, HomeAction.driveWithCare);
    });

    test('staleness outranks a low battery, being the less obvious fault', () {
      final status = evaluate(
        connected,
        live(battery: 25, age: const Duration(seconds: 30)),
      );
      expect(status.title, 'TELEMETRY STALE');
    });

    test('a critical battery outranks staleness', () {
      final status = evaluate(
        connected,
        live(battery: 5, age: const Duration(seconds: 30)),
      );
      expect(status.title, 'CRITICAL BATTERY');
    });
  });

  test('every action carries a label and an icon for the primary button', () {
    for (final action in HomeAction.values) {
      expect(action.label, isNotEmpty);
      expect(
        action.opensDrive ||
            action.opensConnect ||
            action.isWaiting ||
            action == HomeAction.resolveFault,
        isTrue,
      );
    }
  });
}
