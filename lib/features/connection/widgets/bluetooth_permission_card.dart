import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/bluetooth_permission_service.dart';
import '../../../widgets/app_button.dart';

/// Gates the scan/connect flow behind an explained, actionable permission
/// state instead of letting the OS prompt appear (or silently fail) out of
/// context.
///
/// Shown in place of the device list whenever
/// [RoverPermissionStatus] is not [RoverPermissionStatus.granted].
class BluetoothPermissionCard extends StatelessWidget {
  const BluetoothPermissionCard({
    super.key,
    required this.status,
    required this.onRequest,
    required this.onOpenSettings,
  });

  final RoverPermissionStatus status;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  ({
    IconData icon,
    String title,
    String body,
    String action,
    IconData actionIcon,
    VoidCallback onAction,
  })
  get _content => switch (status) {
    RoverPermissionStatus.denied => (
      icon: Icons.bluetooth_rounded,
      title: 'BLUETOOTH ACCESS NEEDED',
      body:
          'ROVEROS uses Bluetooth to find and connect to your rover. It is '
          "only used to talk to your vehicle — never for location tracking "
          'or ads.',
      action: 'ALLOW BLUETOOTH',
      actionIcon: Icons.bluetooth_rounded,
      onAction: onRequest,
    ),
    RoverPermissionStatus.permanentlyDenied => (
      icon: Icons.bluetooth_disabled_rounded,
      title: 'BLUETOOTH ACCESS BLOCKED',
      body:
          "Bluetooth permission was denied, so the OS won't show that "
          'prompt again. Enable it for ROVEROS in Settings to find and '
          'connect to your rover.',
      action: 'OPEN SETTINGS',
      actionIcon: Icons.settings_rounded,
      onAction: onOpenSettings,
    ),
    RoverPermissionStatus.restricted => (
      icon: Icons.block_rounded,
      title: 'BLUETOOTH RESTRICTED',
      body:
          'Bluetooth access is restricted on this device, likely by a '
          "parental control or management profile. Check the device's "
          'Settings, or ask whoever manages it to allow Bluetooth for '
          'ROVEROS.',
      action: 'OPEN SETTINGS',
      actionIcon: Icons.settings_rounded,
      onAction: onOpenSettings,
    ),
    // The caller only renders this card while permission is outstanding.
    RoverPermissionStatus.granted => throw StateError(
      'BluetoothPermissionCard must not be shown once permission is granted',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final content = _content;
    final color = status == RoverPermissionStatus.denied
        ? AppColors.info
        : AppColors.caution;

    return Semantics(
      container: true,
      label: '${content.title}. ${content.body}',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: AppRadii.cardRadius,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(content.icon, size: 26, color: color),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              content.title,
              textAlign: TextAlign.center,
              style: AppTypography.labelStrong.copyWith(color: color),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              content.body,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: content.action,
              icon: content.actionIcon,
              size: AppButtonSize.medium,
              fullWidth: true,
              onPressed: content.onAction,
            ),
          ],
        ),
      ),
    );
  }
}
