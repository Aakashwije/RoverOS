import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Themed bottom sheet with a drag handle and title row.
///
/// Used for secondary panels — lighting, speed presets, device details — that
/// would otherwise crowd the Drive HUD.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;

  /// Presents [builder]'s content in a themed, scroll-safe sheet.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required WidgetBuilder builder,
    String? subtitle,
    IconData? icon,
    Widget? trailing,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (sheetContext) => AppBottomSheet(
        title: title,
        subtitle: subtitle,
        icon: icon,
        trailing: trailing,
        child: Builder(builder: builder),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
      decoration: const BoxDecoration(
        color: AppColors.surfaceOverlay,
        borderRadius: AppRadii.sheetRadius,
        border: Border(
          top: BorderSide(color: AppColors.borderStrong),
          left: BorderSide(color: AppColors.borderStrong),
          right: BorderSide(color: AppColors.borderStrong),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                AppSpacing.lg,
                AppSpacing.xxl,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: AppColors.accent),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(title, style: AppTypography.titleMedium),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: AppTypography.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xxl,
                  0,
                  AppSpacing.xxl,
                  AppSpacing.xxl + media.viewInsets.bottom,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
