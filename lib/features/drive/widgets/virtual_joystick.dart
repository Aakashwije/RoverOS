import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/clamp.dart';

/// Analog virtual joystick.
///
/// Reports a normalised position (-1…1 on each axis, +y forward) on every
/// gesture update. It deliberately does no motor math and no throttling — those
/// belong to `MotorMath` and `DriveController` respectively, so this widget
/// stays a pure input device.
class VirtualJoystick extends StatefulWidget {
  const VirtualJoystick({
    super.key,
    required this.onChanged,
    required this.onReleased,
    this.size = 220,
    this.deadZoneFraction = 0.12,
    this.enabled = true,
    this.onEngaged,
    this.disabledMessage,
  });

  /// Fired continuously while the stick is held.
  final void Function(double x, double y) onChanged;

  final VoidCallback onReleased;

  /// Called once when the user first grabs the stick, for haptics.
  final VoidCallback? onEngaged;

  final double size;

  /// Drawn as a centre well so the user can see where input starts.
  final double deadZoneFraction;

  final bool enabled;

  /// Shown across the pad when [enabled] is false, e.g. during E-STOP.
  final String? disabledMessage;

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick>
    with SingleTickerProviderStateMixin {
  late final AnimationController _returnController = AnimationController(
    vsync: this,
    duration: AppDurations.normal,
  )..addListener(_onReturnTick);

  /// Knob position in normalised space, +y **up** on screen.
  Offset _position = Offset.zero;
  Offset _returnFrom = Offset.zero;
  bool _isDragging = false;

  double get _radius => widget.size / 2;

  @override
  void dispose() {
    _returnController.dispose();
    super.dispose();
  }

  void _onReturnTick() {
    final t = Curves.easeOutBack.transform(_returnController.value);
    setState(() => _position = Offset.lerp(_returnFrom, Offset.zero, t)!);
  }

  /// Converts a local touch point into a normalised, disc-clamped position.
  Offset _normalize(Offset local) {
    final centred = local - Offset(_radius, _radius);
    final normalized = Offset(centred.dx / _radius, centred.dy / _radius);

    final magnitude = normalized.distance;
    if (magnitude <= 1) return normalized;
    // Clamp to the unit disc so corners cannot exceed full deflection.
    return normalized / magnitude;
  }

  void _report() {
    // Screen y grows downward; the drive axis grows forward, so it is inverted
    // exactly once, here.
    widget.onChanged(clampUnit(_position.dx), clampUnit(-_position.dy));
  }

  void _onStart(Offset local) {
    if (!widget.enabled) return;
    _returnController.stop();
    _isDragging = true;
    widget.onEngaged?.call();
    setState(() => _position = _normalize(local));
    _report();
  }

  void _onUpdate(Offset local) {
    if (!widget.enabled || !_isDragging) return;
    setState(() => _position = _normalize(local));
    _report();
  }

  void _onEnd() {
    if (!_isDragging) return;
    _isDragging = false;
    // Tell the controller to stop before the spring animation finishes: the
    // vehicle must not keep driving through the return-to-centre.
    widget.onReleased();
    _returnFrom = _position;
    _returnController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Virtual joystick',
      hint: widget.enabled
          ? 'Drag to drive. Release to stop.'
          : widget.disabledMessage ?? 'Joystick disabled',
      enabled: widget.enabled,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: widget.size,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) => _onStart(details.localPosition),
            onPanUpdate: (details) => _onUpdate(details.localPosition),
            onPanEnd: (_) => _onEnd(),
            onPanCancel: _onEnd,
            child: CustomPaint(
              painter: _JoystickPainter(
                position: _position,
                deadZoneFraction: widget.deadZoneFraction,
                isDragging: _isDragging,
                enabled: widget.enabled,
              ),
              child: widget.enabled
                  ? null
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: Text(
                          widget.disabledMessage ?? '',
                          textAlign: TextAlign.center,
                          style: AppTypography.label.copyWith(
                            color: AppColors.danger,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  const _JoystickPainter({
    required this.position,
    required this.deadZoneFraction,
    required this.isDragging,
    required this.enabled,
  });

  final Offset position;
  final double deadZoneFraction;
  final bool isDragging;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final accent = enabled ? AppColors.accent : AppColors.textTertiary;

    _paintBase(canvas, center, radius);
    _paintAxes(canvas, center, radius);
    _paintDeadZone(canvas, center, radius);

    if (!enabled) return;

    final knob = center + Offset(position.dx * radius, position.dy * radius);
    _paintStick(canvas, center, knob, accent);
    _paintKnob(canvas, knob, radius, accent);
  }

  void _paintBase(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.surfaceElevated, AppColors.surfaceSunken],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.borderStrong,
    );
  }

  /// Cross-hairs and cardinal ticks, so the driver can judge deflection without
  /// looking away from the vehicle for long.
  void _paintAxes(Canvas canvas, Offset center, double radius) {
    final axis = Paint()
      ..strokeWidth = 1
      ..color = AppColors.border.withValues(alpha: 0.7);

    canvas.drawLine(
      Offset(center.dx - radius * 0.75, center.dy),
      Offset(center.dx + radius * 0.75, center.dy),
      axis,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.75),
      Offset(center.dx, center.dy + radius * 0.75),
      axis,
    );

    final tick = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = AppColors.borderStrong;
    for (var i = 0; i < 4; i++) {
      final angle = math.pi / 2 * i;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * (radius - 14),
        center + direction * (radius - 7),
        tick,
      );
    }
  }

  void _paintDeadZone(Canvas canvas, Offset center, double radius) {
    if (deadZoneFraction <= 0) return;
    // Below this size the ring is a smudge a few pixels wide that reads as
    // dirt on the pad rather than as a boundary — drop it and let the
    // cross-hairs carry the centre reference alone.
    if (radius * deadZoneFraction < 8) return;
    canvas.drawCircle(
      center,
      radius * deadZoneFraction,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.border,
    );
  }

  void _paintStick(Canvas canvas, Offset center, Offset knob, Color accent) {
    if ((knob - center).distance < 2) return;
    canvas.drawLine(
      center,
      knob,
      Paint()
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.35),
    );
  }

  void _paintKnob(Canvas canvas, Offset knob, double radius, Color accent) {
    final knobRadius = radius * 0.26;

    if (isDragging) {
      canvas.drawCircle(
        knob,
        knobRadius * 1.5,
        Paint()
          ..color = accent.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    canvas.drawCircle(
      knob,
      knobRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [accent, accent.withValues(alpha: 0.65)],
        ).createShader(Rect.fromCircle(center: knob, radius: knobRadius)),
    );

    canvas.drawCircle(
      knob,
      knobRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: isDragging ? 0.5 : 0.25),
    );

    canvas.drawCircle(
      knob,
      knobRadius * 0.22,
      Paint()..color = AppColors.background.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_JoystickPainter old) =>
      old.position != position ||
      old.isDragging != isDragging ||
      old.enabled != enabled ||
      old.deadZoneFraction != deadZoneFraction;
}
