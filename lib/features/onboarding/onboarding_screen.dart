import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_config.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/providers/app_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/settings.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../connection/bluetooth_permission_controller.dart';
import '../settings/settings_controller.dart';
import '../splash/widgets/rover_mark.dart';

/// First-run setup.
///
/// Five short steps, in the order the answers are needed: what you are driving,
/// permission to reach it, which hand holds the stick, and what the app will
/// and will not do for your safety. Every step is skippable and every choice
/// is a normal setting afterwards — this is a guided tour of decisions the user
/// would otherwise meet one at a time, confused, mid-task.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { welcome, mode, permission, controls, safety }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// The permission step is meaningless in mock mode — there is no radio to
  /// ask about — so it drops out of the flow entirely rather than appearing
  /// as a step the user has to dismiss.
  List<_Step> get _steps {
    final isMock = ref.read(settingsProvider).mockMode;
    return [
      _Step.welcome,
      _Step.mode,
      if (!isMock) _Step.permission,
      _Step.controls,
      _Step.safety,
    ];
  }

  void _next() {
    if (_index >= _steps.length - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: AppDurations.normal,
      curve: AppDurations.emphasized,
    );
  }

  void _back() {
    if (_index == 0) return;
    _pageController.previousPage(
      duration: AppDurations.normal,
      curve: AppDurations.emphasized,
    );
  }

  Future<void> _finish() async {
    await ref.read(storageServiceProvider).setOnboardingComplete();
    if (!mounted) return;

    // Real hardware needs pairing before anything else works, so the guide
    // hands straight over to the scan. Mock mode is already drivable.
    final isMock = ref.read(settingsProvider).mockMode;
    if (isMock) {
      context.go(AppRoute.home);
    } else {
      context.go(AppRoute.home);
      context.push(AppRoute.connect);
    }
  }

  void _setMockMode(bool value) {
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(mockMode: value));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final steps = _steps;
    // Dropping the permission step can strand the index past the end.
    final index = _index.clamp(0, steps.length - 1);
    final isLast = index == steps.length - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.1,
            colors: [Color(0xFF0D1620), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: PageConstraints(
            maxWidth: 620,
            child: Column(
              children: [
                _TopBar(
                  step: index,
                  total: steps.length,
                  onSkip: _finish,
                  onBack: index == 0 ? null : _back,
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: steps.length,
                    onPageChanged: (value) => setState(() => _index = value),
                    itemBuilder: (context, i) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: switch (steps[i]) {
                        _Step.welcome => const _WelcomeStep(),
                        _Step.mode => _ModeStep(
                          isMockMode: settings.mockMode,
                          onChanged: _setMockMode,
                        ),
                        _Step.permission => const _PermissionStep(),
                        _Step.controls => _ControlsStep(
                          side: settings.joystickSide,
                          onChanged: (side) => ref
                              .read(settingsProvider.notifier)
                              .update((s) => s.copyWith(joystickSide: side)),
                        ),
                        _Step.safety => const _SafetyStep(),
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  child: AppButton(
                    label: isLast ? 'START DRIVING' : 'CONTINUE',
                    trailingIcon: Icons.arrow_forward_rounded,
                    size: AppButtonSize.large,
                    fullWidth: true,
                    onPressed: _next,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.step,
    required this.total,
    required this.onSkip,
    required this.onBack,
  });

  final int step;
  final int total;
  final VoidCallback onSkip;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Previous step',
            onPressed: onBack,
          ),
          Expanded(
            child: Semantics(
              label: 'Step ${step + 1} of $total',
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < total; i++) ...[
                      AnimatedContainer(
                        duration: AppDurations.normal,
                        curve: AppDurations.standard,
                        height: 4,
                        width: i == step ? 22 : 8,
                        decoration: BoxDecoration(
                          color: i <= step
                              ? AppColors.accent
                              : AppColors.borderStrong,
                          borderRadius: AppRadii.pillRadius,
                        ),
                      ),
                      if (i < total - 1) const SizedBox(width: 5),
                    ],
                  ],
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: onSkip,
            child: Text(
              'SKIP',
              style: AppTypography.label.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared scaffolding for a step: art, headline, body, then whatever the step
/// actually asks for.
class _StepFrame extends StatelessWidget {
  const _StepFrame({
    required this.title,
    required this.body,
    this.art,
    this.child,
  });

  final String title;
  final String body;
  final Widget? art;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),
        if (art != null) ...[
          Center(child: art),
          const SizedBox(height: AppSpacing.xl),
        ],
        Text(title, style: AppTypography.titleLarge),
        const SizedBox(height: AppSpacing.md),
        Text(body, style: AppTypography.body),
        if (child != null) ...[const SizedBox(height: AppSpacing.xl), child!],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) {
    return _StepFrame(
      art: const RoverMark(size: 132),
      title: 'Welcome to ${AppConfig.appName}',
      body:
          'A control dashboard for an ESP32 four-wheel-drive rover. Four short '
          'steps and you will be driving — you can change any of these answers '
          'later in Settings.',
    );
  }
}

class _ModeStep extends StatelessWidget {
  const _ModeStep({required this.isMockMode, required this.onChanged});

  final bool isMockMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _StepFrame(
      title: 'What are you driving?',
      body:
          'ROVEROS ships with a full rover simulator, so you can explore every '
          'screen with no hardware attached.',
      child: Column(
        children: [
          _ChoiceCard(
            icon: Icons.science_rounded,
            title: 'Simulated rover',
            description:
                'A mock vehicle with battery drain, obstacles and faults you '
                'can trigger yourself. Nothing is sent over Bluetooth.',
            isSelected: isMockMode,
            accent: AppColors.info,
            onTap: () => onChanged(true),
          ),
          const SizedBox(height: AppSpacing.md),
          _ChoiceCard(
            icon: Icons.directions_car_rounded,
            title: 'Real vehicle',
            description:
                'Connect over Bluetooth to an ESP32 board running the ROVEROS '
                'firmware.',
            isSelected: !isMockMode,
            accent: AppColors.accent,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _PermissionStep extends ConsumerWidget {
  const _PermissionStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(bluetoothPermissionProvider).value;
    final isGranted = status?.isGranted ?? false;

    return _StepFrame(
      title: 'Bluetooth permission',
      body:
          'Finding your rover needs permission to scan for nearby Bluetooth '
          'devices. ROVEROS uses it for nothing else — no location data leaves '
          'the phone.',
      child: Column(
        children: [
          AppCard(
            accent: isGranted ? AppColors.good : AppColors.caution,
            child: Row(
              children: [
                Icon(
                  isGranted
                      ? Icons.check_circle_rounded
                      : Icons.lock_outline_rounded,
                  size: 20,
                  color: isGranted ? AppColors.good : AppColors.caution,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    isGranted
                        ? 'Permission granted. You are ready to scan.'
                        : 'Permission is not granted yet.',
                    style: AppTypography.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          if (!isGranted) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'ALLOW BLUETOOTH',
              icon: Icons.bluetooth_rounded,
              fullWidth: true,
              variant: AppButtonVariant.secondary,
              onPressed: () =>
                  ref.read(bluetoothPermissionProvider.notifier).request(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ControlsStep extends StatelessWidget {
  const _ControlsStep({required this.side, required this.onChanged});

  final JoystickSide side;
  final ValueChanged<JoystickSide> onChanged;

  @override
  Widget build(BuildContext context) {
    return _StepFrame(
      title: 'Which thumb drives?',
      body:
          'Driving happens in landscape. Put the stick under whichever thumb '
          'is free — the sensor readouts move to the other side so your hand '
          'never covers them.',
      child: Column(
        children: [
          Row(
            children: [
              for (final option in JoystickSide.values) ...[
                Expanded(
                  child: _SidePreview(
                    side: option,
                    isSelected: option == side,
                    onTap: () => onChanged(option),
                  ),
                ),
                if (option != JoystickSide.values.last)
                  const SizedBox(width: AppSpacing.md),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              const Icon(
                Icons.screen_rotation_rounded,
                size: 16,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'The drive screen rotates to landscape on its own and '
                  'returns to portrait when you leave.',
                  style: AppTypography.bodySmall.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Miniature of the drive HUD showing which side the stick lands on.
class _SidePreview extends StatelessWidget {
  const _SidePreview({
    required this.side,
    required this.isSelected,
    required this.onTap,
  });

  final JoystickSide side;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.accent : AppColors.border;

    final stick = Container(
      height: 30,
      width: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected
            ? AppColors.accent.withValues(alpha: 0.25)
            : AppColors.surfaceElevated,
        border: Border.all(
          color: isSelected ? AppColors.accent : AppColors.borderStrong,
        ),
      ),
    );
    final rail = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++) ...[
          Container(
            height: 4,
            width: 22,
            decoration: BoxDecoration(
              color: AppColors.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (i < 2) const SizedBox(height: 4),
        ],
      ],
    );

    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Joystick on the ${side.label.toLowerCase()}. ${side.description}',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: color, width: isSelected ? 1.5 : 1),
            ),
            child: Column(
              children: [
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(AppRadii.xs),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: side == JoystickSide.left
                        ? [stick, rail]
                        : [rail, stick],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  side.label,
                  style: AppTypography.labelStrong.copyWith(
                    fontSize: 11,
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SafetyStep extends StatelessWidget {
  const _SafetyStep();

  @override
  Widget build(BuildContext context) {
    return _StepFrame(
      title: 'Before you drive',
      body:
          'A rover with a dead radio link is a rover nobody is steering. These '
          'are the rules the app and the firmware hold between them.',
      child: Column(
        children: const [
          _SafetyPoint(
            icon: Icons.pan_tool_rounded,
            title: 'The stop button is always reachable',
            detail:
                'It sits in the corner of the drive screen, takes no '
                'confirmation, and latches until you release it.',
          ),
          _SafetyPoint(
            icon: Icons.timer_outlined,
            title: 'The vehicle stops itself',
            detail:
                'If commands stop arriving — app closed, phone locked, link '
                'dropped — the board cuts the motors on its own timeout. The '
                'phone is never the only thing keeping you safe.',
          ),
          _SafetyPoint(
            icon: Icons.visibility_rounded,
            title: 'Keep the rover in sight',
            detail:
                'Autonomous mode runs on the vehicle, not the phone. Watch it, '
                'and stay ready to stop it.',
          ),
        ],
      ),
    );
  }
}

class _SafetyPoint extends StatelessWidget {
  const _SafetyPoint({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 32,
              width: 32,
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadii.xs),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 16, color: AppColors.accent),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: AppTypography.bodySmall.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$title. $description',
      child: ExcludeSemantics(
        child: AppCard(
          onTap: onTap,
          accent: isSelected ? accent : null,
          borderColor: isSelected ? accent.withValues(alpha: 0.55) : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? accent.withValues(alpha: 0.16)
                      : AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: isSelected ? accent : AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTypography.titleMedium.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: AppTypography.bodySmall.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, size: 18, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
