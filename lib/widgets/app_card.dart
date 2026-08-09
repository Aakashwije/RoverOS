import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Standard dark panel.
///
/// [accent] draws a hairline top edge in a status colour; it is always paired
/// with an icon or label by the caller so it stays decorative rather than
/// load-bearing.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.cardPadding,
    this.onTap,
    this.accent,
    this.elevated = false,
    this.borderColor,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? accent;
  final bool elevated;
  final Color? borderColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: AppDurations.normal,
      curve: AppDurations.standard,
      decoration: BoxDecoration(
        color: elevated ? AppColors.surfaceElevated : AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: borderColor ?? AppColors.border, width: 1),
        boxShadow: elevated ? AppShadows.raised : AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: AppRadii.cardRadius,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (accent != null)
              Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent!, accent!.withValues(alpha: 0)],
                  ),
                ),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );

    final wrapped = onTap == null
        ? card
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadii.cardRadius,
              splashColor: AppColors.accentGlow,
              highlightColor: AppColors.accentGlow,
              child: card,
            ),
          );

    if (semanticLabel == null) return wrapped;
    return Semantics(container: true, label: semanticLabel, child: wrapped);
  }
}
