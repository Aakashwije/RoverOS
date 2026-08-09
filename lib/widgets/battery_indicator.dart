import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/telemetry.dart';

enum BatteryIndicatorStyle {
  /// Icon + percentage. For app bars and dense HUD rows.
  compact,

  /// Icon + percentage + status sentence + fill bar. For Home and Telemetry.
  detailed,
}

/// Battery readout.
///
/// Percentage, icon shape, fill level and a written status label all move
/// together, so a low pack is legible without relying on the colour shift.
class BatteryIndicator extends StatelessWidget {
  const BatteryIndicator({
    super.key,
    required this.percent,
    this.style = BatteryIndicatorStyle.detailed,
    this.isCharging = false,
  });

  /// `null` when the vehicle has not reported a level yet.
  final int? percent;

  final BatteryIndicatorStyle style;
  final bool isCharging;

  BatteryStatus get _status => BatteryStatus.fromPercent(percent);

  IconData get _icon {
    if (isCharging) return Icons.battery_charging_full_rounded;
    final value = percent;
    if (value == null) return Icons.battery_unknown_rounded;
    if (value >= 85) return Icons.battery_full_rounded;
    if (value >= 60) return Icons.battery_5_bar_rounded;
    if (value >= 40) return Icons.battery_4_bar_rounded;
    if (value >= 25) return Icons.battery_3_bar_rounded;
    if (value >= 15) return Icons.battery_2_bar_rounded;
    return Icons.battery_1_bar_rounded;
  }

  String get _percentLabel => percent == null ? '—' : '$percent%';

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final color = AppColors.forStatus(status.level);
    final semantics =
        '${percent == null ? "Battery level unknown" : "Battery $percent percent"}. ${status.label}';

    if (style == BatteryIndicatorStyle.compact) {
      return Semantics(
        label: semantics,
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 18, color: color),
              const SizedBox(width: 5),
              Text(
                _percentLabel,
                style: AppTypography.labelStrong.copyWith(
                  color: color,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      label: semantics,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(_icon, size: 26, color: color),
                const SizedBox(width: AppSpacing.sm),
                Text(_percentLabel, style: AppTypography.metricValue),
                const SizedBox(width: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    status.label,
                    style: AppTypography.bodySmall.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _BatteryBar(percent: percent, color: color),
          ],
        ),
      ),
    );
  }
}

class _BatteryBar extends StatelessWidget {
  const _BatteryBar({required this.percent, required this.color});

  final int? percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.xs),
      child: Container(
        height: 8,
        color: AppColors.surfaceSunken,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: (percent ?? 0) / 100),
          duration: AppDurations.slow,
          curve: AppDurations.standard,
          builder: (context, value, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0, 1),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.55), color],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
