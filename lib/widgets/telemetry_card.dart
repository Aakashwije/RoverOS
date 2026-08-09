import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'app_card.dart';

/// Single dashboard metric: label, large animated value, unit and status.
///
/// Numeric values tween between readings so telemetry updates feel like an
/// instrument settling rather than text being replaced.
class TelemetryCard extends StatelessWidget {
  const TelemetryCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.level = StatusLevel.neutral,
    this.statusLabel,
    this.numericValue,
    this.isStale = false,
    this.onTap,
    this.footer,
    this.compact = false,
  });

  /// Pre-formatted display value, used when [numericValue] is null or while
  /// data is missing.
  final String value;

  final String label;
  final String? unit;
  final IconData? icon;
  final StatusLevel level;

  /// Short status word shown under the value, e.g. `SAFE`, `LOW`.
  final String? statusLabel;

  /// When supplied, the card animates between readings instead of snapping.
  final double? numericValue;

  /// Dims the card and appends a "stale" note when telemetry has gone quiet.
  final bool isStale;

  final VoidCallback? onTap;
  final Widget? footer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(level);
    final showAccent = level != StatusLevel.neutral;

    return AppCard(
      onTap: onTap,
      accent: showAccent ? color : null,
      padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
      semanticLabel: [
        label,
        isStale ? 'last known $value' : value,
        if (unit != null) unit,
        if (statusLabel != null) statusLabel,
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
            SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: _ValueText(
                    value: value,
                    numericValue: numericValue,
                    compact: compact,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Text(unit!, style: AppTypography.metricUnit),
                ],
              ],
            ),
            if (statusLabel != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(AppColors.iconForStatus(level), size: 12, color: color),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      statusLabel!,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label.copyWith(color: color),
                    ),
                  ),
                ],
              ),
            ],
            if (footer != null) ...[
              const SizedBox(height: AppSpacing.md),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

class _ValueText extends StatelessWidget {
  const _ValueText({
    required this.value,
    required this.numericValue,
    required this.compact,
  });

  final String value;
  final double? numericValue;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = compact
        ? AppTypography.metricValue.copyWith(fontSize: 24)
        : AppTypography.metricValue;

    if (numericValue == null) {
      return Text(
        value,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: numericValue, end: numericValue),
      duration: AppDurations.normal,
      curve: AppDurations.standard,
      builder: (context, animated, _) => Text(
        animated.round().toString(),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
