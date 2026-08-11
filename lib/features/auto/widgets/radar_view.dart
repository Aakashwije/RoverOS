import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/perception/perception_engine.dart';
import '../../../core/perception/radar_field.dart';
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
///
/// Supplying [perception] adds the app's own reading of the same sweep on top:
/// the traversable gap, and chords across the returns that resolved into a flat
/// surface. Those are drawn in a single deliberately un-alarming colour —
/// they are the phone's inference, not the vehicle's decision, and they must
/// never be mistaken for one.
class RadarView extends StatelessWidget {
  const RadarView({
    super.key,
    required this.telemetry,
    required this.settings,
    this.size = 260,
    this.compact = false,
    this.isSweeping = false,
    this.perception,
  });

  final Telemetry telemetry;
  final AppSettings settings;
  final double size;

  /// Drops labels and rings for the small Drive-HUD preview.
  final bool compact;

  /// Inferred gaps and surfaces. Omit to draw the raw sweep alone.
  final PerceptionSnapshot? perception;

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

    final field = perception?.field;

    return Semantics(
      label:
          'Radar. Servo at ${telemetry.servoAngle ?? 90} degrees. '
          'Left ${settings.units.format(telemetry.leftDistanceCm)}, '
          'centre ${settings.units.format(telemetry.centerDistanceCm)}, '
          'right ${settings.units.format(telemetry.rightDistanceCm)} '
          '${settings.units.shortLabel}.'
          '${field != null && field.hasData ? " ${field.summary}." : ""}',
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
                field: field,
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
    this.field,
  });

  final double sweepAngle;
  final Map<int, RadarSample> samples;
  final double maxRangeCm;
  final int cautionCm;
  final int dangerCm;
  final bool compact;
  final bool isSweeping;
  final FieldAnalysis? field;

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
    // Under the samples: inference is background, measurement is foreground.
    _paintGap(canvas, origin, radius);
    _paintSweep(canvas, origin, radius);
    _paintSurfaces(canvas, origin, radius);
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

  /// The route the app would take, if it were the one driving. It is not: this
  /// is a wedge and a chevron, drawn so the driver can see the opening the
  /// rover is about to have to thread.
  void _paintGap(Canvas canvas, Offset origin, double radius) {
    final gap = field?.recommended;
    if (gap == null) return;

    final startAngle = RadarView.canvasAngleFor(gap.startDegrees.toDouble());
    final sweep = math.pi * (gap.endDegrees - gap.startDegrees) / 180;

    canvas.drawArc(
      Rect.fromCircle(center: origin, radius: radius),
      startAngle,
      sweep,
      true,
      Paint()
        // A gap resting on bearings the sweep never covered is a guess, and
        // it is drawn at half strength so it cannot pass for a measurement.
        ..color = AppColors.info.withValues(
          alpha: gap.isFullyObserved ? 0.15 : 0.07,
        ),
    );

    final canvasAngle = RadarView.canvasAngleFor(gap.headingDegrees.toDouble());
    final direction = Offset(math.cos(canvasAngle), math.sin(canvasAngle));
    final line = Paint()
      ..strokeWidth = compact ? 1.5 : 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..color = AppColors.info.withValues(alpha: 0.75);

    final tip = origin + direction * (radius - 2);
    canvas.drawLine(origin, tip, line);

    final barb = compact ? 6.0 : 9.0;
    final back = math.atan2(-direction.dy, -direction.dx);
    canvas.drawPath(
      Path()
        ..moveTo(
          tip.dx + math.cos(back - 0.4) * barb,
          tip.dy + math.sin(back - 0.4) * barb,
        )
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(
          tip.dx + math.cos(back + 0.4) * barb,
          tip.dy + math.sin(back + 0.4) * barb,
        ),
      line,
    );
  }

  /// Chords across the returns that resolved into one flat surface. Two dots
  /// joined by a line read as a wall; the same two dots alone read as two
  /// objects, and the difference matters when deciding where to steer.
  void _paintSurfaces(Canvas canvas, Offset origin, double radius) {
    final surfaces = field?.surfaces;
    if (surfaces == null) return;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 1.5 : 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.info.withValues(alpha: 0.5);

    for (final surface in surfaces) {
      if (surface.kind != SurfaceKind.wall &&
          surface.kind != SurfaceKind.corner) {
        continue;
      }

      final plotted = <({int angle, Offset at})>[];
      for (final sample in samples.values) {
        final distance = sample.distanceCm;
        if (distance == null) continue;
        if (sample.angle < surface.startDegrees) continue;
        if (sample.angle > surface.endDegrees) continue;
        plotted.add((
          angle: sample.angle,
          at: _plot(origin, radius, sample.angle, distance),
        ));
      }
      if (plotted.length < 2) continue;
      plotted.sort((a, b) => a.angle.compareTo(b.angle));

      final path = Path()..moveTo(plotted.first.at.dx, plotted.first.at.dy);
      for (final point in plotted.skip(1)) {
        path.lineTo(point.at.dx, point.at.dy);
      }
      canvas.drawPath(path, stroke);
    }
  }

  /// Where a reading at [angleDegrees] and [distanceCm] lands on the disc.
  Offset _plot(
    Offset origin,
    double radius,
    int angleDegrees,
    int distanceCm,
  ) {
    final canvasAngle = RadarView.canvasAngleFor(angleDegrees.toDouble());
    final fraction = (distanceCm / maxRangeCm).clamp(0.05, 1.0).toDouble();
    return origin +
        Offset(math.cos(canvasAngle), math.sin(canvasAngle)) *
            (radius * fraction);
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
      !identical(old.field, field) ||
      old.maxRangeCm != maxRangeCm ||
      old.cautionCm != cautionCm ||
      old.dangerCm != dangerCm ||
      old.isSweeping != isSweeping;
}
