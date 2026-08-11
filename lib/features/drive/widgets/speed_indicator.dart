import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/motor_math.dart';
import '../../../models/commands.dart';
import '../../../widgets/progress_ring.dart';

/// Central speed gauge: the commanded ceiling as a ring, with the live output
/// and heading underneath it.
class SpeedIndicator extends StatelessWidget {
  const SpeedIndicator({
    super.key,
    required this.speedPercent,
    required this.output,
    this.size = 190,
    this.isStopped = false,
    this.showMotorBars = true,
  });

  /// Commanded ceiling, 0–100.
  final int speedPercent;

  /// Live motor output driving the direction readout.
  final MotorOutput output;

  final double size;
  final bool isStopped;

  /// The drive HUD turns these off: it carries a larger left/right readout
  /// under the joystick, and showing the same two numbers twice on one screen
  /// just splits the driver's attention.
  final bool showMotorBars;

  @override
  Widget build(BuildContext context) {
    final direction = MotorMath.directionOf(output);
    final color = isStopped ? AppColors.emergencyLight : AppColors.accent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProgressRing(
          value: speedPercent / 100,
          size: size,
          strokeWidth: size * 0.07,
          color: color,
          semanticLabel: 'Speed limit',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('SPEED', style: AppTypography.label),
              const SizedBox(height: AppSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: speedPercent.toDouble()),
                    duration: AppDurations.normal,
                    curve: AppDurations.standard,
                    builder: (context, value, _) => Text(
                      value.round().toString(),
                      style: AppTypography.displayValue.copyWith(
                        fontSize: size * 0.24,
                        color: isStopped
                            ? AppColors.emergencyLight
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: size * 0.045),
                    child: Text(
                      '%',
                      style: AppTypography.metricUnit.copyWith(
                        fontSize: size * 0.09,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              _DirectionChip(direction: direction, isStopped: isStopped),
            ],
          ),
        ),
        if (showMotorBars) ...[
          const SizedBox(height: AppSpacing.lg),
          _MotorBars(output: output),
        ],
      ],
    );
  }
}

class _DirectionChip extends StatelessWidget {
  const _DirectionChip({required this.direction, required this.isStopped});

  final DriveDirection direction;
  final bool isStopped;

  IconData get _icon => switch (direction) {
    DriveDirection.forward => Icons.arrow_upward_rounded,
    DriveDirection.reverse => Icons.arrow_downward_rounded,
    DriveDirection.left || DriveDirection.spinLeft => Icons.rotate_left_rounded,
    DriveDirection.right ||
    DriveDirection.spinRight => Icons.rotate_right_rounded,
    DriveDirection.forwardLeft => Icons.north_west_rounded,
    DriveDirection.forwardRight => Icons.north_east_rounded,
    DriveDirection.reverseLeft => Icons.south_west_rounded,
    DriveDirection.reverseRight => Icons.south_east_rounded,
    DriveDirection.idle => Icons.remove_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final label = isStopped ? 'E-STOP' : direction.label;
    final color = isStopped
        ? AppColors.emergencyLight
        : direction == DriveDirection.idle
        ? AppColors.textTertiary
        : AppColors.accent;

    return Semantics(
      liveRegion: true,
      label: 'Direction $label',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isStopped ? Icons.block_rounded : _icon,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.label.copyWith(color: color, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrored bars showing each side's signed output — the clearest way to see a
/// turn, and to spot a motor that is not responding.
class _MotorBars extends StatelessWidget {
  const _MotorBars({required this.output});

  final MotorOutput output;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Motor output. Left ${output.left} percent, right ${output.right} percent',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MotorBar(label: 'L', value: output.left),
            const SizedBox(width: AppSpacing.md),
            _MotorBar(label: 'R', value: output.right),
          ],
        ),
      ),
    );
  }
}

class _MotorBar extends StatelessWidget {
  const _MotorBar({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final magnitude = (value.abs() / 100).clamp(0.0, 1.0);
    final isReverse = value < 0;
    final color = value == 0
        ? AppColors.borderStrong
        : isReverse
        ? AppColors.caution
        : AppColors.accent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 46,
          width: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                  border: Border.all(color: AppColors.border),
                ),
              ),
              // Grows up from the midline for forward, down for reverse.
              Align(
                alignment: isReverse
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: 0.5,
                  widthFactor: 1,
                  child: Align(
                    alignment: isReverse
                        ? Alignment.bottomCenter
                        : Alignment.topCenter,
                    child: AnimatedFractionallySizedBox(
                      duration: AppDurations.fast,
                      heightFactor: magnitude,
                      widthFactor: 1,
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(AppRadii.xs),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(height: 1, width: 18, color: AppColors.borderStrong),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTypography.label.copyWith(fontSize: 9)),
      ],
    );
  }
}

/// ECO / NORMAL / SPORT selector plus a custom slider entry point.
class SpeedPresetRow extends StatelessWidget {
  const SpeedPresetRow({
    super.key,
    required this.speedPercent,
    required this.onSelected,
    this.enabled = true,
  });

  final int speedPercent;
  final ValueChanged<int> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = SpeedPreset.forPercent(speedPercent);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final preset in SpeedPreset.selectable) ...[
          _PresetChip(
            preset: preset,
            isActive: preset == active,
            enabled: enabled,
            onTap: () => onSelected(preset.percent),
          ),
          if (preset != SpeedPreset.selectable.last)
            const SizedBox(width: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.preset,
    required this.isActive,
    required this.enabled,
    required this.onTap,
  });

  final SpeedPreset preset;
  final bool isActive;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isActive,
      enabled: enabled,
      label: '${preset.label} speed, ${preset.percent} percent',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.accent.withValues(alpha: 0.16)
                  : AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(
                color: isActive ? AppColors.accent : AppColors.border,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  preset.label,
                  style: AppTypography.label.copyWith(
                    fontSize: 10,
                    color: isActive
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
                Text(
                  '${preset.percent}%',
                  style: AppTypography.labelStrong.copyWith(
                    fontSize: 12,
                    color: isActive
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
