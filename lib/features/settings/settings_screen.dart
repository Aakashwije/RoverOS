import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validation.dart';
import '../../models/commands.dart';
import '../../models/settings.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_modal.dart';
import '../../widgets/app_slider.dart';
import '../connection/connection_controller.dart';
import 'settings_controller.dart';
import 'widgets/motor_calibration_panel.dart';
import 'widgets/servo_calibration_panel.dart';
import 'widgets/settings_tile.dart';

/// App and vehicle configuration.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final link = ref.watch(connectionProvider);
    final controller = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('SETTINGS', style: AppTypography.labelStrong),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          children: [
            SettingsSection(
              title: 'VEHICLE',
              icon: Icons.directions_car_rounded,
              children: [
                SettingsRow(
                  label: 'Vehicle name',
                  description: settings.vehicleName,
                  icon: Icons.badge_outlined,
                  onTap: () => _editVehicleName(context, ref, settings),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: AppSlider(
                    label: 'MAXIMUM SPEED',
                    leadingIcon: Icons.speed_rounded,
                    value: settings.maxSpeedPercent.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 18,
                    unit: '%',
                    helperText: 'Caps every drive command the app sends.',
                    onChanged: (value) => controller.update(
                      (s) => s.copyWith(maxSpeedPercent: value.round()),
                    ),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'CONTROLS',
              icon: Icons.gamepad_rounded,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSlider(
                        label: 'JOYSTICK SENSITIVITY',
                        leadingIcon: Icons.tune_rounded,
                        value: settings.joystickSensitivity,
                        min: SettingsRange.minSensitivity,
                        max: SettingsRange.maxSensitivity,
                        divisions: 15,
                        valueFormatter: (v) => '${v.toStringAsFixed(1)}×',
                        helperText:
                            'Higher values respond more aggressively off-centre.',
                        onChanged: (value) => controller.update(
                          (s) => s.copyWith(joystickSensitivity: value),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppSlider(
                        label: 'DEAD ZONE',
                        leadingIcon: Icons.adjust_rounded,
                        value: settings.deadZonePercent.toDouble(),
                        min: SettingsRange.minDeadZonePercent.toDouble(),
                        max: SettingsRange.maxDeadZonePercent.toDouble(),
                        divisions: 40,
                        unit: '%',
                        helperText:
                            'Stick travel near centre treated as neutral.',
                        onChanged: (value) => controller.update(
                          (s) => s.copyWith(deadZonePercent: value.round()),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppSlider(
                        label: 'ACCELERATION',
                        leadingIcon: Icons.trending_up_rounded,
                        value: settings.accelerationRate,
                        min: SettingsRange.minRamp,
                        max: SettingsRange.maxRamp,
                        divisions: 19,
                        unit: '%/s',
                        helperText:
                            'How quickly output rises toward the stick position.',
                        onChanged: (value) => controller.update(
                          (s) => s.copyWith(accelerationRate: value),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppSlider(
                        label: 'DECELERATION',
                        leadingIcon: Icons.trending_down_rounded,
                        value: settings.decelerationRate,
                        min: SettingsRange.minRamp,
                        max: SettingsRange.maxRamp,
                        divisions: 19,
                        unit: '%/s',
                        helperText: 'How quickly output falls when easing off.',
                        onChanged: (value) => controller.update(
                          (s) => s.copyWith(decelerationRate: value),
                        ),
                      ),
                    ],
                  ),
                ),
                SettingsSwitchRow(
                  label: 'Haptic feedback',
                  description:
                      'Vibrate on joystick engagement and emergency stop',
                  icon: Icons.vibration_rounded,
                  value: settings.hapticsEnabled,
                  onChanged: (value) => controller.update(
                    (s) => s.copyWith(hapticsEnabled: value),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'MOTORS',
              icon: Icons.settings_input_component_rounded,
              subtitle: 'Direction and trim, sent to the vehicle on release',
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: MotorCalibrationPanel(
                    settings: settings,
                    isConnected: link.isConnected,
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'SENSORS',
              icon: Icons.sensors_rounded,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSlider(
                        label: 'MINIMUM OBSTACLE DISTANCE',
                        leadingIcon: Icons.front_hand_rounded,
                        value: settings.minObstacleDistanceCm.toDouble(),
                        min: SettingsRange.minDistanceCm.toDouble(),
                        max: SettingsRange.maxDistanceCm.toDouble(),
                        divisions: 39,
                        unit: 'cm',
                        color: AppColors.info,
                        helperText:
                            'Closest the vehicle will approach while avoiding.',
                        onChanged: (value) => controller.update(
                          (s) =>
                              s.copyWith(minObstacleDistanceCm: value.round()),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppSlider(
                        label: 'CAUTION THRESHOLD',
                        leadingIcon: Icons.warning_amber_rounded,
                        value: settings.cautionDistanceCm.toDouble(),
                        min: SettingsRange.minDistanceCm.toDouble(),
                        max: SettingsRange.maxDistanceCm.toDouble(),
                        divisions: 39,
                        unit: 'cm',
                        color: AppColors.caution,
                        onChanged: (value) => controller.update(
                          (s) => s.copyWith(cautionDistanceCm: value.round()),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppSlider(
                        label: 'DANGER THRESHOLD',
                        leadingIcon: Icons.error_outline_rounded,
                        value: settings.dangerDistanceCm.toDouble(),
                        min: SettingsRange.minDistanceCm.toDouble(),
                        max: SettingsRange.maxDistanceCm.toDouble(),
                        divisions: 39,
                        unit: 'cm',
                        color: AppColors.danger,
                        onChanged: (value) => controller.update(
                          (s) => s.copyWith(dangerDistanceCm: value.round()),
                        ),
                      ),
                      if (!Validators.distanceThresholds(
                        cautionCm: settings.cautionDistanceCm,
                        dangerCm: settings.dangerDistanceCm,
                      ).isValid) ...[
                        const SizedBox(height: AppSpacing.sm),
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
                                '${Validators.distanceThresholds(cautionCm: settings.cautionDistanceCm, dangerCm: settings.dangerDistanceCm).error!} '
                                '— corrected automatically when saved.',
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.caution,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      const Divider(),
                      const SizedBox(height: AppSpacing.lg),
                      ServoCalibrationPanel(settings: settings),
                    ],
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'LIGHTS',
              icon: Icons.lightbulb_rounded,
              children: [
                SettingsRow(
                  label: 'Default state',
                  description: 'Headlight mode when the vehicle connects',
                  icon: Icons.power_settings_new_rounded,
                  trailing: AppBadge(
                    label: settings.defaultLightMode.label,
                    level: StatusLevel.neutral,
                    showIcon: false,
                    size: AppBadgeSize.small,
                  ),
                  onTap: () => controller.update(
                    (s) => s.copyWith(
                      defaultLightMode:
                          LightMode.values[(s.defaultLightMode.index + 1) %
                              LightMode.values.length],
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Flash speed',
                  description: 'Rate the vehicle blinks in a flash mode',
                  icon: Icons.flash_on_rounded,
                  trailing: AppBadge(
                    label: settings.flashSpeed.label,
                    level: StatusLevel.neutral,
                    showIcon: false,
                    size: AppBadgeSize.small,
                  ),
                  onTap: () => controller.update(
                    (s) => s.copyWith(
                      flashSpeed: s.flashSpeed == FlashSpeed.slow
                          ? FlashSpeed.fast
                          : FlashSpeed.slow,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: AppSlider(
                    label: 'BRIGHTNESS',
                    leadingIcon: Icons.brightness_6_rounded,
                    value: settings.lightBrightness.toDouble(),
                    min: SettingsRange.minBrightness.toDouble(),
                    max: SettingsRange.maxBrightness.toDouble(),
                    divisions: 18,
                    unit: '%',
                    helperText:
                        'Requires PWM-capable headlight wiring on the vehicle.',
                    onChanged: (value) => controller.update(
                      (s) => s.copyWith(lightBrightness: value.round()),
                    ),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'CONNECTION',
              icon: Icons.bluetooth_rounded,
              children: [
                SettingsSwitchRow(
                  label: 'Auto reconnect',
                  description:
                      'Retry the saved vehicle with backoff after a dropout',
                  icon: Icons.autorenew_rounded,
                  value: settings.autoReconnect,
                  onChanged: (value) => controller.update(
                    (s) => s.copyWith(autoReconnect: value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: AppSlider(
                    label: 'WATCHDOG TIMEOUT',
                    leadingIcon: Icons.timer_outlined,
                    value: settings.commandTimeoutMs.toDouble(),
                    min: AppConfig.minCommandTimeoutMs.toDouble(),
                    max: AppConfig.maxCommandTimeoutMs.toDouble(),
                    divisions: 17,
                    unit: 'ms',
                    helperText:
                        'Vehicle stops on its own if no drive command arrives within '
                        'this window. Sent to the vehicle on connect.',
                    onChanged: (value) => controller.update(
                      (s) => s.copyWith(commandTimeoutMs: value.round()),
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Last vehicle',
                  description: link.hasRememberedDevice
                      ? link.displayName
                      : 'No vehicle saved on this phone',
                  icon: Icons.memory_rounded,
                ),
                if (link.hasRememberedDevice)
                  SettingsRow(
                    label: 'Forget vehicle',
                    description:
                        'Clear the saved device and start from a fresh scan',
                    icon: Icons.delete_outline_rounded,
                    isDestructive: true,
                    onTap: () => _forgetVehicle(context, ref),
                  ),
              ],
            ),
            SettingsSection(
              title: 'APP',
              icon: Icons.phone_android_rounded,
              children: [
                SettingsSwitchRow(
                  label: 'Mock car mode',
                  description:
                      'Drive a simulated rover. No Bluetooth commands are sent.',
                  icon: Icons.science_rounded,
                  value: settings.mockMode,
                  onChanged: (value) => _setMockMode(context, ref, value),
                ),
                SettingsRow(
                  label: 'Units',
                  description:
                      'Distance readouts use ${settings.units.shortLabel}',
                  icon: Icons.straighten_rounded,
                  trailing: AppBadge(
                    label: settings.units.label,
                    level: StatusLevel.neutral,
                    showIcon: false,
                    size: AppBadgeSize.small,
                  ),
                  onTap: () => controller.update(
                    (s) => s.copyWith(
                      units: s.units == DistanceUnits.metric
                          ? DistanceUnits.imperial
                          : DistanceUnits.metric,
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Reset to defaults',
                  description: 'Restore every setting to its factory value',
                  icon: Icons.restore_rounded,
                  isDestructive: true,
                  onTap: () => _resetSettings(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setMockMode(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final link = ref.read(connectionProvider);
    if (link.isConnected) {
      final confirmed = await AppModal.confirm(
        context,
        title: 'Disconnect vehicle?',
        message: enabled
            ? 'Switching to mock mode disconnects ${link.displayName}.'
            : 'Leaving mock mode disconnects the simulated vehicle.',
        confirmLabel: 'SWITCH',
        icon: Icons.swap_horiz_rounded,
      );
      if (!confirmed) return;
      await ref.read(connectionProvider.notifier).disconnect();
    }
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(mockMode: enabled));
  }

  Future<void> _forgetVehicle(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppModal.confirm(
      context,
      title: 'Forget this vehicle?',
      message:
          'ROVEROS will stop reconnecting automatically and you will need to scan '
          'for the vehicle again.',
      confirmLabel: 'FORGET',
      confirmVariant: AppButtonVariant.danger,
      level: StatusLevel.danger,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    await ref.read(connectionProvider.notifier).forgetDevice();
  }

  Future<void> _resetSettings(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppModal.confirm(
      context,
      title: 'Reset all settings?',
      message:
          'Speed limits, calibration and connection preferences return to their '
          'defaults. The saved vehicle is kept.',
      confirmLabel: 'RESET',
      confirmVariant: AppButtonVariant.danger,
      level: StatusLevel.danger,
      icon: Icons.restore_rounded,
    );
    if (!confirmed) return;
    ref.read(settingsProvider.notifier).resetToDefaults();
  }

  Future<void> _editVehicleName(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final controller = TextEditingController(text: settings.vehicleName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vehicle name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          style: AppTypography.body.copyWith(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'ESP32-CAR',
            counterStyle: TextStyle(color: AppColors.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(vehicleName: name));
  }
}
