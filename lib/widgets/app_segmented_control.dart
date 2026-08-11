import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// One choice in an [AppSegmentedControl].
class SegmentOption<T> {
  const SegmentOption({
    required this.value,
    required this.label,
    required this.icon,
    this.semanticHint,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData icon;

  /// Extra sentence for screen readers, e.g. that a segment asks for
  /// confirmation before it takes effect.
  final String? semanticHint;

  final bool enabled;
}

/// Equal-width mode selector.
///
/// Used where the options are mutually exclusive states of one thing — drive
/// mode, scan behaviour — and stacking them as cards would make choosing feel
/// heavier than it is. The selected segment is marked by a filled pill *and* a
/// bolder label, so selection does not rest on colour alone.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.accent = AppColors.accent,
    this.enabled = true,
    this.height = 60,
  });

  final List<SegmentOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Color accent;
  final bool enabled;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: _Segment<T>(
                option: option,
                isSelected: option.value == value,
                accent: accent,
                enabled: enabled && option.enabled,
                onTap: () => onChanged(option.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.option,
    required this.isSelected,
    required this.accent,
    required this.enabled,
    required this.onTap,
  });

  final SegmentOption<T> option;
  final bool isSelected;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = !enabled
        ? AppColors.textTertiary
        : isSelected
        ? accent
        : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: isSelected,
      enabled: enabled,
      label: option.semanticHint == null
          ? option.label
          : '${option.label}. ${option.semanticHint}',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            curve: AppDurations.standard,
            decoration: BoxDecoration(
              color: isSelected
                  ? accent.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(
                color: isSelected
                    ? accent.withValues(alpha: 0.55)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(option.icon, size: 18, color: foreground),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.label.copyWith(
                      fontSize: 9.5,
                      color: foreground,
                      fontWeight: isSelected
                          ? FontWeight.w900
                          : FontWeight.w700,
                    ),
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
