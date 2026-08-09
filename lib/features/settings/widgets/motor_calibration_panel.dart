import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/commands.dart';
import '../../../models/settings.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_slider.dart';
import '../../drive/drive_controller.dart';
import '../settings_controller.dart';

/// Motor direction and trim calibration, plus bench-test buttons.
///
/// Direction and trim only change local settings as the user drags — nothing
/// transmits until [onChangeEnd] fires, so a slider drag never floods the
/// link. The test buttons are the exception: they exist specifically to spin
/// a motor briefly, and stop themselves automatically.
class MotorCalibrationPanel extends ConsumerWidget {
  const MotorCalibrationPanel({
    super.key,
    required this.settings,
    required this.isConnected,
  });

  final AppSettings settings;
  final bool isConnected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsController = ref.read(settingsProvider.notifier);
    final driveController = ref.read(driveProvider.notifier);

    void applyCalibration() => driveController.pushCalibration();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _DirectionRow(
          label: 'LEFT MOTOR DIRECTION',
          isInverted: settings.invertLeftMotor,
          onChanged: (value) {
            settingsController.update(
              (s) => s.copyWith(invertLeftMotor: value),
            );
            applyCalibration();
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        _DirectionRow(
          label: 'RIGHT MOTOR DIRECTION',
          isInverted: settings.invertRightMotor,
          onChanged: (value) {
            settingsController.update(
              (s) => s.copyWith(invertRightMotor: value),
            );
            applyCalibration();
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        AppSlider(
          label: 'LEFT MOTOR TRIM',
          leadingIcon: Icons.tune_rounded,
          value: settings.leftMotorTrim.toDouble(),
          min: -25,
          max: 25,
          divisions: 50,
          unit: '%',
          onChanged: (value) => settingsController.update(
            (s) => s.copyWith(leftMotorTrim: value.round()),
          ),
          onChangeEnd: (_) => applyCalibration(),
          helperText: 'Corrects a rover that pulls to one side.',
        ),
        const SizedBox(height: AppSpacing.lg),
        AppSlider(
          label: 'RIGHT MOTOR TRIM',
          leadingIcon: Icons.tune_rounded,
          value: settings.rightMotorTrim.toDouble(),
          min: -25,
          max: 25,
          divisions: 50,
          unit: '%',
          onChanged: (value) => settingsController.update(
            (s) => s.copyWith(rightMotorTrim: value.round()),
          ),
          onChangeEnd: (_) => applyCalibration(),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          isConnected
              ? 'Runs each motor briefly at low power to verify wiring and direction.'
              : 'Connect to the vehicle to bench-test the motors.',
          style: AppTypography.bodySmall.copyWith(fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'TEST LEFT',
                size: AppButtonSize.small,
                variant: AppButtonVariant.secondary,
                onPressed: isConnected
                    ? () => _testMotor(driveController, MotorTarget.left)
                    : null,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                label: 'TEST RIGHT',
                size: AppButtonSize.small,
                variant: AppButtonVariant.secondary,
                onPressed: isConnected
                    ? () => _testMotor(driveController, MotorTarget.right)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'TEST BOTH MOTORS',
          size: AppButtonSize.small,
          variant: AppButtonVariant.secondary,
          fullWidth: true,
          onPressed: isConnected
              ? () => _testMotor(driveController, MotorTarget.both)
              : null,
        ),
      ],
    );
  }

  /// Spins the target briefly, then stops it — a bench test must never leave
  /// a motor running unattended.
  void _testMotor(DriveController controller, MotorTarget target) {
    controller.testMotor(target, percent: 45);
    Future<void>.delayed(const Duration(milliseconds: 600), controller.stop);
  }
}

class _DirectionRow extends StatelessWidget {
  const _DirectionRow({
    required this.label,
    required this.isInverted,
    required this.onChanged,
  });

  final String label;
  final bool isInverted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.label)),
        _DirectionSegment(isInverted: isInverted, onChanged: onChanged),
      ],
    );
  }
}

class _DirectionSegment extends StatelessWidget {
  const _DirectionSegment({required this.isInverted, required this.onChanged});

  final bool isInverted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SegmentButton(
            label: 'NORMAL',
            isActive: !isInverted,
            onTap: () => onChanged(false),
          ),
          _SegmentButton(
            label: 'REVERSED',
            isActive: isInverted,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.accent.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.xs),
            ),
            child: Text(
              label,
              style: AppTypography.label.copyWith(
                fontSize: 9.5,
                color: isActive ? AppColors.accent : AppColors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
