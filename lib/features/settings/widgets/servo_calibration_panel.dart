import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validation.dart';
import '../../../models/settings.dart';
import '../../../widgets/app_slider.dart';
import '../../drive/drive_controller.dart';
import '../settings_controller.dart';

/// Servo travel calibration: centre point and physical end stops.
///
/// A live validity check runs on every drag so a driver sees "min must be
/// less than max" immediately, even though [AppSettings.normalized] would
/// silently repair the same inconsistency on save.
class ServoCalibrationPanel extends ConsumerWidget {
  const ServoCalibrationPanel({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsController = ref.read(settingsProvider.notifier);
    final driveController = ref.read(driveProvider.notifier);

    final validity = Validators.servoRange(
      minAngle: settings.servoMinAngle,
      maxAngle: settings.servoMaxAngle,
      center: settings.servoCenter,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSlider(
          label: 'SERVO CENTER',
          leadingIcon: Icons.center_focus_strong_rounded,
          value: settings.servoCenter.toDouble(),
          min: 0,
          max: 180,
          divisions: 36,
          unit: '°',
          onChanged: (value) => settingsController.update(
            (s) => s.copyWith(servoCenter: value.round()),
          ),
          onChangeEnd: (_) => driveController.pushCalibration(),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppSlider(
          label: 'SERVO MINIMUM ANGLE',
          leadingIcon: Icons.rotate_left_rounded,
          value: settings.servoMinAngle.toDouble(),
          min: 0,
          max: 180,
          divisions: 36,
          unit: '°',
          onChanged: (value) => settingsController.update(
            (s) => s.copyWith(servoMinAngle: value.round()),
          ),
          onChangeEnd: (_) => driveController.pushCalibration(),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppSlider(
          label: 'SERVO MAXIMUM ANGLE',
          leadingIcon: Icons.rotate_right_rounded,
          value: settings.servoMaxAngle.toDouble(),
          min: 0,
          max: 180,
          divisions: 36,
          unit: '°',
          onChanged: (value) => settingsController.update(
            (s) => s.copyWith(servoMaxAngle: value.round()),
          ),
          onChangeEnd: (_) => driveController.pushCalibration(),
        ),
        if (!validity.isValid) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: AppColors.caution,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${validity.error!} — corrected automatically when saved.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.caution,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
