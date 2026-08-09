import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

enum AppBadgeSize { small, medium }

/// Compact status pill.
///
/// Always renders text, and by default an icon too, so the state never depends
/// on the badge's colour alone.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.level = StatusLevel.neutral,
    this.icon,
    this.showIcon = true,
    this.filled = false,
    this.size = AppBadgeSize.medium,
    this.semanticLabel,
  });

  final String label;
  final StatusLevel level;

  /// Overrides the default icon for [level].
  final IconData? icon;

  final bool showIcon;

  /// Solid fill instead of tinted-transparent. Use for the single most
  /// important badge on a screen.
  final bool filled;

  final AppBadgeSize size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(level);
    final effectiveIcon = icon ?? AppColors.iconForStatus(level);
    final isSmall = size == AppBadgeSize.small;

    return Semantics(
      label: semanticLabel ?? label,
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isSmall ? AppSpacing.sm : AppSpacing.md,
            vertical: isSmall ? AppSpacing.xs : 6,
          ),
          decoration: BoxDecoration(
            color: filled ? color : color.withValues(alpha: 0.14),
            borderRadius: AppRadii.pillRadius,
            border: Border.all(
              color: filled ? color : color.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showIcon) ...[
                Icon(
                  effectiveIcon,
                  size: isSmall ? 11 : 13,
                  color: filled ? AppColors.background : color,
                ),
                SizedBox(width: isSmall ? 4 : 6),
              ],
              Text(
                label,
                style: AppTypography.label.copyWith(
                  color: filled ? AppColors.background : color,
                  fontSize: isSmall ? 10 : 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
