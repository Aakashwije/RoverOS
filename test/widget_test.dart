import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roveros/app.dart';
import 'package:roveros/core/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_storage.dart';

void main() {
  testWidgets('app boots to the splash screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await createTestStorage();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const RoverApp(),
      ),
    );
    await tester.pump();

    expect(find.text('ROVEROS'), findsOneWidget);
    expect(find.text('SMART VEHICLE CONTROL'), findsOneWidget);

    // Let the splash's timers settle so the test does not leave pending work.
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
