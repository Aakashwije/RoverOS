import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/connection_state.dart';
import 'app_badge.dart';

/// Connection status pill with signal bars.
///
/// Reads the whole [LinkState] rather than a boolean so transient states
/// (scanning, reconnecting) are shown honestly instead of collapsing to
/// "disconnected".
class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({
    super.key,
    required this.link,
    this.showSignal = true,
    this.size = AppBadgeSize.medium,
  });

  final LinkState link;
  final bool showSignal;
  final AppBadgeSize size;

  IconData get _icon => switch (link.status) {
    ConnectionStatus.connected => Icons.bluetooth_connected_rounded,
    ConnectionStatus.scanning => Icons.bluetooth_searching_rounded,
    ConnectionStatus.connecting ||
    ConnectionStatus.reconnecting => Icons.bluetooth_searching_rounded,
    ConnectionStatus.bluetoothOff => Icons.bluetooth_disabled_rounded,
    ConnectionStatus.permissionRequired => Icons.lock_outline_rounded,
    ConnectionStatus.error => Icons.error_outline_rounded,
    ConnectionStatus.disconnected => Icons.bluetooth_disabled_rounded,
    ConnectionStatus.idle => Icons.bluetooth_rounded,
  };

  String get _label =>
      link.isMock && link.isConnected ? 'MOCK LINK' : link.status.label;

  @override
  Widget build(BuildContext context) {
    final badge = AppBadge(
      label: _label,
      level: link.status.level,
      icon: _icon,
      size: size,
      semanticLabel: '${link.status.label}. ${link.status.description}',
    );

    if (!showSignal || !link.isConnected) return badge;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(width: AppSpacing.sm),
        SignalBars(quality: link.signal),
      ],
    );
  }
}

/// Four-bar signal meter. Bar *count* carries the meaning; colour reinforces it.
class SignalBars extends StatelessWidget {
  const SignalBars({
    super.key,
    required this.quality,
    this.height = 14,
    this.showLabel = false,
  });

  final SignalQuality quality;
  final double height;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(quality.level);

    return Semantics(
      label: 'Signal ${quality.label}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var bar = 1; bar <= 4; bar++) ...[
              AnimatedContainer(
                duration: AppDurations.normal,
                width: 3,
                height: height * (0.35 + 0.22 * (bar - 1)),
                decoration: BoxDecoration(
                  color: bar <= quality.bars
                      ? color
                      : AppColors.borderStrong.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              if (bar < 4) const SizedBox(width: 2),
            ],
            if (showLabel) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                quality.label,
                style: AppTypography.label.copyWith(color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
