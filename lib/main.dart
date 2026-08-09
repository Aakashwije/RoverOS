import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/providers/app_providers.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait everywhere by default; the Drive screen opts into landscape for
  // itself and restores this on the way out.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF06080B),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Settings and the remembered vehicle are read synchronously all over the
  // app, so storage is resolved once here and injected into the scope.
  final storage = await StorageService.create();

  runApp(
    ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
      child: const RoverApp(),
    ),
  );
}
