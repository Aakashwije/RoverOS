import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

enum AppButtonVariant {
  /// Accent fill. One per screen — the primary action.
  primary,

  /// Elevated surface with a border. Supporting actions.
  secondary,

  /// Transparent with a border. Tertiary / dismissive actions.
  ghost,

  /// Destructive or safety-critical actions.
  danger,
}

enum AppButtonSize {
  // 44dp clears both Android's and iOS's minimum touch-target guidance —
  // this is the smallest button ROVEROS offers, so it still has to be safely
  // tappable in a moving vehicle.
  small(44, 13, EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
  medium(52, 14, EdgeInsets.symmetric(horizontal: AppSpacing.xl)),
  large(60, 15, EdgeInsets.symmetric(horizontal: AppSpacing.xxl));

  const AppButtonSize(this.height, this.fontSize, this.padding);

  final double height;
  final double fontSize;
  final EdgeInsets padding;
}

/// Primary action control.
///
/// Presses scale the surface slightly rather than rippling, which reads better
/// against the dark panels and gives tactile feedback on a moving vehicle.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.icon,
    this.trailingIcon,
    this.fullWidth = false,
    this.isLoading = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool fullWidth;
  final bool isLoading;

  /// Overrides [label] for screen readers when the visible text is an
  /// abbreviation or all-caps token.
  final String? semanticLabel;

  bool get isEnabled => onPressed != null && !isLoading;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  ({Color background, Color foreground, Color? border}) get _palette {
    if (!widget.isEnabled) {
      return (
        background: AppColors.surfaceElevated,
        foreground: AppColors.textTertiary,
        border: AppColors.border,
      );
    }
    return switch (widget.variant) {
      AppButtonVariant.primary => (
        background: AppColors.accent,
        foreground: AppColors.textOnAccent,
        border: null,
      ),
      AppButtonVariant.secondary => (
        background: AppColors.surfaceElevated,
        foreground: AppColors.textPrimary,
        border: AppColors.borderStrong,
      ),
      AppButtonVariant.ghost => (
        background: Colors.transparent,
        foreground: AppColors.textSecondary,
        border: AppColors.border,
      ),
      AppButtonVariant.danger => (
        background: AppColors.danger,
        foreground: Colors.white,
        border: null,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;

    return Semantics(
      button: true,
      enabled: widget.isEnabled,
      label: widget.semanticLabel ?? widget.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTapDown: widget.isEnabled ? (_) => _setPressed(true) : null,
          onTapUp: widget.isEnabled ? (_) => _setPressed(false) : null,
          onTapCancel: widget.isEnabled ? () => _setPressed(false) : null,
          onTap: widget.isEnabled ? widget.onPressed : null,
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1,
            duration: AppDurations.instant,
            curve: AppDurations.standard,
            child: AnimatedContainer(
              duration: AppDurations.fast,
              height: widget.size.height,
              width: widget.fullWidth ? double.infinity : null,
              padding: widget.size.padding,
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: AppRadii.cardRadius,
                border: palette.border == null
                    ? null
                    : Border.all(color: palette.border!, width: 1),
                boxShadow:
                    widget.variant == AppButtonVariant.primary &&
                        widget.isEnabled &&
                        !_pressed
                    ? AppShadows.glow(AppColors.accent, blur: 18, opacity: 0.25)
                    : null,
              ),
              child: Row(
                mainAxisSize: widget.fullWidth
                    ? MainAxisSize.max
                    : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: _buildContent(palette.foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(Color foreground) {
    if (widget.isLoading) {
      return [
        SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          widget.label,
          style: AppTypography.button.copyWith(
            color: foreground,
            fontSize: widget.size.fontSize,
          ),
        ),
      ];
    }

    return [
      if (widget.icon != null) ...[
        Icon(widget.icon, size: widget.size.fontSize + 5, color: foreground),
        const SizedBox(width: AppSpacing.sm),
      ],
      Flexible(
        child: Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.button.copyWith(
            color: foreground,
            fontSize: widget.size.fontSize,
          ),
        ),
      ),
      if (widget.trailingIcon != null) ...[
        const SizedBox(width: AppSpacing.sm),
        Icon(
          widget.trailingIcon,
          size: widget.size.fontSize + 5,
          color: foreground,
        ),
      ],
    ];
  }
}
