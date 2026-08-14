import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/vehicle.dart';
import '../../../models/vehicle_kind.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/connection_badge.dart';

/// One discovered device in the scan list.
class DeviceTile extends StatelessWidget {
  const DeviceTile({
    super.key,
    required this.vehicle,
    required this.kind,
    required this.onConnect,
    this.isConnecting = false,
    this.isConnected = false,
    this.isRemembered = false,
  });

  final DiscoveredVehicle vehicle;

  /// The vehicle kind currently being scanned for — decides the icon and
  /// which devices are flagged as "likely this vehicle".
  final VehicleKind kind;

  final VoidCallback onConnect;
  final bool isConnecting;
  final bool isConnected;
  final bool isRemembered;

  String get _statusLabel {
    if (isConnected) return 'Connected';
    if (isConnecting) return 'Connecting…';
    if (!vehicle.isConnectable) return 'Not connectable';
    return isRemembered ? 'Saved vehicle' : 'Available';
  }

  @override
  Widget build(BuildContext context) {
    final canConnect = vehicle.isConnectable && !isConnecting && !isConnected;
    final looksLikeVehicle = vehicle.looksLike(kind.nameHints);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        accent: looksLikeVehicle ? AppColors.accent : null,
        semanticLabel:
            '${vehicle.displayName}. $_statusLabel. '
            'Signal ${vehicle.signal.label}. '
            '${formatLastSeen(vehicle.lastSeen)}',
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(
                looksLikeVehicle
                    ? (kind == VehicleKind.spider
                          ? Icons.bug_report_rounded
                          : Icons.directions_car_rounded)
                    : Icons.bluetooth_rounded,
                size: 20,
                color: looksLikeVehicle
                    ? AppColors.accent
                    : AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          vehicle.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleMedium.copyWith(
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (isRemembered) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: AppColors.caution,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        _statusLabel,
                        style: AppTypography.bodySmall.copyWith(fontSize: 12),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SignalBars(quality: vehicle.signal, height: 11),
                      if (vehicle.rssi != null) ...[
                        const SizedBox(width: 5),
                        Text(
                          '${vehicle.rssi} dBm',
                          style: AppTypography.label.copyWith(fontSize: 9),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Freshness matters more than it looks: two rovers on a
                  // bench advertise identically, and "seen 14s ago" is often
                  // the only thing separating the one that is powered on from
                  // the one whose advert is still cached.
                  Text(
                    formatLastSeen(vehicle.lastSeen),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.label.copyWith(
                      fontSize: 9,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            AppButton(
              label: isConnected ? 'LINKED' : 'CONNECT',
              size: AppButtonSize.small,
              variant: isConnected
                  ? AppButtonVariant.ghost
                  : AppButtonVariant.secondary,
              isLoading: isConnecting,
              onPressed: canConnect ? onConnect : null,
              semanticLabel: 'Connect to ${vehicle.displayName}',
            ),
          ],
        ),
      ),
    );
  }
}
