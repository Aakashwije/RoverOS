import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Labelled slider for settings and speed control.
///
/// [onChanged] fires continuously for live UI; [onChangeEnd] is where callers
/// should commit — persisting or transmitting on every drag frame is exactly
/// the pattern this app avoids.
class AppSlider extends StatelessWidget {
  const AppSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.onChanged,
    this.onChangeEnd,
    this.divisions,
    this.unit = '',
    this.valueFormatter,
    this.color = AppColors.accent,
    this.helperText,
    this.leadingIcon,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final int? divisions;
  final String unit;

  /// Overrides the default rounded-integer display.
  final String Function(double value)? valueFormatter;

  final Color color;
  final String? helperText;
  final IconData? leadingIcon;

  bool get isEnabled => onChanged != null;

  String get _displayValue =>
      valueFormatter?.call(value) ?? '${value.round()}$unit';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      slider: true,
      enabled: isEnabled,
      label: label,
      value: _displayValue,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (leadingIcon != null) ...[
                  Icon(leadingIcon, size: 14, color: AppColors.textTertiary),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(child: Text(label, style: AppTypography.label)),
                Text(
                  _displayValue,
                  style: AppTypography.labelStrong.copyWith(
                    color: isEnabled ? color : AppColors.textTertiary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: isEnabled ? color : AppColors.borderStrong,
                inactiveTrackColor: AppColors.surfaceSunken,
                thumbColor: isEnabled ? color : AppColors.textTertiary,
                overlayColor: color.withValues(alpha: 0.18),
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                activeTickMarkColor: Colors.transparent,
                inactiveTickMarkColor: Colors.transparent,
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
            if (helperText != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  helperText!,
                  style: AppTypography.bodySmall.copyWith(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
