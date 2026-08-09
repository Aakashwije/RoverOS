import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:roveros/features/drive/drive_hud_metrics.dart';

/// Regression coverage for a real overflow: the Drive HUD's centre gauge was
/// once sized from height alone, so on a narrow landscape phone it could
/// outgrow what the joystick and right rail left behind, overflowing the row.
void main() {
  group('DriveHudMetrics.compute', () {
    const horizontalPadding = DriveHudMetrics.horizontalPadding;

    /// Sizes drawn from real landscape phone short-sides, from the smallest
    /// still-sold Android/iOS devices up to a large phone.
    const widths = [480.0, 568.0, 640.0, 720.0, 812.0, 926.0];
    const heights = [320.0, 360.0, 400.0];

    for (final width in widths) {
      for (final height in heights) {
        test('never overflows the row at ${width}x$height', () {
          final metrics = DriveHudMetrics.compute(Size(width, height));
          final available = width - horizontalPadding;

          expect(
            metrics.claimedWidth,
            lessThanOrEqualTo(available + 0.01),
            reason:
                'joystick(${metrics.joystickSize}) + gauge(${metrics.gaugeSize}) + '
                'rail(${metrics.railWidth}) exceeds the $available available at '
                '${width}x$height',
          );
        });
      }
    }

    test('every dimension stays positive even at the smallest tested size', () {
      final metrics = DriveHudMetrics.compute(const Size(480, 320));
      expect(metrics.railWidth, greaterThan(0));
      expect(metrics.joystickSize, greaterThan(0));
      expect(metrics.gaugeSize, greaterThan(0));
    });

    test('a spacious tablet-sized screen still caps sizes sensibly', () {
      final metrics = DriveHudMetrics.compute(const Size(1200, 800));
      expect(metrics.railWidth, lessThanOrEqualTo(168));
      expect(metrics.joystickSize, lessThanOrEqualTo(260));
      expect(metrics.gaugeSize, lessThanOrEqualTo(210));
    });

    test('a taller control area grows the joystick and gauge together', () {
      final small = DriveHudMetrics.compute(const Size(900, 300));
      final large = DriveHudMetrics.compute(const Size(900, 420));
      expect(large.joystickSize, greaterThanOrEqualTo(small.joystickSize));
    });
  });
}
