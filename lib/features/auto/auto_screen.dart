import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/commands.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_modal.dart';
import '../../widgets/feature_placeholder.dart';
import '../../widgets/section_header.dart';
import '../connection/connection_controller.dart';
import '../drive/drive_controller.dart';
import '../settings/settings_controller.dart';
import '../telemetry/telemetry_controller.dart';
import 'widgets/auto_status_panel.dart';
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
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('AUTONOMOUS', style: AppTypography.labelStrong),
      ),
      body: SafeArea(
        top: false,
        child: link.isConnected
            ? const _AutoBody()
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
  const _AutoBody();

  Future<void> _requestObstacleAvoidance(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await AppModal.confirm(
      context,
      title: 'Start autonomous driving?',
      message:
          'The vehicle will drive itself using onboard obstacle avoidance. Keep '
          'it in view and stay ready to press STOP.',
      confirmLabel: 'START',
      level: StatusLevel.caution,
      icon: Icons.auto_mode_rounded,
    );
    if (!confirmed) return;
    await ref
        .read(driveProvider.notifier)
        .setDriveMode(DriveMode.obstacleAvoidance);
  }

  Future<void> _stopEverything(WidgetRef ref) async {
    final controller = ref.read(driveProvider.notifier);
    await controller.setDriveMode(DriveMode.manual);
    controller.setScanMode(ScanMode.off);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drive = ref.watch(driveProvider);
    final telemetry = ref.watch(telemetryProvider);
    final settings = ref.watch(settingsProvider);
    final vehicleState = telemetry.vehicleState ?? VehicleState.idle;
    final isAvoiding = drive.driveMode == DriveMode.obstacleAvoidance;
    final isScanning = drive.scanMode == ScanMode.auto;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      children: [
        const SectionHeader(title: 'BEHAVIOUR', icon: Icons.tune_rounded),
        _ModeSelector(
          driveMode: drive.driveMode,
          isScanning: isScanning,
          onManual: () => _stopEverything(ref),
          onObstacleAvoidance: () => _requestObstacleAvoidance(context, ref),
          onAutoScan: () {
            ref
                .read(driveProvider.notifier)
                .setScanMode(isScanning ? ScanMode.off : ScanMode.auto);
          },
        ),
        const SizedBox(height: AppSpacing.xxl),
        AutoStatusPanel(
          telemetry: telemetry,
          settings: settings,
          vehicleState: vehicleState,
        ),
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(title: 'RADAR', icon: Icons.radar_rounded),
        AppCard(
          child: Center(
            // Sized from the card's own available width so it never overflows
            // on a narrow phone, and never grows past a sensible cap on a
            // tablet.
            child: LayoutBuilder(
              builder: (context, constraints) => RadarView(
                telemetry: telemetry,
                settings: settings,
                size: constraints.maxWidth.clamp(200.0, 340.0),
              ),
            ),
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
        const SizedBox(height: AppSpacing.xxl),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'START',
                icon: Icons.play_arrow_rounded,
                onPressed: isAvoiding
                    ? null
                    : () => _requestObstacleAvoidance(context, ref),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppButton(
                label: 'PAUSE',
                icon: Icons.pause_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: isAvoiding
                    ? () => ref
                          .read(driveProvider.notifier)
                          .setDriveMode(DriveMode.manual)
                    : null,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppButton(
                label: 'STOP',
                icon: Icons.stop_rounded,
                variant: AppButtonVariant.danger,
                onPressed: (isAvoiding || isScanning)
                    ? () => _stopEverything(ref)
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.driveMode,
    required this.isScanning,
    required this.onManual,
    required this.onObstacleAvoidance,
    required this.onAutoScan,
  });

  final DriveMode driveMode;
  final bool isScanning;
  final VoidCallback onManual;
  final VoidCallback onObstacleAvoidance;
  final VoidCallback onAutoScan;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ModeCard(
          title: 'MANUAL',
          description: 'You are driving. Autonomous behaviours are off.',
          icon: Icons.sports_esports_rounded,
          isActive: driveMode == DriveMode.manual && !isScanning,
          onTap: onManual,
        ),
        const SizedBox(height: AppSpacing.sm),
        _ModeCard(
          title: 'OBSTACLE AVOIDANCE',
          description:
              'The vehicle drives and steers around obstacles on its own.',
          icon: Icons.auto_mode_rounded,
          isActive: driveMode == DriveMode.obstacleAvoidance,
          accent: AppColors.info,
          requiresConfirmation: true,
          onTap: onObstacleAvoidance,
        ),
        const SizedBox(height: AppSpacing.sm),
        _ModeCard(
          title: 'AUTO SCAN',
          description:
              'Sweeps the servo and maps distances. The chassis stays still.',
          icon: Icons.radar_rounded,
          isActive: isScanning,
          accent: AppColors.info,
          onTap: onAutoScan,
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.accent = AppColors.accent,
    this.requiresConfirmation = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool isActive;
  final Color accent;
  final bool requiresConfirmation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isActive,
      label: requiresConfirmation
          ? '$title. $description. Requires confirmation to start.'
          : '$title. $description',
      child: ExcludeSemantics(
        child: AppCard(
          onTap: onTap,
          accent: isActive ? accent : null,
          borderColor: isActive ? accent.withValues(alpha: 0.5) : null,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: isActive
                      ? accent.withValues(alpha: 0.16)
                      : AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: isActive ? accent : AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: AppTypography.titleMedium.copyWith(
                            fontSize: 15,
                          ),
                        ),
                        if (requiresConfirmation) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.shield_outlined,
                            size: 12,
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: AppTypography.bodySmall.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isActive)
                Icon(Icons.check_circle_rounded, size: 18, color: accent)
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
