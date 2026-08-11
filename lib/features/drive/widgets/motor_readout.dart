import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/motor_math.dart';
import '../../../widgets/animated_reveal.dart';

/// Live left/right motor output, sat directly under the joystick.
///
/// Placed here rather than in the centre gauge on purpose: this is the number
/// that tells you whether a turn is actually differential or whether one side
/// has stopped responding, and it belongs in the same glance as the stick that
/// commands it. The bars grow from a centre line so reverse reads as a
/// direction rather than as a smaller number.
class MotorReadout extends StatelessWidget {
  const MotorReadout({
    super.key,
    required this.output,
    this.enabled = true,
    this.pulseOnChange = true,
  });

  final MotorOutput output;

  /// False while input is refused (E-STOP latched, autonomous mode), which
  /// mutes the readout instead of hiding it — a zero that is being *enforced*
  /// still tells the driver something.
  final bool enabled;

  final bool pulseOnChange;

  @override
  Widget build(BuildContext context) {
    final readout = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Side(label: 'L', value: output.left, enabled: enabled),
          ),
          Container(
            width: 1,
            height: 26,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            color: AppColors.border,
          ),
          Expanded(
            child: _Side(label: 'R', value: output.right, enabled: enabled),
          ),
        ],
      ),
    );

    return Semantics(
      liveRegion: true,
      label:
          'Motor output. Left ${output.left} percent, '
          'right ${output.right} percent',
      child: ExcludeSemantics(
        child: pulseOnChange
            ? PulseOnChange(
                value: output,
                enabled: enabled,
                child: readout,
              )
            : readout,
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.label,
    required this.value,
    required this.enabled,
  });

  final String label;
  final int value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isReverse = value < 0;
    final color = !enabled || value == 0
        ? AppColors.textTertiary
        : isReverse
        ? AppColors.caution
        : AppColors.accent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: AppTypography.label.copyWith(fontSize: 9),
            ),
            const Spacer(),
            Text(
              value == 0 ? '0' : '${value > 0 ? '+' : ''}$value',
              style: AppTypography.metricValue.copyWith(
                fontSize: 17,
                color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 1),
            Text(
              '%',
              style: AppTypography.metricUnit.copyWith(fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _CenteredBar(value: value, color: color),
      ],
    );
  }
}

/// Horizontal bar growing right for forward, left for reverse, from a fixed
/// centre tick.
class _CenteredBar extends StatelessWidget {
  const _CenteredBar({required this.value, required this.color});

  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final magnitude = (value.abs() / 100).clamp(0.0, 1.0);
    final isReverse = value < 0;

    return SizedBox(
      height: 6,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadii.xs),
                border: Border.all(color: AppColors.border),
              ),
            ),
          ),
          // Each half of the track is its own box, so the fill can only ever
          // travel outward from the middle.
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedFractionallySizedBox(
                      duration: AppDurations.fast,
                      curve: AppDurations.standard,
                      widthFactor: isReverse ? magnitude : 0,
                      heightFactor: 1,
                      child: _Fill(color: color),
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: AppDurations.fast,
                      curve: AppDurations.standard,
                      widthFactor: isReverse ? 0 : magnitude,
                      heightFactor: 1,
                      child: _Fill(color: color),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Container(width: 1, color: AppColors.borderStrong),
          ),
        ],
      ),
    );
  }
}

class _Fill extends StatelessWidget {
  const _Fill({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.xs),
      ),
    );
  }
}
