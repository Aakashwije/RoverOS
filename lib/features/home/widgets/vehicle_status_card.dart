import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/commands.dart';
import '../../../models/connection_state.dart';
import '../../../models/telemetry.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/battery_indicator.dart';
import '../../../widgets/connection_badge.dart';
import '../../splash/widgets/rover_mark.dart';

/// Home's hero panel: the vehicle, its link, and its headline vitals.
///
/// Renders an explicit empty state rather than a card full of dashes when no
/// vehicle has ever been paired.
class VehicleStatusCard extends StatelessWidget {
  const VehicleStatusCard({
    super.key,
    required this.link,
    required this.telemetry,
    required this.driveMode,
    required this.onConnect,
  });

  final LinkState link;
  final Telemetry telemetry;
  final DriveMode driveMode;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    if (!link.isConnected) {
      return _DisconnectedCard(link: link, onConnect: onConnect);
    }

    return AppCard(
      elevated: true,
      accent: AppColors.good,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RoverMark(size: 64, animate: false),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('VEHICLE', style: AppTypography.label),
                    const SizedBox(height: 4),
                    Text(
                      link.displayName,
                      style: AppTypography.titleLarge.copyWith(fontSize: 22),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ConnectionBadge(link: link),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const Divider(),
          const SizedBox(height: AppSpacing.lg),
          BatteryIndicator(percent: telemetry.batteryPercent),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: _Vital(
                  label: 'SIGNAL',
                  value: link.signal.label,
                  icon: Icons.settings_input_antenna_rounded,
                  level: link.signal.level,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _Vital(
                  label: 'MODE',
                  value: driveMode.label,
                  icon: driveMode.isAutonomous
                      ? Icons.auto_mode_rounded
                      : Icons.sports_esports_rounded,
                  level: driveMode.isAutonomous
                      ? StatusLevel.info
                      : StatusLevel.neutral,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _Vital(
                  label: 'STATE',
                  value: (telemetry.vehicleState ?? VehicleState.idle).label,
                  icon: Icons.directions_car_rounded,
                  level: telemetry.vehicleState == VehicleState.fault
                      ? StatusLevel.danger
                      : StatusLevel.good,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Vital extends StatelessWidget {
  const _Vital({
    required this.label,
    required this.value,
    required this.icon,
    required this.level,
  });

  final String label;
  final String value;
  final IconData icon;
  final StatusLevel level;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(level);

    return Semantics(
      label: '$label $value',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(height: AppSpacing.sm),
              Text(label, style: AppTypography.label.copyWith(fontSize: 9.5)),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelStrong.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisconnectedCard extends StatelessWidget {
  const _DisconnectedCard({required this.link, required this.onConnect});

  final LinkState link;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final remembered = link.hasRememberedDevice;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Opacity(
            opacity: 0.4,
            child: const RoverMark(size: 84, animate: false),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            remembered ? 'Vehicle not connected' : 'No vehicle connected',
            style: AppTypography.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            remembered
                ? 'Last paired with ${link.displayName}. Reconnect to start driving.'
                : 'Pair with your ESP32 rover to unlock driving, telemetry and autonomous mode.',
            style: AppTypography.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: remembered ? 'RECONNECT VEHICLE' : 'CONNECT VEHICLE',
            icon: Icons.bluetooth_rounded,
            onPressed: onConnect,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}
