import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/commands.dart';
import '../../../models/settings.dart';
import '../../../models/telemetry.dart';

/// The three numbers worth reading before you drive: charge, clearance, mode.
///
/// Sits above the detailed vehicle card so the common question — "is it worth
/// picking the rover up?" — is answered without scrolling. Values dim when
/// telemetry is stale, matching the telemetry cards, so a still dashboard is
/// never mistaken for a live one.
class VitalsStrip extends StatelessWidget {
  const VitalsStrip({
    super.key,
    required this.telemetry,
    required this.settings,
    required this.driveMode,
    required this.isConnected,
  });

  final Telemetry telemetry;
  final AppSettings settings;
  final DriveMode driveMode;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final isStale = isConnected && telemetry.isStale();
    final battery = telemetry.batteryStatus;
    final distance = telemetry.distanceStatus(
      cautionCm: settings.cautionDistanceCm,
      dangerCm: settings.dangerDistanceCm,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _Vital(
            label: 'BATTERY',
            value: telemetry.batteryPercent?.toString() ?? '—',
            unit: '%',
            caption: isConnected ? battery.label : 'No link',
            icon: Icons.battery_5_bar_rounded,
            level: isConnected ? battery.level : StatusLevel.neutral,
            isStale: isStale,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _Vital(
            label: 'CLEARANCE',
            value: settings.units.format(telemetry.distanceCm),
            unit: settings.units.shortLabel,
            caption: isConnected ? distance.label : 'No link',
            icon: Icons.straighten_rounded,
            level: isConnected ? distance.level : StatusLevel.neutral,
            isStale: isStale,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _Vital(
            label: 'MODE',
            value: driveMode == DriveMode.manual ? 'MAN' : 'AUTO',
            caption: driveMode.label,
            icon: driveMode.isAutonomous
                ? Icons.auto_mode_rounded
                : Icons.sports_esports_rounded,
            level: driveMode.isAutonomous
                ? StatusLevel.info
                : StatusLevel.neutral,
            isStale: false,
            isCompactValue: true,
          ),
        ),
      ],
    );
  }
}

class _Vital extends StatelessWidget {
  const _Vital({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.level,
    required this.isStale,
    this.unit,
    this.isCompactValue = false,
  });

  final String label;
  final String value;
  final String? unit;
  final String caption;
  final IconData icon;
  final StatusLevel level;
  final bool isStale;

  /// Word-shaped values (MAN / AUTO) need a smaller size than numeric ones to
  /// survive a narrow phone column at large text scales.
  final bool isCompactValue;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(level);

    return Semantics(
      label: [
        label,
        isStale ? 'last known $value' : value,
        if (unit != null) unit,
        caption,
      ].join(' '),
      child: ExcludeSemantics(
        child: Opacity(
          opacity: isStale ? 0.55 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 13, color: color),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.label.copyWith(fontSize: 9),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.metricValue.copyWith(
                          fontSize: isCompactValue ? 18 : 22,
                        ),
                      ),
                    ),
                    if (unit != null) ...[
                      const SizedBox(width: 3),
                      Text(
                        unit!,
                        style: AppTypography.metricUnit.copyWith(fontSize: 11),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    fontSize: 8.5,
                    color: level == StatusLevel.neutral
                        ? AppColors.textTertiary
                        : color,
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
