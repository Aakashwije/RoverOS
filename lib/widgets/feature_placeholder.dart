import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'app_button.dart';
import 'app_card.dart';

/// Empty state for a screen that has nothing to show yet.
///
/// Every instance states the precondition and offers the action that satisfies
/// it, so an empty screen is never a dead end.
class FeaturePlaceholder extends StatelessWidget {
  const FeaturePlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 56,
                  width: 56,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Icon(icon, size: 26, color: AppColors.textTertiary),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTypography.body,
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    label: actionLabel!,
                    onPressed: onAction,
                    fullWidth: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
