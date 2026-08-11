import 'dart:math' as math;
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
    required this.motorReadoutHeight,
  });

  final double railWidth;
  final double joystickSize;
  final double gaugeSize;

  /// Height available to the live motor readout under the stick, or zero on a
  /// screen too short to carry both.
  final double motorReadoutHeight;

  bool get showMotorReadout => motorReadoutHeight > 0;

  /// Total width the three columns claim, excluding the outer padding that
  /// [compute] already accounts for. Callers can use this to sanity-check
  /// that a layout fits: `railWidth + joystickSize + gaugeSize` should never
  /// exceed the available width minus [horizontalPadding].
  double get claimedWidth => railWidth + joystickSize + gaugeSize;

  /// Total height the joystick column claims, stick plus readout plus the gap
  /// between them. Must not exceed the control area's height.
  double get claimedJoystickColumnHeight =>
      joystickSize + (showMotorReadout ? columnGap + motorReadoutHeight : 0);

  static const double horizontalPadding = AppSpacing.lg * 2;

  /// Reserved height for the top bar and bottom bar combined.
  ///
  /// Top bar: 42dp control plus 8dp of padding above and below. Bottom bar:
  /// the 64dp emergency-stop zone plus 8dp above and 12dp below. The stop
  /// button is the reason this is as large as it is — it was given its own
  /// zone rather than a slot in a row of equals.
  static const double chromeHeight = 142;

  /// Height the motor readout is given when there is room for it.
  ///
  /// All-or-nothing: a readout at 70% height is a readout whose bars have
  /// nowhere to go, so a screen that cannot fit it gets a bigger stick
  /// instead.
  static const double preferredMotorReadoutHeight = 46;

  /// Gap between the joystick and its readout.
  static const double columnGap = AppSpacing.sm;

  /// Height of the emergency-stop zone in the bottom bar.
  static const double emergencyStopHeight = 64;

  /// Absolute floor for the stick. Below this it stops being drivable with a
  /// thumb, at which point a cramped layout is the lesser problem.
  static const double _minJoystick = 110;
  static const double _maxJoystick = 260;

  static DriveHudMetrics compute(Size available) {
    final controlHeight = available.height - chromeHeight;

    final railWidth = (available.width * 0.26).clamp(120.0, 168.0);
    final widthBound = available.width * 0.36;

    // The stick is bounded by three things at once, and the smallest wins.
    // Taking the minimum *before* clamping matters: a clamp whose floor
    // exceeds the height budget silently reintroduces the overflow it was
    // meant to prevent.
    double fit(double heightBudget) => math
        .min(math.min(heightBudget, widthBound), _maxJoystick)
        .clamp(_minJoystick, _maxJoystick);

    var joystickSize = fit(
      controlHeight - preferredMotorReadoutHeight - columnGap,
    );
    var motorReadoutHeight = preferredMotorReadoutHeight;

    if (joystickSize + columnGap + preferredMotorReadoutHeight >
        controlHeight) {
      // Not enough height for both — the stick has hit its usable floor. The
      // stick is the control; the readout is commentary on it, so the readout
      // is what goes.
      motorReadoutHeight = 0;
      joystickSize = fit(controlHeight);
    }

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
      motorReadoutHeight: motorReadoutHeight,
    );
  }
}
