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
    /// still-sold Android/iOS devices up to a large phone. The 280–300 rows
    /// are the case where system bars eat into an already short screen.
    const widths = [480.0, 568.0, 640.0, 720.0, 812.0, 926.0];
    const heights = [280.0, 300.0, 320.0, 360.0, 400.0, 440.0];

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

        test('the joystick column fits vertically at ${width}x$height', () {
          final metrics = DriveHudMetrics.compute(Size(width, height));
          final controlHeight = height - DriveHudMetrics.chromeHeight;

          expect(
            metrics.claimedJoystickColumnHeight,
            lessThanOrEqualTo(controlHeight + 0.01),
            reason:
                'stick(${metrics.joystickSize}) plus readout'
                '(${metrics.motorReadoutHeight}) exceeds the $controlHeight '
                'available at ${width}x$height',
          );
        });
      }
    }

    test('the motor readout is dropped rather than squeezed when short', () {
      // At this height the stick has already hit its usable floor, so there is
      // nothing left to give the readout. Half a readout is worse than none.
      final cramped = DriveHudMetrics.compute(const Size(480, 280));
      expect(cramped.showMotorReadout, isFalse);
      expect(cramped.motorReadoutHeight, 0);

      final roomy = DriveHudMetrics.compute(const Size(480, 400));
      expect(roomy.showMotorReadout, isTrue);
      expect(
        roomy.motorReadoutHeight,
        DriveHudMetrics.preferredMotorReadoutHeight,
      );
    });

    test('the readout is never rendered at a partial height', () {
      // All-or-nothing: any intermediate value would be a readout whose bars
      // have nowhere to go.
      for (var height = 260.0; height <= 500; height += 4) {
        final metrics = DriveHudMetrics.compute(Size(640, height));
        expect(
          metrics.motorReadoutHeight,
          anyOf(0.0, DriveHudMetrics.preferredMotorReadoutHeight),
          reason: 'partial readout height at 640x$height',
        );
      }
    });

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

    test('the chrome allowance covers the bars it is meant to reserve', () {
      // Top bar: a 42dp control with 8dp of padding above and below.
      // Bottom bar: the stop zone with 8dp above and 12dp below.
      const topBar = 42 + 8 * 2;
      const bottomBar = DriveHudMetrics.emergencyStopHeight + 8 + 12;
      expect(
        DriveHudMetrics.chromeHeight,
        greaterThanOrEqualTo(topBar + bottomBar),
      );
    });
  });
}
