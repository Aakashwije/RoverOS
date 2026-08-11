import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// The ROVEROS logo: a top-down 4WD chassis with a sweeping sensor arc.
///
/// Drawn rather than shipped as an asset so it scales cleanly at any size and
/// can animate its draw-in and servo sweep.
class RoverMark extends StatefulWidget {
  const RoverMark({
    super.key,
    this.size = 132,
    this.animate = true,
    this.color = AppColors.accent,
  });

  final double size;

  /// When false the mark renders fully drawn and static — for use as an inline
  /// icon where a looping animation would be noise.
  final bool animate;

  final Color color;

  @override
  State<RoverMark> createState() => _RoverMarkState();
}

class _RoverMarkState extends State<RoverMark> with TickerProviderStateMixin {
  late final AnimationController _drawController = AnimationController(
    vsync: this,
    duration: AppDurations.deliberate,
  );

  late final AnimationController _sweepController = AnimationController(
    vsync: this,
    duration: AppDurations.radarSweep,
  );

  late final Animation<double> _draw = CurvedAnimation(
    parent: _drawController,
    curve: Curves.easeOutCubic,
  );

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = AppMotion.reduceMotion(context);
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.animate && !_reduceMotion) {
      _drawController.forward();
      _sweepController.repeat(reverse: true);
    } else {
      // Reduce motion, or a static mark: draw the logo complete and park the
      // servo arc mid-sweep.
      _drawController.value = 1;
      _sweepController.stop();
      _sweepController.value = 0.5;
    }
  }

  @override
  void dispose() {
    _drawController.dispose();
    _sweepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ROVEROS logo',
      image: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: Listenable.merge([_draw, _sweepController]),
          builder: (context, _) => CustomPaint(
            size: Size.square(widget.size),
            painter: _RoverMarkPainter(
              progress: _draw.value,
              sweep: _sweepController.value,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoverMarkPainter extends CustomPainter {
  const _RoverMarkPainter({
    required this.progress,
    required this.sweep,
    required this.color,
  });

  /// 0–1 draw-in.
  final double progress;

  /// 0–1 servo position, mapped to the sweep arc.
  final double sweep;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = size.center(Offset.zero);

    _paintSweep(canvas, center, s);
    _paintWheels(canvas, center, s);
    _paintChassis(canvas, center, s);
  }

  void _paintSweep(Canvas canvas, Offset center, double s) {
    if (progress < 0.55) return;
    final fade = ((progress - 0.55) / 0.45).clamp(0.0, 1.0);

    final pod = center.translate(0, -s * 0.31);
    final radius = s * 0.42;
    // Servo travel is 0–180°; the mark shows the forward-facing half of it.
    final angle = math.pi + (math.pi * 0.25) + (math.pi * 0.5) * sweep;

    canvas.drawArc(
      Rect.fromCircle(center: pod, radius: radius),
      math.pi * 1.15,
      math.pi * 0.7,
      true,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.22 * fade),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: pod, radius: radius)),
    );

    canvas.drawLine(
      pod,
      pod + Offset(math.cos(angle), math.sin(angle)) * radius,
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0.9 * fade),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: pod, radius: radius)),
    );
  }

  void _paintWheels(Canvas canvas, Offset center, double s) {
    final wheelFade = ((progress - 0.25) / 0.4).clamp(0.0, 1.0);
    if (wheelFade <= 0) return;

    final paint = Paint()
      ..color = AppColors.borderStrong.withValues(alpha: wheelFade)
      ..style = PaintingStyle.fill;

    final w = s * 0.11;
    final h = s * 0.20;
    final dx = s * 0.27;
    final dy = s * 0.19;

    for (final sx in [-1.0, 1.0]) {
      for (final sy in [-1.0, 1.0]) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center.translate(dx * sx, dy * sy),
            width: w,
            height: h,
          ),
          Radius.circular(s * 0.035),
        );
        canvas.drawRRect(rect, paint);
      }
    }
  }

  void _paintChassis(Canvas canvas, Offset center, double s) {
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: s * 0.46, height: s * 0.64),
      Radius.circular(s * 0.09),
    );

    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.surfaceElevated, AppColors.surfaceSunken],
        ).createShader(body.outerRect),
    );

    // Outline draws itself in, clockwise from the front.
    final outline = Path()..addRRect(body);
    canvas.drawPath(
      _trimPath(outline, progress),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.018
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    if (progress < 0.5) return;
    final detailFade = ((progress - 0.5) / 0.5).clamp(0.0, 1.0);

    // Sensor pod at the front.
    canvas.drawCircle(
      center.translate(0, -s * 0.31),
      s * 0.045,
      Paint()..color = color.withValues(alpha: detailFade),
    );

    // Headlight bar.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center.translate(0, -s * 0.20),
          width: s * 0.26,
          height: s * 0.035,
        ),
        Radius.circular(s * 0.02),
      ),
      Paint()..color = AppColors.headlight.withValues(alpha: 0.75 * detailFade),
    );

    // Deck lines.
    final deck = Paint()
      ..color = AppColors.border.withValues(alpha: detailFade)
      ..strokeWidth = s * 0.012
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = center.dy - s * 0.02 + i * s * 0.075;
      canvas.drawLine(
        Offset(center.dx - s * 0.13, y),
        Offset(center.dx + s * 0.13, y),
        deck,
      );
    }
  }

  /// Returns the first [t] fraction of [path] by arc length.
  Path _trimPath(Path path, double t) {
    if (t >= 1) return path;
    final trimmed = Path();
    for (final metric in path.computeMetrics()) {
      trimmed.addPath(metric.extractPath(0, metric.length * t), Offset.zero);
    }
    return trimmed;
  }

  @override
  bool shouldRepaint(_RoverMarkPainter old) =>
      old.progress != progress || old.sweep != sweep || old.color != color;
}
