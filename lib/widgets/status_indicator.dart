import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Dot-plus-label status row.
///
/// The dot pulses only while [pulsing] is set (live/transient states such as
/// scanning or reconnecting), which keeps motion meaningful rather than
/// ambient. The label is never optional — colour alone is not a status.
class StatusIndicator extends StatefulWidget {
  const StatusIndicator({
    super.key,
    required this.label,
    this.level = StatusLevel.neutral,
    this.detail,
    this.pulsing = false,
    this.showIcon = false,
    this.dotSize = 9,
    this.labelStyle,
  });

  final String label;
  final StatusLevel level;
  final String? detail;

  /// Animates the dot. Reserve for genuinely in-progress states.
  final bool pulsing;

  /// Adds the status icon alongside the dot, for higher-stakes readouts.
  final bool showIcon;

  final double dotSize;
  final TextStyle? labelStyle;

  @override
  State<StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<StatusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.pulse,
  );

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = AppMotion.reduceMotion(context);
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(StatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing == oldWidget.pulsing) return;
    _syncAnimation();
  }

  /// The dot holds steady bright instead of pulsing under reduce motion — a
  /// transient state is still marked, just not by movement.
  void _syncAnimation() {
    if (widget.pulsing && !_reduceMotion) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = widget.pulsing ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(widget.level);
    final semanticLabel = widget.detail == null
        ? widget.label
        : '${widget.label}. ${widget.detail}';

    return Semantics(
      label: semanticLabel,
      liveRegion: widget.pulsing,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = _controller.value;
                return Container(
                  height: widget.dotSize,
                  width: widget.dotSize,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.55 - 0.35 * t),
                        blurRadius: 5 + 7 * t,
                        spreadRadius: 1 + 3 * t,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(width: AppSpacing.sm),
            if (widget.showIcon) ...[
              Icon(
                AppColors.iconForStatus(widget.level),
                size: 13,
                color: color,
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style:
                        widget.labelStyle ??
                        AppTypography.labelStrong.copyWith(color: color),
                  ),
                  if (widget.detail != null)
                    Text(
                      widget.detail!,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
