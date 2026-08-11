import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Compact trend line for a telemetry series.
///
/// Deliberately axis-free: the number beside it is the reading, and the
/// sparkline only has to answer "which way is this going, and how steadily".
/// `null` entries are real gaps in the record — a dropout leaves a break in the
/// line rather than a straight segment implying data that never arrived.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.color = AppColors.accent,
    this.height = 34,
    this.minValue,
    this.maxValue,
    this.showFill = true,
    this.showLatestDot = true,
    this.semanticLabel,
  });

  /// Oldest first. `null` marks a sample the vehicle did not report.
  final List<double?> values;

  final Color color;
  final double height;

  /// Fixes the vertical scale. Leave null to fit the data.
  ///
  /// Battery passes 0–100 so a pack sitting at 80% does not render as a
  /// dramatic mountain range; distance fits its own data because its useful
  /// range depends on where the rover is.
  final double? minValue;
  final double? maxValue;

  final bool showFill;
  final bool showLatestDot;
  final String? semanticLabel;

  /// Fewer points than this cannot describe a trend, so the widget renders its
  /// empty state instead of a misleading single segment.
  static const int minimumPoints = 2;

  bool get _hasTrend =>
      values.whereType<double>().length >= minimumPoints;

  @override
  Widget build(BuildContext context) {
    if (!_hasTrend) {
      return Semantics(
        label: semanticLabel == null
            ? 'No trend recorded yet'
            : '$semanticLabel. No trend recorded yet',
        child: ExcludeSemantics(
          child: SizedBox(
            height: height,
            child: Center(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _SparklinePainter(
              values: values,
              color: color,
              minValue: minValue,
              maxValue: maxValue,
              showFill: showFill,
              showLatestDot: showLatestDot,
            ),
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.minValue,
    required this.maxValue,
    required this.showFill,
    required this.showLatestDot,
  });

  final List<double?> values;
  final Color color;
  final double? minValue;
  final double? maxValue;
  final bool showFill;
  final bool showLatestDot;

  /// Smallest span the vertical scale is allowed to collapse to. Without it a
  /// perfectly flat series divides by zero; with it, a flat series renders as
  /// the flat line it is instead of amplified sensor noise.
  static const double _minimumSpan = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final readings = values.whereType<double>();
    if (readings.length < Sparkline.minimumPoints) return;

    var low = minValue ?? readings.reduce((a, b) => a < b ? a : b);
    var high = maxValue ?? readings.reduce((a, b) => a > b ? a : b);
    if (high - low < _minimumSpan) {
      final mid = (high + low) / 2;
      low = mid - _minimumSpan / 2;
      high = mid + _minimumSpan / 2;
    }

    // Inset so the stroke and the latest-value dot are not clipped.
    const inset = 3.0;
    final usableHeight = size.height - inset * 2;
    final step = values.length <= 1
        ? 0.0
        : (size.width - inset * 2) / (values.length - 1);

    Offset pointAt(int index, double value) {
      final t = ((value - low) / (high - low)).clamp(0.0, 1.0);
      return Offset(inset + step * index, inset + usableHeight * (1 - t));
    }

    // Each run of consecutive readings is its own path, so gaps stay gaps.
    final runs = <List<Offset>>[];
    var current = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null) {
        if (current.length > 1) runs.add(current);
        current = <Offset>[];
        continue;
      }
      current.add(pointAt(i, value));
    }
    if (current.length > 1) runs.add(current);
    if (runs.isEmpty) return;

    if (showFill) {
      final fill = Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.28),
                color.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromLTWH(0, 0, size.width, size.height),
            );

      for (final run in runs) {
        final path = Path()..moveTo(run.first.dx, size.height);
        for (final point in run) {
          path.lineTo(point.dx, point.dy);
        }
        path
          ..lineTo(run.last.dx, size.height)
          ..close();
        canvas.drawPath(path, fill);
      }
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    for (final run in runs) {
      final path = Path()..moveTo(run.first.dx, run.first.dy);
      for (final point in run.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, stroke);
    }

    if (!showLatestDot) return;
    final latest = runs.last.last;
    canvas.drawCircle(latest, 3.4, Paint()..color = AppColors.background);
    canvas.drawCircle(latest, 2.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color ||
      old.minValue != minValue ||
      old.maxValue != maxValue ||
      old.showFill != showFill ||
      old.showLatestDot != showLatestDot ||
      !identical(old.values, values);
}
