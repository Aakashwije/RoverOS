import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// Root widget.
///
/// ROVEROS is dark-only and ignores the platform text-scale ceiling only to the
/// extent of capping it — the dashboard must stay legible at large accessibility
/// sizes without letting a 2× scale break the landscape HUD.
class RoverApp extends ConsumerWidget {
  const RoverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
