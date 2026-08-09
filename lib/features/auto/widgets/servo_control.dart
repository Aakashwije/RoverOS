import 'package:flutter/material.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/commands.dart';
import '../../../widgets/app_slider.dart';

/// Manual servo angle control and scan-mode selector.
///
/// Angle is only meaningful in manual mode — once obstacle avoidance is
/// running, the ESP32 owns the servo and this control disables itself rather
/// than fighting the firmware for the same actuator.
class ServoControl extends StatelessWidget {
  const ServoControl({
    super.key,
    required this.currentAngle,
    required this.scanMode,
    required this.onAngleChanged,
    required this.onScanModeChanged,
    this.enabled = true,
  });

  final int currentAngle;
  final ScanMode scanMode;
  final ValueChanged<int> onAngleChanged;
  final ValueChanged<ScanMode> onScanModeChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSlider(
          label: 'SERVO ANGLE',
          leadingIcon: Icons.rotate_right_rounded,
          value: currentAngle.toDouble(),
          min: 0,
          max: 180,
          divisions: 36,
          unit: '°',
          color: AppColors.info,
          onChanged: enabled ? (value) => onAngleChanged(value.round()) : null,
          helperText: enabled
              ? 'Sweeps the ultrasonic sensor. Disabled during autonomous modes.'
              : 'The vehicle is sweeping this automatically.',
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final angle in AppConfig.radarAngles) ...[
              _AnglePresetButton(
                angle: angle,
                isActive: currentAngle == angle,
                enabled: enabled,
                onTap: () => onAngleChanged(angle),
              ),
              if (angle != AppConfig.radarAngles.last)
                const SizedBox(width: AppSpacing.xs),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            const Text('AUTO SCAN', style: AppTypography.label),
            const Spacer(),
            _ScanModeToggle(mode: scanMode, onChanged: onScanModeChanged),
          ],
        ),
      ],
    );
  }
}

class _AnglePresetButton extends StatelessWidget {
  const _AnglePresetButton({
    required this.angle,
    required this.isActive,
    required this.enabled,
    required this.onTap,
  });

  final int angle;
  final bool isActive;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.textTertiary
        : isActive
        ? AppColors.info
        : AppColors.textSecondary;

    return Expanded(
      child: Semantics(
        button: true,
        selected: isActive,
        enabled: enabled,
        label: 'Set servo to $angle degrees',
        child: ExcludeSemantics(
          child: GestureDetector(
            onTap: enabled ? onTap : null,
            child: AnimatedContainer(
              duration: AppDurations.fast,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.info.withValues(alpha: 0.14)
                    : AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadii.xs),
                border: Border.all(
                  color: isActive ? AppColors.info : AppColors.border,
                ),
              ),
              child: Text(
                '$angle°',
                style: AppTypography.label.copyWith(color: color, fontSize: 10),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanModeToggle extends StatelessWidget {
  const _ScanModeToggle({required this.mode, required this.onChanged});

  final ScanMode mode;
  final ValueChanged<ScanMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final isScanning = mode == ScanMode.auto;

    return Semantics(
      button: true,
      toggled: isScanning,
      label: 'Continuous auto scan, currently ${isScanning ? "on" : "off"}',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () => onChanged(isScanning ? ScanMode.off : ScanMode.auto),
          child: AnimatedContainer(
            duration: AppDurations.fast,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isScanning
                  ? AppColors.info.withValues(alpha: 0.16)
                  : AppColors.surfaceElevated,
              borderRadius: AppRadii.pillRadius,
              border: Border.all(
                color: isScanning ? AppColors.info : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isScanning ? Icons.radar_rounded : Icons.radar_outlined,
                  size: 14,
                  color: isScanning ? AppColors.info : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  isScanning ? 'SCANNING' : 'OFF',
                  style: AppTypography.label.copyWith(
                    color: isScanning
                        ? AppColors.info
                        : AppColors.textSecondary,
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
