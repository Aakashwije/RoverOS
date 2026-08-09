import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/commands.dart';
import '../../models/connection_state.dart';
import '../../models/settings.dart';
import '../../models/telemetry.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/battery_indicator.dart';
import '../../widgets/connection_badge.dart';
import '../../widgets/feature_placeholder.dart';
import '../../widgets/section_header.dart';
import '../../widgets/telemetry_card.dart';
import '../connection/connection_controller.dart';
import '../settings/settings_controller.dart';
import 'telemetry_controller.dart';

/// Full telemetry dashboard: every value the vehicle reports, plus the health
/// of the link carrying them.
class TelemetryScreen extends ConsumerStatefulWidget {
  const TelemetryScreen({super.key});

  @override
  ConsumerState<TelemetryScreen> createState() => _TelemetryScreenState();
}

class _TelemetryScreenState extends ConsumerState<TelemetryScreen> {
  Timer? _stalenessTicker;

  @override
  void initState() {
    super.initState();
    // Telemetry only pushes an update when a frame arrives, so without a timer
    // a dropout would never visibly go "stale" — the last numbers would just
    // sit there looking current. This tick exists purely to re-evaluate that.
    _stalenessTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stalenessTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(connectionProvider);
    final telemetry = ref.watch(telemetryProvider);
    final settings = ref.watch(settingsProvider);
    final lastAck = ref.watch(lastAckProvider);
    final error = ref.watch(vehicleErrorProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoute.home),
        ),
        title: const Text('TELEMETRY', style: AppTypography.labelStrong),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Center(
              child: ConnectionBadge(link: link, size: AppBadgeSize.small),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: !link.isConnected && !telemetry.hasData
            ? FeaturePlaceholder(
                icon: Icons.insights_rounded,
                title: 'No telemetry yet',
                message:
                    'Connect to the vehicle to stream battery, distance, motor and '
                    'servo data.',
                actionLabel: 'CONNECT VEHICLE',
                onAction: () => context.push(AppRoute.connect),
              )
            : _TelemetryBody(
                telemetry: telemetry,
                settings: settings,
                link: link,
                lastAck: lastAck,
                error: error,
                onDismissError: () =>
                    ref.read(vehicleErrorProvider.notifier).dismiss(),
              ),
      ),
    );
  }
}

class _TelemetryBody extends StatelessWidget {
  const _TelemetryBody({
    required this.telemetry,
    required this.settings,
    required this.link,
    required this.lastAck,
    required this.error,
    required this.onDismissError,
  });

  final Telemetry telemetry;
  final AppSettings settings;
  final LinkState link;
  final CommandAck? lastAck;
  final RoverError? error;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final isStale = telemetry.isStale();
    final distanceStatus = telemetry.distanceStatus(
      cautionCm: settings.cautionDistanceCm,
      dangerCm: settings.dangerDistanceCm,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      children: [
        if (error != null) ...[
          _ErrorCard(error: error!, onDismiss: onDismissError),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (link.status == ConnectionStatus.reconnecting) ...[
          _ReconnectingBanner(link: link),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (isStale && link.isConnected) ...[
          const _StaleBanner(),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppCard(
          elevated: true,
          child: BatteryIndicator(percent: telemetry.batteryPercent),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(title: 'DRIVE', icon: Icons.speed_rounded),
        _MetricGrid(
          children: [
            TelemetryCard(
              label: 'MOTOR SPEED',
              value: telemetry.speedPercent?.toString() ?? '—',
              numericValue: telemetry.speedPercent?.toDouble(),
              unit: '%',
              icon: Icons.speed_rounded,
              level: StatusLevel.info,
              isStale: isStale,
            ),
            TelemetryCard(
              label: 'MODE',
              value: (telemetry.driveMode ?? settings.defaultDriveMode).label,
              icon: Icons.tune_rounded,
              level:
                  (telemetry.driveMode ?? settings.defaultDriveMode)
                      .isAutonomous
                  ? StatusLevel.info
                  : StatusLevel.neutral,
              isStale: isStale,
            ),
            TelemetryCard(
              label: 'LEFT MOTOR',
              value: formatSignedPercent(telemetry.leftMotor),
              statusLabel: formatMotorDirection(telemetry.leftMotor),
              icon: Icons.arrow_circle_left_outlined,
              level: StatusLevel.neutral,
              isStale: isStale,
            ),
            TelemetryCard(
              label: 'RIGHT MOTOR',
              value: formatSignedPercent(telemetry.rightMotor),
              statusLabel: formatMotorDirection(telemetry.rightMotor),
              icon: Icons.arrow_circle_right_outlined,
              level: StatusLevel.neutral,
              isStale: isStale,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(title: 'SENSORS', icon: Icons.sensors_rounded),
        _MetricGrid(
          children: [
            TelemetryCard(
              label: 'FRONT DISTANCE',
              value: settings.units.format(telemetry.distanceCm),
              numericValue: telemetry.distanceCm?.toDouble(),
              unit: settings.units.shortLabel,
              icon: Icons.straighten_rounded,
              level: distanceStatus.level,
              statusLabel: distanceStatus.label,
              isStale: isStale,
            ),
            TelemetryCard(
              label: 'SERVO',
              value: telemetry.servoAngle?.toString() ?? '—',
              numericValue: telemetry.servoAngle?.toDouble(),
              unit: '°',
              icon: Icons.rotate_right_rounded,
              level: StatusLevel.neutral,
              isStale: isStale,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(title: 'LINK', icon: Icons.bluetooth_rounded),
        _MetricGrid(
          children: [
            TelemetryCard(
              label: 'CONNECTION',
              value: link.status.label,
              icon: Icons.link_rounded,
              level: link.status.level,
              statusLabel: link.isMock ? 'MOCK VEHICLE' : null,
            ),
            TelemetryCard(
              label: 'SIGNAL',
              value: link.signal.label,
              icon: Icons.settings_input_antenna_rounded,
              level: link.signal.level,
              statusLabel: link.rssi == null ? null : '${link.rssi} dBm',
            ),
            TelemetryCard(
              label: 'LIGHTS',
              value: (telemetry.lightMode ?? LightMode.off).label,
              icon: Icons.light_mode_rounded,
              level: (telemetry.lightMode ?? LightMode.off).isEmitting
                  ? StatusLevel.caution
                  : StatusLevel.neutral,
              isStale: isStale,
            ),
            TelemetryCard(
              label: 'LAST ACK',
              value: lastAck?.verb ?? '—',
              icon: Icons.check_circle_outline_rounded,
              level: lastAck == null ? StatusLevel.neutral : StatusLevel.good,
              statusLabel: lastAck == null
                  ? 'No command acknowledged'
                  : formatRelativeTime(lastAck!.receivedAt),
            ),
            TelemetryCard(
              label: 'LINK UPTIME',
              value: link.uptime == null ? '—' : formatDuration(link.uptime!),
              icon: Icons.timer_outlined,
              level: StatusLevel.neutral,
              statusLabel: link.isConnected
                  ? 'Since connection'
                  : 'Not connected',
            ),
          ],
        ),
      ],
    );
  }
}

/// Two-up on phones, wider grids on tablets and landscape.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth ~/ 200;
        final effectiveColumns = columns.clamp(1, 4);
        final spacing = AppSpacing.md;
        final itemWidth =
            (constraints.maxWidth - spacing * (effectiveColumns - 1)) /
            effectiveColumns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onDismiss});

  final RoverError error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: AppColors.danger,
      borderColor: AppColors.danger.withValues(alpha: 0.45),
      semanticLabel: '${error.code.name}. ${error.message}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_rounded, size: 20, color: AppColors.danger),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      error.code.name.toUpperCase(),
                      style: AppTypography.labelStrong.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AppBadge(
                      label: 'CODE ${error.code.code}',
                      level: StatusLevel.danger,
                      showIcon: false,
                      size: AppBadgeSize.small,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(error.message, style: AppTypography.bodySmall),
                if (error.isFailSafe) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Autonomous mode drops to manual automatically on this error.',
                    style: AppTypography.bodySmall.copyWith(fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          AppIconButton(
            icon: Icons.close_rounded,
            semanticLabel: 'Dismiss error',
            size: 32,
            iconSize: 16,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner({required this.link});

  final LinkState link;

  @override
  Widget build(BuildContext context) {
    final secondsLeft = link.nextReconnectAt
        ?.difference(DateTime.now())
        .inSeconds
        .clamp(0, 999);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.10),
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.info,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              secondsLeft == null
                  ? 'Reconnecting — attempt ${link.reconnectAttempt}'
                  : 'Reconnecting — attempt ${link.reconnectAttempt}, next try in ${secondsLeft}s',
              style: AppTypography.bodySmall.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.caution.withValues(alpha: 0.10),
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.caution.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.history_toggle_off_rounded,
            size: 18,
            color: AppColors.caution,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'These readings are stale — the vehicle has stopped reporting.',
              style: AppTypography.bodySmall.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
