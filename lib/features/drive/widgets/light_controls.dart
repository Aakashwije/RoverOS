import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/commands.dart';
import '../../../widgets/app_icon_button.dart';

/// Headlight and flash-mode controls.
///
/// Each button names a mode. The ESP32 performs all flash timing — the app
/// never toggles the LED itself, so a dropped packet can't leave the lights
/// stuck mid-blink.
class LightControls extends StatelessWidget {
  const LightControls({
    super.key,
    required this.mode,
    required this.onChanged,
    this.enabled = true,
    this.compact = false,
    this.visibleModes,
  });

  final LightMode mode;
  final ValueChanged<LightMode> onChanged;
  final bool enabled;

  /// Icon-only row for the Drive HUD; the labelled layout is for sheets.
  final bool compact;

  /// Restricts the row to a subset. The drive HUD shows three, because five
  /// 48dp buttons plus a horn plus the emergency-stop zone do not fit across a
  /// narrow landscape phone — and the two flash rates are a sheet-level
  /// decision, not something reached for mid-drive.
  final List<LightMode>? visibleModes;

  static const List<({LightMode mode, IconData icon, String label})> _modes = [
    (mode: LightMode.off, icon: Icons.light_mode_outlined, label: 'OFF'),
    (mode: LightMode.on, icon: Icons.lightbulb_rounded, label: 'ON'),
    (mode: LightMode.flashSlow, icon: Icons.flash_on_rounded, label: 'SLOW'),
    (mode: LightMode.flashFast, icon: Icons.bolt_rounded, label: 'FAST'),
    (
      mode: LightMode.hazard,
      icon: Icons.warning_amber_rounded,
      label: 'HAZARD',
    ),
  ];

  List<({LightMode mode, IconData icon, String label})> get _visible {
    final allowed = visibleModes;
    if (allowed == null) return _modes;
    return _modes.where((entry) => allowed.contains(entry.mode)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visible;

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in entries) ...[
            AppIconButton(
              icon: entry.icon,
              semanticLabel: 'Headlights ${entry.label}',
              tooltip: 'Headlights ${entry.label}',
              size: 48,
              isActive: entry.mode == mode,
              activeColor: entry.mode == LightMode.hazard
                  ? AppColors.caution
                  : AppColors.headlight,
              onPressed: enabled ? () => onChanged(entry.mode) : null,
            ),
            if (entry != entries.last) const SizedBox(width: AppSpacing.sm),
          ],
        ],
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final entry in entries)
          _LightModeChip(
            icon: entry.icon,
            label: entry.label,
            isActive: entry.mode == mode,
            isHazard: entry.mode == LightMode.hazard,
            onTap: enabled ? () => onChanged(entry.mode) : null,
          ),
      ],
    );
  }
}

class _LightModeChip extends StatelessWidget {
  const _LightModeChip({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isHazard,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final bool isHazard;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = isHazard ? AppColors.caution : AppColors.headlight;
    final color = onTap == null
        ? AppColors.textTertiary
        : isActive
        ? accent
        : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: isActive,
      enabled: onTap != null,
      label: 'Headlight mode $label',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? accent.withValues(alpha: 0.14)
                  : AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(color: isActive ? accent : AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: AppSpacing.sm),
                Text(label, style: AppTypography.label.copyWith(color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
