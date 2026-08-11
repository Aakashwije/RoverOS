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
import '../perception/perception_controller.dart';
import '../settings/settings_controller.dart';
import '../telemetry/telemetry_controller.dart';
import 'drive_controller.dart';
import 'drive_hud_metrics.dart';
import 'widgets/distance_card.dart';
import 'widgets/emergency_stop_button.dart';
import 'widgets/light_controls.dart';
import 'widgets/motor_readout.dart';
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

  void _swapJoystickSide() {
    final controller = ref.read(settingsProvider.notifier);
    Haptics.selection(enabled: ref.read(settingsProvider).hapticsEnabled);
    controller.update((s) => s.copyWith(joystickSide: s.joystickSide.opposite));
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
          final perception = ref.watch(perceptionProvider);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadarView(
                telemetry: telemetry,
                settings: settings,
                size: 260,
                perception: perception,
                isSweeping: drive.scanMode == ScanMode.auto,
              ),
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
    final perception = ref.watch(perceptionProvider);

    // A tick when the commanded direction changes, so the driver feels the
    // vehicle switch from forward to a pivot without looking down. Deliberately
    // keyed on direction rather than on raw output: the ramp emits a new output
    // every 66ms, and buzzing at 15Hz would be noise, not information.
    ref.listen(driveProvider, (previous, next) {
      if (previous == null || previous.direction == next.direction) return;
      if (!next.acceptsInput) return;
      Haptics.selection(enabled: ref.read(settingsProvider).hapticsEnabled);
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: link.isConnected
            ? _DriveHud(
                link: link,
                drive: drive,
                telemetry: telemetry,
                settings: settings,
                perception: perception,
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
                onSwapSide: _swapJoystickSide,
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
            tooltip: 'Back',
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
/// Three columns: the stick with its motor readout, the speed gauge, and the
/// sensor rail. Which side the stick sits on follows
/// [AppSettings.joystickSide] — the whole row mirrors, so the driving hand
/// never covers the readouts whichever hand that is.
class _DriveHud extends StatelessWidget {
  const _DriveHud({
    required this.link,
    required this.drive,
    required this.telemetry,
    required this.settings,
    required this.perception,
    required this.onJoystick,
    required this.onJoystickReleased,
    required this.onEngaged,
    required this.onEmergencyStop,
    required this.onResetEmergency,
    required this.onOpenSpeed,
    required this.onOpenLights,
    required this.onOpenServo,
    required this.onLightMode,
    required this.onSwapSide,
    required this.onExit,
  });

  final LinkState link;
  final DriveState drive;
  final Telemetry telemetry;
  final AppSettings settings;
  final PerceptionSnapshot perception;
  final void Function(double x, double y) onJoystick;
  final VoidCallback onJoystickReleased;
  final VoidCallback onEngaged;
  final VoidCallback onEmergencyStop;
  final VoidCallback onResetEmergency;
  final VoidCallback onOpenSpeed;
  final VoidCallback onOpenLights;
  final VoidCallback onOpenServo;
  final ValueChanged<LightMode> onLightMode;
  final VoidCallback onSwapSide;
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

        final columns = <Widget>[
          _JoystickColumn(
            metrics: metrics,
            drive: drive,
            settings: settings,
            onJoystick: onJoystick,
            onJoystickReleased: onJoystickReleased,
            onEngaged: onEngaged,
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: SpeedIndicator(
                  speedPercent: drive.speedPercent,
                  output: drive.output,
                  size: metrics.gaugeSize,
                  isStopped: drive.isEmergencyStopped,
                  showMotorBars: false,
                ),
              ),
            ),
          ),
          SizedBox(
            width: metrics.railWidth,
            child: _SensorRail(
              telemetry: telemetry,
              settings: settings,
              drive: drive,
              perception: perception,
              onOpenServo: onOpenServo,
              onOpenSpeed: onOpenSpeed,
              onOpenLights: onOpenLights,
            ),
          ),
        ];

        return Column(
          children: [
            _HudTopBar(
              link: link,
              drive: drive,
              telemetry: telemetry,
              joystickSide: settings.joystickSide,
              onSwapSide: onSwapSide,
              onExit: onExit,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: settings.joystickSide == JoystickSide.right
                      ? columns.reversed.toList()
                      : columns,
                ),
              ),
            ),
            _HudBottomBar(
              drive: drive,
              onEmergencyStop: onEmergencyStop,
              onResetEmergency: onResetEmergency,
              onLightMode: onLightMode,
              mirrored: settings.joystickSide == JoystickSide.right,
            ),
          ],
        );
      },
    );
  }
}

class _JoystickColumn extends StatelessWidget {
  const _JoystickColumn({
    required this.metrics,
    required this.drive,
    required this.settings,
    required this.onJoystick,
    required this.onJoystickReleased,
    required this.onEngaged,
  });

  final DriveHudMetrics metrics;
  final DriveState drive;
  final AppSettings settings;
  final void Function(double x, double y) onJoystick;
  final VoidCallback onJoystickReleased;
  final VoidCallback onEngaged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: metrics.joystickSize,
      // The readout's intrinsic height follows the platform text scale, which
      // the layout maths cannot know in advance. Scaling the whole column down
      // to fit keeps large-text users on the same layout instead of trading
      // their accessibility setting for an overflow stripe.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: metrics.joystickSize,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VirtualJoystick(
                size: metrics.joystickSize,
                deadZoneFraction: settings.deadZoneFraction,
                enabled: drive.acceptsInput,
                disabledMessage: drive.isEmergencyStopped
                    ? 'EMERGENCY STOP ENGAGED'
                    : 'AUTONOMOUS MODE ACTIVE',
                onChanged: onJoystick,
                onReleased: onJoystickReleased,
                onEngaged: onEngaged,
              ),
              if (metrics.showMotorReadout) ...[
                const SizedBox(height: DriveHudMetrics.columnGap),
                MotorReadout(
                  output: drive.output,
                  enabled: drive.acceptsInput,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SensorRail extends StatelessWidget {
  const _SensorRail({
    required this.telemetry,
    required this.settings,
    required this.drive,
    required this.perception,
    required this.onOpenServo,
    required this.onOpenSpeed,
    required this.onOpenLights,
  });

  final Telemetry telemetry;
  final AppSettings settings;
  final DriveState drive;
  final PerceptionSnapshot perception;
  final VoidCallback onOpenServo;
  final VoidCallback onOpenSpeed;
  final VoidCallback onOpenLights;

  @override
  Widget build(BuildContext context) {
    // The rail stacks a distance card, a radar preview sized from the rail's
    // own width, and two 48dp buttons — comfortably more than a short
    // landscape phone has room for. Centring a scroll view keeps it centred
    // when it fits and scrollable when it does not, which is the only
    // arrangement that cannot overflow. A FittedBox is not an option here:
    // the radar preview measures itself with a LayoutBuilder, and a FittedBox
    // lays its child out unbounded.
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DistanceCard(
              distanceCm: telemetry.distanceCm,
              settings: settings,
              isStale: telemetry.isStale(),
              compact: true,
              proximity: perception.hasData ? perception.proximity : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _RadarPreviewCard(
              telemetry: telemetry,
              settings: settings,
              perception: perception,
              isSweeping: drive.scanMode == ScanMode.auto,
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
    );
  }
}

class _HudTopBar extends StatelessWidget {
  const _HudTopBar({
    required this.link,
    required this.drive,
    required this.telemetry,
    required this.joystickSide,
    required this.onSwapSide,
    required this.onExit,
  });

  final LinkState link;
  final DriveState drive;
  final Telemetry telemetry;
  final JoystickSide joystickSide;
  final VoidCallback onSwapSide;
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
          AppIconButton(
            icon: Icons.swap_horiz_rounded,
            semanticLabel:
                'Joystick is on the ${joystickSide.label.toLowerCase()}. '
                'Activate to move it to the '
                '${joystickSide.opposite.label.toLowerCase()}.',
            tooltip: 'Move joystick to the '
                '${joystickSide.opposite.label.toLowerCase()}',
            size: 42,
            onPressed: onSwapSide,
          ),
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

/// The one-word answer to "will this thing move if I push the stick?".
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
          child: Row(
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small radar preview for the sensor rail. Tapping it opens the full servo
/// and radar sheet — kept out of the main HUD so Drive stays uncluttered, per
/// the servo/radar being a lower control priority than joystick, speed and
/// lights.
class _RadarPreviewCard extends StatelessWidget {
  const _RadarPreviewCard({
    required this.telemetry,
    required this.settings,
    required this.perception,
    required this.isSweeping,
    required this.onOpenServo,
  });

  final Telemetry telemetry;
  final AppSettings settings;
  final PerceptionSnapshot perception;
  final bool isSweeping;
  final VoidCallback onOpenServo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          'Servo and radar preview. Servo at ${telemetry.servoAngle ?? 90} degrees. '
          'Opens manual servo control.',
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'Servo and radar',
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
                      perception: perception,
                      isSweeping: isSweeping,
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
          tooltip: 'Speed limit — ${drive.speedPercent}%',
          size: 48,
          onPressed: onOpenSpeed,
        ),
        const SizedBox(width: AppSpacing.sm),
        AppIconButton(
          icon: drive.lightMode.isEmitting
              ? Icons.lightbulb_rounded
              : Icons.lightbulb_outline_rounded,
          semanticLabel: 'Lighting, currently ${drive.lightMode.label}',
          tooltip: 'Lighting — ${drive.lightMode.label}',
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
    required this.mirrored,
  });

  final DriveState drive;
  final VoidCallback onEmergencyStop;
  final VoidCallback onResetEmergency;
  final ValueChanged<LightMode> onLightMode;

  /// Keeps the stop zone under the free hand: it sits opposite the joystick,
  /// so the thumb that is not driving is the one that reaches it.
  final bool mirrored;

  /// Only three light modes reach the HUD; the flash rates live in the sheet.
  /// Five 48dp buttons plus a horn plus the stop zone does not fit across a
  /// 480dp landscape phone, and silently overflowing is worse than choosing.
  static const List<LightMode> _hudLightModes = [
    LightMode.off,
    LightMode.on,
    LightMode.hazard,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A third of the bar, floored at a width that still fits the words
          // "EMERGENCY STOP" without ellipsis.
          final stopWidth = (constraints.maxWidth * 0.34).clamp(184.0, 320.0);

          // Scaled down rather than clipped if the stop zone leaves less than
          // the buttons' natural width. These are fixed-size icon buttons with
          // no internal measurement, so shrinking them is safe — and a
          // slightly smaller lights row is a far better outcome than an
          // overflow stripe across the bottom of a driving screen.
          final controls = Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: mirrored
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LightControls(
                    mode: drive.lightMode,
                    compact: true,
                    visibleModes: _hudLightModes,
                    onChanged: onLightMode,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Reserved for a horn/buzzer. The Optimus board in this
                  // build has no buzzer wired up, so the control is present
                  // but disabled rather than sending a command the firmware
                  // cannot act on.
                  const AppIconButton(
                    icon: Icons.campaign_outlined,
                    semanticLabel: 'Horn. Not supported by this vehicle.',
                    tooltip: 'No horn on this vehicle',
                    size: 48,
                    onPressed: null,
                  ),
                ],
              ),
            ),
          );

          final stop = SizedBox(
            width: stopWidth,
            child: EmergencyStopButton(
              height: DriveHudMetrics.emergencyStopHeight,
              compact: true,
              isStopped: drive.isEmergencyStopped,
              onPressed: onEmergencyStop,
              onReset: onResetEmergency,
            ),
          );

          return Row(
            children: mirrored
                ? [stop, const SizedBox(width: AppSpacing.lg), controls]
                : [controls, const SizedBox(width: AppSpacing.lg), stop],
          );
        },
      ),
    );
  }
}
