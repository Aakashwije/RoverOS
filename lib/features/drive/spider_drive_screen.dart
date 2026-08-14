import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/connection_state.dart';
import '../../models/telemetry.dart';
import '../../services/haptics.dart';
import '../../services/spider_commands.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/app_slider.dart';
import '../../widgets/battery_indicator.dart';
import '../../widgets/connection_badge.dart';
import '../../widgets/feature_placeholder.dart';
import '../connection/connection_controller.dart';
import '../settings/settings_controller.dart';
import '../telemetry/telemetry_controller.dart';
import 'drive_controller.dart' show DriveArmState;
import 'spider_drive_controller.dart';
import 'widgets/direction_pad.dart';
import 'widgets/emergency_stop_button.dart';
import 'widgets/walking_indicator.dart';

/// Landscape driving HUD for the spiderbot.
///
/// Deliberately smaller than [DriveScreen][drive_screen.dart]: a direction
/// pad and a speed slider instead of a joystick, no lights/signals/radar —
/// the spiderbot has none of that hardware. Safety behaviour mirrors the car
/// exactly: entering forces landscape, leaving sends STOP, backgrounding
/// sends STOP, and a lost link clears the commanded direction.
class SpiderDriveScreen extends ConsumerStatefulWidget {
  const SpiderDriveScreen({super.key});

  @override
  ConsumerState<SpiderDriveScreen> createState() => _SpiderDriveScreenState();
}

class _SpiderDriveScreenState extends ConsumerState<SpiderDriveScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [SystemUiOverlay.top],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    ref.read(spiderDriveProvider.notifier).stop(reason: 'Left drive screen');

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    ref.read(spiderDriveProvider.notifier).stop(reason: 'App backgrounded');
  }

  void _onPress(WalkDirection direction) {
    Haptics.light(enabled: ref.read(settingsProvider).hapticsEnabled);
    ref.read(spiderDriveProvider.notifier).press(direction);
  }

  void _onRelease() {
    Haptics.selection(enabled: ref.read(settingsProvider).hapticsEnabled);
    ref.read(spiderDriveProvider.notifier).release();
  }

  Future<void> _onEmergencyStop() async {
    Haptics.emergency();
    await ref.read(spiderDriveProvider.notifier).emergencyStop();
  }

  void _onExit() =>
      context.canPop() ? context.pop() : context.go(AppRoute.home);

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(connectionProvider);
    final drive = ref.watch(spiderDriveProvider);
    final telemetry = ref.watch(telemetryProvider);
    final controller = ref.read(spiderDriveProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: link.isConnected
            ? Stack(
                children: [
                  Column(
                    children: [
                      _SpiderHudTopBar(
                        link: link,
                        drive: drive,
                        telemetry: telemetry,
                        onExit: _onExit,
                      ),
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              WalkingIndicator(direction: drive.direction),
                              const SizedBox(height: AppSpacing.lg),
                              DirectionPad(
                                activeDirection: drive.direction,
                                enabled: !drive.isEmergencyStopped,
                                onPress: _onPress,
                                onRelease: _onRelease,
                              ),
                              const SizedBox(height: AppSpacing.xxl),
                              SizedBox(
                                width: 260,
                                child: AppSlider(
                                  label: 'GAIT SPEED',
                                  leadingIcon: Icons.speed_rounded,
                                  value: drive.speedPercent.toDouble(),
                                  min: 20,
                                  max: 100,
                                  divisions: 16,
                                  unit: '%',
                                  onChanged: (value) =>
                                      controller.setSpeed(value.round()),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    right: AppSpacing.lg,
                    bottom: AppSpacing.lg,
                    child: EmergencyStopButton(
                      onPressed: _onEmergencyStop,
                      isStopped: drive.isEmergencyStopped,
                      onReset: drive.isEmergencyStopped
                          ? controller.clearEmergencyStop
                          : null,
                      compact: true,
                    ),
                  ),
                ],
              )
            : _DisconnectedSpiderDrive(link: link),
      ),
    );
  }
}

class _SpiderHudTopBar extends StatelessWidget {
  const _SpiderHudTopBar({
    required this.link,
    required this.drive,
    required this.telemetry,
    required this.onExit,
  });

  final LinkState link;
  final SpiderDriveState drive;
  final Telemetry telemetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.arrow_back_rounded,
            semanticLabel: 'Leave drive mode and stop the vehicle',
            tooltip: 'Exit and stop',
            size: 42,
            onPressed: onExit,
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              link.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleMedium.copyWith(fontSize: 15),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          ConnectionBadge(link: link, size: AppBadgeSize.small),
          const Spacer(),
          _ArmStatePill(state: drive.armState),
          const SizedBox(width: AppSpacing.md),
          BatteryIndicator(
            percent: telemetry.batteryPercent,
            style: BatteryIndicatorStyle.compact,
          ),
        ],
      ),
    );
  }
}

/// The one-word answer to "will this thing move if I hold a direction?".
/// Same visual language as the car HUD's arm pill, kept as its own tiny copy
/// here rather than shared — it is presentation only, and the two screens
/// must be free to diverge without one dragging the other along.
class _ArmStatePill extends StatelessWidget {
  const _ArmStatePill({required this.state});

  final DriveArmState state;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(state.level);

    return Semantics(
      liveRegion: true,
      label: '${state.label}. ${state.description}',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: AppDurations.fast,
          curve: AppDurations.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: AppRadii.pillRadius,
            border: Border.all(color: color.withValues(alpha: 0.55)),
            boxShadow: state == DriveArmState.armed
                ? AppShadows.glow(color, blur: 14, opacity: 0.30)
                : null,
          ),
          child: AnimatedSwitcher(
            duration: AppDurations.fast,
            switchInCurve: AppDurations.emphasized,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Row(
              key: ValueKey(state),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(state.icon, size: 13, color: color),
                const SizedBox(width: 5),
                Text(
                  state.label,
                  style: AppTypography.label.copyWith(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
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

class _DisconnectedSpiderDrive extends StatelessWidget {
  const _DisconnectedSpiderDrive({required this.link});

  final LinkState link;

  @override
  Widget build(BuildContext context) {
    final isRecovering = link.status.isBusy;

    return Stack(
      children: [
        FeaturePlaceholder(
          icon: isRecovering
              ? Icons.bluetooth_searching_rounded
              : Icons.bluetooth_disabled_rounded,
          title: isRecovering ? 'Reconnecting to the vehicle' : 'Link lost',
          message: isRecovering
              ? 'Hold on — restoring the link. The spiderbot has already '
                    'stopped itself via its safety timeout.'
              : 'The spiderbot stopped automatically when the link dropped. '
                    'Reconnect to keep driving.',
          actionLabel: isRecovering ? null : 'RECONNECT',
          onAction: isRecovering
              ? null
              : () => context.push(AppRoute.connect),
        ),
        Positioned(
          top: AppSpacing.md,
          left: AppSpacing.md,
          child: AppIconButton(
            icon: Icons.arrow_back_rounded,
            semanticLabel: 'Back',
            size: 42,
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(AppRoute.home),
          ),
        ),
      ],
    );
  }
}
