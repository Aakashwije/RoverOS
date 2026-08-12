import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/commands.dart';
import '../../services/haptics.dart';
import '../../widgets/animated_reveal.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_modal.dart';
import '../../widgets/app_segmented_control.dart';
import '../../widgets/feature_placeholder.dart';
import '../../widgets/section_header.dart';
import '../connection/connection_controller.dart';
import '../drive/drive_controller.dart';
import '../drive/widgets/emergency_stop_button.dart';
import '../perception/perception_controller.dart';
import '../settings/settings_controller.dart';
import '../telemetry/telemetry_controller.dart';
import 'auto_behaviour.dart';
import 'widgets/auto_status_panel.dart';
import 'widgets/decision_readout.dart';
import 'widgets/radar_view.dart';
import 'widgets/servo_control.dart';

/// Autonomous mode: mode selection, live radar and the vehicle's own reported
/// decisions. The phone never decides where the vehicle goes — it only names a
/// firmware behaviour and displays what came back.
class AutoScreen extends ConsumerStatefulWidget {
  const AutoScreen({super.key});

  @override
  ConsumerState<AutoScreen> createState() => _AutoScreenState();
}

class _AutoScreenState extends ConsumerState<AutoScreen> {
  /// The fault that stood the vehicle down, kept on screen until the user
  /// acknowledges it. Without this the only evidence of a fail-safe is the
  /// segmented control quietly flipping back to MANUAL, which reads as if
  /// the user pressed it themselves.
  RoverError? _standDownFault;

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(connectionProvider);

    // Fail-safe: a sensor or motor fault reported while driving autonomously
    // must drop the vehicle back to manual, not leave it navigating blind.
    ref.listen(vehicleErrorProvider, (previous, next) {
      if (next == null || !next.isFailSafe) return;
      final drive = ref.read(driveProvider);
      if (!drive.driveMode.isAutonomous) return;
      ref.read(driveProvider.notifier).setDriveMode(DriveMode.manual);
      // The driver is watching the rover, not the phone — the stop has to be
      // felt, and the reason has to be on screen when they look down.
      Haptics.medium(enabled: ref.read(settingsProvider).hapticsEnabled);
      setState(() => _standDownFault = next);
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('AUTONOMOUS', style: AppTypography.labelStrong),
      ),
      body: SafeArea(
        top: false,
        child: link.isConnected
            ? _AutoBody(
                standDownFault: _standDownFault,
                onAcknowledgeFault: () =>
                    setState(() => _standDownFault = null),
              )
            : FeaturePlaceholder(
                icon: Icons.auto_mode_rounded,
                title: 'No vehicle connected',
                message:
                    'Autonomous mode runs on the vehicle. Connect to it to choose a '
                    'behaviour and watch its decisions.',
                actionLabel: 'CONNECT VEHICLE',
                onAction: () => context.push(AppRoute.connect),
              ),
      ),
    );
  }
}

class _AutoBody extends ConsumerWidget {
  const _AutoBody({
    required this.standDownFault,
    required this.onAcknowledgeFault,
  });

  final RoverError? standDownFault;
  final VoidCallback onAcknowledgeFault;

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    AutoBehaviour behaviour,
  ) async {
    final controller = ref.read(driveProvider.notifier);
    Haptics.selection(enabled: ref.read(settingsProvider).hapticsEnabled);

    switch (behaviour) {
      case AutoBehaviour.manual:
        await _standDown(ref);

      case AutoBehaviour.avoid:
        final confirmed = await AppModal.confirm(
          context,
          title: 'Start autonomous driving?',
          message:
              'The vehicle will drive itself using onboard obstacle avoidance. '
              'Keep it in view and stay ready to press STOP.',
          confirmLabel: 'START',
          level: StatusLevel.caution,
          icon: Icons.auto_mode_rounded,
        );
        if (!confirmed) return;
        await controller.setDriveMode(DriveMode.obstacleAvoidance);

      case AutoBehaviour.scan:
        // Scanning sweeps the servo with the chassis still, so any driving
        // behaviour has to be handed back first.
        await controller.setDriveMode(DriveMode.manual);
        controller.setScanMode(ScanMode.auto);
    }
  }

  /// The single "everything off" path, shared by the segmented control and the
  /// persistent stop button so they cannot leave different residue behind.
  Future<void> _standDown(WidgetRef ref) async {
    final controller = ref.read(driveProvider.notifier);
    await controller.setDriveMode(DriveMode.manual);
    controller.setScanMode(ScanMode.off);
    await controller.stop(reason: 'Autonomous stop');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drive = ref.watch(driveProvider);
    final telemetry = ref.watch(telemetryProvider);
    final settings = ref.watch(settingsProvider);
    final perception = ref.watch(perceptionProvider);
    final vehicleState = telemetry.vehicleState ?? VehicleState.idle;
    final behaviour = AutoBehaviour.of(drive.driveMode, drive.scanMode);
    final isSweeping =
        behaviour == AutoBehaviour.scan || behaviour == AutoBehaviour.avoid;

    final radar = AppCard(
      child: Center(
        // Sized from the card's own available width so it never overflows
        // on a narrow phone, and never grows past a sensible cap on a
        // tablet.
        child: LayoutBuilder(
          builder: (context, constraints) => RadarView(
            telemetry: telemetry,
            settings: settings,
            size: constraints.maxWidth.clamp(200.0, 340.0),
            isSweeping: isSweeping,
            perception: perception,
          ),
        ),
      ),
    );

    return Column(
      children: [
        Expanded(
          child: PageConstraints(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              children: [
                AnimatedReveal(
                  child: standDownFault == null
                      ? null
                      : Padding(
                          key: ValueKey(standDownFault!.receivedAt),
                          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                          child: _StandDownBanner(
                            fault: standDownFault!,
                            onAcknowledge: onAcknowledgeFault,
                          ),
                        ),
                ),
                DecisionReadout(
                  telemetry: telemetry,
                  behaviour: behaviour,
                  vehicleState: vehicleState,
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSegmentedControl<AutoBehaviour>(
                  value: behaviour,
                  accent: AppColors.info,
                  options: [
                    for (final option in AutoBehaviour.values)
                      SegmentOption(
                        value: option,
                        label: option.label,
                        icon: option.icon,
                        semanticHint: option.requiresConfirmation
                            ? '${option.description} Requires confirmation.'
                            : option.description,
                      ),
                  ],
                  onChanged: (value) => _select(context, ref, value),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  behaviour.description,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(fontSize: 12),
                ),
                const SizedBox(height: AppSpacing.xxl),
                TwoPane(
                  primaryFlex: 1,
                  secondaryFlex: 1,
                  primary: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SectionHeader(
                        title: 'RADAR',
                        icon: Icons.radar_rounded,
                      ),
                      radar,
                    ],
                  ),
                  secondary: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SectionHeader(
                        title: 'CLEARANCE',
                        icon: Icons.sensors_rounded,
                      ),
                      AutoStatusPanel(
                        telemetry: telemetry,
                        settings: settings,
                        vehicleState: vehicleState,
                        perception: perception,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                const SectionHeader(
                  title: 'SERVO',
                  icon: Icons.rotate_right_rounded,
                  subtitle: 'Manual control is available only in MANUAL mode',
                ),
                AppCard(
                  child: ServoControl(
                    currentAngle: telemetry.servoAngle ?? 90,
                    scanMode: drive.scanMode,
                    enabled: drive.driveMode == DriveMode.manual,
                    onAngleChanged: (angle) =>
                        ref.read(driveProvider.notifier).setServoAngle(angle),
                    onScanModeChanged: (mode) =>
                        ref.read(driveProvider.notifier).setScanMode(mode),
                  ),
                ),
              ],
            ),
          ),
        ),
        _StopBar(
          isActive: behaviour != AutoBehaviour.manual,
          onStop: () {
            Haptics.emergency();
            _standDown(ref);
          },
        ),
      ],
    );
  }
}

/// One-shot explanation shown after the fail-safe fires. Stays until
/// dismissed: the user must acknowledge that *the vehicle* ended autonomous
/// driving, not them.
class _StandDownBanner extends StatelessWidget {
  const _StandDownBanner({required this.fault, required this.onAcknowledge});

  final RoverError fault;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
        boxShadow: AppShadows.glow(AppColors.danger, blur: 18, opacity: 0.18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.report_problem_rounded,
                size: 18,
                color: AppColors.danger,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'RETURNED TO MANUAL',
                  style: AppTypography.labelStrong.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The vehicle reported a fault (${fault.message}) and autonomous '
            'driving was stopped for you.',
            style: AppTypography.bodySmall.copyWith(fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onAcknowledge,
              child: Text(
                'UNDERSTOOD',
                style: AppTypography.label.copyWith(color: AppColors.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Always-visible stop.
///
/// Pinned rather than parked at the end of the list on purpose: the moment you
/// need it is the moment you are watching the rover, not the phone, and
/// hunting for a scrolled-away button is not a recovery plan. It stays enabled
/// even when nothing is running — a stop control that greys out is one you
/// have to think about before trusting.
class _StopBar extends StatelessWidget {
  const _StopBar({required this.isActive, required this.onStop});

  final bool isActive;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: AppShadows.raised,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isActive ? 'VEHICLE IS DRIVING ITSELF' : 'VEHICLE IDLE',
                      style: AppTypography.labelStrong.copyWith(
                        fontSize: 11,
                        color: isActive
                            ? AppColors.info
                            : AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Keep it in sight',
                      style: AppTypography.bodySmall.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              EmergencyStopButton(
                compact: true,
                isStopped: false,
                onPressed: onStop,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
