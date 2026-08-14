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

/// A direction button: presses squash down like a real key, and a held
/// direction breathes with an outward pulse so "this is actively walking"
/// reads at a glance instead of relying on the accent colour alone.
class _DirectionButton extends StatefulWidget {
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
  State<_DirectionButton> createState() => _DirectionButtonState();
}

class _DirectionButtonState extends State<_DirectionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: AppDurations.pulse,
  );

  bool _pressed = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _pulse.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = AppMotion.reduceMotion(context);
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    _syncPulse();
  }

  @override
  void didUpdateWidget(_DirectionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) _syncPulse();
  }

  void _syncPulse() {
    if (widget.isActive && !_reduceMotion) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = !widget.enabled
        ? AppColors.textTertiary
        : (widget.isActive ? AppColors.accent : AppColors.textSecondary);

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: '${widget.label}. Hold to walk, release to stop.',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTapDown: widget.enabled
              ? (_) {
                  widget.onTapDown();
                  _setPressed(true);
                }
              : null,
          onTapUp: widget.enabled
              ? (_) {
                  widget.onTapUp();
                  _setPressed(false);
                }
              : null,
          onTapCancel: widget.enabled
              ? () {
                  widget.onTapUp();
                  _setPressed(false);
                }
              : null,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final pulse = _reduceMotion ? 0.0 : _pulse.value;

              return AnimatedScale(
                scale: _pressed ? 0.90 : 1,
                duration: AppDurations.instant,
                curve: AppDurations.standard,
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  curve: AppDurations.standard,
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: widget.isActive
                          ? [
                              AppColors.accent.withValues(alpha: 0.28),
                              AppColors.accent.withValues(alpha: 0.10),
                            ]
                          : [AppColors.surfaceElevated, AppColors.surfaceSunken],
                    ),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(
                      color: widget.isActive ? AppColors.accent : AppColors.border,
                      width: widget.isActive ? 2 : 1,
                    ),
                    boxShadow: widget.isActive
                        ? AppShadows.glow(
                            AppColors.accent,
                            blur: 14 + 8 * pulse,
                            opacity: 0.30 + 0.25 * pulse,
                          )
                        : null,
                  ),
                  child: child,
                ),
              );
            },
            child: Icon(widget.icon, size: 30, color: color),
          ),
        ),
      ),
    );
  }
}
