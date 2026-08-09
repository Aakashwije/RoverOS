import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/commands.dart';
import '../../models/connection_state.dart';
import '../../models/settings.dart';
import '../../models/telemetry.dart';
import '../../services/haptics.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/app_slider.dart';
import '../../widgets/battery_indicator.dart';
import '../../widgets/connection_badge.dart';
import '../../widgets/feature_placeholder.dart';
import '../auto/widgets/radar_view.dart';
import '../auto/widgets/servo_control.dart';
import '../connection/connection_controller.dart';
import '../settings/settings_controller.dart';
import '../telemetry/telemetry_controller.dart';
import 'drive_controller.dart';
import 'drive_hud_metrics.dart';
import 'widgets/distance_card.dart';
import 'widgets/emergency_stop_button.dart';
import 'widgets/light_controls.dart';
import 'widgets/speed_indicator.dart';
import 'widgets/virtual_joystick.dart';

/// Landscape driving HUD.
///
/// Safety behaviour concentrated here:
/// * entering forces landscape, leaving restores portrait;
/// * leaving the screen sends STOP;
/// * backgrounding the app sends STOP and then leans on the ESP32 watchdog;
/// * a lost link clears the commanded output rather than leaving it latched.
class DriveScreen extends ConsumerStatefulWidget {
  const DriveScreen({super.key});

  @override
  ConsumerState<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends ConsumerState<DriveScreen>
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

    // Leaving Drive always stops the vehicle. Fire-and-forget: the widget is
    // going away, and the firmware watchdog is the backstop if this never
    // reaches the radio.
    ref.read(driveProvider.notifier).stop(reason: 'Left drive screen');

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A backgrounded app must not leave the motors running. The send may not
    // complete if the process is suspended immediately — that is exactly what
    // the ESP32 timeout exists for.
    if (state == AppLifecycleState.resumed) return;
    ref.read(driveProvider.notifier).stop(reason: 'App backgrounded');
  }

  void _onJoystick(double x, double y) =>
      ref.read(driveProvider.notifier).updateJoystick(x: x, y: y);

  void _onJoystickReleased() =>
      ref.read(driveProvider.notifier).releaseJoystick();

  void _onEngaged() =>
      Haptics.light(enabled: ref.read(settingsProvider).hapticsEnabled);

  Future<void> _onEmergencyStop() async {
    Haptics.emergency();
    await ref.read(driveProvider.notifier).emergencyStop();
  }

  void _onLightMode(LightMode mode) {
    Haptics.light(enabled: ref.read(settingsProvider).hapticsEnabled);
    ref.read(driveProvider.notifier).setLightMode(mode);
  }

  void _openSpeedSheet() {
    AppBottomSheet.show<void>(
      context,
      title: 'Speed limit',
      subtitle: 'Caps every drive command sent to the vehicle',
      icon: Icons.speed_rounded,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final drive = ref.watch(driveProvider);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SpeedPresetRow(
                speedPercent: drive.speedPercent,
                onSelected: (percent) {
                  Haptics.selection(
                    enabled: ref.read(settingsProvider).hapticsEnabled,
                  );
                  ref.read(driveProvider.notifier).setSpeed(percent);
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              AppSlider(
                label: 'CUSTOM SPEED',
                value: drive.speedPercent.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                unit: '%',
                leadingIcon: Icons.tune_rounded,
                onChanged: (value) =>
                    ref.read(driveProvider.notifier).setSpeed(value.round()),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openLightSheet() {
    AppBottomSheet.show<void>(
      context,
      title: 'Lighting',
      subtitle: 'Flash timing runs on the vehicle, not the phone',
      icon: Icons.lightbulb_rounded,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) => LightControls(
          mode: ref.watch(driveProvider).lightMode,
          onChanged: (mode) {
            Haptics.light(enabled: ref.read(settingsProvider).hapticsEnabled);
            ref.read(driveProvider.notifier).setLightMode(mode);
          },
        ),
      ),
    );
  }

  void _openServoSheet() {
    AppBottomSheet.show<void>(
      context,
      title: 'Servo & radar',
      subtitle: 'Manual angle control is available in MANUAL mode',
      icon: Icons.radar_rounded,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final drive = ref.watch(driveProvider);
          final telemetry = ref.watch(telemetryProvider);
          final settings = ref.watch(settingsProvider);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadarView(telemetry: telemetry, settings: settings, size: 260),
              const SizedBox(height: AppSpacing.xl),
              ServoControl(
                currentAngle: telemetry.servoAngle ?? 90,
                scanMode: drive.scanMode,
                enabled: drive.driveMode == DriveMode.manual,
                onAngleChanged: (angle) =>
                    ref.read(driveProvider.notifier).setServoAngle(angle),
                onScanModeChanged: (mode) =>
                    ref.read(driveProvider.notifier).setScanMode(mode),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(connectionProvider);
    final drive = ref.watch(driveProvider);
    final telemetry = ref.watch(telemetryProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: link.isConnected
            ? _DriveHud(
                link: link,
                drive: drive,
                telemetry: telemetry,
                settings: settings,
                onJoystick: _onJoystick,
                onJoystickReleased: _onJoystickReleased,
                onEngaged: _onEngaged,
                onEmergencyStop: _onEmergencyStop,
                onResetEmergency: () =>
                    ref.read(driveProvider.notifier).clearEmergencyStop(),
                onOpenSpeed: _openSpeedSheet,
                onOpenLights: _openLightSheet,
                onOpenServo: _openServoSheet,
                onLightMode: _onLightMode,
                onExit: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoute.home),
              )
            : _DisconnectedDrive(link: link),
      ),
    );
  }
}

class _DisconnectedDrive extends StatelessWidget {
  const _DisconnectedDrive({required this.link});

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
              ? 'Hold on — restoring the link. The vehicle has already stopped '
                    'itself via its safety timeout.'
              : 'The vehicle stopped automatically when the link dropped. '
                    'Reconnect to keep driving.',
          actionLabel: isRecovering ? null : 'RECONNECT',
          onAction: isRecovering ? null : () => context.push(AppRoute.connect),
        ),
        Positioned(
          top: AppSpacing.md,
          left: AppSpacing.md,
          child: AppIconButton(
            icon: Icons.arrow_back_rounded,
            semanticLabel: 'Leave drive mode',
            size: 48,
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(AppRoute.home),
          ),
        ),
      ],
    );
  }
}

/// The live HUD.
///
/// Laid out with the joystick on the left, the speed gauge centred and sensor
/// data on the right, so the driving hand never covers the readouts.
class _DriveHud extends StatelessWidget {
  const _DriveHud({
    required this.link,
    required this.drive,
    required this.telemetry,
    required this.settings,
    required this.onJoystick,
    required this.onJoystickReleased,
    required this.onEngaged,
    required this.onEmergencyStop,
    required this.onResetEmergency,
    required this.onOpenSpeed,
    required this.onOpenLights,
    required this.onOpenServo,
    required this.onLightMode,
    required this.onExit,
  });

  final LinkState link;
  final DriveState drive;
  final Telemetry telemetry;
  final AppSettings settings;
  final void Function(double x, double y) onJoystick;
  final VoidCallback onJoystickReleased;
  final VoidCallback onEngaged;
  final VoidCallback onEmergencyStop;
  final VoidCallback onResetEmergency;
  final VoidCallback onOpenSpeed;
  final VoidCallback onOpenLights;
  final VoidCallback onOpenServo;
  final ValueChanged<LightMode> onLightMode;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Scale every control to the space actually available rather than
        // hardcoding sizes that break on small or tall screens. Height alone
        // is not enough here: on a narrow landscape phone (short-side widths
        // as low as ~480–568dp are still common), a height-only gauge size
        // can outgrow what's left after the joystick and the right rail claim
        // their share of the width, which is exactly the kind of overflow the
        // brief's "do not hardcode dimensions" rule exists to prevent.
        final metrics = DriveHudMetrics.compute(constraints.biggest);
        final railWidth = metrics.railWidth;
        final joystickSize = metrics.joystickSize;
        final gaugeSize = metrics.gaugeSize;

        return Column(
          children: [
            _HudTopBar(
              link: link,
              drive: drive,
              telemetry: telemetry,
              onExit: onExit,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    VirtualJoystick(
                      size: joystickSize,
                      deadZoneFraction: settings.deadZoneFraction,
                      enabled: drive.acceptsInput,
                      disabledMessage: drive.isEmergencyStopped
                          ? 'EMERGENCY STOP ENGAGED'
                          : 'AUTONOMOUS MODE ACTIVE',
                      onChanged: onJoystick,
                      onReleased: onJoystickReleased,
                      onEngaged: onEngaged,
                    ),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          child: SpeedIndicator(
                            speedPercent: drive.speedPercent,
                            output: drive.output,
                            size: gaugeSize,
                            isStopped: drive.isEmergencyStopped,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: railWidth,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DistanceCard(
                            distanceCm: telemetry.distanceCm,
                            settings: settings,
                            isStale: telemetry.isStale(),
                            compact: true,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _RadarPreviewCard(
                            telemetry: telemetry,
                            settings: settings,
                            onOpenServo: onOpenServo,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _QuickControls(
                            drive: drive,
                            onOpenSpeed: onOpenSpeed,
                            onOpenLights: onOpenLights,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _HudBottomBar(
              drive: drive,
              onEmergencyStop: onEmergencyStop,
              onResetEmergency: onResetEmergency,
              onLightMode: onLightMode,
            ),
          ],
        );
      },
    );
  }
}

class _HudTopBar extends StatelessWidget {
  const _HudTopBar({
    required this.link,
    required this.drive,
    required this.telemetry,
    required this.onExit,
  });

  final LinkState link;
  final DriveState drive;
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
          _ModePill(mode: drive.driveMode.label),
          const SizedBox(width: AppSpacing.lg),
          BatteryIndicator(
            percent: telemetry.batteryPercent,
            style: BatteryIndicatorStyle.compact,
          ),
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({required this.mode});

  final String mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: AppRadii.pillRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Text(mode, style: AppTypography.label.copyWith(fontSize: 9.5)),
    );
  }
}

/// Small radar preview for the right rail. Tapping it opens the full servo
/// and radar sheet — kept out of the main HUD so Drive stays uncluttered, per
/// the servo/radar being a lower control priority than joystick, speed and
/// lights.
class _RadarPreviewCard extends StatelessWidget {
  const _RadarPreviewCard({
    required this.telemetry,
    required this.settings,
    required this.onOpenServo,
  });

  final Telemetry telemetry;
  final AppSettings settings;
  final VoidCallback onOpenServo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          'Servo and radar preview. Servo at ${telemetry.servoAngle ?? 90} degrees. '
          'Opens manual servo control.',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onOpenServo,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sized from the rail's own width rather than a fixed pixel
                // value, so the preview never overflows a rail that has had
                // to shrink on a narrow landscape screen.
                LayoutBuilder(
                  builder: (context, constraints) => RadarView(
                    telemetry: telemetry,
                    settings: settings,
                    size: constraints.maxWidth,
                    compact: true,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'SERVO ${telemetry.servoAngle ?? 90}°',
                  style: AppTypography.label.copyWith(fontSize: 9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickControls extends StatelessWidget {
  const _QuickControls({
    required this.drive,
    required this.onOpenSpeed,
    required this.onOpenLights,
  });

  final DriveState drive;
  final VoidCallback onOpenSpeed;
  final VoidCallback onOpenLights;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AppIconButton(
          icon: Icons.speed_rounded,
          semanticLabel: 'Speed limit, currently ${drive.speedPercent} percent',
          tooltip: 'Speed',
          size: 48,
          onPressed: onOpenSpeed,
        ),
        const SizedBox(width: AppSpacing.sm),
        AppIconButton(
          icon: drive.lightMode.isEmitting
              ? Icons.lightbulb_rounded
              : Icons.lightbulb_outline_rounded,
          semanticLabel: 'Lighting, currently ${drive.lightMode.label}',
          tooltip: 'Lights',
          size: 48,
          isActive: drive.lightMode.isEmitting,
          activeColor: AppColors.headlight,
          onPressed: onOpenLights,
        ),
      ],
    );
  }
}

class _HudBottomBar extends StatelessWidget {
  const _HudBottomBar({
    required this.drive,
    required this.onEmergencyStop,
    required this.onResetEmergency,
    required this.onLightMode,
  });

  final DriveState drive;
  final VoidCallback onEmergencyStop;
  final VoidCallback onResetEmergency;
  final ValueChanged<LightMode> onLightMode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: LightControls(
              mode: drive.lightMode,
              compact: true,
              onChanged: onLightMode,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Reserved for a horn/buzzer. The Optimus board in this build has no
          // buzzer wired up, so the control is present but disabled rather than
          // sending a command the firmware cannot act on.
          const AppIconButton(
            icon: Icons.campaign_outlined,
            semanticLabel: 'Horn. Not supported by this vehicle.',
            tooltip: 'No horn on this vehicle',
            size: 48,
            onPressed: null,
          ),
          const SizedBox(width: AppSpacing.lg),
          EmergencyStopButton(
            compact: true,
            isStopped: drive.isEmergencyStopped,
            onPressed: onEmergencyStop,
            onReset: onResetEmergency,
          ),
        ],
      ),
    );
  }
}
