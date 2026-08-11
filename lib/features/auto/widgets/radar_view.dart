import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/settings.dart';
import '../../../models/telemetry.dart';

/// Servo-swept ultrasonic radar.
///
/// Draws a half-disc facing forward: 0° at the left edge, 180° at the right,
/// matching the servo's physical sweep. A sample at each angle is plotted at a
/// radius proportional to its distance; the sweep needle animates to the
/// vehicle's current servo angle. All rendering is a single [CustomPainter] so
/// the sweep can update every telemetry tick without rebuilding a widget tree.
class RadarView extends StatelessWidget {
  const RadarView({
    super.key,
    required this.telemetry,
    required this.settings,
    this.size = 260,
    this.compact = false,
    this.isSweeping = false,
  });

  final Telemetry telemetry;
  final AppSettings settings;
  final double size;

  /// Drops labels and rings for the small Drive-HUD preview.
  final bool compact;

  /// Brightens the needle and widens its trail while the servo is actually
  /// sweeping. Standing still, a radar drawn at full intensity implies the
  /// vehicle is scanning when it is not — the emphasis has to mean something.
  final bool isSweeping;

  /// Canvas angle (standard math convention) for a servo angle in degrees,
  /// 0–180. The sweep runs left→forward→right across the top half-plane.
  static double canvasAngleFor(double servoDegrees) =>
      math.pi * (1 + servoDegrees / 180);

  @override
  Widget build(BuildContext context) {
    final maxRange = (settings.cautionDistanceCm * 2.5)
        .clamp(80, AppConfig.sensorMaxRangeCm)
        .toDouble();

    final samples = <int, RadarSample>{
      for (final angle in AppConfig.radarAngles)
        angle:
            telemetry.radarSamples[angle] ??
            RadarSample(
              angle: angle,
              distanceCm: null,
              takenAt: DateTime.now(),
            ),
      ...telemetry.radarSamples,
    };

    return Semantics(
      label:
          'Radar. Servo at ${telemetry.servoAngle ?? 90} degrees. '
          'Left ${settings.units.format(telemetry.leftDistanceCm)}, '
          'centre ${settings.units.format(telemetry.centerDistanceCm)}, '
          'right ${settings.units.format(telemetry.rightDistanceCm)} '
          '${settings.units.shortLabel}.',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size / 2 + (compact ? 0 : 22),
          child: TweenAnimationBuilder<double>(
            tween: Tween(
              begin: 90,
              end: (telemetry.servoAngle ?? 90).toDouble(),
            ),
            duration: AppDurations.normal,
            curve: AppDurations.standard,
            builder: (context, angle, _) => CustomPaint(
              size: Size(size, size / 2 + (compact ? 0 : 22)),
              painter: _RadarPainter(
                sweepAngle: angle,
                samples: samples,
                maxRangeCm: maxRange,
                cautionCm: settings.cautionDistanceCm,
                dangerCm: settings.dangerDistanceCm,
                compact: compact,
                isSweeping: isSweeping,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({
    required this.sweepAngle,
    required this.samples,
    required this.maxRangeCm,
    required this.cautionCm,
    required this.dangerCm,
    required this.compact,
    required this.isSweeping,
  });

  final double sweepAngle;
  final Map<int, RadarSample> samples;
  final double maxRangeCm;
  final int cautionCm;
  final int dangerCm;
  final bool compact;
  final bool isSweeping;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height - (compact ? 4 : 22));
    final radius = math.min(
      size.width / 2 - 8,
      size.height - (compact ? 8 : 26),
    );

    _paintSector(canvas, origin, radius);
    _paintRings(canvas, origin, radius);
    _paintSpokes(canvas, origin, radius);
    _paintSweep(canvas, origin, radius);
    _paintSamples(canvas, origin, radius);
    _paintOrigin(canvas, origin);
  }

  void _paintSector(Canvas canvas, Offset origin, double radius) {
    final rect = Rect.fromCircle(center: origin, radius: radius);
    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      true,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.bottomCenter,
          radius: 1.3,
          colors: [AppColors.surfaceElevated, AppColors.surfaceSunken],
        ).createShader(rect),
    );
    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      true,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.borderStrong,
    );
  }

  void _paintRings(Canvas canvas, Offset origin, double radius) {
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.border.withValues(alpha: 0.7);

    for (final fraction in const [0.34, 0.67, 1.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: radius * fraction),
        math.pi,
        math.pi,
        false,
        ringPaint,
      );
    }

    // Danger-band ring, drawn distinctly so the threshold is visible at a
    // glance rather than only inferred from dot colour.
    final dangerFraction = (dangerCm / maxRangeCm).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: origin, radius: radius * dangerFraction),
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.danger.withValues(alpha: 0.35),
    );
  }

  void _paintSpokes(Canvas canvas, Offset origin, double radius) {
    final spokePaint = Paint()
      ..strokeWidth = 1
      ..color = AppColors.border.withValues(alpha: 0.6);

    for (final angle in AppConfig.radarAngles) {
      final canvasAngle = RadarView.canvasAngleFor(angle.toDouble());
      final direction = Offset(math.cos(canvasAngle), math.sin(canvasAngle));
      canvas.drawLine(origin, origin + direction * radius, spokePaint);

      if (compact) continue;

      final labelPos = origin + direction * (radius + 12);
      final painter = TextPainter(
        text: TextSpan(
          text: '$angle°',
          style: AppTypography.label.copyWith(fontSize: 8.5),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        labelPos - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  void _paintSweep(Canvas canvas, Offset origin, double radius) {
    final canvasAngle = RadarView.canvasAngleFor(sweepAngle);
    final direction = Offset(math.cos(canvasAngle), math.sin(canvasAngle));
    final tip = origin + direction * radius;

    canvas.drawLine(
      origin,
      tip,
      Paint()
        ..strokeWidth = isSweeping ? 3 : 2
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.9),
            AppColors.accent.withValues(alpha: 0.05),
          ],
        ).createShader(Rect.fromPoints(origin, tip)),
    );

    if (isSweeping) {
      // Bloom at the needle tip — the strongest cue that this is live, and the
      // one that survives being glanced at from across a room.
      canvas.drawCircle(
        tip,
        compact ? 4 : 6,
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // Wedge trailing the needle reads as motion even on a static frame.
    final trailSpan = isSweeping ? 0.30 : 0.14;
    final trailAngle = canvasAngle - trailSpan;
    final trailDirection = Offset(math.cos(trailAngle), math.sin(trailAngle));
    final path = Path()
      ..moveTo(origin.dx, origin.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(
        origin.dx + trailDirection.dx * radius,
        origin.dy + trailDirection.dy * radius,
      )
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent.withValues(
          alpha: isSweeping ? 0.16 : 0.08,
        ),
    );
  }

  void _paintSamples(Canvas canvas, Offset origin, double radius) {
    for (final sample in samples.values) {
      final canvasAngle = RadarView.canvasAngleFor(sample.angle.toDouble());
      final direction = Offset(math.cos(canvasAngle), math.sin(canvasAngle));

      final status = DistanceStatus.fromDistance(
        sample.distanceCm,
        cautionCm: cautionCm,
        dangerCm: dangerCm,
      );
      final color = AppColors.forStatus(status.level);

      final fraction = sample.hasReading
          ? (sample.distanceCm! / maxRangeCm).clamp(0.05, 1.0)
          : 1.0;
      final point = origin + direction * (radius * fraction);

      canvas.drawCircle(
        point,
        compact ? 3.5 : 5,
        Paint()..color = sample.hasReading ? color : AppColors.textTertiary,
      );
      if (sample.hasReading) {
        canvas.drawCircle(
          point,
          compact ? 6 : 9,
          Paint()
            ..color = color.withValues(alpha: 0.22)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
    }
  }

  void _paintOrigin(Canvas canvas, Offset origin) {
    canvas.drawCircle(origin, 4, Paint()..color = AppColors.textPrimary);
    canvas.drawCircle(
      origin,
      4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.background,
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.sweepAngle != sweepAngle ||
      !identical(old.samples, samples) ||
      old.maxRangeCm != maxRangeCm ||
      old.cautionCm != cautionCm ||
      old.dangerCm != dangerCm ||
      old.isSweeping != isSweeping;
}
