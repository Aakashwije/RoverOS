import 'package:flutter/services.dart';

/// Haptic feedback, gated by the user's setting.
///
/// Driving feedback has to be felt rather than watched, so engagement and the
/// emergency stop both buzz — but every call routes through here so the setting
/// is honoured in exactly one place.
abstract final class Haptics {
  /// Light tick — joystick engagement, toggle changes.
  static void light({required bool enabled}) {
    if (!enabled) return;
    HapticFeedback.lightImpact();
  }

  /// Medium tap — mode changes, preset selection.
  static void medium({required bool enabled}) {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// Strong, unmistakable feedback for the emergency stop.
  ///
  /// Deliberately not gated by the setting: E-STOP confirmation is a safety
  /// signal, not a nicety, and the user should feel it even with haptics off.
  static void emergency() {
    HapticFeedback.heavyImpact();
  }

  /// Selection tick for discrete steps, e.g. crossing a speed preset.
  static void selection({required bool enabled}) {
    if (!enabled) return;
    HapticFeedback.selectionClick();
  }
}
