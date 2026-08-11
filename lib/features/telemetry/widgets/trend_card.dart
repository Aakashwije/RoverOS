import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/sparkline.dart';

/// A metric with its recent history underneath it.
///
/// The number answers "where is it now"; the line answers "and is that a
/// problem" — a battery at 40% means something very different climbing out of
/// a mock reset than it does five minutes into a hard drive.
class TrendCard extends StatelessWidget {
  const TrendCard({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    this.unit,
    this.icon,
    this.level = StatusLevel.neutral,
    this.caption,
    this.minValue,
    this.maxValue,
    this.isStale = false,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final StatusLevel level;

  /// Trailing note under the sparkline — the trend in words, for anyone who
  /// cannot read the line itself.
  final String? caption;

  final List<double?> values;
  final double? minValue;
  final double? maxValue;
  final bool isStale;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(level);
    final showAccent = level != StatusLevel.neutral;

    return AppCard(
      accent: showAccent ? color : null,
      padding: const EdgeInsets.all(AppSpacing.lg),
      semanticLabel: [
        label,
        isStale ? 'last known $value' : value,
        if (unit != null) unit,
        if (caption != null) caption,
        if (isStale) 'Reading is stale',
      ].join(' '),
      child: Opacity(
        opacity: isStale ? 0.55 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 14,
                    color: showAccent ? color : AppColors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isStale)
                  const Icon(
                    Icons.history_toggle_off_rounded,
                    size: 13,
                    color: AppColors.textTertiary,
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
                    style: AppTypography.metricValue.copyWith(fontSize: 26),
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Text(unit!, style: AppTypography.metricUnit),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Sparkline(
              values: values,
              color: showAccent ? color : AppColors.accent,
              minValue: minValue,
              maxValue: maxValue,
            ),
            if (caption != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label.copyWith(fontSize: 9.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
