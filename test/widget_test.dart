import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roveros/app.dart';
import 'package:roveros/core/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_storage.dart';

/// Boot smoke tests.
///
/// These deliberately pump fixed durations rather than calling
/// `pumpAndSettle`: the splash and the onboarding welcome both run looping
/// animations — the accent bloom and the logo's servo sweep — that never come
/// to rest, so settling would run until the test timed out.
void main() {
  Future<void> boot(WidgetTester tester, {required bool onboarded}) async {
    SharedPreferences.setMockInitialValues(
      onboarded ? {'roveros.onboarded.v1': true} : {},
    );
    final storage = await createTestStorage();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const RoverApp(),
      ),
    );
    await tester.pump();
  }

  /// Advances past the splash's boot sequence and its minimum hold.
  Future<void> settleSplash(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('app boots to the splash screen', (tester) async {
    await boot(tester, onboarded: false);

    expect(find.text('ROVEROS'), findsOneWidget);
    expect(find.text('SMART VEHICLE CONTROL'), findsOneWidget);
  });

  testWidgets('a first run lands on the setup guide', (tester) async {
    await boot(tester, onboarded: false);
    await settleSplash(tester);

    expect(find.text('Welcome to ROVEROS'), findsOneWidget);
    expect(find.text('CONTINUE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a returning user goes straight to the dashboard', (
    tester,
  ) async {
    await boot(tester, onboarded: true);
    await settleSplash(tester);

    // The bottom navigation is the marker that the shell, not the guide, is up.
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('DATA'), findsOneWidget);
    expect(find.text('DRIVE'), findsOneWidget);
    expect(find.text('AUTO'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dashboard offers a single primary action', (tester) async {
    await boot(tester, onboarded: true);
    await settleSplash(tester);

    // Nothing is paired on a fresh install, so the one thing to do is connect.
    expect(find.text('CONNECT VEHICLE'), findsWidgets);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
