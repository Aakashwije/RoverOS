import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/spider_commands.dart';

/// A small badge that visibly reacts to what the spiderbot is doing: a slow
/// idle float, a brisk double-hop while walking forward/back/sideways, or a
/// continuous spin while rotating in place.
///
/// The car HUD has a motor readout with real numbers to show; the spiderbot
/// has no equivalent continuous telemetry (see `SpiderDriveState`'s doc
/// comment), so this is its stand-in — confirmation that a held direction is
/// actually commanding something, not just lighting up a button.
class WalkingIndicator extends StatefulWidget {
  const WalkingIndicator({super.key, required this.direction});

  final WalkDirection? direction;

  @override
  State<WalkingIndicator> createState() => _WalkingIndicatorState();
}

class _WalkingIndicatorState extends State<WalkingIndicator>
    with SingleTickerProviderStateMixin {
  static const _idleDuration = Duration(milliseconds: 1800);
  static const _walkDuration = Duration(milliseconds: 480);
  static const _rotateDuration = Duration(milliseconds: 900);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _idleDuration,
  );

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = AppMotion.reduceMotion(context);
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    _sync();
  }

  @override
  void didUpdateWidget(WalkingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.direction != oldWidget.direction) _sync();
  }

  bool get _isRotating =>
      widget.direction == WalkDirection.rotateLeft ||
      widget.direction == WalkDirection.rotateRight;

  void _sync() {
    if (_reduceMotion) {
      _controller.stop();
      return;
    }
    _controller.duration = widget.direction == null
        ? _idleDuration
        : (_isRotating ? _rotateDuration : _walkDuration);
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direction = widget.direction;
    final isWalking = direction != null;
    final color = isWalking ? AppColors.accent : AppColors.textTertiary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _reduceMotion ? 0.0 : _controller.value;

        var bounce = 0.0;
        var tilt = 0.0;
        var spin = 0.0;

        if (!_reduceMotion) {
          if (_isRotating) {
            spin =
                t *
                2 *
                math.pi *
                (direction == WalkDirection.rotateLeft ? -1 : 1);
          } else if (isWalking) {
            // Two quick hops per cycle, like little footsteps.
            final hopPhase = (t * 2) % 1.0;
            bounce = -8 * math.sin(hopPhase * math.pi).abs();
            tilt = 0.08 * math.sin(t * 2 * math.pi);
          } else {
            // A slow, barely-there float while parked.
            bounce = -3 * (0.5 + 0.5 * math.sin(t * 2 * math.pi));
          }
        }

        return Transform.translate(
          offset: Offset(0, bounce),
          child: Transform.rotate(angle: spin + tilt, child: child),
        );
      },
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: AppDurations.standard,
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: isWalking ? 0.18 : 0.08),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          boxShadow: isWalking
              ? AppShadows.glow(AppColors.accent, blur: 18, opacity: 0.35)
              : null,
        ),
        child: Icon(Icons.bug_report_rounded, size: 32, color: color),
      ),
    );
  }
}
