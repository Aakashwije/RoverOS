import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Animates a conditional panel in and out instead of letting it pop.
///
/// Banners on this dashboard appear because something changed on the vehicle —
/// telemetry went stale, the link dropped, a fault arrived. A panel that
/// materialises instantly reads as a rendering glitch; one that expands and
/// fades in reads as the app reacting, and the motion draws the eye to the
/// thing that just became true.
///
/// Pass `null` to hide. Children should carry a [Key] when the *content*
/// changes but the widget type does not, so the cross-fade fires.
class AnimatedReveal extends StatelessWidget {
  const AnimatedReveal({
    super.key,
    this.child,
    this.duration = AppDurations.normal,
    this.alignment = Alignment.topCenter,
  });

  final Widget? child;
  final Duration duration;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    // Reduce-motion users get the state change without the transition: the
    // banner still appears and disappears, it just does not slide or fade.
    final duration = AppMotion.of(context, this.duration);
    return AnimatedSize(
      duration: duration,
      curve: AppDurations.standard,
      alignment: alignment,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: AppDurations.emphasized,
        switchOutCurve: Curves.easeIn,
        // The default switcher centres its children while both are alive,
        // which makes an expanding banner drift. Pinning to the top keeps the
        // outgoing and incoming panels aligned with the layout above them.
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: alignment,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        ),
        child:
            child ??
            const SizedBox(
              key: ValueKey('roveros.reveal.empty'),
              width: double.infinity,
            ),
      ),
    );
  }
}

/// Draws attention to a value that just changed, without moving the layout.
///
/// Used where a number updates faster than the eye tracks it — the commanded
/// motor output on the drive HUD, for instance — so a change registers
/// peripherally while the driver is watching the vehicle, not the phone.
class PulseOnChange extends StatefulWidget {
  const PulseOnChange({
    super.key,
    required this.value,
    required this.child,
    this.color = AppColors.accent,
    this.enabled = true,
  });

  /// Any change to this triggers one pulse.
  final Object? value;

  final Widget child;
  final Color color;
  final bool enabled;

  @override
  State<PulseOnChange> createState() => _PulseOnChangeState();
}

class _PulseOnChangeState extends State<PulseOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.slow,
    value: 1,
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.reduceMotion(context);
  }

  @override
  void didUpdateWidget(PulseOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value || !widget.enabled) return;
    // A glow that pulses is a strobe to a vestibular-sensitive user; the
    // value itself still updates, which is the actual information.
    if (_reduceMotion) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Bright at the moment of change, gone by the end — a decay, so a
        // stream of rapid updates reads as a steady glow rather than a strobe.
        final intensity = 1 - Curves.easeOutCubic.transform(_controller.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadii.cardRadius,
            boxShadow: intensity <= 0.01
                ? null
                : AppShadows.glow(
                    widget.color,
                    blur: 14,
                    opacity: 0.30 * intensity,
                  ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
