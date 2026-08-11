import 'package:flutter/material.dart';

import '../../../core/perception/perception_engine.dart';
import '../../../core/perception/proximity_gate.dart';
import '../../../core/perception/radar_field.dart';
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
    this.perception,
  });

  final Telemetry telemetry;
  final AppSettings settings;
  final VehicleState vehicleState;
  final PerceptionSnapshot? perception;

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
    final hasPerception = perception?.hasData ?? false;
    final assessment = hasPerception ? perception?.proximity : null;
    final field = hasPerception ? perception?.field : null;
    final contactSeconds = assessment?.contactSeconds;

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
                  statusOverride: assessment?.status,
                  isUncertain:
                      assessment?.cause == ProximityCause.lowConfidence,
                  detail: contactSeconds == null
                      ? assessment?.confidence.label
                      : '${contactSeconds}s TTC',
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
          if (assessment != null || (field != null && field.hasData)) ...[
            _PerceptionReadout(
              assessment: assessment,
              field: field,
              settings: settings,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
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
    this.statusOverride,
    this.detail,
    this.isUncertain = false,
  });

  final String label;
  final int? distanceCm;
  final AppSettings settings;
  final DistanceStatus? statusOverride;
  final String? detail;

  /// The sensor is contradicting itself at this bearing. The number is muted
  /// and the word changes: a low-confidence distance is not a worse reading,
  /// it is no reading, and the panel has to say so rather than whisper it in
  /// the detail line.
  final bool isUncertain;

  @override
  Widget build(BuildContext context) {
    final status = isUncertain
        ? DistanceStatus.unknown
        : statusOverride ??
              DistanceStatus.fromDistance(
                distanceCm,
                cautionCm: settings.cautionDistanceCm,
                dangerCm: settings.dangerDistanceCm,
              );
    final color = isUncertain
        ? AppColors.caution
        : AppColors.forStatus(status.level);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.label.copyWith(fontSize: 9.5)),
        const SizedBox(height: 3),
        isUncertain
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  'UNRELIABLE',
                  style: AppTypography.metricValue.copyWith(
                    fontSize: 14,
                    color: color,
                    letterSpacing: 0.8,
                  ),
                ),
              )
            : Row(
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
                isUncertain ? 'UNRELIABLE' : status.label,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label.copyWith(color: color, fontSize: 9),
              ),
            ),
          ],
        ),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(
            detail!,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.label.copyWith(
              color: AppColors.textTertiary,
              fontSize: 8.5,
            ),
          ),
        ],
      ],
    );
  }
}

class _PerceptionReadout extends StatelessWidget {
  const _PerceptionReadout({
    required this.assessment,
    required this.field,
    required this.settings,
  });

  final ProximityAssessment? assessment;
  final FieldAnalysis? field;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final gap = field?.recommended;
    final surfaces =
        field?.surfaces
            .where((surface) => surface.kind != SurfaceKind.opening)
            .take(3)
            .toList(growable: false) ??
        const <RadarSurface>[];
    final level = assessment?.level ?? StatusLevel.info;
    final color = AppColors.forStatus(level);
    final confidence = assessment?.confidence;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_rounded, size: 15, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  assessment?.headline ?? 'PERCEPTION',
                  style: AppTypography.labelStrong.copyWith(
                    color: color,
                    fontSize: 11,
                  ),
                ),
              ),
              if (confidence != null)
                Text(
                  'CONF ${confidence.label}',
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 9,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            assessment?.detail ?? 'Advisory radar analysis from phone-side filtering',
            style: AppTypography.bodySmall.copyWith(fontSize: 11.5),
          ),
          if (gap != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _PerceptionLine(
              icon: Icons.navigation_rounded,
              text:
                  'Gap ${gap.describeRelativeTo(field?.referenceBearing ?? 90)} · '
                  '${gap.widthDegrees}° · ${settings.units.format(gap.clearanceCm)} '
                  '${settings.units.shortLabel} clear',
            ),
          ],
          if (surfaces.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final surface in surfaces)
                  _SurfaceChip(surface: surface, settings: settings),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PerceptionLine extends StatelessWidget {
  const _PerceptionLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppColors.info),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _SurfaceChip extends StatelessWidget {
  const _SurfaceChip({required this.surface, required this.settings});

  final RadarSurface surface;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.10),
        borderRadius: AppRadii.pillRadius,
        border: Border.all(color: AppColors.info.withValues(alpha: 0.28)),
      ),
      child: Text(
        '${surface.kind.label} ${surface.bearingDegrees}° · '
        '${settings.units.format(surface.nearestCm)}${settings.units.shortLabel}',
        style: AppTypography.label.copyWith(
          color: AppColors.textSecondary,
          fontSize: 8.5,
        ),
      ),
    );
  }
}
