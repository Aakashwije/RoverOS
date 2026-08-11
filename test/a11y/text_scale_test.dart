import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roveros/core/providers/app_providers.dart';
import 'package:roveros/core/theme/app_theme.dart';
import 'package:roveros/core/utils/motor_math.dart';
import 'package:roveros/features/auto/auto_behaviour.dart';
import 'package:roveros/features/auto/widgets/decision_readout.dart';
import 'package:roveros/features/connection/widgets/device_tile.dart';
import 'package:roveros/features/drive/widgets/motor_readout.dart';
import 'package:roveros/features/home/home_status.dart';
import 'package:roveros/features/home/widgets/status_banner.dart';
import 'package:roveros/features/home/widgets/vitals_strip.dart';
import 'package:roveros/features/telemetry/widgets/trend_card.dart';
import 'package:roveros/models/commands.dart';
import 'package:roveros/models/connection_state.dart';
import 'package:roveros/models/settings.dart';
import 'package:roveros/models/telemetry.dart';
import 'package:roveros/models/vehicle.dart';
import 'package:roveros/widgets/app_segmented_control.dart';
import 'package:roveros/widgets/battery_indicator.dart';
import 'package:roveros/widgets/sparkline.dart';
import 'package:roveros/widgets/telemetry_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_storage.dart';

/// Large-text regression coverage.
///
/// The app caps the platform text scale at 1.3, which is the largest a user
/// can push it — and the size at which a dense instrument panel is most likely
/// to overflow. A RenderFlex overflow throws during a widget test, so pumping
/// each dense component at the cap and asserting no exception is a direct test
/// of "does this still lay out for someone who needs bigger text".
void main() {
  const cap = 1.3;

  /// The narrowest phone the dashboard targets, which is where overflow shows
  /// up first.
  const narrow = Size(320, 640);

  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = await createTestStorage();
    container = ProviderContainer(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pumpAtScale(
    WidgetTester tester,
    Widget child, {
    double scale = cap,
    Size size = narrow,
  }) async {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              backgroundColor: AppColors.background,
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final telemetry = Telemetry(
    batteryPercent: 84,
    distanceCm: 142,
    servoAngle: 90,
    speedPercent: 70,
    leftMotor: 64,
    rightMotor: -58,
    driveMode: DriveMode.obstacleAvoidance,
    lightMode: LightMode.hazard,
    vehicleState: VehicleState.avoiding,
    decision: 'TURN LEFT AROUND OBSTACLE',
    updatedAt: DateTime.now(),
  );

  const settings = AppSettings.defaults;
  const link = LinkState(
    status: ConnectionStatus.connected,
    deviceName: 'MOCK-ESP32-CAR',
    rssi: -58,
  );

  /// Each entry is a dense component that carries numbers and long labels
  /// side by side — the shape most at risk from a larger type scale.
  final cases = <String, Widget>{
    'VitalsStrip': const VitalsStrip(
      telemetry: Telemetry(
        batteryPercent: 84,
        distanceCm: 142,
        driveMode: DriveMode.obstacleAvoidance,
      ),
      settings: settings,
      driveMode: DriveMode.obstacleAvoidance,
      isConnected: true,
    ),
    'StatusBanner (calm)': StatusBanner(
      status: HomeStatus.evaluate(
        link: link,
        telemetry: telemetry,
        isMockMode: false,
      ),
    ),
    'StatusBanner (blocking)': StatusBanner(
      status: HomeStatus.evaluate(
        link: link,
        telemetry: const Telemetry(batteryPercent: 4, updatedAt: null),
        isMockMode: false,
      ),
    ),
    'MotorReadout': const MotorReadout(output: MotorOutput(-100, 100)),
    'TelemetryCard': const TelemetryCard(
      label: 'FRONT DISTANCE',
      value: '142',
      unit: 'cm',
      icon: Icons.straighten_rounded,
      level: StatusLevel.caution,
      statusLabel: 'OBSTACLE AHEAD',
    ),
    'TrendCard': const TrendCard(
      label: 'BATTERY DRAIN',
      value: '84',
      unit: '%',
      icon: Icons.battery_5_bar_rounded,
      level: StatusLevel.good,
      caption: 'Down 12% · Last 9m',
      values: [92.0, 90.0, 88.0, 84.0, 84.0, 80.0, null, 78.0, 76.0],
      minValue: 0.0,
      maxValue: 100.0,
    ),
    'BatteryIndicator': const BatteryIndicator(percent: 84),
    'DeviceTile': DeviceTile(
      vehicle: DiscoveredVehicle(
        id: 'mock-rover-01',
        name: 'MOCK-ESP32-CAR-LONG-NAME',
        rssi: -58,
        lastSeen: DateTime.now().subtract(const Duration(seconds: 14)),
      ),
      isRemembered: true,
      onConnect: () {},
    ),
    'DecisionReadout': DecisionReadout(
      telemetry: telemetry,
      behaviour: AutoBehaviour.avoid,
      vehicleState: VehicleState.avoiding,
    ),
    'AppSegmentedControl': AppSegmentedControl<AutoBehaviour>(
      value: AutoBehaviour.avoid,
      onChanged: (_) {},
      options: [
        for (final option in AutoBehaviour.values)
          SegmentOption(
            value: option,
            label: option.label,
            icon: option.icon,
          ),
      ],
    ),
    'Sparkline': const Sparkline(
      values: [1.0, 4.0, 2.0, 8.0, 5.0, null, 9.0, 3.0],
    ),
  };

  for (final entry in cases.entries) {
    testWidgets('${entry.key} lays out at the ${cap}x text cap', (
      tester,
    ) async {
      await pumpAtScale(tester, entry.value);
      expect(
        tester.takeException(),
        isNull,
        reason: '${entry.key} overflowed at a ${cap}x text scale',
      );
    });

    testWidgets('${entry.key} lays out at the 0.9x text floor', (tester) async {
      await pumpAtScale(tester, entry.value, scale: 0.9);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the dense strips survive a very narrow window too', (
    tester,
  ) async {
    // 280dp is narrower than anything shipping, but it is where a three-up
    // row of numbers breaks first, and it costs nothing to hold the line.
    await pumpAtScale(
      tester,
      const VitalsStrip(
        telemetry: Telemetry(batteryPercent: 100, distanceCm: 400),
        settings: settings,
        driveMode: DriveMode.obstacleAvoidance,
        isConnected: true,
      ),
      size: const Size(280, 640),
    );
    expect(tester.takeException(), isNull);
  });
}
