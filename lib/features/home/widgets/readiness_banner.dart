import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/commands.dart';
import '../../../models/connection_state.dart';
import '../../../models/telemetry.dart';

/// One-line answer to "can I drive right now?".
///
/// Deliberately states the reason, not just the state — a driver glancing at
/// the phone should not have to infer why the car will not move.
class ReadinessBanner extends StatelessWidget {
  const ReadinessBanner({
    super.key,
    required this.link,
    required this.telemetry,
    required this.isMockMode,
  });

  final LinkState link;
  final Telemetry telemetry;
  final bool isMockMode;

  ({String title, String detail, StatusLevel level, IconData icon})
  get _readiness {
    if (!link.isConnected) {
      return (
        title: 'VEHICLE OFFLINE',
        detail: link.hasRememberedDevice
            ? 'Reconnect to ${link.displayName} to start driving'
            : 'Pair a vehicle to start driving',
        level: StatusLevel.neutral,
        icon: Icons.power_settings_new_rounded,
      );
    }

    if (telemetry.batteryStatus == BatteryStatus.critical) {
      return (
        title: 'CRITICAL BATTERY',
        detail: 'Charge the pack before driving',
        level: StatusLevel.danger,
        icon: Icons.battery_alert_rounded,
      );
    }

    if (telemetry.vehicleState == VehicleState.fault) {
      return (
        title: 'VEHICLE FAULT',
        detail: 'Clear the reported fault before driving',
        level: StatusLevel.danger,
        icon: Icons.report_problem_rounded,
      );
    }

    if (telemetry.batteryStatus == BatteryStatus.low) {
      return (
        title: 'READY — LOW BATTERY',
        detail: 'Vehicle will drive, but range is limited',
        level: StatusLevel.caution,
        icon: Icons.battery_2_bar_rounded,
      );
    }

    return (
      title: isMockMode ? 'READY — MOCK VEHICLE' : 'VEHICLE READY',
      detail: isMockMode
          ? 'Simulated rover: no hardware commands are sent'
          : 'All systems nominal. Ready to drive.',
      level: isMockMode ? StatusLevel.info : StatusLevel.good,
      icon: isMockMode ? Icons.science_rounded : Icons.check_circle_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final readiness = _readiness;
    final color = AppColors.forStatus(readiness.level);

    return Semantics(
      liveRegion: true,
      label: '${readiness.title}. ${readiness.detail}',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: AppDurations.normal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: AppRadii.cardRadius,
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(readiness.icon, size: 20, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      readiness.title,
                      style: AppTypography.labelStrong.copyWith(color: color),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      readiness.detail,
                      style: AppTypography.bodySmall.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
