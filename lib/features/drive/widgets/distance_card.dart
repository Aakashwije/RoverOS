import 'package:flutter/material.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/settings.dart';
import '../../../models/telemetry.dart';
import '../../../widgets/app_card.dart';

/// Front ultrasonic readout.
///
/// Proximity is communicated four ways at once — number, status word, icon and
/// a fill bar — so a driver glancing down gets the state without decoding a
/// colour.
class DistanceCard extends StatelessWidget {
  const DistanceCard({
    super.key,
    required this.distanceCm,
    required this.settings,
    this.isStale = false,
    this.compact = false,
  });

  final int? distanceCm;
  final AppSettings settings;
  final bool isStale;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final status = DistanceStatus.fromDistance(
      distanceCm,
      cautionCm: settings.cautionDistanceCm,
      dangerCm: settings.dangerDistanceCm,
    );
    final color = AppColors.forStatus(status.level);
    final display = settings.units.format(distanceCm);

    return AppCard(
      accent: status.level == StatusLevel.neutral ? null : color,
      borderColor: status == DistanceStatus.danger
          ? AppColors.danger.withValues(alpha: 0.5)
          : null,
      padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
      semanticLabel: distanceCm == null
          ? 'Front distance unavailable. ${status.description}'
          : 'Front distance $display ${settings.units.shortLabel}. '
                '${status.label}. ${status.description}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.straighten_rounded, size: 13, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'FRONT DISTANCE',
                  style: AppTypography.label.copyWith(fontSize: 9.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                display,
                style: AppTypography.metricValue.copyWith(
                  fontSize: compact ? 26 : 32,
                  color: isStale
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Text(settings.units.shortLabel, style: AppTypography.metricUnit),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _ProximityBar(
            distanceCm: distanceCm,
            color: color,
            settings: settings,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                AppColors.iconForStatus(status.level),
                size: 12,
                color: color,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  status.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(color: color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fill bar scaled so the caution band occupies a useful part of the track,
/// rather than compressing everything below 60 cm into a sliver.
class _ProximityBar extends StatelessWidget {
  const _ProximityBar({
    required this.distanceCm,
    required this.color,
    required this.settings,
  });

  final int? distanceCm;
  final Color color;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final fullScale = (settings.cautionDistanceCm * 2)
        .clamp(60, AppConfig.sensorMaxRangeCm)
        .toDouble();
    final fraction = distanceCm == null
        ? 0.0
        : (distanceCm! / fullScale).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.xs),
      child: Container(
        height: 6,
        color: AppColors.surfaceSunken,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: fraction),
          duration: AppDurations.fast,
          builder: (context, value, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }
}
