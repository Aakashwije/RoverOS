import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// The emergency stop.
///
/// Deliberately the loudest control on the screen and always reachable: no
/// confirmation, no delay, no gesture to learn. Pressing it must be the easiest
/// thing on the HUD to do by accident-proof reflex.
///
/// Size is part of that. A driver reaching for this is not aiming — they are
/// slapping the corner of the phone they know it lives in — so on the drive
/// HUD it claims a whole zone rather than sitting as one button among several.
class EmergencyStopButton extends StatefulWidget {
  const EmergencyStopButton({
    super.key,
    required this.onPressed,
    required this.isStopped,
    this.onReset,
    this.compact = false,
    this.height,
  });

  final VoidCallback onPressed;

  /// True once the stop has latched.
  final bool isStopped;

  /// Clears the latch. When null, the button stays latched.
  final VoidCallback? onReset;

  /// Shorter layout for tight landscape rows.
  final bool compact;

  /// Overrides the height the variant would otherwise pick. The drive HUD
  /// passes a taller value so the strike zone matches the corner of the screen
  /// a driver actually hits.
  final double? height;

  @override
  State<EmergencyStopButton> createState() => _EmergencyStopButtonState();
}

class _EmergencyStopButtonState extends State<EmergencyStopButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: AppDurations.pulse,
  );

  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isStopped) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(EmergencyStopButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStopped == oldWidget.isStopped) return;
    if (widget.isStopped) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLatched = widget.isStopped;
    final label = isLatched ? 'STOPPED' : 'EMERGENCY STOP';
    final onTap = isLatched ? widget.onReset : widget.onPressed;
    final height = widget.height ?? (widget.compact ? 56 : 68);

    // Latched, the control is red-on-dark rather than white-on-red, so the two
    // states never look alike at a glance. That foreground red has to clear
    // 4.5:1 on the dark surface, which the fill red does not.
    final foreground = isLatched ? AppColors.emergencyLight : Colors.white;

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: isLatched
          ? 'Vehicle stopped. Activate to release the emergency stop.'
          : 'Emergency stop. Stops the vehicle immediately.',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTapDown: onTap == null
              ? null
              : (_) => setState(() => _pressed = true),
          onTapUp: onTap == null
              ? null
              : (_) => setState(() => _pressed = false),
          onTapCancel: onTap == null
              ? null
              : () => setState(() => _pressed = false),
          onTap: onTap,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final glow = isLatched ? 0.25 + 0.35 * _pulse.value : 0.30;

              return AnimatedScale(
                scale: _pressed ? 0.95 : 1,
                duration: AppDurations.instant,
                child: Container(
                  height: height,
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? AppSpacing.lg : AppSpacing.xxl,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isLatched
                          ? [AppColors.surfaceElevated, AppColors.surfaceSunken]
                          : [AppColors.emergency, AppColors.emergencyDeep],
                    ),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(
                      color: isLatched
                          ? AppColors.emergencyLight
                          : Colors.white.withValues(alpha: 0.25),
                      width: 2,
                    ),
                    boxShadow: AppShadows.glow(
                      AppColors.emergency,
                      blur: 22,
                      opacity: glow,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLatched
                            ? Icons.lock_reset_rounded
                            : Icons.pan_tool_rounded,
                        size: widget.compact ? 22 : 26,
                        color: foreground,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.button.copyWith(
                                fontSize: widget.compact ? 15 : 17,
                                letterSpacing: 1.6,
                                color: foreground,
                              ),
                            ),
                            if (isLatched && widget.onReset != null)
                              Text(
                                'TAP TO RELEASE',
                                style: AppTypography.label.copyWith(
                                  fontSize: 9,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
