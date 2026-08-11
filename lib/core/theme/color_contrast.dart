import 'dart:math' as math;
import 'dart:ui' show Color;

/// WCAG 2.1 contrast maths.
///
/// This lives in `lib/` rather than beside the tests because the palette's
/// accessibility guarantees are asserted against the real shipped colours —
/// a copy of these formulas in the test folder could drift from the values the
/// app actually paints.
abstract final class ColorContrast {
  /// Minimum ratio for body text and any label carrying meaning (WCAG AA).
  static const double aaText = 4.5;

  /// Minimum ratio for large text, icons and other non-text graphics.
  static const double aaLarge = 3.0;

  static double _linearize(double channel) => channel <= 0.03928
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

  /// WCAG relative luminance: 0 for black, 1 for white.
  ///
  /// Also doubles as the greyscale value a monochrome or severely
  /// colour-blind viewer perceives, which is why [ratio] between two *status*
  /// colours is a meaningful "can these be told apart without hue" measure.
  static double relativeLuminance(Color color) =>
      0.2126 * _linearize(color.r) +
      0.7152 * _linearize(color.g) +
      0.0722 * _linearize(color.b);

  /// Contrast ratio between two opaque colours, 1.0 (identical) – 21.0.
  static double ratio(Color a, Color b) {
    final la = relativeLuminance(a);
    final lb = relativeLuminance(b);
    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static bool meetsAA(Color foreground, Color background) =>
      ratio(foreground, background) >= aaText;

  static bool meetsAALarge(Color foreground, Color background) =>
      ratio(foreground, background) >= aaLarge;
}
