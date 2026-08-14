import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/spider_commands.dart';

/// Six press-and-hold direction buttons driving the spiderbot's gait.
///
/// Discrete buttons, not a joystick: a fixed-gait quadruped only has a
/// handful of shapes to step in at a time, so there is nothing continuous to
/// drag the way there is for the car's differential drive.
class DirectionPad extends StatelessWidget {
  const DirectionPad({
    super.key,
    required this.activeDirection,
    required this.onPress,
    required this.onRelease,
    this.enabled = true,
  });

  /// The direction currently held, or null.
  final WalkDirection? activeDirection;

  /// Fired on press-down for a direction — including a direct switch from one
  /// held direction to another.
  final ValueChanged<WalkDirection> onPress;

  /// Fired when the held button is released or the gesture is cancelled.
  final VoidCallback onRelease;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(const [
          (WalkDirection.rotateLeft, Icons.rotate_left_rounded),
          (WalkDirection.forward, Icons.keyboard_arrow_up_rounded),
          (WalkDirection.rotateRight, Icons.rotate_right_rounded),
        ]),
        const SizedBox(height: AppSpacing.sm),
        _row(const [
          (WalkDirection.left, Icons.keyboard_arrow_left_rounded),
          (WalkDirection.back, Icons.keyboard_arrow_down_rounded),
          (WalkDirection.right, Icons.keyboard_arrow_right_rounded),
        ]),
      ],
    );
  }

  Widget _row(List<(WalkDirection, IconData)> buttons) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          _DirectionButton(
            icon: buttons[i].$2,
            label: buttons[i].$1.label,
            isActive: activeDirection == buttons[i].$1,
            enabled: enabled,
            onTapDown: () => onPress(buttons[i].$1),
            onTapUp: onRelease,
          ),
        ],
      ],
    );
  }
}

class _DirectionButton extends StatelessWidget {
  const _DirectionButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.enabled,
    required this.onTapDown,
    required this.onTapUp,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final bool enabled;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.textTertiary
        : (isActive ? AppColors.accent : AppColors.textSecondary);

    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label. Hold to walk, release to stop.',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTapDown: enabled ? (_) => onTapDown() : null,
          onTapUp: enabled ? (_) => onTapUp() : null,
          onTapCancel: enabled ? onTapUp : null,
          child: AnimatedContainer(
            duration: AppDurations.instant,
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isActive
                    ? [
                        AppColors.accent.withValues(alpha: 0.28),
                        AppColors.accent.withValues(alpha: 0.10),
                      ]
                    : [AppColors.surfaceElevated, AppColors.surfaceSunken],
              ),
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: isActive ? AppColors.accent : AppColors.border,
                width: isActive ? 2 : 1,
              ),
              boxShadow: isActive
                  ? AppShadows.glow(AppColors.accent, blur: 16, opacity: 0.35)
                  : null,
            ),
            child: Icon(icon, size: 30, color: color),
          ),
        ),
      ),
    );
  }
}
