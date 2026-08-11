import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/providers/app_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/session_log.dart';
import '../../models/commands.dart';
import '../../models/connection_state.dart';
import '../../models/settings.dart';
import '../../models/telemetry.dart';
import '../../widgets/animated_reveal.dart';
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
import 'telemetry_history.dart';
import 'widgets/trend_card.dart';

/// Full telemetry dashboard: every value the vehicle reports, plus the health
/// of the link carrying them, plus where each has been heading.
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

  Future<void> _shareSessionLog() async {
    final log = SessionLog.build(
      history: ref.read(telemetryHistoryProvider),
      activity: ref.read(activityLogProvider),
      now: DateTime.now(),
    );

    // Nothing captured yet: fall back to the clipboard rather than handing the
    // share sheet an empty file, and say so.
    if (log.trim().isEmpty) {
      await Clipboard.setData(const ClipboardData(text: 'No data recorded.'));
      return;
    }

    await SharePlus.instance.share(
      ShareParams(text: log, subject: 'ROVEROS session log'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(connectionProvider);
    final telemetry = ref.watch(telemetryProvider);
    final settings = ref.watch(settingsProvider);
    final history = ref.watch(telemetryHistoryProvider);
    final lastAck = ref.watch(lastAckProvider);
    final error = ref.watch(vehicleErrorProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        // A tab root, not a pushed page — there is nothing behind it to go
        // back to.
        automaticallyImplyLeading: false,
        title: const Text('TELEMETRY', style: AppTypography.labelStrong),
        actions: [
          AppIconButton(
            icon: Icons.ios_share_rounded,
            semanticLabel: 'Share session log',
            tooltip: 'Share session log',
            size: 40,
            onPressed: _shareSessionLog,
          ),
          const SizedBox(width: AppSpacing.sm),
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
                history: history,
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
    required this.history,
    required this.lastAck,
    required this.error,
    required this.onDismissError,
  });

  final Telemetry telemetry;
  final AppSettings settings;
  final LinkState link;
  final TelemetryHistory history;
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

    return PageConstraints(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: [
          AnimatedReveal(
            child: error == null
                ? null
                : _ErrorCard(
                    key: ValueKey(error!.code),
                    error: error!,
                    onDismiss: onDismissError,
                  ),
          ),
          AnimatedReveal(
            child: link.status == ConnectionStatus.reconnecting
                ? _ReconnectingBanner(
                    key: const ValueKey('reconnecting'),
                    link: link,
                  )
                : null,
          ),
          AnimatedReveal(
            child: isStale && link.isConnected
                ? const _StaleBanner(key: ValueKey('stale'))
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            elevated: true,
            child: BatteryIndicator(percent: telemetry.batteryPercent),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _TrendsSection(
            telemetry: telemetry,
            settings: settings,
            link: link,
            history: history,
            isStale: isStale,
          ),
          const SizedBox(height: AppSpacing.xxl),
          // Two-up on a phone becomes four-up on a tablet via _MetricGrid, and
          // the DRIVE and SENSORS blocks sit side by side rather than stacking
          // into a column of half-empty rows.
          TwoPane(
            primaryFlex: 1,
            secondaryFlex: 1,
            primary: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
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
                      value: (telemetry.driveMode ?? settings.defaultDriveMode)
                          .label,
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
              ],
            ),
            secondary: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SectionHeader(
                  title: 'SENSORS',
                  icon: Icons.sensors_rounded,
                ),
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
              ],
            ),
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
      ),
    );
  }
}

/// Sparklines for the four series worth watching over time.
class _TrendsSection extends StatelessWidget {
  const _TrendsSection({
    required this.telemetry,
    required this.settings,
    required this.link,
    required this.history,
    required this.isStale,
  });

  final Telemetry telemetry;
  final AppSettings settings;
  final LinkState link;
  final TelemetryHistory history;
  final bool isStale;

  String get _spanCaption {
    final span = history.span;
    if (span == null) return 'Recording…';
    if (span.inMinutes < 1) return 'Last ${span.inSeconds}s';
    return 'Last ${span.inMinutes}m';
  }

  String get _batteryCaption {
    final delta = history.batteryDelta;
    if (delta == null) return _spanCaption;
    if (delta >= -0.5 && delta <= 0.5) return 'Steady · $_spanCaption';
    final direction = delta < 0 ? 'Down' : 'Up';
    return '$direction ${delta.abs().round()}% · $_spanCaption';
  }

  @override
  Widget build(BuildContext context) {
    final distanceStatus = telemetry.distanceStatus(
      cautionCm: settings.cautionDistanceCm,
      dangerCm: settings.dangerDistanceCm,
    );
    final outputPercent = history.samples.isEmpty
        ? null
        : history.samples.last.outputPercent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeader(
          title: 'TRENDS',
          icon: Icons.show_chart_rounded,
          subtitle: history.isEmpty
              ? 'Trends build while the vehicle is connected'
              : 'Sampled every 5 seconds · $_spanCaption',
        ),
        _MetricGrid(
          children: [
            TrendCard(
              label: 'BATTERY DRAIN',
              value: telemetry.batteryPercent?.toString() ?? '—',
              unit: '%',
              icon: Icons.battery_5_bar_rounded,
              level: telemetry.batteryStatus.level,
              // Pinned to the full scale: a pack sitting between 78% and 81%
              // should look flat, not like a cliff edge.
              minValue: 0.0,
              maxValue: 100.0,
              values: history.battery,
              caption: _batteryCaption,
              isStale: isStale,
            ),
            TrendCard(
              label: 'SIGNAL',
              value: link.rssi?.toString() ?? '—',
              unit: 'dBm',
              icon: Icons.settings_input_antenna_rounded,
              level: link.signal.level,
              minValue: 0.0,
              maxValue: 100.0,
              values: history.signal,
              caption: 'Link quality · ${link.signal.label}',
            ),
            TrendCard(
              label: 'DISTANCE',
              value: settings.units.format(telemetry.distanceCm),
              unit: settings.units.shortLabel,
              icon: Icons.straighten_rounded,
              level: distanceStatus.level,
              // Free scale: what counts as near depends on where the rover is,
              // so the interesting detail is the shape, not the absolute band.
              values: history.distance,
              caption: distanceStatus.description,
              isStale: isStale,
            ),
            TrendCard(
              label: 'MOTOR OUTPUT',
              value: outputPercent?.round().toString() ?? '—',
              unit: '%',
              icon: Icons.speed_rounded,
              level: StatusLevel.info,
              minValue: 0.0,
              maxValue: 100.0,
              values: history.output,
              caption: 'Mean of both sides',
              isStale: isStale,
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
        const spacing = AppSpacing.md;
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
  const _ErrorCard({super.key, required this.error, required this.onDismiss});

  final RoverError error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        accent: AppColors.danger,
        borderColor: AppColors.danger.withValues(alpha: 0.45),
        semanticLabel: '${error.code.name}. ${error.message}',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.dangerous_rounded,
              size: 20,
              color: AppColors.danger,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          error.code.name.toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelStrong.copyWith(
                            color: AppColors.danger,
                          ),
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
              tooltip: 'Dismiss',
              size: 32,
              iconSize: 16,
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner({super.key, required this.link});

  final LinkState link;

  @override
  Widget build(BuildContext context) {
    final secondsLeft = link.nextReconnectAt == null
        ? null
        : secondsRemaining(link.nextReconnectAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
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
                    : 'Reconnecting — attempt ${link.reconnectAttempt}, '
                          'next try in ${secondsLeft}s',
                style: AppTypography.bodySmall.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
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
      ),
    );
  }
}
