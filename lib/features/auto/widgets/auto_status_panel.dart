import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/commands.dart';
import '../../../models/settings.dart';
import '../../../models/telemetry.dart';
import '../../../widgets/app_card.dart';

/// Live readout of what the vehicle's own autonomous logic is doing.
///
/// Every value here is reported by the ESP32, never decided by the phone — the
/// panel is a window onto firmware state, not a control surface.
class AutoStatusPanel extends StatelessWidget {
  const AutoStatusPanel({
    super.key,
    required this.telemetry,
    required this.settings,
    required this.vehicleState,
  });

  final Telemetry telemetry;
  final AppSettings settings;
  final VehicleState vehicleState;

  bool get _isActive =>
      vehicleState == VehicleState.avoiding ||
      vehicleState == VehicleState.scanning;

  @override
  Widget build(BuildContext context) {
    final level = switch (vehicleState) {
      VehicleState.fault => StatusLevel.danger,
      VehicleState.avoiding => StatusLevel.info,
      VehicleState.scanning => StatusLevel.info,
      VehicleState.driving => StatusLevel.good,
      _ => StatusLevel.neutral,
    };
    final color = AppColors.forStatus(level);

    return AppCard(
      elevated: true,
      accent: color,
      semanticLabel:
          'Autonomous mode. Vehicle is ${_isActive ? "active" : "idle"}. '
          '${telemetry.decision ?? "No decision reported"}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('AUTONOMOUS MODE', style: AppTypography.label),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: AppRadii.pillRadius,
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  vehicleState.label,
                  style: AppTypography.label.copyWith(
                    color: color,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _DistanceReadout(
                  label: 'FRONT',
                  distanceCm: telemetry.centerDistanceCm,
                  settings: settings,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _DistanceReadout(
                  label: 'LEFT',
                  distanceCm: telemetry.leftDistanceCm,
                  settings: settings,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _DistanceReadout(
                  label: 'RIGHT',
                  distanceCm: telemetry.rightDistanceCm,
                  settings: settings,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.psychology_outlined,
                  size: 15,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('DECISION', style: AppTypography.label),
                      const SizedBox(height: 2),
                      Text(
                        telemetry.decision ?? 'No decision reported yet',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DistanceReadout extends StatelessWidget {
  const _DistanceReadout({
    required this.label,
    required this.distanceCm,
    required this.settings,
  });

  final String label;
  final int? distanceCm;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final status = DistanceStatus.fromDistance(
      distanceCm,
      cautionCm: settings.cautionDistanceCm,
      dangerCm: settings.dangerDistanceCm,
    );
    final color = AppColors.forStatus(status.level);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.label.copyWith(fontSize: 9.5)),
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              settings.units.format(distanceCm),
              style: AppTypography.metricValue.copyWith(fontSize: 20),
            ),
            const SizedBox(width: 3),
            Text(
              settings.units.shortLabel,
              style: AppTypography.metricUnit.copyWith(fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(AppColors.iconForStatus(status.level), size: 10, color: color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                status.label,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label.copyWith(color: color, fontSize: 9),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
