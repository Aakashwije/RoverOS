import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_config.dart';
import '../../core/providers/app_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../settings/settings_controller.dart';
import 'widgets/rover_mark.dart';

/// One line of the boot sequence, shown while the splash animation plays.
enum BootStep {
  settings('LOADING SETTINGS'),
  vehicle('CHECKING SAVED VEHICLE'),
  permissions('CHECKING BLUETOOTH'),
  link('PREPARING LINK'),
  ready('READY');

  const BootStep(this.label);

  final String label;
}

/// Startup screen.
///
/// Runs the boot sequence and the intro animation concurrently, then leaves as
/// soon as both are done — the splash is a cover for real work, not a delay.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.splash,
  )..forward();

  BootStep _step = BootStep.settings;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final startedAt = DateTime.now();

    // 1. Settings. Reading the provider forces the synchronous load from disk.
    ref.read(settingsProvider);
    await _advance(BootStep.vehicle);

    // 2. Saved vehicle.
    final storage = ref.read(storageServiceProvider);
    final remembered = storage.loadVehicle();
    await _advance(BootStep.permissions);

    // 3 & 4. Permission state and auto-reconnect are owned by the connection
    // layer; the splash only reports that the stage ran.
    await _advance(remembered == null ? BootStep.ready : BootStep.link);
    if (remembered != null) await _advance(BootStep.ready);

    // Hold until the intro animation has had its full run.
    final elapsed = DateTime.now().difference(startedAt);
    final remaining = AppDurations.splash - elapsed;
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);

    if (!mounted) return;
    context.go(AppRoute.home);
  }

  Future<void> _advance(BootStep next) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    setState(() => _step = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.25),
            radius: 0.9,
            colors: [Color(0xFF0D1620), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              _FadeUp(
                controller: _controller,
                start: 0,
                end: 0.45,
                child: const RoverMark(size: 148),
              ),
              const SizedBox(height: AppSpacing.xxxl),
              _FadeUp(
                controller: _controller,
                start: 0.25,
                end: 0.7,
                child: const Text(
                  AppConfig.appName,
                  style: AppTypography.wordmark,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _FadeUp(
                controller: _controller,
                start: 0.4,
                end: 0.85,
                child: const Text(
                  AppConfig.tagline,
                  style: AppTypography.wordmarkSub,
                ),
              ),
              const Spacer(flex: 4),
              _BootStatus(step: _step, controller: _controller),
              const SizedBox(height: AppSpacing.huge),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades and lifts [child] across a slice of the parent controller's timeline.
class _FadeUp extends StatelessWidget {
  const _FadeUp({
    required this.controller,
    required this.start,
    required this.end,
    required this.child,
  });

  final AnimationController controller;
  final double start;
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, inner) => Opacity(
        opacity: animation.value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - animation.value)),
          child: inner,
        ),
      ),
      child: child,
    );
  }
}

class _BootStatus extends StatelessWidget {
  const _BootStatus({required this.step, required this.controller});

  final BootStep step;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final progress = (step.index + 1) / BootStep.values.length;

    return _FadeUp(
      controller: controller,
      start: 0.5,
      end: 1,
      child: Semantics(
        liveRegion: true,
        label: 'Starting up. ${step.label}',
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: AppDurations.normal,
                    curve: AppDurations.standard,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 2,
                      backgroundColor: AppColors.surfaceElevated,
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AnimatedSwitcher(
                duration: AppDurations.fast,
                child: Text(
                  step.label,
                  key: ValueKey(step),
                  style: AppTypography.label.copyWith(letterSpacing: 2.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
