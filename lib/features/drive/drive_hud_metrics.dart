import 'dart:ui' show Size;

import '../../core/theme/app_theme.dart';

/// Sizes for the Drive HUD's three columns (joystick, speed gauge, right
/// rail), derived from the space actually available.
///
/// Pulled out as a pure function — rather than inline in the widget's
/// [LayoutBuilder] — so the layout math can be unit-tested directly across a
/// range of screen sizes without pumping a widget tree.
class DriveHudMetrics {
  const DriveHudMetrics({
    required this.railWidth,
    required this.joystickSize,
    required this.gaugeSize,
  });

  final double railWidth;
  final double joystickSize;
  final double gaugeSize;

  /// Total width the three columns claim, excluding the outer padding that
  /// [compute] already accounts for. Callers can use this to sanity-check
  /// that a layout fits: `railWidth + joystickSize + gaugeSize` should never
  /// exceed the available width minus [horizontalPadding].
  double get claimedWidth => railWidth + joystickSize + gaugeSize;

  static const double horizontalPadding = AppSpacing.lg * 2;

  /// Reserved height for the top bar and bottom bar combined.
  static const double chromeHeight = 120;

  static DriveHudMetrics compute(Size available) {
    final controlHeight = available.height - chromeHeight;

    final railWidth = (available.width * 0.26).clamp(120.0, 168.0);
    final joystickSize = controlHeight
        .clamp(140.0, 260.0)
        .clamp(120.0, available.width * 0.36);

    final centerWidth =
        (available.width - horizontalPadding - joystickSize - railWidth).clamp(
          90.0,
          double.infinity,
        );
    final heightBoundGauge = (controlHeight * 0.85).clamp(120.0, 210.0);
    final gaugeSize = heightBoundGauge < centerWidth - 16
        ? heightBoundGauge
        : (centerWidth - 16).clamp(90.0, heightBoundGauge);

    return DriveHudMetrics(
      railWidth: railWidth,
      joystickSize: joystickSize,
      gaugeSize: gaugeSize,
    );
  }
}
