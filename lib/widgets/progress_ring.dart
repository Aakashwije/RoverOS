import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/clamp.dart';

/// Animated circular gauge used for speed, battery and signal readouts.
///
/// Drawn with a [CustomPainter] rather than a stack of widgets so the sweep,
/// tick marks and cap glow stay in one repaint and cost a single layer.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 160,
    this.strokeWidth = 12,
    this.color = AppColors.accent,
    this.trackColor = AppColors.surfaceSunken,
    this.child,
    this.startAngle = _defaultStart,
    this.sweepAngle = _defaultSweep,
    this.showTicks = true,
    this.tickCount = 40,
    this.animate = true,
    this.semanticLabel,
  });

  /// Open-bottom gauge: starts at 8 o'clock and sweeps 280°, the automotive
  /// convention that leaves room for a label under the dial.
  static const double _defaultStart = math.pi * 0.75;
  static const double _defaultSweep = math.pi * 1.5;

  /// 0–1. Values outside are clamped.
  final double value;

  final double size;
  final double strokeWidth;
  final Color color;
  final Color trackColor;
  final Widget? child;

  /// Radians, clockwise from 3 o'clock.
  final double startAngle;
  final double sweepAngle;

  final bool showTicks;
  final int tickCount;
  final bool animate;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final target = clampDouble(value, 0, 1);

    Widget painter(double displayValue) => CustomPaint(
      size: Size.square(size),
      painter: _ProgressRingPainter(
        value: displayValue,
        strokeWidth: strokeWidth,
        color: color,
        trackColor: trackColor,
        startAngle: startAngle,
        sweepAngle: sweepAngle,
        showTicks: showTicks,
        tickCount: tickCount,
      ),
      child: SizedBox.square(
        dimension: size,
        child: child == null ? null : Center(child: child),
      ),
    );

    final ring = animate
        ? TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: target),
            duration: AppDurations.slow,
            curve: AppDurations.standard,
            builder: (context, animated, _) => painter(animated),
          )
        : painter(target);

    if (semanticLabel == null) return ring;
    return Semantics(
      label: semanticLabel,
      value: '${(target * 100).round()}%',
      child: ExcludeSemantics(child: ring),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.value,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
    required this.startAngle,
    required this.sweepAngle,
    required this.showTicks,
    required this.tickCount,
  });

  final double value;
  final double strokeWidth;
  final Color color;
  final Color trackColor;
  final double startAngle;
  final double sweepAngle;
  final bool showTicks;
  final int tickCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(rect, startAngle, sweepAngle, false, track);

    if (showTicks) _paintTicks(canvas, center, radius);

    if (value <= 0) return;

    final progressSweep = sweepAngle * value;
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: [color.withValues(alpha: 0.55), color],
        transform: GradientRotation(startAngle),
      ).createShader(rect);
    canvas.drawArc(rect, startAngle, progressSweep, false, progress);

    // Bloom at the leading edge reads as a live needle rather than a static arc.
    final capAngle = startAngle + progressSweep;
    final cap =
        center + Offset(math.cos(capAngle), math.sin(capAngle)) * radius;
    canvas.drawCircle(
      cap,
      strokeWidth * 0.75,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  void _paintTicks(Canvas canvas, Offset center, double radius) {
    final tick = Paint()
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final inner = radius - strokeWidth * 0.9;
    final outer = radius - strokeWidth * 1.55;

    for (var i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      final angle = startAngle + sweepAngle * t;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final isMajor = i % 5 == 0;
      tick.color = t <= value
          ? color.withValues(alpha: isMajor ? 0.75 : 0.35)
          : AppColors.borderStrong.withValues(alpha: isMajor ? 0.8 : 0.4);
      canvas.drawLine(
        center + direction * (isMajor ? outer : inner - 1),
        center + direction * inner,
        tick,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth ||
      old.startAngle != startAngle ||
      old.sweepAngle != sweepAngle ||
      old.showTicks != showTicks ||
      old.tickCount != tickCount;
}
