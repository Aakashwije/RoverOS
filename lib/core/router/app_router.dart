import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auto/auto_screen.dart';
import '../../features/connection/connection_screen.dart';
import '../../features/drive/drive_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/telemetry/telemetry_screen.dart';
import '../../widgets/rover_shell.dart';

/// Route paths. Screens never write a literal path string.
abstract final class AppRoute {
  static const String splash = '/';
  static const String onboarding = '/welcome';

  // Shell branches, in tab order.
  static const String home = '/home';
  static const String telemetry = '/telemetry';
  static const String auto = '/auto';
  static const String settings = '/settings';

  /// Presented over the shell — the drive HUD owns the whole screen.
  static const String drive = '/drive';
  static const String connect = '/connect';
}

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

/// Slides a full-screen route up from the bottom — used for Drive and Connect
/// so entering them reads as "taking over" rather than as a sideways step.
CustomTransitionPage<void> _verticalPage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoute.splash,
    routes: [
      GoRoute(
        path: AppRoute.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoute.connect,
        pageBuilder: (context, state) =>
            _verticalPage(const ConnectionScreen(), state),
      ),
      GoRoute(
        path: AppRoute.drive,
        pageBuilder: (context, state) =>
            _verticalPage(const DriveScreen(), state),
      ),
      GoRoute(
        path: AppRoute.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state, navigationShell) =>
            RoverShell(shell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoute.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // Telemetry is a branch rather than a pushed page: it is where the
          // user goes to *watch* the vehicle, often for minutes at a time, and
          // a pushed route would lose its scroll position every time they
          // stepped away to check something else.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoute.telemetry,
                builder: (context, state) => const TelemetryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoute.auto,
                builder: (context, state) => const AutoScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoute.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
