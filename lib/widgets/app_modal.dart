import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'app_button.dart';

/// Themed dialog with a status treatment.
///
/// [AppModal.confirm] is the single entry point for consequential decisions —
/// arming autonomous mode, forgetting a device, resetting settings — so those
/// confirmations look and behave identically wherever they appear.
class AppModal extends StatelessWidget {
  const AppModal({
    super.key,
    required this.title,
    required this.message,
    this.level = StatusLevel.info,
    this.confirmLabel = 'CONFIRM',
    this.cancelLabel = 'CANCEL',
    this.onConfirm,
    this.onCancel,
    this.confirmVariant = AppButtonVariant.primary,
    this.icon,
    this.body,
  });

  final String title;
  final String message;
  final StatusLevel level;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final AppButtonVariant confirmVariant;
  final IconData? icon;

  /// Extra content between the message and the actions.
  final Widget? body;

  /// Shows a confirmation and resolves to `true` only if confirmed.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'CONFIRM',
    String cancelLabel = 'CANCEL',
    StatusLevel level = StatusLevel.caution,
    AppButtonVariant confirmVariant = AppButtonVariant.primary,
    IconData? icon,
    Widget? body,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (dialogContext) => AppModal(
        title: title,
        message: message,
        level: level,
        icon: icon,
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        confirmVariant: confirmVariant,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(level);

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xxl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      border: Border.all(color: color.withValues(alpha: 0.35)),
                    ),
                    child: Icon(
                      icon ?? AppColors.iconForStatus(level),
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(title, style: AppTypography.titleMedium),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(message, style: AppTypography.body),
              if (body != null) ...[
                const SizedBox(height: AppSpacing.lg),
                body!,
              ],
              const SizedBox(height: AppSpacing.xxl),
              Row(
                children: [
                  if (onCancel != null)
                    Expanded(
                      child: AppButton(
                        label: cancelLabel,
                        variant: AppButtonVariant.ghost,
                        onPressed: onCancel,
                        fullWidth: true,
                      ),
                    ),
                  if (onCancel != null && onConfirm != null)
                    const SizedBox(width: AppSpacing.md),
                  if (onConfirm != null)
                    Expanded(
                      child: AppButton(
                        label: confirmLabel,
                        variant: confirmVariant,
                        onPressed: onConfirm,
                        fullWidth: true,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
