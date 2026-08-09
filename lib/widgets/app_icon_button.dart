import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Square icon control sized for use while driving.
///
/// [isActive] renders a lit state so toggles (headlights, hazards, scan) read
/// as on/off without a separate label — though callers on the Drive HUD still
/// pair it with a caption.
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.isActive = false,
    this.activeColor,
    this.size = AppSpacing.minTouchTarget,
    this.iconSize,
    this.tooltip,
    this.badgeCount,
  });

  final IconData icon;

  /// Required: an icon-only control is invisible to a screen reader without it.
  final String semanticLabel;

  final VoidCallback? onPressed;
  final bool isActive;
  final Color? activeColor;
  final double size;
  final double? iconSize;
  final String? tooltip;

  /// Small counter overlay, e.g. queued faults.
  final int? badgeCount;

  bool get isEnabled => onPressed != null;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.activeColor ?? AppColors.accent;
    final foreground = !widget.isEnabled
        ? AppColors.textTertiary
        : widget.isActive
        ? active
        : AppColors.textSecondary;

    Widget button = AnimatedScale(
      scale: _pressed ? 0.93 : 1,
      duration: AppDurations.instant,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        height: widget.size,
        width: widget.size,
        decoration: BoxDecoration(
          color: widget.isActive
              ? active.withValues(alpha: 0.16)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: widget.isActive
                ? active.withValues(alpha: 0.6)
                : AppColors.border,
            width: 1,
          ),
          boxShadow: widget.isActive
              ? AppShadows.glow(active, blur: 16, opacity: 0.28)
              : null,
        ),
        child: Icon(
          widget.icon,
          size: widget.iconSize ?? widget.size * 0.42,
          color: foreground,
        ),
      ),
    );

    if (widget.badgeCount != null && widget.badgeCount! > 0) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: const BoxDecoration(
                color: AppColors.danger,
                borderRadius: AppRadii.pillRadius,
              ),
              child: Text(
                '${widget.badgeCount}',
                style: AppTypography.label.copyWith(
                  color: Colors.white,
                  fontSize: 9,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final gesture = GestureDetector(
      onTapDown: widget.isEnabled ? (_) => _setPressed(true) : null,
      onTapUp: widget.isEnabled ? (_) => _setPressed(false) : null,
      onTapCancel: widget.isEnabled ? () => _setPressed(false) : null,
      onTap: widget.isEnabled ? widget.onPressed : null,
      child: button,
    );

    return Semantics(
      button: true,
      enabled: widget.isEnabled,
      toggled: widget.isActive,
      label: widget.semanticLabel,
      child: ExcludeSemantics(
        child: widget.tooltip == null
            ? gesture
            : Tooltip(message: widget.tooltip!, child: gesture),
      ),
    );
  }
}
