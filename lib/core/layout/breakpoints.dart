import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Width thresholds for the dashboard's layouts.
///
/// Measured against the *available* width rather than the screen's, so a pane
/// nested inside another two-column layout collapses correctly instead of
/// inheriting the tablet decision made by its parent.
abstract final class Breakpoints {
  /// Below this the dashboard is a single column: phones in portrait, and
  /// anything narrow enough that two columns would each be cramped.
  static const double wide = 700;

  /// Large tablets and desktop-class windows, where a third of the width is
  /// still a comfortable reading measure.
  static const double extraWide = 1040;

  static bool isWide(double width) => width >= wide;

  static bool isExtraWide(double width) => width >= extraWide;

  /// Screen-level query, for decisions that cannot be made from a
  /// [LayoutBuilder] — page padding, for instance.
  static bool screenIsWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;
}

/// Stacks two panes on a phone and sets them side by side on a tablet.
///
/// The split is driven by the width this widget is actually given, so the same
/// call site works on Home (full width) and inside a sheet (constrained).
class TwoPane extends StatelessWidget {
  const TwoPane({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryFlex = 3,
    this.secondaryFlex = 2,
    this.spacing = AppSpacing.xl,
    this.breakpoint = Breakpoints.wide,
  });

  final Widget primary;
  final Widget secondary;
  final int primaryFlex;
  final int secondaryFlex;
  final double spacing;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              primary,
              SizedBox(height: spacing),
              secondary,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: primaryFlex, child: primary),
            SizedBox(width: spacing),
            Expanded(flex: secondaryFlex, child: secondary),
          ],
        );
      },
    );
  }
}

/// Centres a page's content and caps its measure on very wide screens.
///
/// A settings list stretched across a 1200dp window is unreadable; this keeps
/// the line length sane without special-casing every screen.
class PageConstraints extends StatelessWidget {
  const PageConstraints({super.key, required this.child, this.maxWidth = 1100});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
